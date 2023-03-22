//
//  ZmqHelper.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-28.
//

import Foundation
import SwiftyJSON
import SwiftyZeroMQ5

class Replier: NSObject {
    var context: SwiftyZeroMQ.Context?          // Context
    var socket: SwiftyZeroMQ.Socket?            // Socket
    var receiveTimeOut: Int32 = 500             // Receive timeout to not halt on receive
    var name = ""                               // The cusom name of the socket
    var port: Int = 5560                        // The port
    var endPoint = ""                           // EnpointString for printing
    var replyEnable = false                      // Use this flag as loop condition
    
    // General socket commands
    
    // ********************************
    // Setup repler. Init to connect
    func setupReplier(name: String, zmqContext: SwiftyZeroMQ.Context, port: Int){
        self.context = zmqContext
        self.name = name
        self.port = port
        self.endPoint = "tcp://*:" + String(port)
    }
    
    // ******************************
    // Init replyer. Run setup first
    func initReplier()->Bool{
        do{
            socket = try context!.socket(.reply)
            try socket!.bind(endPoint)
            try socket!.setRecvTimeout(receiveTimeOut)
            replyEnable = true
            // Replier ready, start a replier thread
            return true
        }
        catch{
            print(name, "Failed connecting to:", String(endPoint), error)
            return false
        }
    }
    
    // ***********************
    // Close replier socket
    func close(){
        // Stop reply thread
        replyEnable = false
        
        // Wait the receiveTimeOut to not risk closing on socket receiving.
        usleep(UInt32((receiveTimeOut+100)*1000))
        
        // Close socket
        print(name, "Closing socket")
        do{
            try socket?.close()
        }
        catch{
            print(name, "Error closing socket: ", error)
        }
    }
    
    // ************
    // Send message
    func sendJson(json: JSON){
        let messStr = getJsonString(json: json)
        do{
            try socket!.send(string: messStr)
        }
        catch{
            let eStr = self.name + "Failed to send"
            NotificationCenter.default.post(name: .didNewLogItem, object: nil, userInfo: ["logItem": eStr])
        }
    }
}

class Requestor: NSObject {
    var context: SwiftyZeroMQ.Context?              // Context
    var socket: SwiftyZeroMQ.Socket?                // Socket
    var logPub: Publisher?                          // Log publisher socket
    var name = ""                                   // The custom name of the socket
    var endPoint = ""                               // EndpointString for printing
    var ip = ""                                     // The ip
    var port = 0                                    // The port
    var id = ""                                     // The id to use when sending requests
    let recvTimeout: Int32 = 1000                   // Receive timeout ms.
    var lastBeatSent = CACurrentMediaTime()         // Track sent messages
    var requestEnable = false                       // A flag to help stopping heartBeat thread.
    var allocator: Allocator?                       // An allocator since socket is not thread safe and messages will be triggered from user and heartbeat.
    var linkLostTime: Double = 10.0                 // Time for when link is considered lost
    var linkLost = false                            // Link lost flag
    var HBTicker = 0                                // Ticker for heartbeats, incremental counter
    
    // General socket commands
    
    // ********************************
    // Setup requestor. Init to connect
    func setupRequestor(name: String, zmqContext: SwiftyZeroMQ.Context, ip: String, port: Int, logPublisher: Publisher?, id: String = ""){
        self.context = zmqContext
        self.name = name
        self.ip = ip
        self.port = port
        self.endPoint = "tcp://" + ip + ":" + String(port)
        self.allocator = Allocator(name: name)
        self.logPub = logPublisher
        self.id = id
    }
    
    // ******************************
    // Init requstor. Run setup first
    func initRequestor(heartBeatPeriod: Double, linkLostTime: Double)->Bool{
        do{
            socket = try context!.socket(.request)
            try socket?.setSendBufferSize(4096)
            try socket?.setLinger(0)
            try socket?.setRecvTimeout(self.recvTimeout)
            try socket?.connect(endPoint)
            
            // Set linkLostTime, in relation to period. User can choose to loose link on one missed message
            self.linkLostTime = max(linkLostTime, heartBeatPeriod+0.2)
            // Start heartbeats thread if wanted hbPeriod is positive (don't restart thread in case of reconnect).
            if heartBeatPeriod > 0 {
                requestEnable = true
                Dispatch.background {
                    self.sendHeartBeats(period: heartBeatPeriod)
                }
            }
            return true
        }
        catch{
            print("Cannot connect to server at ", String(endPoint), error) // error can be: Can't assign requested address
            return false
        }
    }
    
    // **************
    // Send hearbeats
    func sendHeartBeats(period: Double){
        while requestEnable{
            // Send heartbeat if needed.
            let timePassed = CACurrentMediaTime() - self.lastBeatSent
            //print(name, timePassed, linkLostTime)
            if timePassed > linkLostTime{
                // Link lost
                print(name, "link lost, last successful message: ", timePassed)
                linkLost = true
                requestEnable = false
                continue
            }
            if timePassed > period - 0.1 {
                let call = "heart_beat"
                var jsonM = JSON()
                
                jsonM["fcn"] = JSON(call)
                jsonM["id"] = JSON(self.id)
                jsonM["tick"] = JSON(HBTicker)
                HBTicker += 1
                
                // Send receive
                let jsonR = sendReceive(caller: call, json: jsonM)
                // Check noReply, caorrect call and nack
                if jsonR["que"].exists(){
                    // Message was dropped because an other message was being sent
                    usleep(100000) // 0.1s
                }
                else if noReply(jsonR){
                    print(name, "Link degraded, last successful message age: ", CACurrentMediaTime() - self.lastBeatSent, "tic: ", HBTicker - 1)
                }
                else if replyMixup(jsonR, call){}
                else if nack(jsonR){}
                // Heartbeat successful
                else {
                    self.lastBeatSent = CACurrentMediaTime()
                }
            }
            else{
                let sleepTime = (period - timePassed - 0.1)
                if sleepTime > 0 {
                    usleep(UInt32(sleepTime*1000000))
                }
            }
        }
        print(self.name, "Exiting heart beat thread")
    }
    
    // ************
    // Close socket
    func close(){
        // Note heartBeat thread can take long to exit using 'active' flag.
        requestEnable = false
        // If socket has no name, the socket has not been setup. Nothing to close.
        if name == "" {
            print("Request socket not setup, cannot be closed")
            return
        }
        // Make sure socket is idle
        while !self.allocator!.allocate("Close_socket", maxTime: 1){
            usleep(1000000/100) // 0.01s
        }
        
        print(name, "Closing socket")
        do{
            try socket?.close()
            self.allocator?.deallocate()
        }
        catch{
            print(name, "Could not close socket")
        }
    }
    
    // *******************************************************************************
    // Send and receive. Caller parses. Reconnect if there is no answer within TIMEOUT
    func sendReceive(caller: String, json: JSON)->JSON{
        while !self.allocator!.allocate(caller, maxTime: Double(self.recvTimeout+50)/1000){ //1.05s
            // Socket is occupied, dont choke socket with heartbeats. Drop heart beat and return empty JSON
            if json["fcn"].stringValue == "heart_beat"{
                var dummyJson = JSON()
                dummyJson["que"] = "yes"
                return dummyJson
            }
            usleep(50000) //0.05s
        }
        // Create string from json and send request
        let requestStr = getJsonString(json: json)
        do{
            try socket!.send(string: requestStr)
            if logPub != nil{
                var logJson = json
                logJson["time"] = JSON(CACurrentMediaTime())
                _ = logPub?.publish(topic: name + "_s", json: logJson)
            }
        }
        catch{
            // error = Operation cannot be accomplished in current state
            print(self.name, "Error: ", error)
            print("Busy waiting for reply")
        }
        
        // Receive and parse the reposnse..
        var jsonR = JSON()
        do{
            let _message: String? = try socket?.recv(bufferLength: 65536, options: .none)
            self.allocator?.deallocate()
            (_, jsonR) = getJsonObject(uglyString: _message!)
            if logPub != nil {
                var logJson = jsonR
                logJson["time"] = JSON(CACurrentMediaTime())
                _ = logPub?.publish(topic: name + "_r", json: logJson)
            }
            if noReply(jsonR){}
            else if replyMixup(jsonR, json["fcn"].stringValue){}
            else if nack(jsonR){}
            else{
                // Link is valid. Update last sent (and correcty replied to)
                self.lastBeatSent = CACurrentMediaTime()
            }
        }
        catch{
            print(self.name, error, "No answer:", json["fcn"])
            self.reconnect()
            self.allocator?.deallocate()
        }
        return jsonR
    }
    
    // *******************************************************
    // Reconnect by disconnecting and init the requestor again
    func reconnect(){
        // Notify user connection is poor? TODO introduce notifier
        do{
            try socket?.disconnect(endPoint)
            _ = initRequestor(heartBeatPeriod: -1, linkLostTime: linkLostTime)      // Heartbeat thread is already running
            //self.lastBeatSent = CACurrentMediaTime()                              // Give socket some slack from heartbeats
        }
        catch{
            print("Reconnect caught an error: ", error)
        }
    }
    
    // ********************
    // Application commands
    // ******************************************
    // Follow stream Call directly to DSS
    func followStream(enable: Bool, streamIp: String, streamPort: Int)->Bool{
        let call = "follow_stream"
        var success = false
        var jsonM = JSON()
        
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(self.id)
        jsonM["enable"] = JSON(enable)
        jsonM["ip"] = JSON(streamIp)
        jsonM["port"] = JSON(streamPort)
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReply, caorrect call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse ack
        else {
            success = true
        }
        return success
    }
    
    // ********
    // Ping, get the available pub-ports
    func get_info(pubType: String)->Int?{
        let call = "get_info"
        var port: Int? = nil
        
        var jsonM = JSON()
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(id)
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReply, correct call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse
        else{
            if jsonR["info_pub_port"].exists() && pubType == "info" {
                port = jsonR["info_pub_port"].intValue
            }
            else if jsonR["data_pub_port"].exists() && pubType == "data" {
                port = jsonR["data_pub_port"].intValue
            }
        }
        return port
    }
    
    // ************
    // CRM commands
    
    // **************************************
    // Register to the CRM and retreive an id
    func register(ip: String, port: Int, name: String, description: String, capabilities: [String], type: String)-> String{
        var id = ""
        let call = "register"
        
        var jsonM = JSON()
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON("")
        jsonM["name"] = JSON(name)
        jsonM["desc"] = JSON(description)
        jsonM["type"] = JSON(type)
        jsonM["ip"] = JSON(ip)
        jsonM["port"] = JSON(port)
        jsonM["capabilities"] = JSON(capabilities)
         
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReply, correct call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse
        else{
            id = jsonR["id"].stringValue
        }
        return id
    }
    
    // *******************
    // Unregister from CRM
    func unregister()->Bool{
        let call = "unregister"
        var success = false
        var jsonM = JSON()
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(self.id)
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReply, correct call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse
        else{
            success = true
        }
        return success
    }
    
    
    // *****************************
    // App requests a drone from CRM
    func getDrone(capabilities: [String] = [""], force: String = "")->(Bool, String, String, String){
        let call = "get_drone"
        var success = false
        var dssId = ""
        var dssIp = ""
        var dssPort = ""

        var jsonM = JSON()
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(self.id)
        
        // One of two arguemnts is mandatory and exclusive
        // No arg given, fail
        if capabilities[0] == force {
            return (success, "", "", "")
        }
        // Forse given
        else if capabilities[0] == ""{
            jsonM["force"] = JSON(force)
        }
        // Capabilities given
        else{
            jsonM["capabilities"] = JSON(capabilities)
        }
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReply, correct call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse
        else{
            dssId = jsonR["id"].stringValue
            dssIp = jsonR["ip"].stringValue
            dssPort = jsonR["port"].stringValue
            success = true
        }
        return (success, dssId, dssIp, dssPort)
    }
    
    // *************
    // Release drone
    func releaseDrone(id: String, dssID: String)->Bool{
        let call = "relese_drone"
        var success = false
        
        var jsonM = JSON()
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(id)
        jsonM["id-released"] = JSON(dssID)
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReply, correct call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse
        else{
            // Must be ack..
            success = true
        }
        return success
    }
    
    // *************************************************************
    // Launch App, returns enPoint as empty string if not successful
    func launchApp(app: String)->String{
        let call = "launch_app"
        var appId = ""
        
        var jsonM = JSON()
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(self.id)
        jsonM["app"] = JSON(app)
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReply, correct call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse
        else {
            // let tyrappId = jsonM["id"]
            appId = jsonR["id"].stringValue
        }
        return appId
    }
    
    // **************************************************************************
    // Request DSS list from CRM, returns list as an empty list if not successful
    func clients(filter: String = "")->JSON{
        let call = "clients"
        
        var jsonM = JSON()
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(self.id)
        jsonM["filter"] = JSON(filter)
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReply, correct call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Return the clients json struct
        return jsonR["clients"]
    }
    
    // **********************************************************************
    // DSS reports app lost when application is lost, returns success as bool
    func appLost()->Bool{
        let call = "app_lost"
        var success = false
        
        var jsonM = JSON()
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(self.id)
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReply, correct call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse
        else {
            success = true
        }
        return success
    }
    
    // TYRApp commands
    
    // ***************************************
    // Set pattern
    func setPattern(pattern: Pattern)->Bool {//, relAlt: Double, heading: Double, radius: Double = 10, yawRate: Double = 10)->Bool{
        let call = "set_pattern"
        var success = false
        var jsonM = JSON()
        
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(self.id)
        jsonM["rel_alt"] = JSON(pattern.relAlt)
        jsonM["pattern"] = JSON(pattern.name)
        
        // The heading can be string or number. It comes numbercoded from the GUI
        if pattern.headingMode == "course"{
            jsonM["heading"] = JSON("course")
        }
        else if pattern.headingMode == "poi"{
            jsonM["heading"] = JSON("poi")
        }
        else if 0 <= pattern.heading && pattern.heading < 360 {
            jsonM["heading"] = JSON(pattern.heading)
        }
        
        // Cirlce pattern have two more arguments
        if pattern.name == "circle"{
            jsonM["radius"] = JSON(pattern.radius)
            jsonM["yaw_rate"] = JSON(pattern.yawRate)
        }
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReplu, caorrect call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse ack
        else {
            success = true
        }
        return success
    }
    
    // ******************************************
    // Follow me
    func followMe(enable: Bool, capability: String)->Bool{
        let call = "follow_me"
        var success = false
        var jsonM = JSON()
        
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(self.id)
        jsonM["enable"] = JSON(enable)
        jsonM["capability"] = JSON(capability)
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReplu, caorrect call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse ack
        else {
            success = true
        }
        return success
    }
    
    // **********************************
    // Photo stream
    func photo_stream(enable:Bool)->Bool{
        let call = "photo_stream"
        var success = false
        var jsonM = JSON()
        
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(self.id)
        jsonM["enable"] = JSON(enable)
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReplu, caorrect call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse ack
        else {
            success = true
        }
        return success
    }
    
    func upgrade(id: String)->Bool{
        let call = "upgrade"
        var success = false
        var jsonM = JSON()
        
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON("root")
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReplu, caorrect call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse ack
        else {
            success = true
        }
        return success
    }
    
    func clean(id: String)->Bool{
        let call = "delStaleClients"
        var success = false
        var jsonM = JSON()
        
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON("root")
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReplu, caorrect call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse ack
        else {
            success = true
        }
        return success
    }
    
    // ********************
    // DSS commands
    // ******************************************
    func data_stream(stream: String, enable: Bool)->Bool{
        let call = "data_stream"
        var success = false
        var jsonM = JSON()
        
        jsonM["fcn"] = JSON(call)
        jsonM["id"] = JSON(self.id)
        jsonM["stream"] = JSON(stream)
        jsonM["enable"] = JSON(enable)
        
        // Send receive
        let jsonR = sendReceive(caller: call, json: jsonM)
        // Check noReplu, caorrect call and nack
        if noReply(jsonR){}
        else if replyMixup(jsonR, call){}
        else if nack(jsonR){}
        // Parse ack
        else {
            success = true
        }
        return success
    }
}


class Publisher: NSObject {
    var context: SwiftyZeroMQ.Context?              // Context
    var socket: SwiftyZeroMQ.Socket?                // Socket
    var logPub: Publisher?                          // The log publisher
    var name = ""                                   // The custom name of the socket
    var endPoint = ""                               // EndpointString for printing
    var port = 0                                    // The port
    var id = ""                                     // The id to use when sending requests
    var publishing = false                          // Flag that indicates publish activity
    var lastPub = CACurrentMediaTime()              // Time stamp for last message published
    var connectionType = ""                         // Connection type string
    
    // ***************
    // Setup Publisher
    func setupPublisher(name: String, zmqContext: SwiftyZeroMQ.Context, port: Int, logPublisher: Publisher?){
        self.context = zmqContext
        self.name = name
        self.port = port
        self.endPoint = "tcp://*:" + String(port)
        self.logPub = logPublisher
    }
    
    // *************************
    // Init the publisher socket
    func initPublisher()->Bool{
        do{
            socket = try context!.socket(.publish)
            try socket?.setSendBufferSize(524288)//(32768)(2097152)
            // Dont buffer messages, set linger to 0
            try socket?.setLinger(0)
            try socket?.setSendHighWaterMark(1)
            try socket!.bind(endPoint)
            return true
        }
        catch{
            print("Publish setup failed: ", error)
            return false
        }
    }
    
    // ************
    // Close socket
    func close(){
        while publishing{
            usleep(10000)
            print("Will close after publishing ends")
        }
        print(name, "Closing socket")
        do{
            try socket?.close()
        }
        catch{
            print(name, "Could not close socket: ")
        }
    }
    
    // *****************************************************************************
    // Bind the publisher socket, needs to be done prior to each publish due to bug:
    // https://stackoverflow.com/questions/66063569/
    func bindPublisher(){
        do {
            try socket?.bind(endPoint)
            print(name, " bind to: ", endPoint)
        }
        catch {
            if String(describing: error) != "Address already in use"{
                print(name, " Error: ", error)
            }
        }
    }
    
    //*********************************************************
    // ZMQ publish. Publishes string and serialized json-object
    func publish(topic: String, json: JSON)->Bool{
        // Only publish if connection type allows. Only dataPub will be updated with connection type,
        // info pub will publish no matter the connection type
        // This relates more the DSS that publishes photos
        if connectionType != "3G"{
            // Create string with topic and json representation
            let publishStr = getJsonStringAndTopic(topic: topic, json: json)
            
            publishing = true
            do{
                // Rebind socket due to ZMQ-lib bug (pick up new subscribers).
                bindPublisher()
                try socket?.send(string: publishStr)
                if logPub != nil{
                    // Don't publish pohotos on logPub, sned dummy data only.
                    if topic == "photo" || topic == "photo_low" {
                        // Create dummy json for log and publish
                        var logJson = JSON()
                        logJson["photo"] = JSON("base64EncodedString - removed from this log item")
                        logJson["metadata"] = json["metadata"]
                        logJson["theTopic"] = JSON(topic)
                        logJson["time"] = JSON(CACurrentMediaTime())
                        _ = logPub?.publish(topic: name, json: logJson)
                    }
                    else{
                        var logJson = json
                        logJson["time"] = JSON(CACurrentMediaTime())
                        logJson["theTopic"] = JSON(topic)
                        _ = logPub?.publish(topic: name, json: logJson)
                    }
                }
                publishing = false
                return true
            }
            catch{
                if String(describing: error) != "Address already in use"{
                    print("publish: Error: ", error)
                }
                publishing = false
                return false
            }
        }
        // Connection type to poor for publishing
        return false
    }
}

class Subscriber: NSObject {
    var context: SwiftyZeroMQ.Context?          // Context
    var socket: SwiftyZeroMQ.Socket?            // Socket
    var receiveTimeOut: Int32 = 500             // Receive timeout in ms
    var registered = false                      // Registered with poller?
    var subscribeEnable = false
    var name = ""                               // The custom name of the socket
    var endPoint = ""                           // EndpointString for printing
    var ip = ""                                 // The ip
    var port = 0                                // The port
    var id = ""
    
    
    // ************************************************************************
    // Setup the subscriber object, use init to connect, subscribe to subscribe
    func setupSubscriber(name: String, zmqContext: SwiftyZeroMQ.Context, ip: String, port: Int, id: String, timeout: Int = 500){
        self.context = zmqContext
        self.name = name
        self.ip = ip
        self.port = port
        self.id = id
        self.endPoint = ""
        self.receiveTimeOut = Int32(timeout)
    }
    
    // *************************
    // Init the publisher socket
    func initSubscriber()->Bool{
        endPoint = "tcp://" + ip + ":" + String(port)
        do{
            socket = try context!.socket(.subscribe)
            try socket?.setRecvBufferSize(2097152)
            try socket?.setRecvHighWaterMark(1)
            try socket?.connect(endPoint)
            try socket?.setRecvTimeout(receiveTimeOut)
            subscribeEnable = true
            return true
        }
        catch{
            print("Subscriber setup failed: ", error)
            return false
        }
    }
    
    // *******************************************
    // Subscribe to a topic. nil subscribes to all
    func subscribe(topic: String?){
        do{
            try socket?.setSubscribe(topic)
        }
        catch{
            print("Subscribe error: ", error)
        }
    }
    
    // **************************************************************************
    // Unsubscribe and unregister with poller. Nil unsubscibes a nil subscription
    func unsubscribe(topic: String?){
        do{
            try socket?.setUnsubscribe(topic)
        }
        catch{
            print("Unsubscribe error: ", error)
        }
    }
    
    // ***********************
    // Close subscriber socket
    func close(){
        // Stop thread and disconnect
        disconnect()
        
        print(self.name, "Closing socket")
        do{
            try socket?.close()
        }
        catch{
            print("Error closing socket: ", error)
        }
    }
    
    func disconnect(){
        // Stop subscriber thread
        subscribeEnable = false
        
        // Wait the receiveTimeOut to not risk closing on socket receiving.
        usleep(UInt32((receiveTimeOut+200)*1000))
        
        if self.name != ""{
            print(self.name, "Disconnecting socket")
        }
        do{
            try socket?.disconnect(endPoint)
        }
        catch{
            print(self.name, "Error disconnecting socket: ", error)
        }
    }
}

// ********************
// Parse helper noreply
func noReply(_ json: JSON)-> Bool{
    if json["fcn"].exists(){
        return false
    }
    else {
        //print("No answer")
        return true
    }
}

// ************************
// Parse helper reply mixup
func replyMixup(_ json: JSON, _ fcn: String)->Bool{
    if json["call"].stringValue != fcn{
        print("Reply mixup: ", json["call"], "vs ", fcn)
        return true
    }
    else{
        return false
    }
}

// *****************
// Parse helper nack
func nack(_ json: JSON, silent: Bool=false)->Bool {
    if json["fcn"].stringValue == "nack"{
        // Build error string
        var eStr = ""
        if json["description"].exists(){
            eStr = "Nack: " + json["call"].stringValue + ", " + json["description"].stringValue
        }
        else{
            eStr = "Nack: " + json["call"].stringValue
        }
        // Print error string silent or to screen
        if silent{
            print(eStr)
        }
        else{
            NotificationCenter.default.post(name: .didNewLogItem, object: nil, userInfo: ["logItem": eStr])
        }
        
        // Nack is true
        return true
    }
    else{
        // Nack is false
        return false
    }
}
    
//***************************************************************************
// Clean string from leading and trailing quotationmarks and also backslashes
func cleanUpString(str: String)->String{
    let str2 = str.dropLast()
    let str3 = str2.dropFirst()
    let str4 = str3.replacingOccurrences(of: "\\", with: "")
    return str4
}

//**************************************
// Add quotation marks around the string
func addQuotations(string: String)->String{
    return "\"" + string + "\""
}

//*******************
// Insert backslashes
func uglyfyString(string: String)->String{
    // let slashQuote = "\\\""
    // let quote = "\""
    let str1 = string.replacingOccurrences(of: "\"", with: "\\\"")
    return str1
}

//*************************************
// Get the json-object from json-string
func getJsonObject(uglyString: String, stringIncludesTopic: Bool = false) -> (String?, JSON) {
    var topic: String? = nil
    var message = uglyString
    if stringIncludesTopic{
        // Incoming messages from iOS and python are a bit different. From python there are whitespaces between key: and value. For iOS no such whitespaces occur.
        // Start by getting topic, slice string on every whitespace. First occurance is topic:
        let strArray = message.components(separatedBy: " ")
        topic = strArray[0]
        
        // Start over, drop the first topic characters including the whitespace after topic
        message = String(message.dropFirst(topic!.count))
        // Remove all whitespaces
        message = message.replacingOccurrences(of: " ", with: "")
    }
    else{
        // Messages received on REQ socket needs to be modified before parsing.
        //Clean up leading, trailing and replace som backslashes
        message = cleanUpString(str: message)
    }
    // Parse string into JSON
    guard let data = message.data(using: .utf8) else {return (topic, JSON())}
    guard let json = try? JSON(data: data) else {return (topic,JSON())}
    return (topic, json)
}

// Formatting for publish. This works iOS to iOS and iOS to python
//**********************************************************************
// Get ZMQ string consisting of the topic and the serialized json-object
func getJsonStringAndTopic(topic: String, json: JSON) -> String{
    let str1 = json.rawString(.utf8, options: .sortedKeys)!
    let str2 = topic + " " + str1
    return str2
}

//*************************************************
// Get the ZMQ string of the serialized json-object
func getJsonString(json: JSON) -> String{
    let str1 = json.rawString(.utf8, options: .withoutEscapingSlashes)!
    let str2 = uglyfyString(string: str1)
    let str3 = addQuotations(string: str2)
    return str3
}

//**************************
// Create a json ack message
func createJsonAck(_ str: String) -> JSON {
    var json = JSON()
    json["fcn"] = JSON("ack")
    json["call"] = JSON(str)
    return json
}

//***************************
// Create a json nack message
func createJsonNack(fcn: String, description: String) -> JSON {
    var json = JSON()
    json["fcn"] = JSON("nack")
    json["call"] = JSON(fcn)
    json["description"] = JSON(description)
    return json
}

//********************
// Print a json-object
func printJson(jsonObject: JSON){
    print(jsonObject)
}

//******************************
// Encode data object to base 64
func getBase64utf8(data: Data)->String{
    let base64Data = data.base64EncodedString()
    return base64Data
}

// ************************************
// Decode base64 encoded string to data
func decodeBase64String(base64Str: String)->Data{
    if let data = Data(base64Encoded: base64Str){
        return data
    }
    else{
        return Data()
    }
}

// **********************************************
// Print ZeroMQ library and our framework version
func printZmqVersions(){
    let (major, minor, patch, versionString) = SwiftyZeroMQ.version
    print("ZeroMQ library version is \(major).\(minor) with patch level .\(patch)")
    print("ZeroMQ library version is \(versionString)")
    print("SwiftyZeroMQ version is \(SwiftyZeroMQ.frameworkVersion)")
}

// Return IP address of WiFi interface (en0) as a String, or `nil` https://stackoverflow.com/questions/30748480/swift-get-devices-wifi-ip-address
func getIPAddress() -> String {
    var address = ""
    var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
    var interfaces = JSON()
    if getifaddrs(&ifaddr) == 0 {
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { return "" }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) { //|| addrFamily == UInt8(AF_LINK){
                
                // wifi = ["en0"]
                // wired = ["en1", "en2", "en3", "en4"]
                // cellular = ["pdp_ip0","pdp_ip1","pdp_ip2","pdp_ip3","pdp_ip4"]
                // VPN1? = ["ipsec0", "ipsec1","ipsec3","ipsec4","ipsec5","ipsec7"]
                // VPN2 = ["utun0", "utun1", "utun2", "utun3"]
                
                let name: String = String(cString: (interface.ifa_name))
                //print("name: ",name)
                if  name == "en0" || name == "pdp_ip0" || name.contains("utun"){
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t((interface.ifa_addr.pointee.sa_len)), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    let hostnameStr = String(cString: hostname)
                    // If the identified interface is not a mac address (conatins :), suggest it as an ip
                    if !hostnameStr.contains(":"){
                        // Inferface is VPN. Sometimes two utun networkdev are found, 10.8.0.10 and the dronenet ip.
                        if name.contains("utun"){
                            interfaces["utun"] = JSON(hostnameStr)
                        }
                        // Interface is local network
                        else if name.contains("en"){
                            interfaces["en"] = JSON(hostnameStr)
                        }
                        // Interface is mobile network
                        else if name.contains("pdp") {
                            interfaces["pdp"] = JSON(hostnameStr)
                        }
                        // For debug, set if statement to true
                        else{
                            address = hostnameStr
                            print("Name: ", name, " Address: :", address)
                        }
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
    }
    
    // prioritize return string as: 1. VPN 2. Local network 3. mobile connection
    if interfaces["utun"].exists(){
        print("VPN connection identified")
        return interfaces["utun"].stringValue
    }
    else if interfaces["en"].exists(){
        print("Wifi connection identified")
        return interfaces["en"].stringValue
    }
    else if interfaces["pdp"].exists(){
        print("Cellular connection identified")
        return interfaces["pdp"].stringValue
    }
    else{
        print("Connection not identified")
        return "??: " + address
    }
}

// Calc CRM-port based on subnet of this device (what VPN network is used?)
func calcCRMPort(ipStr: String) -> Int? {
    let splits = ipStr.split(separator: ".")
    if let subNet = Int(splits[2]){
        return subNet*100
    }
    else{
        return nil
    }
}
