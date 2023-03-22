//
//  DSSViewController.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-16.
//


// header serach path "$(SRCROOT)/Frameworks/VideoPreviewer/VideoPreviewer/ffmpeg/include"/**
// $(inherited) $(PROJECT_DIR)/Frameworks/VideoPreviewer/VideoPreviewer/ffmpeg/lib


// framework search paht debug : $(inherited) $(PROJECT_DIR)/Frameworks $(PROJECT_DIR)/../DJIWidget/**
// feamework search path release : $(inherited) $(PROJECT_DIR)/Frameworks $(PROJECT_DIR)/../DJIWidget/**
import UIKit
import DJIUXSDK
import DJIWidget
import SwiftyZeroMQ5 // https://github.com/azawawi/SwiftyZeroMQ  good examples in readme
import SwiftyJSON // https://github.com/SwiftyJSON/SwiftyJSON good examples in readme

// ZeroMQ https://stackoverflow.com/questions/49204713/zeromq-swift-code-with-swiftyzeromq-recv-still-blocks-gui-text-update-even-a
// Build ZeroMQ https://www.ics.com/blog/lets-build-zeromq-library

// Background process https://stackoverflow.com/questions/24056205/how-to-use-background-thread-in-swift
// Related issue https://stackoverflow.com/questions/49204713/zeromq-swift-code-with-swiftyzeromq-recv-still-blocks-gui-text-update-even-a

// Generate App icons: https://appicon.co/

// Look into media download scheduler: fetchFileDataWithOffset:updateQueue:updateBlock

public class DSSViewController: UIViewController, Storyboarded {
    //**********************
    // Variable declarations
    
    var brighttemp: UInt = 25
    
    weak var coordinator: MainCoordinator?
    var debug: Int = 0                  // 0 - off, 1 debug to screen, 2 debug to StatusLabel (user)
    var sim: Bool = false               // Flag to indicate if we are in simulated mode or not
    var tictoc = Tictoc()               // Tictoc object for timing events
    
    
    var resetKalmanFlag = false
    
    
    @IBOutlet var fpvView: UIView!
    var fpvViewController = DUXFPVViewController()
    
    @IBOutlet var topBarView: UIView!
    var topBarViewController = DUXStatusBarViewController()
    
    var aircraft: DJIAircraft?
    
    var leftTicker = 0
    var rightTicker = 0
    
    var lockedButtonsList: [UIButton] = []                          // List of buttons to lock/unlock
    var lockedButtonTicker: Int = 0                                 // Counter.
    
    // TODO - for test/demo only
    var overrideBattery = false
    
    // Zero MQ
    var context: SwiftyZeroMQ.Context = try! SwiftyZeroMQ.Context()
    //var poller: SwiftyZeroMQ.Poller = SwiftyZeroMQ.Poller()
    
    // ZeroMQ Publishers
    var infoPub = Publisher()                                   // For publishing info
    var infoPubPort = 5558                                      // Publish info port
    var dataPub = Publisher()                                   // For publishing data
    var dataPubPort = 5559                                      // Publish data port
    var logPub: Publisher?                                      // LogPublisher that publishes all zmq
    var logPubPort = 5566
    
    // ZeroMQ subscribers
    var streamSub: Subscriber?                                  // For subscribing to pos data
    
    // ZeroMQ crm req
    var crm = Requestor()                                       // The requestor to the crm
    var crmPort = 5556                                          // The port of the crm
    var crmInUse = false                                        // Flag for crm in use or not
    var crmHeartBeatPeriod: Double = 10                         // Heartbeat period
    var crmLinkLostTime: Double = 20                            // Link lost time for crm
    
    var clients: [String: Subscriber] = [:]                     // List of other clients (other dss)
    
    // ZeroMQ app replyer
    var cmdRep = Replier()                                      // The replier of the application
    var cmdRepPort: Int = 5557                                  // The standard port of the replier
    
    var subscriptions = Subscriptions()                         // For info subscription from application
    var heartBeat = HeartBeat()
    var inControls = "PILOT"
    
    var pitchRangeExtension_set: Bool = false
    var nextGimbalPitch: Int = 0
    var preCalibGimbalPitchRef: Double = 0                         // Memory for resetting gimbal pitch after calibration.
    
    //var gimbalcapability: [AnyHashable: Any]? = [:]
    
    var copter = CopterController()                             // Helper object for copter (flightcontroller)
    var camera = CameraController()                             // Helper object for camera
    var battery = BatteryController()                           // Helper for battery
    var accessory = AccessoryController()                       // Helper for accessories
    var capabilities: [String] = []                             // List of capabilities
    
    var initModLocked = true                                    // Flag for locking adjustment of init heading
    var ownerID: String = ""                                    // The owner of the dss, only this app can control the dss
    var connectionType = ""                                     // String for connection type
    var monitorConnectionTypeEnabled = false                    // Flag for controlliong connectio Type thread
    var monitorDSSClientsEnabled = false                        // Thread flag for maintaining DSS list from crm, collisionAvoidance
    
    var GPSKalmanTimer: Timer?                                     // Timed thread for GPS kalmanFilter
    var GPSKalmanTimeInterval = 0.1                                // GSP Kalman filter loop time
    var LLAStreamMeasurement = CLLocation()                     // An object to store the last measurement
    var newLLAMeasurement = false                               // A flag to see if there is a new meaurement
    var streamNorthBias: Double = 0                                   // An adjustable bias for followstream
    var logQueue = Queue<String>()                              // A queue for log prints, to be able to control update rate of log messages
    var logTimer: Timer?                                        // Timer for updating log table view (to often causes crashes)
    
    
    
    // Steppers
    @IBOutlet weak var leftStepperStackView: UIStackView!
    @IBOutlet weak var leftStepperLabel: UILabel!
    @IBOutlet weak var leftStepperName: UILabel!
    @IBOutlet weak var leftStepperButton: UIStepper!
    @IBOutlet weak var rightStepperStackView: UIStackView!
    @IBOutlet weak var rightStepperLabel: UILabel!
    @IBOutlet weak var rightStepperName: UILabel!
    @IBOutlet weak var rightStepperButton: UIStepper!
    @IBOutlet weak var extraStepperStackView: UIStackView!
    @IBOutlet weak var extraStepperLabel: UILabel!
    @IBOutlet weak var extraStepperName: UILabel!
    @IBOutlet weak var extraStepperButton: UIStepper!
    
    
    @IBOutlet weak var idLabel: UILabel!
    @IBOutlet weak var ownerLabel: UILabel!
    @IBOutlet weak var connectionLabel: UILabel!
    
    @IBOutlet weak var headingLabel: UILabel!               // Current heading in center of screen
    @IBOutlet weak var posXLabel: UILabel!                  // Current X pos
    @IBOutlet weak var posYLabel: UILabel!                  // Current Y pos
    @IBOutlet weak var posZLabel: UILabel!                  // Current Z pos
    @IBOutlet weak var localYawLabel: UILabel!              // Current xyz heading
    
    //    @IBOutlet declaration: ImageView
    //    @IBOutlet weak var previewImageView: UIImageView!
    
    @IBOutlet weak var controlsButton: UIButton!            // The controls button
    @IBOutlet weak var DuttLeftButton: UIButton!            // The Dutt left button
    @IBOutlet weak var DuttRightButton: UIButton!           // The Dutt right button
    @IBOutlet weak var modInitButton: UIButton!             // The initMod button for controlling mods of init heading
    @IBOutlet weak var xCloseButton: UIButton!
    
    @IBOutlet weak var simBatteryButton: UIButton!
    
    @IBOutlet weak var unlockButton: UIButton!
    
    @IBOutlet weak var spotButton: UIButton!
    
    // TableView (failed to set corner radius, not used now.
    @IBOutlet weak var logTableView: UIView!
    
    // Widget outlsets
    @IBOutlet weak var compassWidget: DUXCompassWidget!
    @IBOutlet weak var mapWidget: DUXMapWidget!
    
    @IBOutlet weak var sdLabel: UILabel!
    
    
    
    // Just to test an init function
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    
    //**********************
    // Fucntion declarations
    //**********************
    
    //***********************
    // Set who is in controls
    func setInControls(_ str: String){
        // Set inControls
        self.inControls = str
        // Additional actions
        switch str{
        case "APPLICATION":
            // Track gimbal commands sent by APPLICATION
            self.copter.gimbal.gimbalTrack = true
        case "PILOT":
            // Give gimbal control to PILOT
            self.copter.gimbal.gimbalTrack = false
        case "DSS":
            // Override PILOT gimbal commands
            self.copter.gimbal.gimbalTrack = true
            
        default:
            print("Error, no such user can be inControls")
        }
    }
    
    
    @IBAction func unlockButtonPressed(_ sender: UIButton) {
        lockedButtonTicker += 1
        if lockedButtonTicker > lockedButtonsList.count{
            lockedButtonTicker = 0
        }
        unlockSpecialButtons()
    }
    
    // **********************************
    // Unlock special buttons, one by one
    func unlockSpecialButtons(){
        // The calling functio will handle the ticker
        var i = 0
        for button in lockedButtonsList{
            if i == lockedButtonTicker{
                enableButton(button)
                button.setImage(UIImage(systemName: "lock.open.fill"), for: .normal)
            }
            else{
                disableButton(button)
                button.setImage(UIImage(systemName: "lock.fill"), for: .normal)
            }
            i += 1
        }
    }
    
    // *************************************
    // Hide/show special buttons, one by one
    func hideSpecialButtons(hide: Bool){
        // The calling functio will handle the ticker
        var i = 0
        for button in lockedButtonsList{
            button.isHidden = hide
            i += 1
        }
    }
    
    @IBAction func spotButtonPressed(_ sender: UIButton) {

        if self.accessory.spotlight != nil{
            let enabled = self.accessory.spotlight!.enabled
            self.accessory.spotlight!.setEnable(enable: !enabled)
            self.accessory.spotlight!.setBrightness(brightness: 100)
            print("The brightness state is: ", self.accessory.spotlight!.getBrightness)
        }
    }
    
    //************************************
    // Disable button and change colormode
    func disableButton(_ button: UIButton!){
        button.isEnabled = false
        button.backgroundColor = UIColor.lightGray
    }
    
    //***********************************
    // Enable button and change colormode
    func enableButton(_ button: UIButton!){
        button.isEnabled = true
        button.backgroundColor = UIColor.systemOrange
    }
    
    //***********************************************
    // Deactivate the sticks and disable dutt buttons
    func deactivateSticks(){
        //GUI handling
        
        //DeactivateSticksButton.backgroundColor = UIColor.lightGray
        //ActivateSticksButton.backgroundColor = UIColor.systemBlue
    }
    
    //****************************************************************
    // Activate sticks and dutt buttons, reset any velocity references
    func activateSticks(){
        //GUI handling
        //ActivateSticksButton.backgroundColor = UIColor.lightGray
        //DeactivateSticksButton.backgroundColor = UIColor.systemRed

    }
    
    //*****************************************************
    // Support function to step through gimbal pitch values
    func updateGnextGimbalPitch(){
        self.nextGimbalPitch -= 20
        if self.nextGimbalPitch < -40 {
            self.nextGimbalPitch = 20
        }
    }
    
    
    // Function could be redefined to send a notification that updates the GUI
    //****************************************************
    // Print to terminal and display
    func log(_ str: String){
        // CACurrentMediaTime().description, current time in seconds. Offset by a start time if used.
        print(str)
        logQueue.enqueue(str)
    }
    
    // Update log not more often than 2Hz
    @objc func fireLogQueueTimer(){
        // If there is a log item i queue, dequeue and send it to tableViewController
        if logQueue.head != nil{
            guard let str = logQueue.dequeue() else {return}
            NotificationCenter.default.post(name: .didNewLogItem, object: self, userInfo: ["logItem": str])
        }
    }
    
    func printDB(_ str: String){
        if debug == 1 {
            print(str)
        }
        if debug == 2 {
            self.log(str)
        }
        else{
            // Nothing
        }
    }
    
    func setSDStatus(occupied: Bool){
        Dispatch.main{
            if occupied{
                self.sdLabel.backgroundColor = .systemRed
                print("SD card status occupied")
            }
            else{
                self.sdLabel.backgroundColor = .systemGreen
                print("SD card status available")
            }
        }
    }
    
    func followStream(enable: Bool, ip: String, port: Int, monitorOnly: Bool = false){
        if enable {
            if streamSub == nil{
                streamSub = Subscriber()
            }
            else{
                print("Error followStream: Trying to enable follow stream when streamSub is already defined")
            }
            
            // Open a new socket and connect to it
            streamSub!.setupSubscriber(name: "LLA_foll_Sub", zmqContext: self.context, ip: ip, port: port, id: crm.id)
            if streamSub!.initSubscriber(){
                print(streamSub!.name, "initiated with:", streamSub!.endPoint)
            }
            
            // Subscribe to LLA topic
            streamSub!.subscribe(topic: "LLA")
            print(streamSub!.name, " subscribed to LLA topic")
            
            // Dispatch the kalmanFilter timer thread
            
            let timeInterval = 0.1
            let info = ["timeInterval": timeInterval]
            
            if self.GPSKalmanTimer == nil{
                // Dispatch the kalman filter timer thread, kill with stopFollowStreamSubscription
                Dispatch.main{
                    self.GPSKalmanTimer = Timer.scheduledTimer(timeInterval: self.GPSKalmanTimeInterval, target: self, selector: #selector(self.GPSKalmanFilterThread), userInfo: info, repeats: true)
                }
            }
            else {
                print("Error: oops GPSKalman Timer was not nil")
            }
             
            // Dispatch the gps Subscription thread feeding the filter, kill with subscribeEnable
            Dispatch.background {
                self.gpsSubThread(subscriber: self.streamSub!)
            }
            
            // Dispatch the Controller timer controlling the dss
            Dispatch.main{
                self.copter.startFollowStream()
            }
        }
        
        // User want to disable follow stream
        else{
            // Stop kalman filter thread and close the subscription socket.
            self.stopFollowStreamSubscription()
            self.log("stopped follow stream subscription")
            
            // Enable idle control
            Dispatch.main{
                self.copter.idleCtrl()
            }
        }
    }
    
    // Stops the kalman filter thread and closes the socket listening to the stream
    func stopFollowStreamSubscription(){
        // Stop the gpsKalmanFilterThread that updates the filter
        if GPSKalmanTimer != nil{
            self.GPSKalmanTimer!.invalidate()
            self.GPSKalmanTimer = nil
            print("KalmanTimer thread set to nil")
        }
        
        // Close the socket, this set subscirbe enable to false and waits for timeout + some time
        if streamSub != nil{
            streamSub!.close()
            streamSub = nil
            self.newLLAMeasurement = false
            print("streamSubscriber set to nil")
        }
        
        // Reset the stream filter.
        if self.copter.pattern.stream.posFilter != nil{
            self.copter.pattern.stream.posFilter = nil
            print("streamFilter set to nil")
        }
    }
    
    @objc func GPSKalmanFilterThread(_ timer: Timer){
        // This is a timer, it will loop at timeInterval set
        // Check if filter is initialised
        if self.copter.pattern.stream.posFilter == nil{
            // Pick up the timeInterval
            guard let info = GPSKalmanTimer?.userInfo as? [String: Double] else {print("OOps"); return}
            guard let timeInterval = info["timeInterval"] else
                {
                    print("Send kalman time interval properly, stopping filter")
                    return
                }
            // Filter not initialised, is there a measurement?
            if self.newLLAMeasurement{
                // Initialise
                self.copter.pattern.stream.posFilter = GPSKalmanFilterAcc(initialLocation: self.LLAStreamMeasurement, timeInterval: timeInterval)
                self.newLLAMeasurement = false

            }
            return
        }
        
        // Reset if necessary
        if self.copter.pattern.stream.posFilter!.resetNeeded(){
            if self.newLLAMeasurement{
                self.copter.pattern.stream.posFilter!.reset(newStartLocation: self.LLAStreamMeasurement)
                self.newLLAMeasurement = false
            }
        }
        
        self.copter.pattern.stream.posFilter!.predict()
        
        if newLLAMeasurement{
            self.copter.pattern.stream.posFilter!.update(currentLocation: self.LLAStreamMeasurement)
            newLLAMeasurement = false
        }
    }

    // Make sure local clients list is the same as the retreived list of clients (add or remove diff)
    // Start subscription thread for each client in the list
    func updateClientsList(crmClients: JSON, verbose: Bool = true){
        // Keep count
        let numClients = self.clients.count
        // Clients arg cannot be empty since this dss is in the list
        for (key, value) in crmClients{
            if key == self.crm.id{
                // Don't put my self into the list
                continue
            }
            if self.clients[key] != nil{
                // Client already in local client list
                continue
            }
            if !key.hasPrefix("dss"){
                // Key is not a dss
                continue
            }
            if verbose{
                self.log("New dss in system " + key)
            }
            // Get info from dss to find subcribe port
            let req = Requestor()
            self.printDB("Going through clients, next: " + key)
            req.setupRequestor(name: key + "_req", zmqContext: self.context, ip: value["ip"].stringValue, port: value["port"].intValue, logPublisher: logPub, id: self.crm.id)
            if req.initRequestor(heartBeatPeriod: 0, linkLostTime: 10){
                print(req.name + " Init " + req.endPoint)
            }
            else{
                self.log(req.name + "Failed to initiate with" + req.endPoint)
                self.log("Warning: Could not connect to " + key)
                continue
            }
            
            // Get sub port and enable STATE stream. Close req socket.
            var subPort: Int? = nil
            var attempt = 0
            while subPort == nil && attempt != 3{
                subPort = req.get_info(pubType: "info")
                if !req.data_stream(stream: "STATE", enable: true){
                    self.log("Warning: Could not enable STATE data stream")
                    subPort = nil
                }
                attempt += 1
            }
            req.close()
            
            if subPort == 0{
                self.log("Error: Can't connect. No CA for " + key)
                continue
            }
            
            
            let dssSub = Subscriber()
            let subscriberName = key + "_SUB"
            dssSub.setupSubscriber(name: subscriberName, zmqContext: context, ip: value["ip"].stringValue, port: subPort!, id: crm.id, timeout: 500)
            if dssSub.initSubscriber(){
                print(dssSub.name + " initiated to " + dssSub.endPoint)
                dssSub.subscribe(topic: "STATE")
                // Start the subscription thread for the dss
                Dispatch.background{
                    self.clientPosSubThread(dssId: key, subscriber: dssSub)
                }
            }
            // Add client to client list TODO, is the socket used from the dict?
            self.clients[key] = dssSub
        }
        // Remove clients form local list that is not in crm list
        for (key, socket) in self.clients{
            // If key from local list is not in crmList, close and toss
            if !crmClients[key].exists(){
                socket.subscribeEnable = false
                socket.close()
                self.clients.removeValue(forKey: key)
            }
        }
        
        let newNumClients = self.clients.count
        if verbose{
            let diff = newNumClients - numClients
            if diff > 0{
                self.log(String(newNumClients) + " other drones active ( +" + String(diff) + ")")
            }
            else{
                self.log(String(newNumClients) + " other drones active (" + String(diff) + ")")
            }
        }
        
        print("Client list updated:")
        for (client, _) in self.clients{
            print(client)
        }
    }
    
    
    // Thread for monitoring clients list of CRM. Takes a snapshot and then subscribes to changes
    func monitorDSSClientsThread(){
        self.monitorDSSClientsEnabled = true

        // Initiate clients list with crm request
        let clients = self.crm.clients(filter: "dss")
        updateClientsList(crmClients: clients, verbose: false)

        // Maintain clients list by subscribing to changes
        
        // Create subscription socket to crm, subscribe to clients list.
        guard let crmInfoPort = self.crm.get_info(pubType: "info") else {
            self.log("Warning: Could not retreive crm info port, new clients will not be Collision Avoided")
            return
        }
        let crmSub = Subscriber()
        crmSub.setupSubscriber(name: "CrmInfo_SUB ", zmqContext: self.context, ip: self.crm.ip, port: crmInfoPort, id: self.crm.id)
        if crmSub.initSubscriber(){
            print(crmSub.name + "initiated to " + crmSub.endPoint)
            crmSub.subscribe(topic: "clients")
            print("Listening for client changes from CRM")
        }
        
        // Monitor if any clients connects or disconnects to/from crm
        while self.monitorDSSClientsEnabled && crmSub.subscribeEnable{
            do{
                // Try to receive a message
                let _message: String? = try crmSub.socket!.recv(bufferLength: 65536, options: .none)
                if crmSub.subscribeEnable == false{
                    print(crmSub.name, " Exiting thread")
                    return
                }
                // Parse message
                let (topic,json_m) = getJsonObject(uglyString: _message!, stringIncludesTopic: true)
                // Publish to log
                if logPub != nil {
                    // Create dummy json for log and publish
                    var logJson = json_m
                    logJson["theTopic"] = JSON(topic ?? "")
                    logJson["time"] = JSON(CACurrentMediaTime())
                    _ = logPub?.publish(topic: crmSub.name, json: logJson)
                }
                if topic == nil{
                    print("Found no topic, the parsed json_m: ", json_m)
                }
                
                else if topic == "clients"{
                    // Maintain the client list
                    updateClientsList(crmClients: json_m)
                }
            }
            catch{
                // ReceiveTimeout occured (the inteded functionality)
                // print(subscriber.name, " Nothing to receive")
                _ = 1
            }
        }
        
        // Close crmSub socket
        crmSub.close()

        // Close socketes and clear clitenst list
        print("Close sub sockets to clients")
        for (key, socket) in self.clients{
            // Could be run in background to save some time, but throws error because context is gone. TBD
            socket.close()
            self.clients.removeValue(forKey: key)
        }
        print("Exiting monitorDSSClientsThread")
    }
    
    // Thread to collect positoin data from a client
    func clientPosSubThread(dssId: String, subscriber: Subscriber){
        var lastUpdate = CACurrentMediaTime()
        let maxTime: Double = 5
        
        while subscriber.subscribeEnable && self.monitorDSSClientsEnabled{
            do{
                // Try to receive a message
                let _message: String? = try subscriber.socket!.recv(bufferLength: 65536, options: .none)
                if subscriber.subscribeEnable == false{
                    print(subscriber.name, " Exiting thread")
                    return
                }
                // Parse message
                let (topic,json_m) = getJsonObject(uglyString: _message!, stringIncludesTopic: true)
                // Publish to log
                if logPub != nil {
                    // Create dummy json for log and publish
                    var logJson = json_m
                    logJson["theTopic"] = JSON(topic ?? "")
                    logJson["time"] = JSON(CACurrentMediaTime())
                    _ = logPub?.publish(topic: subscriber.name, json: logJson)
                }
                if topic == nil{
                    print("Found no topic, the parsed json_m: ", json_m)
                }
                else if topic == "STATE"{
                    lastUpdate = CACurrentMediaTime()
                    // If already tracking this dss, update its location
                    if self.copter.clientLoc[dssId] != nil{
                        //self.copter.clientLoc[dssId]!.setUpFromJsonWp(jsonWP: json_m, defaultSpeed: 1, initLoc: self.copter.initLoc)
                        self.copter.clientLoc[dssId]!.updateSTATEFromJsonWp(jsonWP: json_m)
                    }
                    // If not tracking this dss, initiate a MyLocation and start tracking
                    else{
                        print("Creating new dss loc for ", dssId)
                        let pos = MyLocation()
                        pos.setUpFromJsonWp(jsonWP: json_m, defaultSpeed: 1, initLoc: self.copter.initLoc)
                        self.copter.clientLoc[dssId] = pos
                    }
                }
            }
            catch{
                // ReceiveTimeout occured (the inteded functionality)
                // print(subscriber.name, " Nothing to receive")
                
                if CACurrentMediaTime() - lastUpdate > maxTime {
                    // Check if dssId is still registered with crm
                    // This can cause a lot of requests
                    // If no updates for x seconds, check that dss is still registered to crm.
                    print("Time since last pos from : ", dssId, ": ", CACurrentMediaTime() - lastUpdate)
                    print("Checking with crm if dss is still registered")
                    // Update lastUpdate to not spam crm.
                    lastUpdate = CACurrentMediaTime()
                    if crm.clients(filter: dssId).isEmpty{
                        // Client is not registered, stop listening (and stop avoiding its last pos).
                        subscriber.subscribeEnable = false
                    }
                }
            }
        }
        
        // Clear from clientsLoc list
        let keyExists = self.copter.clientLoc[dssId] != nil
        if keyExists{
            //if self.copter.clientLoc[dssId] != nil{
            if self.copter.clientLoc[dssId] != nil{
                self.copter.clientLoc[dssId] = nil
            }
            else{
                self.log("dssId " + dssId + " is nil")
            }
        }
        else{
            self.log("dssId " + dssId + " key does not exist?")
        }
    }
    
    
    func gpsSubThread(subscriber: Subscriber){
        // This should not need protection from nil. Close() should set subscribEnable and wait more than receive timeout.
        while subscriber.subscribeEnable{
            do{
                // Try to receive a message
                let _message: String? = try subscriber.socket!.recv(bufferLength: 65536, options: .none)
                if subscriber.subscribeEnable == false{
                    print(subscriber.name, "Exiting thread")
                    return
                }
                // Parse message
                let (topic,json_m) = getJsonObject(uglyString: _message!, stringIncludesTopic: true)
                // Publish to log
                if logPub != nil {
                    // Create dummy json for log and publish
                    var logJson = json_m
                    logJson["theTopic"] = JSON(topic ?? "")
                    logJson["time"] = JSON(CACurrentMediaTime())
                    _ = logPub?.publish(topic: subscriber.name, json: logJson)
                }
                if topic == nil{
                    print("Found no topic, the parsed json_m: ", json_m)
                }
                else if topic == "LLA"{
                    // Decode the stream message and apply pattern
                    let lat = json_m["lat"].doubleValue + self.streamNorthBias*0.00001
                    let lon = json_m["lon"].doubleValue
                    let alt = json_m["alt"].doubleValue
                    //let yaw = json_m["yaw"].doubleValue
                    
                    // Puth the strem data in a CLLoaction object and set the flag
                    let streamLocation: CLLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat,longitude: lon), altitude: alt, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: Date())
                    
                    // Stor the measurement and signal that it is available
                    self.LLAStreamMeasurement = streamLocation
                    self.newLLAMeasurement = true
                }
            }
            catch{
                
                
                print(subscriber.name, " did not receive anything")
                
                
                // ReceiveTimeout occured (the inteded functionality)
                // print(subscriber.name, " Nothing to receive")
            }
        }
        print(subscriber.name, "Exiting thread 2")
    }
    
    // ***************************************************************
    // Background thread for publishing battery status on subscription
    func pubBatInfoThread(){
        var json_m = JSON()
        var t: Double = 0
        var rTime: UInt = 0
        var overrideBatTime: UInt = 300
        while self.subscriptions.battery{
            // Remaining flight time in seconds
            if overrideBattery{
                overrideBatTime -= 10
                rTime = overrideBatTime
            }
            else{
                rTime = self.copter.flightControllerState.goHomeAssessment.remainingFlightTime
            }
            // Dont publish if rTime not known
            if rTime != 0{
                json_m["remaining_time"] = JSON(rTime)
                // Remaining voltage
                json_m["voltage"] = JSON(self.battery.batteryState.cellVoltageLevel)
                // Publish
                _ = self.infoPub.publish(topic: "battery", json: json_m)
            }
            // Sleep 10s in short periods to be able to exit quicker
            t = 0
            while t <= 10 && self.subscriptions.battery{
                // Sleep 0.5s
                usleep(500000)
                t += 0.5
            }
        }
        print("Exiting battery pub thread")
    }
    
    // *****************
    // Heart beat thread
    func startHeartBeatThread(){
        Dispatch.background{
            self.heartBeats()
        }
    }
    
    func heartBeats() {
        // Wait for first heartbeat
        while !self.heartBeat.beatDetected {
            usleep(1000000)
        }
        print("heartBeats: Starting to monitor heartBests")
        
        // Monitor heartbeats
        while self.heartBeat.alive() {
            if cmdRep.replyEnable == false{
                // Reply thread is shut down. No need to monitor heartbeats
                return
            }
            // If crm is owner and dss on ground - Restart heartbeats state machine.
            if ownerID == "crm" && !copter.flightControllerState.areMotorsOn {
                heartBeat.beatDetected = false
                startHeartBeatThread()
                return
            }
            usleep(150000)
            // User disconnect will call crm immidiatly on receive of comma
        }
        
        // Lost 1 time
        if self.crmInUse{
            // If the link is lost for the first time
            if !self.heartBeat.lostOnce {
                // TODO: call crm
                if self.crm.appLost(){
                    self.log("App link lost. crm will take control")
                    // reset lost link counter
                    self.heartBeat.lostOnce = false
                }
                else{
                    self.log("Link lost to APP and crm")
                }
                // Reset the timer by sending a new beat.
                self.heartBeat.newBeat()
                // Set lostOnce flag
                self.heartBeat.lostOnce = true
                Dispatch.background{
                    self.heartBeats()
                }
                return
            }
        }
        
        // Lost 2 times
        self.log("Link lost. Autopilot Rtl")
        
        if self.inControls != "PILOT"{
            Dispatch.main{
                self.takeControls(toControls: "DSS")
            }
            // Activate RTL
            Dispatch.main{
                self.copter.rtl()
            }
        }
        // Reset the heartbeat state diagram. Wait for new heartbeats
        self.heartBeat.beatDetected = false
        Dispatch.background{
            self.heartBeats()
        }
        return
    }
    
    
    // *********************************
    // Change owner convinience function
    func setOwner(id: String){
        if ownerID != id{
            ownerID = id
            self.log("Owner changed to: " + id)
            Dispatch.main{
                self.ownerLabel.text = self.ownerID
            }
        }
    }
    
    
    // If function is not used in more than parser, put it in parser.
    // Function checks if the ownerID and the id from a request matches or not.
    func isOwner(id: String)->Bool{
        if id == self.ownerID{
            // Owner match
            return true
        }
        else{
            // Owner mismatch
            print("Requestor owner: ", id, " registered owner: ", self.ownerID)
            return false
        }
    }
    
    // ***************************************************************************
    // Function the evaluates if the position is initialized or not.
    // Should/can we require takeoff alt to be set here too? That would be great..
    func navReady()->Bool{
        var isReady = false
        let (lat, lon, _) = self.copter.getCurrentLocation()
        // If both lat and lon are not nil and not 0, nav is ready
        if ((lat != nil && lat != 0) && (lon != nil && lon != 0)) {
            isReady = true
        }
        return isReady
    }
    
    // MARK: Reply thread
    // ****************************************************
    // zmq reply thread that reads command from applictaion
    func readSocket(replier: Replier){
        var fromOwner = false
        var requesterID = ""
        var nackOwnerStr = ""
        var messageQualifiesForHeartBeat = false
        
        var simSpotlightEnable = false
        var simSpotlightBrightness = 1
        
        while replier.replyEnable{
            do {
                let _message: String? = try replier.socket!.recv(bufferLength: 32768, options: .none) // buffer 4096 ~30 waypoints
                
                if replier.replyEnable == false{ // Since code can halt on socket.recv(), check if input is still desired
                    print(replier.name, "Exithing thread")
                    return
                }
                // A message is received.
                
                // Parse and create an ack/nack
                let (_, json_m) = getJsonObject(uglyString: _message!)
                if logPub != nil {
                    var logJson = json_m
                    logJson["time"] = JSON(CACurrentMediaTime())
                    _ = logPub?.publish(topic: replier.name + "_r", json: logJson)
                }
                
                if json_m["fcn"] != "heart_beat"{
                    self.printDB("Received message: " +  _message!)
                    //print(json_m)
                }
                var json_r = JSON()
                
                // Update message owner status
                requesterID = json_m["id"].stringValue
                if isOwner(id: requesterID){
                    fromOwner = true
                }
                else {
                    fromOwner = false
                    nackOwnerStr = "Requester (" + requesterID + ") is not the DSS owner"
                    print(nackOwnerStr, json_m)
                }
                
                // Message valid for heartbeat? (and part of state machine)
                messageQualifiesForHeartBeat = false
                // If heart beat is detected, just look if requestor is owner
                if heartBeat.beatDetected{
                    if fromOwner{
                        messageQualifiesForHeartBeat = true
                    }
                }
                // Heartbeat not yet detected, onwer is not crm - look if requestor is owner
                else if ownerID != "crm"{
                    if fromOwner{
                        messageQualifiesForHeartBeat = true
                    }
                }
                // Heartbeat not yet detected, onwerID is crm - look if requestor is crm and message is set_owner
                else {
                    if json_m["id"].stringValue == "crm" && json_m["fcn"] == "set_owner"{
                        messageQualifiesForHeartBeat = true
                    }
                    
                }
                
                switch json_m["fcn"]{
                case "heart_beat":
                    self.printDB("Cmd: heart_beat")
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "heart_beat", description: nackOwnerStr)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("heart_beat")
                    }
                    
                case "get_info":
                    self.printDB("Cmd: get_info")
                    // Accept command
                    json_r = createJsonAck("get_info")
                    json_r["id"] = JSON(crm.id)
                    json_r["info_pub_port"] = JSON(infoPub.port)
                    json_r["data_pub_port"] = JSON(dataPub.port)
                    json_r["log_pub_port"] = JSON(logPubPort)
                    
                case "who_controls":
                    // Print to display if application does not have the controls
                    if inControls == "APPLICATION"{
                        print("Cmd: who_controls")
                    }
                    else{
                        self.log("Cmd: who_controls")
                    }
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("who_controls")
                    json_r["in_controls"].stringValue = self.inControls
                    
                case "get_owner":
                    printDB("Cmd: get_owner")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_owner")
                    json_r["owner"].stringValue = self.ownerID
                    
                case "set_owner":
                    log("Cmd: set_owner")
                    // Check if crm is the caller
                    if json_m["id"].stringValue != "crm"{
                        json_r = createJsonNack(fcn: "set_owner", description: "Requestor is not crm")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("set_owner")
                        setOwner(id: json_m["owner"].stringValue)
                    }
                    
                case "set_geofence":
                    self.log("Cmd: set_geofence")
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_geofence", description: nackOwnerStr)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("set_geofence")
                        // Parse
                        let radius = json_m["radius"].doubleValue
                        var height: [Double] = [0,0]
                        height[0] = json_m["height_low"].doubleValue
                        height[1] = json_m["height_high"].doubleValue
                        // Set Geo fence
                        self.copter.initLoc.setGeoFence(radius: radius, height: height)
                    }
                    
                case "get_idle":
                    // self.log("Cmd: get_idle"), to much spam
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_idle")
                    json_r["idle"].boolValue = self.copter.idle
                    
                case "get_state":
                    self.log("Cmd: get_state")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_state")
                    json_r["lat"].doubleValue = copter.loc.coordinate.latitude
                    json_r["lon"].doubleValue = copter.loc.coordinate.longitude
                    json_r["alt"].doubleValue = round(100 * copter.loc.altitude) / 100
                    json_r["heading"].doubleValue = copter.loc.heading
                    json_r["agl"].doubleValue = -1
                    json_r["vel_n"].doubleValue = copter.loc.vel.north
                    json_r["vel_e"].doubleValue = copter.loc.vel.east
                    json_r["vel_d"].doubleValue = copter.loc.vel.down
                    json_r["gnss_state"].intValue = getStateGNSS(state: self.copter.flightControllerState)
                    json_r["flight_state"].stringValue = copter.flightState

                case "set_init_point":
                    self.log("Cmd: set_init_point")
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_init_point", description: nackOwnerStr)
                    }
                    // Nack nav not ready
                    else if !navReady() { //self.copter.loc.coordinate.latitude == 0{
                        json_r = createJsonNack(fcn: "set_init_point", description: "Navigation not ready")
                    }
                    // Nack init point already set
                    else if self.copter.initLoc.isInitLocation{
                        json_r = createJsonNack(fcn: "set_init_point", description: "Init point already set")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("set_init_point")
                        let headingRef = json_m["heading_ref"].stringValue
                        
                        // Test robustness
                        if !copter.setInitLocation(headingRef: headingRef){
                            print("Error: Debug. Something is wrong, should not have passed to here.")
                            json_r = createJsonNack(fcn: "set_init_point", description: "Navigation not ready")
                        }
                        
                        // ALso set stream default to avoid flying to Arfica
                        let lat = self.copter.loc.coordinate.latitude
                        let lon = self.copter.loc.coordinate.latitude
                        let alt = self.copter.loc.altitude
                        let yaw = self.copter.loc.heading
                        
                        self.copter.pattern.streamUpdate(lat: lat, lon: lon, alt: alt, yaw: yaw)
                    }
                    
                case "reset_dss_srtl":
                    self.log("Cmd: reset_dss_srtl")
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "reset_dss_srtl", description: nackOwnerStr)
                    }
                    // Nack nav not ready
                    else if !navReady(){
                        json_r = createJsonNack(fcn: "reset_dss_srtl", description: "Navigation not ready")
                    }
                    // Accept command
                    else{
                        if copter.resetDSSSRTLMission(){
                            json_r = createJsonAck("reset_dss_srtl")
                        }
                        else {
                            json_r = createJsonNack(fcn: "reset_dss_srtl", description: "Position not available")
                        }
                    }
                    
                case "arm_take_off":
                    self.log("Cmd: arm_take_off")
                    let toHeight = json_m["height"].doubleValue
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "arm_take_off", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "arm_take_off", description: "Application is not in controls")
                    }
                    // Nack not enough nsat. Nsat check
                    else if self.copter.flightControllerState.satelliteCount < 8 {
                        json_r = createJsonNack(fcn: "arm_take_off", description: "Less than 8 satellites")
                    }
                    // Nack is flying
                    else if copter.getIsFlying() ?? false{ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "arm_take_off", description: "State is flying")
                    }
                    // Nack height limits
                    else if toHeight < 2 || toHeight > 40 {
                        json_r = createJsonNack(fcn: "arm_take_off", description: "Height is out of limits")
                    }
                    // Nack init point not set
                    else if !self.copter.initLoc.isInitLocation {
                        json_r = createJsonNack(fcn: "arm_take_off", description: "Init point not set")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("arm_take_off")
                        copter.toHeight = toHeight
                        copter.takeOff()
                    }
                    
                case "land":
                    self.log("Cmd: land")
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "land", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "land", description: "Application is not in controls")
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "land", description: "Not flying")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("land")
                        copter.land()
                    }
                    
                case "rtl":
                    self.log("Cmd: rtl")
                    // We want to know if the command is accepted or not. Problem is that it takes ~1s to know for sure that the RTL is accepted (completion code of rtl) and we can't wait 1s with the reponse.
                    // Instead we look at flight mode which changes much faster, although we do not know for sure that the rtl is accepted. For example, the flight mode is already GPS after take-off..
                    
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "rtl", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "rtl", description: "Application is not in controls")
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "rtl", description: "Not flying")
                    }
                    // Accept command
                    else{
                        // Activate the rtl, then figure if the command whent through or not
                        copter.rtl()
                        // Sleep for max 8*50ms = 0.4s to allow for mode change to go through.
                        var max_attempts = 8
                        // while flightMode is neither GPS nor Landing -  wait. If flightMode is GPS or Landing - continue
                        while copter.flightMode != "GPS" && copter.flightMode != "Landing" {
                            if max_attempts > 0{
                                max_attempts -= 1
                                // Sleep 0.1s
                                print("ReadSocket: Waiting for rtl to go through before replying.")
                                usleep(50000)
                            }
                            else {
                                // We tried many times, it must have failed somehow -> nack
                                print("ReadSocket: RTL did not go through. Debug.")
                                json_r = createJsonNack(fcn: "rtl", description: "RTL failed to engage, try again")
                                break
                            }
                        }
                        // If RTL is engaged send ack.
                        if copter.flightMode == "GPS" || copter.flightMode == "Landing" {
                            json_r = createJsonAck("rtl")
                        }
                    }
                    
                case "dss_srtl":
                    self.log("Cmd: dss srtl")
                    let hoverT = json_m["arg"]["hover_time"].intValue
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "dss_srtl", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "dss_srtl", description: "Application is not in controls")
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "dss_srtl", description: "Not flying")
                    }
                    // Nack hover time out of limits
                    else if !(0 <= hoverT && hoverT <= 300){
                        json_r = createJsonNack(fcn: "dss_srtl", description: "Hover_time is out of limits")
                    }
                    // Accept command
                    else {
                        json_r = createJsonAck("dss_srtl")
                        Dispatch.main{
                            self.copter.dssSrtl(hoverTime: hoverT)
                        }
                    }
                    
                case "set_vel_BODY":
                    self.log("Cmd: set_vel_BODY")
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_vel_BODY", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "set_vel_BODY", description: "Application is not in controls")
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "set_vel_BODY", description: "Not flying")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("set_vel_BODY")
                        let velX = Float(json_m["x"].doubleValue)
                        let velY = Float(json_m["y"].doubleValue)
                        let velZ = Float(json_m["z"].doubleValue)
                        let yawRate = Float(json_m["yaw_rate"].doubleValue)
                        print("VelX: " + String(velX) + ", velY: " + String(velY) + ", velZ: " + String(velZ) + ", yawRate: "  + String(yawRate))
                        Dispatch.main{
                            self.copter.dutt(x: velX, y: velY, z: velZ, yawRate: yawRate)
                            print("Dutt command sent from readSocket")
                        }
                    }
                    
                case "set_heading":
                    self.log("Cmd: set_heading")
                    let heading = json_m["heading"].doubleValue
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_heading", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "set_heading", description: "Application is not in controls")
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "set_heading", description: "Not flying")
                    }
                    // Nack yaw out of limits
                    else if heading < 0 || 360 < heading {
                        json_r = createJsonNack(fcn: "set_heading", description: "Yaw is out of limits")
                    }
                    // Nack mission active
                    else if copter.missionIsActive{
                        json_r = createJsonNack(fcn: "set_heading", description: "Mission is active")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("set_heading")
                        Dispatch.main{
                            self.copter.setHeading(targetHeading: heading)
                        }
                    }
                    
                case "set_alt":
                    self.log("Cmd: set_alt")
                    var alt = json_m["alt"].doubleValue
                    let reference = json_m["reference"].stringValue
                    // If alt is given relative to init, add the init altitude
                    if reference == "init"{
                        alt +=  self.copter.initLoc.altitude
                    }
                    // Alt is now in AMSL
                    
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_alt", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "set_alt", description: "Application is not in controls")
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "set_alt", description: "Not flying")
                    }
                    // Nack alt out of limits
                    else if alt - self.copter.initLoc.altitude < 2 {
                        json_r = createJsonNack(fcn: "set_alt", description: "Alt is out of limits")
                    }
                    // Nack mission active
                    else if copter.missionIsActive{
                        json_r = createJsonNack(fcn: "set_alt", description: "Mission is active")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("set_alt")
                        Dispatch.main{
                            self.copter.setAlt(targetAlt: alt)
                        }
                    }
                    
                case "upload_mission_LLA":
                    self.log("Cmd: upload_mission_LLA")
                    let fcnStr = "upload_mission_LLA"
                    let (fenceOK, fenceDescr, numberingOK, numberingDescr, speedOK, speedDescr, actionOK, actionDescr, headingOK, headingDescr) = copter.uploadMission(mission: json_m["mission"])
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: fcnStr, description: nackOwnerStr)
                    }
                    // Nack init point not set
                    else if !copter.initLoc.isInitLocation{
                        json_r = createJsonNack(fcn: fcnStr, description: "Init point is not set")
                    }
                    // Nack wp violate geofence
                    else if !fenceOK {
                        json_r = createJsonNack(fcn: fcnStr, description: fenceDescr)
                    }
                    // Nack wp numbering
                    else if !numberingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: numberingDescr)
                    }
                    // Nack action not supported
                    else if !actionOK{
                        json_r = createJsonNack(fcn: fcnStr, description: actionDescr)
                    }
                    // Nack speed too low
                    else if !speedOK{
                        json_r = createJsonNack(fcn: fcnStr, description: speedDescr)
                    }
                    // Nack heading error
                    else if !headingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: headingDescr)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck(fcnStr)
                    }
                    
                case "upload_mission_NED":
                    self.log("Cmd: upload_mission_NED")
                    let fcnStr = "upload_mission_NED"
                    let (fenceOK, fenceDescr, numberingOK, numberingDescr, speedOK, speedDescr, actionOK, actionDescr, headingOK, headingDescr) = copter.uploadMission(mission: json_m["mission"])
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: fcnStr, description: nackOwnerStr)
                    }
                    // Nack init point not set
                    else if !copter.initLoc.isInitLocation{
                        json_r = createJsonNack(fcn: fcnStr, description: "Init point is not set")
                    }
                    // Nack wp violate geofence
                    else if !fenceOK {
                        json_r = createJsonNack(fcn: fcnStr, description: fenceDescr)
                    }
                    // Nack wp numbering
                    else if !numberingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: numberingDescr)
                    }
                    // Nack action not supported
                    else if !actionOK{
                        json_r = createJsonNack(fcn: fcnStr, description: actionDescr)
                    }
                    // Nack speed too low
                    else if !speedOK{
                        json_r = createJsonNack(fcn: fcnStr, description: speedDescr)
                    }
                    // Nack heading error
                    else if !headingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: headingDescr)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck(fcnStr)
                    }
                    
                case "upload_mission_XYZ":
                    self.log("Cmd: upload_mission_XYZ")
                    let fcnStr = "upload_mission_XYZ"
                    let (fenceOK, fenceDescr, numberingOK, numberingDescr, speedOK, speedDescr, actionOK, actionDescr, headingOK, headingDescr) = copter.uploadMission(mission: json_m["mission"])
                    // Nack not owner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: fcnStr, description: nackOwnerStr)
                    }
                    // Nack init point not set
                    else if !copter.initLoc.isInitLocation{
                        json_r = createJsonNack(fcn: fcnStr, description: "Init point is not set")
                    }
                    // Nack wp violate geofence
                    else if !fenceOK {
                        json_r = createJsonNack(fcn: fcnStr, description: fenceDescr)
                    }
                    // Nack wp numbering
                    else if !numberingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: numberingDescr)
                    }
                    // Nack action not supported
                    else if !actionOK{
                        json_r = createJsonNack(fcn: fcnStr, description: actionDescr)
                    }
                    // Nack speed too low
                    else if !speedOK{
                        json_r = createJsonNack(fcn: fcnStr, description: speedDescr)
                    }
                    // Nack heading error
                    else if !headingOK{
                        json_r = createJsonNack(fcn: fcnStr, description: headingDescr)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck(fcnStr)
                    }
                    
                case "gogo":
                    self.log("Cmd: gogo")
                    let next_wp = json_m["next_wp"].intValue
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "gogo", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "gogo", description: "Application is not in controls")
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "gogo", description: "Not flying")
                    }
                    // Nack Wp number is not available in pending mission
                    else if !copter.pendingMission["id" + String(next_wp)].exists(){
                        json_r = createJsonNack(fcn: "gogo", description: "Wp number is not available in pending mission")
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("gogo")
                        Dispatch.main{
                            _ = self.copter.gogo(startWp: next_wp, useCurrentMission: false)
                        }
                    }
                    
                case "set_pattern":
                    self.log("Cmd: set_pattern")
                    let heading = parseHeading(json: json_m)
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_pattern", description: nackOwnerStr)
                    }
                    // Nack faulty heading
                    else if heading == -99{
                        // heading faulty
                        json_r = createJsonNack(fcn: "set_pattern", description: "Heading faulty")
                    }
                    // Accept command
                    else {
                        // Parse and set pattern
                        let pattern = json_m["pattern"].stringValue
                        let relAlt = json_m["rel_alt"].doubleValue
                        if pattern == "above"{
                            copter.pattern.setPattern(pattern: pattern, relAlt: relAlt, heading: heading)
                            json_r = createJsonAck("set_pattern")
                        }
                        else if pattern == "circle"{
                            let radius = json_m["radius"].doubleValue
                            let yawRate = json_m["yaw_rate"].doubleValue
                            copter.pattern.setPattern(pattern: pattern, relAlt: relAlt, heading: heading, radius: radius, yawRate: yawRate)
                            json_r = createJsonAck("set_pattern")
                        }
                    }
                    
                    
                case "follow_stream":
                    self.log("Cmd: follow_stream")
                    let enable = json_m["enable"].boolValue
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "follow_stream", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "follow_stream", description: "Application is not in controls")
                    }
                    // Nack not flying
                    else if !(copter.getIsFlying() ?? false){ // Default to false to handle nil
                        json_r = createJsonNack(fcn: "follow_stream", description: "Not flying")
                    }
                    // Nack pattern not set
                    else if copter.pattern.pattern.name == "" {
                        json_r = createJsonNack(fcn: "follow_stream", description: "Pattern not set")
                    }
                    // Nack stream already running
                    else if enable && streamSub != nil{
                        json_r = createJsonNack(fcn: "follow_stream", description: "Stream already enabled")
                    }
                    // Acccept command
                    else {
                        let ip = json_m["ip"].stringValue
                        let port = json_m["port"].intValue
                        Dispatch.background {
                            self.followStream(enable: enable, ip: ip, port: port)
                        }
                        json_r = createJsonAck("follow_stream")
                    }
                    
                case "set_gimbal":
                    self.log("Cmd: set_gimbal")
                    _ = json_m["roll"].doubleValue
                    let pitch = json_m["pitch"].doubleValue
                    _ = json_m["yaw"].doubleValue
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "gogo", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "set_gimbal", description: "Application is not in controls")
                    }
                    // Nack out of range
                    else if !(self.copter.gimbal.pitchRange[0] <= pitch && pitch <= self.copter.gimbal.pitchRange[1]) {
                        json_r = createJsonNack(fcn: "set_gimbal", description: "Roll, pitch or yaw is out of range for the gimbal")
                    }
                    // Acccept command
                    else{
                        json_r = createJsonAck("set_gimbal")
                        self.copter.gimbal.gimbalPitchRef = pitch
                    }
                    
                case "set_gripper":
                    self.log("Cmd: set_gripper")
                    json_r = createJsonNack(fcn: "set_gripper", description: "Not applicable to DJI")
                    
                case "set_spotlight":
                    self.log("Cmd: set_spotlight")
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "set_spotlight", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "set_spotlight", description: "Application is not in controls")
                    }
                    // Accept spotlight command if in sim even without the hardware
                    else if sim && self.accessory.spotlight == nil{
                        simSpotlightEnable = json_m["enable"].boolValue
                        simSpotlightBrightness = json_m["brightness"].intValue
                        json_r = createJsonAck("set_spotlight")
                    }
                    // Nack spotlight not installed
                    else if self.accessory.spotlight == nil{
                        json_r = createJsonNack(fcn: "set_spotlight", description: "Spotlight not available")
                    }
                    // Accept command
                    else {
                        self.accessory.spotlight!.setEnable(enable: json_m["enable"].boolValue)
                        self.accessory.spotlight!.setBrightness(brightness: json_m["brightness"].uIntValue)
                        json_r = createJsonAck("set_spotlight")
                    }
                    
                case "get_spotlihgt":
                    self.log("Cmd: get_spotlight")
                    // Accept spotlight command if in sim even without the hardware
                    if sim{
                        json_r = createJsonAck("get_spotlight")
                        json_r["enable"] = JSON(simSpotlightEnable)
                        json_r["brightness"] = JSON(simSpotlightBrightness)
                    }
                    // Nack spot not avaialble
                    else if self.accessory.spotlight == nil{
                        json_r = createJsonNack(fcn: "get_spotlight", description: "Spotlight is not available")
                    }
                    
                    // Accept command
                    else{
                        // Update the spot state
                        self.accessory.spotlight!.updateEnabled()
                        json_r = createJsonAck("get_spotlight")
                        self.accessory.spotlight?.updateEnabled()
                        json_r["enable"] = JSON(self.accessory.spotlight!.enabled)
                        json_r["brightness"] = JSON(self.accessory.spotlight!.getBrightness())
                    }
                    
                case "photo":
                    self.log("Cmd: photo")
                    let parsedIndex = parseIndex(json: json_m, sessionLastIndex: self.camera.sessionLastIndex)
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "photo", description: nackOwnerStr)
                    }
                    // Nack not in controls
                    else if self.inControls != "APPLICATION"{
                        json_r = createJsonNack(fcn: "photo", description: "Application is not in controls")
                    }
                    // Nack camera busy (uless it is continous photo or record command)
                    else if self.camera.cameraAllocator.allocated &&
                                json_m["cmd"].stringValue != "continous_photo" &&
                                json_m["cmd"].stringValue != "record"{
                        json_r = createJsonNack(fcn: "photo", description: "Camera resource is busy")
                    }
                    // Nack index out of range (coded from parseIndex)
                    else if parsedIndex == -11{
                        json_r = createJsonNack(fcn: "photo", description: "Index out of range, " + String(json_m["index"].intValue))
                    }
                    // Nack index faulty (coded from parseIndex)
                    else if parsedIndex == -12{
                        json_r = createJsonNack(fcn: "photo", description: "Index string faulty, " + json_m["index"].stringValue)
                    }
                    // Accept command:
                    else {
                        json_r = createJsonAck("photo")
                        // Switch cmd
                        switch json_m["cmd"]{
                        case "take_photo":
                            self.log("Cmd: photo, with arg take_photo")
                            if !self.camera.transferAllAllocator.allocated{
                                if self.camera.cameraAllocator.allocate("take_photo", maxTime: 5) {
                                    // Complete ack message
                                    json_r["description"] = "take_photo"
                                    camera.takePhotoCMD()
                                }
                            }
                            else{
                                json_r = createJsonNack(fcn: "photo", description: "Allocator1 denied, report")
                                print("DEBUG: Allocator1 denied")
                                self.log("Allocator1 denied, report")
                            }
                        case "continous_photo":
                            self.log("Cmd: photo, with arg continous_photo")
                            let enable = json_m["enable"].boolValue
                            if enable{
                                self.log("Enable continous_photo")
                            }
                            else{
                                self.log("Disable continous_photo")
                            }
                            // Default period
                            var period = 0.0
                            if json_m["period"].exists(){
                                period = json_m["period"].doubleValue
                            }
                            // Default subscription
                            var publish = "off"
                            if json_m["publish"].exists(){
                                publish = json_m["publish"].stringValue
                            }
                            // Start thread
                            self.camera.startContinousPhotoThread(enable: enable, period: period, publish: publish)
                            
                            // Update response description string
                            json_r["description"].stringValue = "continous_photo - " + String(enable)
                            
                        case "record":
                            self.log("Cmd: photo, with arg record")
                            let enable = json_m["enable"].boolValue
                            print(json_m)
                            if enable{
                                // Try to allocate and start recording
                                if !self.camera.transferAllAllocator.allocated{
                                    if self.camera.cameraAllocator.allocate("record", maxTime: 600) {
                                        // Complete ack message
                                        json_r["description"] = "record"
                                        self.camera.recording(enable: enable, completion: {success in
                                            if !success{
                                                json_r = createJsonNack(fcn: "photo", description: "Recording failed")
                                                // Deallocate
                                                self.camera.cameraAllocator.deallocate()
                                            }
                                        })
                                    }
                                }
                                else{
                                    json_r = createJsonNack(fcn: "photo", description: "Resource busy")
                                }
                            }
                            // Stop recording and deallocate Allocator
                            else{
                                if self.camera.cameraAllocator.owner == "record"{
                                    self.camera.recording(enable: enable, completion: {success in
                                        if !success{
                                            json_r = createJsonNack(fcn: "photo", description: "Recording failed")
                                        }
                                        else{
                                            self.camera.cameraAllocator.deallocate()
                                        }
                                    })
                                }
                            }
                            
                        case "download":
                            self.log("Cmd: photo, with arg download")
                            // Default resolution
                            var resolution  = "high"
                            // Parse resolution argument, nack faulty arg
                            if json_m["resolution"].exists(){
                                if json_m["resolution"].stringValue == "high"{
                                    resolution = "high"
                                }
                                else if json_m["resolution"].stringValue == "low"{
                                    resolution = "low"
                                }
                                // Faulty resolution argument, Nack
                                else {
                                    json_r = createJsonNack(fcn: "photo", description: "Cmd faulty")
                                    // Transfer control to the switch statement’s closing brace
                                    break
                                }
                            }
                            // Apply default resolution
                            else {
                                resolution = "high"
                            }
                            
                            // Download all or single index
                            if parsedIndex == -1 {
                                // transferAllAllocator prevents simultaniuous download processes
                                if camera.transferAllAllocator.allocate("transferAll", maxTime: 300) {
                                    // Complete ack message
                                    json_r["description"].stringValue = "download all " + resolution + "_res"
                                    // Transfer all in background, transferAll handles the allcoator
                                    Dispatch.background {
                                        // Transfer function handles the allocator
                                        self.log("Downloading all photos...")
                                        self.camera.transferAll(res: resolution)
                                    }
                                }
                                else {
                                    json_r = createJsonNack(fcn: "photo", description: "Allocator2 denied, report")
                                    print("DEBUG: Allocator2 denied")
                                    self.log("Allocator2 denied, report")
                                }
                            }
                            // Index must be ok, download the index
                            else{
                                // Complete ack message
                                json_r["description"].stringValue = "download " + String(parsedIndex)
                                Dispatch.background{
                                    // Download function handles the allocator
                                    self.log("Download photo index " + String(parsedIndex))
                                    self.camera.transferSingle(sessionIndex: parsedIndex, res: resolution, attempt: 1)
                                }
                            }
                        default:
                            self.log("Photo cmd faulty: " + json_m["cmd"].stringValue)
                            json_r = createJsonNack(fcn: "photo", description: "Cmd faulty")
                        }
                    }
                    
                case "get_armed":
                    printDB("Cmd: get_armed")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_armed")
                    if self.copter.getAreMotorsOn(){
                        json_r["armed"].boolValue = true
                    }
                    else{
                        json_r["armed"].boolValue = false
                    }
                    
                case "get_currentWP":
                    printDB("Cmd: get_currentWP")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_currentWP")
                    json_r["currentWP"].intValue = copter.missionNextWp
                    json_r["finalWP"].intValue = copter.mission.count - 1
                    
                case "get_flightmode":
                    self.log("Cmd: get_flightmode")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_flightmode")
                    if copter.flightMode != nil {
                        json_r["flightmode"].stringValue = copter.flightMode!
                    }
                    else{
                        json_r["flightmode"].stringValue = "No flight mode"
                    }
                case "get_metadata":
                    self.log("Cmd: get_metadata")
                    let parsedIndex = parseIndex(json: json_m, sessionLastIndex: self.camera.sessionLastIndex)
                    // Nack reference faulty
                    if parsedIndex == -10{
                        json_r = createJsonNack(fcn: "get_metadata", description: "Reference faulty, " + json_m["ref"].stringValue)
                    }
                    // Nack index out of range (coded from parseIndex)
                    else if parsedIndex == -11{
                        json_r = createJsonNack(fcn: "get_metadata", description: "Index out of range, " + String(json_m["index"].intValue))
                    }
                    // Nack index faulty (coded from parseIndex)
                    else if parsedIndex == -12{
                        json_r = createJsonNack(fcn: "get_metadata", description: "Index string faulty, " + json_m["index"].stringValue)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("get_metadata")
                        let frame = json_m["ref"].stringValue
                        // All indexes
                        if  parsedIndex == -1{
                            if frame == "XYZ"{
                                json_r["metadata"] = self.camera.jsonMetaDataXYZ
                            }
                            else if frame == "NED"{
                                json_r["metadata"] = self.camera.jsonMetaDataNED
                            }
                            else if frame == "LLA"{
                                json_r["metadata"] = self.camera.jsonMetaDataLLA
                            }
                        }
                        // Specific index
                        else{
                            if frame == "XYZ"{
                                json_r["metadata"] = self.camera.jsonMetaDataXYZ[String(describing: parsedIndex)]
                            }
                            else if frame == "NED"{
                                json_r["metadata"] = self.camera.jsonMetaDataNED[String(describing: parsedIndex)]
                            }
                            else if frame == "LLA"{
                                json_r["metadata"] = self.camera.jsonMetaDataLLA[String(describing: parsedIndex)]
                            }
                        }
                    }
                    
                case "get_posD":
                    printDB("Cmd: get_posD")
                    // No nack reasons
                    // Accept command
                    json_r = createJsonAck("get_posD")
                    json_r["posD"].doubleValue = self.copter.loc.pos.down
                    
                case "get_PWM":
                    printDB("Cmd: get_PWM")
                    json_r = createJsonNack(fcn: "get_PWM", description: "Not applicable to DJI")
                    
                case "disconnect":
                    self.log("Cmd: disconnect")
                    // Nack not fromOwner
                    if !fromOwner{
                        json_r = createJsonNack(fcn: "disconnect", description: nackOwnerStr)
                    }
                    // Accept command
                    else{
                        json_r = createJsonAck("disconnect")
                        // Stop and call app_lost. Should DSS take controls? Could be difficult for CRM to take controls then.
                        Dispatch.main{
                            self.copter.stop()
                            self.copter.dutt(x: 0, y: 0, z: 0, yawRate: 0)
                        }
                        // Prevent wp action to resume mission
                        self.heartBeat.disconnected = true
                        // Call CRM
                        if crmInUse{
                            _ = self.crm.appLost()
                        }
                    }
                    
                case "data_stream":
                    self.log("Cmd: data_stream - " + json_m["stream"].stringValue + " - " + String(json_m["enable"].boolValue))
                    let enable = json_m["enable"].boolValue
                    // Nack faulty stream handeled in switch case
                    // Accept command (and nack later if neccessary)
                    json_r = createJsonAck("data_stream")
                    switch json_m["stream"]{
                    case "ATT":
                        json_r["stream"].stringValue = "ATT"
                        self.subscriptions.setATT(bool: enable)
                        print("TODO: support ATT")
                    case "LLA":
                        json_r["stream"].stringValue = "LLA"
                        self.subscriptions.setLLA(bool: enable)
                    case "NED":
                        json_r["stream"].stringValue = "NED"
                        self.subscriptions.setNED(bool: enable)
                    case "XYZ":
                        json_r["stream"].stringValue = "XYZ"
                        self.subscriptions.setXYZ(bool: enable)
                    case "photo_LLA":
                        json_r["stream"].stringValue = "photo_LLA"
                        self.subscriptions.setPhotoLLA(bool: enable)
                    case "photo_XYZ":
                        json_r["stream"].stringValue = "photo_XYZ"
                        self.subscriptions.setPhotoXYZ(bool: enable)
                    case "currentWP":
                        json_r["stream"].stringValue = "currentWP"
                        self.subscriptions.setWpId(bool: enable)
                    case "battery":
                        json_r["stream"].stringValue = "battery"
                        self.subscriptions.setBattery(bool: enable)
                        if enable{
                            Dispatch.background{
                                self.pubBatInfoThread()
                            }
                        }
                    case "STATE":
                        json_r["stream"].stringValue = "STATE"
                        self.subscriptions.setSTATE(bool: enable)
                    default:
                        json_r = createJsonNack(fcn: "data_stream", description: "Stream faulty, " + json_m["stream"].stringValue)
                    }
                    
                default:
                    json_r = createJsonNack(fcn: json_m["fcn"].stringValue, description: "API call not recognized")
                    self.log("API call not recognized: " + json_m["fcn"].stringValue)
                    messageQualifiesForHeartBeat = false
                }
                if messageQualifiesForHeartBeat{
                    self.heartBeat.newBeat()
                }
                
                // Send reply
                replier.sendJson(json: json_r)
                if logPub != nil {
                    var logJson = json_r
                    logJson["time"] = JSON(CACurrentMediaTime())
                    _ = logPub?.publish(topic: replier.name + "_s", json: logJson)
                }
                
                // Print nack replies
                if json_r["fcn"].stringValue == "nack"{
                    self.log("Nack: " + json_r["call"].stringValue + " " + json_r["description"].stringValue)
                }
                // Print any interesting replies..
                else if json_r["call"].stringValue != "heart_beat" && json_r["call"].stringValue != "info_request" && json_r["call"].stringValue != "get_currentWP" && json_r["call"].stringValue != "who_controls" && json_r["call"].stringValue != "get_idle"{
                    print(json_r)
                }
            }
            catch {
                // receiveTimeout occured (the intended funcitonality)
                // print(replier.name, " Nothing to receive")
            }
        }
        print(replier.name, " Exiting reply thread")
        //return
    }
    
    // MARK: Stepper buttons
    //***************
    // Button actions
    //***************
    @IBAction func leftStepperAction(_ sender: UIStepper) {
        leftStepperLabel.text = String(sender.value/100)
        leftStepperName.text = "kP"
        copter.kP = sender.value/100
        print("kP updated: ", sender.value/100)
    }

    @IBAction func rightStepperAction(_ sender: UIStepper) {
//        rightStepperLabel.text = String(sender.value*100)
//        rightStepperName.text = "rNE"
//        let rNE = sender.value*100
//        if copter.pattern.stream.posFilter != nil{
//            copter.pattern.stream.posFilter!.tuneR(rNE: rNE, rAlt: nil)
        rightStepperLabel.text = String(sender.value/10)
        rightStepperName.text = "Nort_b"
        streamNorthBias = sender.value/10
        print("Stream nort bias updated :", streamNorthBias)
    }
    
    @IBAction func extraStepperAction(_ sender: UIStepper) {        
        extraStepperLabel.text = String(sender.value/100)
        extraStepperName.text = "kFF"
        copter.kFF = sender.value/100
        print("kFF updated: ", sender.value/100)
    }
    
    //*******************************************************************************************************
    // Exit view, but first deactivate Sticks (which invalidates fireTimer-timer to stop any joystick command)
    @IBAction func xClose(_ sender: UIButton) {
        close(reason: "")
    }
    
    // **************
    // close fucntion
    func close(reason: String){
        print("Closing down due to: ", reason)
        
        self.monitorDSSClientsEnabled = false
        self.monitorConnectionTypeEnabled = false
        
        // Allow display do be dimmed
        UIApplication.shared.isIdleTimerDisabled = false
        
        takeControls(toControls: "PILOT")
        print("close: Sticks deactivated")
        
        // stop continous photo
        self.camera.continousPhotoEnabled = false
        
        // Stop GPSKalmanTimer and close streamSub if not nil
        stopFollowStreamSubscription()
//        if self.GPSKalmanTimer != nil{
//            self.GPSKalmanTimer!.invalidate()
//        }
        
        // Stop battery stream
        self.subscriptions.battery = false
        
        // Unregister with crm if registered
        if crmInUse{
            if self.crm.unregister(){
                self.crm.id = "dss000"
                print("Unregistered from crm")
            }
            else{
                print("Error: Failed to unregister")
            }
        }
        
        // Close rep socket
        cmdRep.close()
        // streamSub socket closed in stopFollowStreamSubscriiption
        // streamSub.close()
        // Close publish sockets
        logPub?.close()
        infoPub.close()
        dataPub.close()
        // Close crm req socket if initiated
        if self.crm.name != ""{
            crm.close()
        }
        
        // Allow some slack to close client sockets (collission avoidance)
        var k = 0
        while self.clients.count > 0 && k < 3{
            self.log("Closing client socket..")
            usleep(1000000)
            k += 1
        }
        
        // Terminate context
        do{
            try context.terminate()
        }
        catch{
            print("Failed to terminate context")
        }
        
        // Stop listener prenumerations
        copter.stopListenToParam(DJIFlightControllerKeyString: DJIFlightControllerParamHomeLocation)
        copter.stopListenToParam(DJIFlightControllerKeyString: DJIFlightControllerParamAircraftLocation)
        copter.stopListenToParam(DJIFlightControllerKeyString: DJIFlightControllerParamFlightModeString)
        copter.stopListenToParam(DJIFlightControllerKeyString: DJIFlightControllerParamVelocity)
        copter.stopListenToParam(DJIFlightControllerKeyString: DJIFlightControllerParamAreMotorsOn)
        //copter.stopListenToParam(DJIFlightControllerKeyString: DJIFlightControllerParamTakeoffLocationAltitude)
        //stopListenToCamera()
        print("Close: Stopped listening to velocity-, flight mode-, position loc, home loc and motors on updates")
        
        NotificationCenter.default.removeObserver(self, name: .didPosUpdate, object: nil)
        NotificationCenter.default.removeObserver(self, name: .didVelUpdate, object: nil)
        NotificationCenter.default.removeObserver(self, name: .didPrintThis, object: nil)
        NotificationCenter.default.removeObserver(self, name: .didNextWp, object: nil)
        NotificationCenter.default.removeObserver(self, name: .didWPAction, object: nil)
        NotificationCenter.default.removeObserver(self, name: .didStickMove, object: nil)
        NotificationCenter.default.removeObserver(self, name: .doWriteMetaData, object: nil)
        NotificationCenter.default.removeObserver(self, name: .didChangeSDStatus, object: nil)
        NotificationCenter.default.removeObserver(self, name: .doUnregister, object: nil)
        
        
        // Transition to Settings
        coordinator?.gotoSettings(reason, toAlt: copter.loc.takeOffLocationAltitude)
        // Terminate the log timer
        stopTimer(timer: logTimer)
        logTimer = nil
    }
    
    
    // *******************************************
    // ActivateSticks: Touch down up inside action
    @IBAction func ActivateSticksPressed(_ sender: UIButton) {
        if inControls == "PILOT"{
            giveControls()
        }
        else{
            takeControls(toControls: "PILOT")
        }
    }
    
    
    @IBOutlet weak var calibPosButton: UIButton!
    @IBAction func calibPosButtonPressed(_ sender: Any) {
        // Cursor button isEnabled is toggled below if statement
        if cursorButton.isEnabled{
            // Shall be disabled
            calibPosButton.backgroundColor = UIColor.systemOrange
            calibPosButton.setImage(UIImage(systemName: "lock.fill"), for: .normal)
            cursorButton.isHidden = true
            copter.gimbal.gimbalPitchRef = self.preCalibGimbalPitchRef
            //_ = copter.gimbal.setPitch(pitch: 0)
        }
        else {
            // Shall be enabled
            calibPosButton.backgroundColor = UIColor.systemGreen
            calibPosButton.setImage(UIImage(systemName: "lock.open.fill"), for: .normal)
            cursorButton.isHidden = false
            // Save the current gimbal pitch setting, (can be nil)
            self.preCalibGimbalPitchRef = copter.gimbal.gimbalPitchRef
            
            // To not break the mission on a wpAction, wait for it to complete without halting everything..
            Dispatch.background{
                while self.camera.cameraAllocator.allocated {
                    // Sleep 0.2s
                    usleep(200000)
                }
                // Make sure wpAction has time to send gogo again.
                // Sleep 0.15s
                usleep(15000)
                
                // stop
                //self.copter.invalidateTimers()
                self.copter.idleCtrl()
                // Set up the wp
                var calibrateWP = JSON()
                calibrateWP["x"].doubleValue = 0
                calibrateWP["y"].doubleValue = 0
                calibrateWP["z"].doubleValue = -10
                calibrateWP["heading"].doubleValue = 0
                calibrateWP["action"].stringValue = "calibrate"
                calibrateWP["speed"].doubleValue = 1
                calibrateWP["gimbal_pitch"].doubleValue = -90
                
                self.copter.activeWP.setUpFromJsonWp(jsonWP: calibrateWP, defaultSpeed: self.copter.defaultHVel, initLoc: self.copter.initLoc)
                // send goto to get in calib position
                Dispatch.main{
                    if self.inControls == "APPLICATION"{
                        // wp will set gimbal
                        self.copter.goto()
                    }
                    else{
                        // Set gimbal manually
                        _ = self.copter.gimbal.setPitch(pitch: -90)
                    }
                }
            }
        }
        cursorButton.isEnabled.toggle()
    }
    
    @IBOutlet weak var cursorButton: UIButton!
    @IBAction func cursorButtonPressed(_ sender: Any) {
        //print(self.copter.missionIsActive)
        self.copter.initLoc.coordinate.latitude = self.copter.loc.coordinate.latitude
        self.copter.initLoc.coordinate.longitude = self.copter.loc.coordinate.longitude
        self.copter.initLoc.gimbalYaw = self.copter.loc.heading + self.copter.gimbal.yawRelativeToHeading
        
        // Reset the calibButton, which also reloads the gimbal pitch setting
        calibPosButtonPressed(self)
        
        if self.heartBeat.alive() && !self.heartBeat.disconnected{
            //_ = copter.gimbal.setPitch(pitch: 0)
            giveControls()
            usleep(100000)
            Dispatch.main {
                // If mission was aborted to calibrate, resume, otherwise start pending mission at wp0
                if self.copter.missionIsActive{
                    print("next wp mission is active: ", self.copter.missionNextWp)
                    _ = self.copter.gogo(startWp: self.copter.missionNextWp, useCurrentMission: true)
                }
                else{
                    print("next wp mission not active: ", self.copter.missionNextWp)
                    _ = self.copter.gogo(startWp: 0, useCurrentMission: false)
                }
            }
        }
        
    }
    
    // ************************************
    // Give the controls to the APPLICATION
    func giveControls(){
        // Enable copter stick mode
        copter.stickEnable()
        
        // Set controls string and gimbal control
        setInControls("APPLICATION")
        
        // Update button layout
        controlsButton.setTitle("TAKE Controls", for: .normal)
        controlsButton.backgroundColor = UIColor.systemGreen
        // Enable engineering buttons
        enableButton(DuttLeftButton)
        enableButton(DuttRightButton)
        
        self.log("APPLICATION has the Controls")
    }
    
    // *****************************************
    // Take the controls from APPLICATION or DSS
    func takeControls(toControls: String){
        // Disable copter stick mode
        copter.stickDisable()
        
        // Set controls string and gimbal control
        setInControls(toControls)
        
        // Update button layout
        if toControls == "DSS"{
            self.controlsButton.backgroundColor = UIColor.systemGreen
            self.controlsButton.setTitle("TAKE Controls from DSS", for: .normal)
        }
        else if toControls == "PILOT"{
            controlsButton.setTitle("GIVE Controls", for: .normal)
            controlsButton.backgroundColor = UIColor.systemOrange
        }
        
        // Disable engineering buttons
        disableButton(DuttLeftButton)
        disableButton(DuttRightButton)
        
        self.log(toControls + " has the Controls")
        
        // If following stream, stop GPSKalman filter thread and close sub socket
        stopFollowStreamSubscription()
    }
    
    
    @IBAction func modInitButtonPressed(_ sender: UIButton) {
        initModLocked.toggle()
        if initModLocked{
            modInitButton.backgroundColor = UIColor.systemOrange
            modInitButton.setImage(UIImage(systemName: "lock.fill"), for: .normal)
        }
        else {
            modInitButton.backgroundColor = UIColor.systemGreen
            modInitButton.setImage(UIImage(systemName: "lock.open.fill"), for: .normal)
        }
    }
    
    
    @IBAction func simBatteryButtonPressed(_ sender: Any) {
        let batImage = UIImage(systemName: "battery.25")
        let redImage = batImage?.withTintColor(.red, renderingMode: .alwaysOriginal)
        
        self.overrideBattery.toggle()
        if overrideBattery{
            simBatteryButton.setImage(redImage, for: .normal)
            simBatteryButton.backgroundColor = UIColor.systemGreen
        }
        else{
            simBatteryButton.setImage(UIImage(systemName:"lock.open.fill"), for: .normal)
            simBatteryButton.backgroundColor = UIColor.systemOrange
        }
    }
    
    //***************************************************************************************************************
    // Sends a command to go body right for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttRightPressed(_ sender: UIButton) {
        
    }
    
    //***************************************************************************************************************
    // Sends a command to go body left for some time at some speed per settings. Cancel any current joystick command
    @IBAction func DuttLeftPressed(_ sender: UIButton) {
        
    }
    
    
    //*************************************************************************
    // Download last photoData from sdCard and save to app memory. Save URL to self.
    @IBAction func savePhotoButton(_ sender: Any) {
        self.camera.savePhoto(sessionIndex: -1, res: "high"){(success) in
            if success{
                self.log("Photo saved to app memory")
            }
        }
    }
    
    
    //*************************************************
    // Update gui when nofication didposupdate happened
    @objc func onDidPosUpdate(_ notification: Notification){
        // These fields should perhaps be configurable to use.
        self.posXLabel.text = String(format: "%.1f", copter.loc.pos.x)
        self.posYLabel.text = String(format: "%.1f", copter.loc.pos.y)
        self.posZLabel.text = String(format: "%.1f", copter.loc.pos.z)
        self.localYawLabel.text = String(format: "%.1f", getDoubleWithinAngleRange(angle: self.copter.loc.heading - self.copter.initLoc.gimbalYaw))
        self.headingLabel.text = String(format: "%.1f", copter.loc.heading)
        // Check subscriptions and publish if enabled
        // LLA
        if subscriptions.LLA{
            var json = JSON()
            json["lat"].doubleValue = copter.loc.coordinate.latitude
            json["lon"].doubleValue = copter.loc.coordinate.longitude
            json["alt"].doubleValue = round(100 * copter.loc.altitude) / 100
            json["heading"].doubleValue = copter.loc.heading
            json["agl"].doubleValue = -1
           
            // TODO - similar for photo publish??
            
            // Only so often
            let interval:Double = 0  // Earlier set to 1s
            if CACurrentMediaTime() - self.infoPub.lastPub > interval{
                self.infoPub.lastPub = CACurrentMediaTime()
                json["time"] = JSON(CACurrentMediaTime())
                _ = self.infoPub.publish(topic: "LLA", json: json)
            }
            
        }
        // NED
        if subscriptions.NED {
            var json = JSON()
            json["north"].doubleValue = round(100 * copter.loc.pos.north) / 100
            json["east"].doubleValue = round(100 * copter.loc.pos.east) / 100
            json["down"].doubleValue = round(100 * copter.loc.pos.down) / 100
            json["heading"].doubleValue = copter.loc.heading
            json["agl"].doubleValue = -1
            _ = self.infoPub.publish(topic: "NED", json: json)
            
        }
        // XYZ
        if subscriptions.XYZ{
            var json = JSON()
            json["x"].doubleValue = round(100 * copter.loc.pos.x) / 100
            json["y"].doubleValue = round(100 * copter.loc.pos.y) / 100
            json["z"].doubleValue = round(100 * copter.loc.pos.z) / 100
            json["agl"].doubleValue = -1
            json["heading"].doubleValue =
            round(100 * (copter.loc.gimbalYaw - self.copter.initLoc.gimbalYaw)) / 100
            _ = self.infoPub.publish(topic: "XYZ", json: json)
            
        }
        // State
        if subscriptions.STATE{
            var json = JSON()
            json["lat"].doubleValue = copter.loc.coordinate.latitude
            json["lon"].doubleValue = copter.loc.coordinate.longitude
            json["alt"].doubleValue = round(100 * copter.loc.altitude) / 100
            json["heading"].doubleValue = copter.loc.heading
            json["agl"].doubleValue = -1
           
            json["vel_n"].doubleValue = copter.loc.vel.north
            json["vel_e"].doubleValue = copter.loc.vel.east
            json["vel_d"].doubleValue = copter.loc.vel.down
            json["gnss_state"].intValue = getStateGNSS(state: self.copter.flightControllerState)
            json["flight_state"].stringValue = copter.flightState
            _ = self.infoPub.publish(topic: "STATE", json: json)
        }
    }
    
    //************************************************************
    // Update gui when nofication didvelupdata happened  TEST only
    @objc func onDidVelUpdate(_ notification: Notification){
        //self.posXLabel.text = String(format: "%.1f", copter.velX)
        //self.posYLabel.text = String(format: "%.1f", copter.velY)
        //self.posZLabel.text = String(format: "%.1f", copter.velZ)
    }
    
    //******************************************************************************
    // Prints notification to log. Notifications can be sent from everywhere
    @objc func onDidPrintThis(_ notification: Notification){
        let strToPrint = String(describing: notification.userInfo!["printThis"]!)
        if strToPrint == "Stream does not update, stopping"{
            self.stopFollowStreamSubscription()
            self.log("Follow stream disabled")
        }
        self.log(strToPrint)
    }
    
    //*************************************************
    // Update gui and publish when nofication didnextwp happened
    @objc func onDidNextWp(_ notification: Notification){
        if let data = notification.userInfo as? [String: String]{
            var json_o = JSON()
            for (key, value) in data{
                json_o[key] = JSON(value)
            }
            
            // print to screen
            log("Going to WP " + json_o["currentWP"].stringValue + " (of " + json_o["finalWP"].stringValue + ")")
            
            // Publish if subscribed
            if self.subscriptions.WpId {
                _ = self.infoPub.publish(topic: "currentWP", json: json_o)
            }
        }
    }
    
    // ***************************************************************
    // Execute a wp action. Signal wpActionExecuting = false when done
    @objc func onDidWPAction(_ notification: Notification){
        if let data = notification.userInfo as? [String: String]{
            if data["wpAction"] == "take_photo"{
                self.log("wpAction: take photo")
                // Wait for allocator, allocate
                // must be in background to not halt everything.
                Dispatch.background {
                    while !self.camera.cameraAllocator.allocate("take_photo", maxTime: 3){
                        usleep(300000)
                        //print("WP action trying to allocate camera")
                    }
                    self.printDB("Camera allocator allocated by wpAction")
                    
                    // Test if there is a gimbal pitch reference in the wp. refGimbalPitch is default nil
                    // Moved to goto
                    //                    if let pitch = self.copter.activeWP.refGimbalPitch{
                    //                        // Try to set gimbal, if successful, wait for gimbal to get in position
                    //                        if self.copter.gimbal.setPitch(pitch: pitch){
                    //                            // Wait for gimbal get in position +-1 deg
                    //                            while !(self.copter.gimbal.gimbalPitch < Float(pitch) + 1 && self.copter.gimbal.gimbalPitch > Float(pitch) - 1) {
                    //                                usleep(100000)
                    //                            }
                    //                        }
                    //                        else {
                    //                            self.log("Error: Photo action gimbal pitch out of range")
                    //                        }
                    //                    }
                    
                    self.camera.takePhotoCMD()
                    // takePhotoCMD will execute and deallocate
                    while self.camera.cameraAllocator.allocated{
                        // Sleep 0.1s
                        usleep(100000)
                        //print("WP action waiting for takePhoto to complete")
                    }
                    // Stop continuation if link is lost or application disconnected.
                    if self.heartBeat.alive() && !self.heartBeat.disconnected && self.inControls == "APPLICATION"{
                        Dispatch.main {
                            _ = self.copter.gogo(startWp: self.copter.missionNextWp + 1 , useCurrentMission: true)
                        }
                    }
                }
            }
            if data["wpAction"] == "land"{
                print("wpAction: land")
                // dispatch to background, delay and land?
                Dispatch.background {
                    var hover = self.copter.hoverTime
                    while hover > 0 {
                        self.log("Hover at home, landing in: " + String(describing: hover))
                        hover -= 1
                        usleep(1000000)
                    }
                    self.copter.land()
                }
            }
            if data["wpAction"] == "calibrate"{
                self.log("wpAction: calibrate")
                // Test if there is a gimbal pitch reference in the wp. refGimbalPitch is default nil
                takeControls(toControls: "PILOT")
                // Delay message a little bit to let through flight mode message
                Dispatch.background{
                    usleep(500000)
                    self.log("Fly cursor to Take-off mat, press cursor")
                }
            }
        }
    }
    
    @objc func onDidStickMove(_ notification: Notification){
        // Pilot moved a stick or pressed home button. Take controls if not modifying init heading!
        if let data = notification.userInfo as? [String: Double]{
            let leftStickHor: Double = data["leftStick.horizontalPosition"]!
            //let rightStickHor: Double = data["rightStick.horizontalPosition"]!/660
            //let rightStickVer: Double = data["rightStick.verticalPosition"]!/660
            //print("leftStick.horizontalPosition: ", String(leftStickHor))
            
            // If initMod is locked, take controls
            if initModLocked{
                if inControls == "PILOT"{
                    _ = "Already handled"
                }
                else{
                    self.log("Pilot took controls via sticks")
                    takeControls(toControls: "PILOT")
                }
            }
            // initMod is unlocked but pilot did not move Left stick horisontal, take controls
            else if leftStickHor == 0{
                if inControls == "PILOT"{
                    _ = "Already handled"
                }
                else{
                    self.log("Pilot took controls via sticks")
                    takeControls(toControls: "PILOT")
                }
            }
            // The pilot wants to adjust the init heading
            else if leftStickHor != 0{
                self.copter.initLoc.gimbalYaw += leftStickHor / 1000 //660
                print("Init heading: ", self.copter.initLoc.gimbalYaw)
                // Update the activeWP to effectuate the change
                let id = "id" + String(self.copter.missionNextWp)
                self.copter.activeWP.setUpFromJsonWp(jsonWP: self.copter.mission[id], defaultSpeed: self.copter.defaultHVel, initLoc: self.copter.initLoc)
            }
        }
    }
    
    @objc func onDoWriteMetaData(_ notification: Notification){
        if let data = notification.userInfo as? [String: Int]{
            let sessionLastIndex = data["sessionLastIndex"]
            if self.camera.writeMetaData(sessionLastIndex: sessionLastIndex!, loc: self.copter.loc, initLoc: self.copter.initLoc, gimbalPitch: self.copter.gimbal.gimbalPitch, gnssState: getStateGNSS(state: self.copter.flightControllerState)){
                
                // Metadata written, check for subscriptions
                if self.subscriptions.photoXYZ{
                    _ = self.infoPub.publish(topic: "photo_XYZ", json: self.camera.jsonMetaDataXYZ[String(sessionLastIndex!)])
                }
                if self.subscriptions.photoLLA{
                    _ = self.infoPub.publish(topic: "photo_LLA", json: self.camera.jsonMetaDataLLA[String(sessionLastIndex!)])
                }
            }
        }
    }
    
    @objc func onDoUnregister(_ notification: Notification){
        if let _ = notification.userInfo as? [String: String]{
            if crm.unregister(){
                crmInUse = false
                crm.requestEnable = false
                self.log("Unregistered from crm")
            }
        }
    }
    
    @objc func onDidChangeSDStatus(_ notification: Notification){
        if let data = notification.userInfo as? [String: Bool]{
            setSDStatus(occupied: data["occupied"]!)
        }
    }
    
    // MARK: ViewDidLoad
    // ************
    // viewDidLoad
    override public func viewDidLoad() {
        super.viewDidLoad()  // run the viDidoad of the superclass
        // DUXWidget setup, topBarView does not work with UXSDK 4.14, use 4.13
        // Check FPVWidget class to remove camera name: setSourceCameraNameVisibility
        
        // Launch logger timer that controls rate of log messages
        Dispatch.main{
            self.logTimer = Timer.scheduledTimer(timeInterval: 0.3, target: self, selector: #selector(self.fireLogQueueTimer), userInfo: nil, repeats: true)
        }
        
        // ************** Layout settings
        
        self.addChild(self.fpvViewController)
        self.fpvView.addSubview(self.fpvViewController.view)
        self.addChild(self.topBarViewController)
        self.topBarView.addSubview(self.topBarViewController.view)
        self.topBarViewController.view.translatesAutoresizingMaskIntoConstraints = false;
        self.topBarViewController.view.topAnchor.constraint(equalTo: self.topBarView.topAnchor).isActive = true
        self.topBarViewController.view.bottomAnchor.constraint(equalTo: self.topBarView.bottomAnchor).isActive = true
        self.topBarViewController.view.leadingAnchor.constraint(equalTo: self.topBarView.leadingAnchor).isActive = true
        self.topBarViewController.view.trailingAnchor.constraint(equalTo: self.topBarView.trailingAnchor).isActive = true
        self.topBarViewController.didMove(toParent: self)
        
        self.mapWidget.isMapCameraLockedOnAircraft = true
        self.mapWidget.showDirectionToHome = true
        // Original size: 10p from safe area, width 120, height 80
        
        // Prevent display from dimming. Will cause battery drain, but flight control is lost if display is dimmed..
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Init steppers (for controller tuning for example
        leftStepperStackView.isHidden = false
        leftStepperStackView.backgroundColor = UIColor.lightGray
        leftStepperButton.value = copter.kP*100
        leftStepperLabel.text = String(copter.kP)
        leftStepperName.text = "kP"
        
//        rightStepperStackView.isHidden = false
//        rightStepperStackView.backgroundColor = UIColor.lightGray
//        rightStepperButton.value = 50 // Set same as filterAcc rNE/100
//        rightStepperLabel.text = "5000"
//        rightStepperName.text = "rNE"

        rightStepperStackView.isHidden = false
        rightStepperStackView.backgroundColor = UIColor.lightGray
        rightStepperButton.value = 0 // Set same as filterAcc rNE/100
        rightStepperLabel.text = "0"
        rightStepperName.text = "North"

        extraStepperStackView.isHidden = false
        extraStepperStackView.backgroundColor = UIColor.lightGray
        extraStepperButton.value = copter.kFF*100
        extraStepperLabel.text = String(copter.kFF)
        extraStepperName.text = "kFF"
        
        
        
        
        
        // Set up layout
        let radius: CGFloat = 5
        let bigRadius: CGFloat = 10
        // Set corner radiuses to buttons
        // set property to be able to set corner radius
        self.sdLabel.layer.masksToBounds = true
        self.sdLabel.layer.cornerRadius = bigRadius
        self.sdLabel.backgroundColor = .systemGreen
        
        controlsButton.layer.cornerRadius = radius
        DuttLeftButton.layer.cornerRadius = radius
        DuttRightButton.layer.cornerRadius = radius
        
        // Disable some buttons
        disableButton(DuttLeftButton)
        disableButton(DuttRightButton)
        DuttLeftButton.isHidden = true
        DuttRightButton.isHidden = true
        localYawLabel.isHidden = true
        
        DuttLeftButton.setTitle("Disable PhotoS", for: .normal)
        
        // cursorButton is not handeled by lockedButtonList
        cursorButton.isEnabled = false
        cursorButton.isHidden = true
        // calibPosButton.backgroundColor = UIColor.systemOrange
        // calibPosButton.setImage(UIImage(systemName: "lock.fill"), for: .normal)
        
        
        lockedButtonsList.append(simBatteryButton)
        lockedButtonsList.append(calibPosButton)
        lockedButtonsList.append(modInitButton)
        // Set ticker to list.count and call unlock to lock all buttons.
        lockedButtonTicker = lockedButtonsList.count
        unlockSpecialButtons()
        hideSpecialButtons(hide: true)
        
        
        // Hide some buttons. TODO remove of not used..
        //        takePhotoButton.isHidden = true
        //        previewButton.isHidden = true
        //        savePhotoButton.isHidden = true
        //        getDataButton.isHidden = true
        //        putDataButton.isHidden = true
        
        log("Setting up aircraft")
        
        self.log("Take-off alt: " + String(round(10*self.copter.loc.takeOffLocationAltitude)/10))
        
        // Setup aircraft
        if let product = DJISDKManager.product() as? DJIAircraft {
            self.aircraft = product
            
            // Store flight controller reference in the Copter object
            if let fc = self.aircraft?.flightController {
                // Store the flightController reference
                self.copter.flightController = fc
                self.copter.initFlightController()
            }
            else{
                close(reason: "Flight controller not loaded")
                return
            }
            
            // Store the remote controller reference in the Copter object
            if let rcReference = self.aircraft?.remoteController{
                self.copter.rcController = rcReference
                self.copter.initRemoteController()
            }
            else{
                close(reason: "Remote controller not loaded")
                return
            }
            
            // Store the camera refence
            if let cam = product.camera {
                // Implement the camera functions, including delegate in class CameraController.
                self.camera.camera = cam
                self.camera.initCamera(publisherSocket: dataPub)
                // Check for SD-Card
                if !camera.getSDCardInserted(){
                    close(reason: "Error: No SD-Card!")
                    return
                }
                // Else check storage status
                // else{
                if let availableMB = camera.getSDCardAvailableSpace(){
                    if let totalMB = camera.getSDCardCapacity(){
                        let availableGB = round(Double(availableMB)/100)/10
                        let totalGB = round(Double(totalMB)/100)/10
                        self.log("SDCard: GB available " + String(availableGB) + " of" + String(totalGB))
                        if availableGB < 1{
                            self.log("Warning: SD card available space low")
                        }
                    }
                }
                //}
                self.camera.camera = cam
                self.camera.camera?.setPhotoAspectRatio(DJICameraPhotoAspectRatio.ratio4_3, withCompletion: {(error) in
                    if error != nil{
                        self.log("Aspect ratio 4:3 could not be set")
                    }
                })
                
                //self.startListenToCamera()
            }
            else{
                close(reason: "Camera not loaded")
                return
            }
            // Store the gimbal reference in the Gimbal object in the Copter object
            if let gimbalReference = self.aircraft?.gimbal {
                self.copter.gimbal.gimbal = gimbalReference
                self.copter.gimbal.initGimbal()
            }
            else{
                close(reason: "Gimbal not loaded")
                return
            }
            
            // Store battery reference in the Battery object
            if let bat = self.aircraft?.battery {
                // Store the battery reference
                self.battery.battery = bat
                self.battery.initBattery()
            }
            else{
                close(reason: "Battery not loaded")
                return
            }
            
            // Store accessoryAggregation in Accessory object
            if let payload = self.aircraft?.accessoryAggregation {
                // Store the accessory reference
                self.accessory.accessory = payload
                self.accessory.initAccessory()
            }
            else{
                // setupOk =
                self.log("Accessory not loaded")
            }
            
            // Set up payload specific buttons
            // If spotlight is not a capability, hide its button
            if !self.accessory.capabilities.contains("SPOTLIGHT"){
                self.spotButton.isEnabled = false
                self.spotButton.isHidden = true
            }
        }
        else{
            close(reason: "Aircraft not loaded")
            return
        }
        
        log("Aircraft componentes set up OK")
        
        // Reset and Collect capabilities
        self.capabilities = []
        self.capabilities = self.camera.capabilities + self.accessory.capabilities
        if self.sim {
            // Simulated minis reports SPOTLIGT capability. Future feature, graphically add capabilities in sim.
            if self.camera.capabilities.contains("C0"){
                self.capabilities.append("SPOTLIGHT")
            }
            // Add SIM capability to simulated drones
            self.capabilities.append("SIM")
        }
        else{
            // Add REAL capability to non simulated drones
            self.capabilities.append("REAL")
        }
        
        // ******************* Setup ZMQ sockets
        
        self.log("DSS ip: " + getIPAddress())
        
        // ****** Setup ports if using crm, firewall allows app on dronehost subnet*100 port range
        if crm.ip != ""{
            cmdRepPort = crmPort + 1
            logPubPort = crmPort + 2
            infoPubPort = crmPort + 3
            dataPubPort = crmPort + 4
        }
        
        // Setup log publisher
        logPub = Publisher()
        logPub!.setupPublisher(name: "log______Pub", zmqContext: context, port: logPubPort, logPublisher: nil)
        if logPub!.initPublisher(){
            self.log(logPub!.name + ": Init " + logPub!.endPoint)
        }
        else {
            self.log(logPub!.name + " Failed init: " + logPub!.endPoint)
            close(reason: "Failed ot init log pub")
            return
        }
        
        // Setup and init Info Publisher
        infoPub.setupPublisher(name: "Info_____Pub", zmqContext: context, port: infoPubPort, logPublisher: logPub)
        if infoPub.initPublisher(){
            self.log(infoPub.name + " Init: " + infoPub.endPoint)
        }
        else {
            self.log(infoPub.name + " Failed init: " + infoPub.endPoint)
            close(reason: "Failed ot init info pub")
            return
        }
        // Setup and init Data Publisher
        dataPub.setupPublisher(name: "Data_____Pub", zmqContext: context, port: dataPubPort, logPublisher: logPub)
        if dataPub.initPublisher(){
            self.log(dataPub.name + " Init: " + dataPub.endPoint)
        }
        else {
            print(dataPub.name, "failed to initiate with", dataPub.endPoint)
            close(reason: "Failed ot init data pub")
            return

        }
        
        
        // Set default owner and id
        setOwner(id: "da000")
        crm.id = "da000"
        idLabel.text = crm.id
        
        
        // ********** Setup the replier
        cmdRep.setupReplier(name: "DSS______Rep", zmqContext: self.context, port: cmdRepPort)
        if cmdRep.initReplier(){
            self.log(cmdRep.name + " Init: " + cmdRep.endPoint)
            Dispatch.background{
                self.readSocket(replier: self.cmdRep)
            }
            Dispatch.background{
                self.heartBeats()
            }
        }
        else{
            print(cmdRep.name + "Failed init: " + cmdRep.endPoint)
            close(reason: "Failed ot init CMD rep")
            return
        }
        

        // MARK: CRM reg
        // If the user entered an ip to crm
        if crm.ip != ""{
            // Use crm, setup and connect
            crmInUse = true
            crm.setupRequestor(name: "CRM______Req", zmqContext: context, ip: crm.ip, port: crmPort, logPublisher: logPub)
            if crm.initRequestor(heartBeatPeriod: self.crmHeartBeatPeriod, linkLostTime: crmLinkLostTime){
                self.log(crm.name + " Init " + crm.endPoint)
            }
            else{
                self.log(crm.name + "Failed to initiate with" + crm.endPoint)
                crmInUse = false
                close(reason: "Failed ot init CRM socket")
                return
            }
            
            // ********** Register to crm
            print("Calling crm to register")  // call getIPAdress instead (below)?
            let shortName = getShortName(cameraName: self.camera.cameraType)
            // Parse capabilites!
            let description = getDescription(sim: self.sim, camera: camera.cameraType, accessory: self.accessory.name)
            crm.id = crm.register(ip: getIPAddress(), port: cmdRepPort, name: shortName, description: description, capabilities: self.capabilities, type: "dss")
            // If crm does not respond, the tyramoteId will be empty, close connections and start over in Settings VC
            if crm.id == ""{
                self.log("Error: crm does not respond. Go back to Settings screen.")
                crmInUse = false
                close(reason: "CRM did not respond, check VPN connection")
                return
            }
            else{
                // Register command is acked, set owner to crm
                setOwner(id: "crm")
                idLabel.text = crm.id
            }
            // Save the id in the requestors. Id is used in all requests
            // Only one requestor: crm
            self.log("Registered with CRM, received id is: " + self.crm.id)
        }
        
        // Set id label to default or the given id upon successful registration
        idLabel.text = crm.id
        
        // Start monitoring other clients for collision avoidance
        Dispatch.background{
            self.monitorDSSClientsThread()
        }
        // Start monitoring connection type
        Dispatch.background{
            self.monitorConnectionTypeEnabled = true
            self.monitorConnectionTypeThread()
        }
        
        // Air link properties
        if let airlink = aircraft?.airLink{
            // Some clues on streaming: https://forum.dji.com/forum.php?mod=viewthread&tid=213732
            var airlinkProps: [String] = []
            
            if airlink.isWiFiLinkSupported{
                airlinkProps.append("wifi")
            }
            if airlink.isOcuSyncLinkSupported{
                airlinkProps.append("Ocusync")
            }
            if airlink.isLightbridgeLinkSupported {
                airlinkProps.append("LightBridge")
            }
            
            //for properties in airlinkProps{
            print("Link technology supported: ", airlinkProps)
            //}
        }
        // Add observers to the notification center
        // Notification center,https://learnappmaking.com/notification-center-how-to-swift/
        NotificationCenter.default.addObserver(self, selector: #selector(onDidPosUpdate(_:)), name: .didPosUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidVelUpdate(_:)), name: .didVelUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidPrintThis(_:)), name: .didPrintThis, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidNextWp(_:)), name: .didNextWp, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidWPAction(_:)), name: .didWPAction, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidStickMove(_:)), name: .didStickMove, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDoWriteMetaData(_:)), name: .doWriteMetaData, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDidChangeSDStatus(_:)), name: .didChangeSDStatus, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDoUnregister(_:)), name: .doUnregister, object: nil)
    }
    
    func monitorConnectionTypeThread(){
        while self.monitorConnectionTypeEnabled{
            self.connectionType = getConnectionType()
            // Prevent continous photo to download and publish if poor conneciton
            self.camera.connectionType = self.connectionType
            // Prevent publiher to publish if poor conneciton
            self.dataPub.connectionType = self.connectionType
            // Update GUI
            Dispatch.main{
                self.connectionLabel.text = self.connectionType
            }
            // Check conneciton every 2s
            usleep(2000000)
        }
        
    }
    override public func viewWillAppear(_ animated: Bool) {
        //print("will appear")
        super.viewWillAppear(animated)
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        //print("did appear")
        super.viewDidAppear(animated)
    }
    
    override public func viewWillLayoutSubviews() {
        //print("Will layout subviews")
        super.viewWillLayoutSubviews()
    }
    
    override public func viewDidLayoutSubviews() {
        //print("Did layout subviews")
        super.viewDidLayoutSubviews()
    }
}
