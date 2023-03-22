//
//  CopterHelper.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-28.
//

import Foundation
import DJIUXSDK
import SwiftyJSON

class CopterController: NSObject, DJIFlightControllerDelegate, DJIRemoteControllerDelegate {
    var flightController: DJIFlightController?                                  // Reference to flight controller
    var rcController: DJIRemoteController?                                      // Reference to remote controller
    var flightControllerState: DJIFlightControllerState = DJIFlightControllerState()         // State for flight controller state updated by delegate function
    var stickState: DJIRCHardwareState = DJIRCHardwareState()                   // State for the remote hardware state updated by delegate function
    var gimbal = GimbalController()                                             // The Gimbal controller class
   

    // Geofencing defaults set in initLoc init code.

    //let djiDatumAltOffset: Double = 30.8            // DJI uses a some geoid altitude. The offset should be around 30m in Sweden..
            
    // Mission stuff
    var pendingMission = JSON()
    var mission = JSON()
    var missionNextWp = -1
    var missionNextWpId = "id-1"
    var missionType = ""
    var activeWP: MyLocation = MyLocation()
    var pattern: PatternHolder = PatternHolder()
    var missionIsActive = false
    var wpActionExecuting = false
    var hoverTime: Int = 0                          // Hovertime to wait prior to landing in dssSRTL. TODO, make parameter in mission.

    var refVelBodyX: Float = 0.0
    var refVelBodyY: Float = 0.0
    var refVelBodyZ: Float = 0.0
    var refYawRate: Float = 0.0
    
    var refYawLLA: Double = 0
    
    var relAltLimitCA: Double = 5                   // Relative altitude threshold for collission avoidance
    var caMaxbrake: Float = 15                      // Max contribution from collision avoidance
    var caVelBodyX: Float = 0.0                     // Reference velocities for collision avoidance
    var caVelBodyY: Float = 0.0
    var caVelBodyZ: Float = 0.0
    var caActive: Bool = false                      // Collision avoidance system active flag
    var lastCaNotification = CACurrentMediaTime()   // Time of last collision avoidance notification sent
    
    
    var xyVelLimit: Float = 1000 // 300             // cm/s horizontal speed
    var zVelLimit: Float = 150                      // cm/s vertical speed
    var yawRateLimit:Float = 150 //50               // deg/s, defensive.
    
    var defaultXYVel: Float = 1.5                   // m/s default horizontal speed (fallback) TODO remove.
    var defaultHVel: Float = 1.5                    // m/s default horizontal speed (fallback)
    var toHeight: Double = -1                       // Take-Off height. Set to -1 when not in use.
    private var _takingOffToAlt: Bool = false       // A flag for protecting ongoing takeoff (climb to altitude)
    public var takingOffToAlt: Bool{
        get { return self._takingOffToAlt }
        set { if newValue != self._takingOffToAlt {
                print("takingOffToAlt changed to:", newValue)}
            self._takingOffToAlt = newValue
            }
    }
    var homeHeading: Double?                        // Heading of last updated homewaypoint
    var homeLocation: CLLocation?                   // Location of last updated homewaypoint (autopilot home)
    var dssSmartRtlMission: JSON = JSON()           // JSON LLA wayopints to follow in smart rtl
    var dssSrtlActive: Bool = false

    var flightMode: String?                         // The flight mode as a string
    var flightState: String = "ground"              // The flight state, ground -> flying <-> landed
    var loc: MyLocation = MyLocation()
    var initLoc: MyLocation = MyLocation()          // The init location as a MyLocation. Used for origin of geofence.
    var clientLoc: [String: MyLocation] = [:]       // Dict for other clients positions

    // Timer settings
    let sampleTime: Double = 120                    // Sample time in ms
    let controlPeriod: Double = 2000                // Number of millliseconds to send dutt command (stated in API)

    // Timers for position control
    var duttTimer: Timer?
    var duttLoopCnt: Int = 0
    var duttLoopTarget: Int = 0                     // Set in init
    var posCtrlTimer: Timer?                        // Position control Timer
    var posCtrlLoopCnt: Int = 0                     // Position control loop counter
    var posCtrlLoopTarget: Int = 1000                // Position control loop counter max
    var caTimer: Timer?                             // Collision avoidance Timer, calc brake actions
    var idleCtrlTimer: Timer?                       // Ctrl timer for idle that allows collision avoidance to act
    private var _idle: Bool = false                 // Idle flag, use setter and getter functions
    public var idle: Bool{
        get { return self._idle}
        set {self._idle = newValue}
    }
        
    // Control paramters, acting on errors in meters, meters per second and degrees
    var hPosKP: Float = 0.75
    var hPosKI: Double = 0.001
    var hPosKD: Float = 0.6
    var etaLimit: Float = 2.0
    private let vPosKP: Float = 1
    private let vVelKD: Float = 0
    private let yawKP: Float = 1.3
    private let yawKI: Float = 0.15
    //private let yawFFKP: Float = 0.05
    private let radKP: Double = 0.5                    // KP for radius tracking
    var yawErrorIntegrated: Double = 0                 // Value of yaw error integrator in velocity controller
    var horErrorIntegrated: Double = 0                 // Value of horisontal error integrated
    
    // MARK: New control paramters CLEAN UP
    var kP:Double = 0.2 //0.7         // P gain in follow me above course
    var kFF:Double = 1.0 // 0.6       // Feed forward gain
    
    // refvelFilt - defined here just to test.
    var refVelXFilt: Double = 0
    var refVelYFilt: Double = 0

    
    override init(){
    // Calc number of loops for dutt cycle
        duttLoopTarget = Int(controlPeriod / sampleTime)
    }

    // ****************************************************
    // Init the flight controller, set the delegate to self
    func initFlightController(){
        // Set properties of VirtualSticks
        self.flightController?.rollPitchCoordinateSystem = DJIVirtualStickFlightCoordinateSystem.body
        self.flightController?.yawControlMode = DJIVirtualStickYawControlMode.angularVelocity // Auto reset to angle if controller reconnects
        self.flightController?.rollPitchControlMode = DJIVirtualStickRollPitchControlMode.velocity
   
        // Activate listeners
        self.startListenToHomePosUpdated()
        self.startListenToPos()
        self.startListenToFlightMode()
        self.startListenToMotorsOn()
        self.startListenToVel()
        //self.startListenToTakeOffLocationAlt()    Pressure altitude at takeoff not used. Stop listen on xCloes if activated
        
        flightController!.delegate = self
    }
    
    // ***********************************
    // Flight controller delegate function
    func flightController(_ fc: DJIFlightController, didUpdate state: DJIFlightControllerState) {
        self.flightControllerState = state
     }
   
    // *******************************************
    // Init the RC, set the delegate to self
    func initRemoteController(){
        rcController!.delegate = self
    }
    
    //************************************
    // Remote controller delegate funciton
    func remoteController(_ remoteController: DJIRemoteController, didUpdate state: DJIRCHardwareState){
        self.stickState = state
        let deadband = 80 // 80 out of 660 that is max output
        if (abs(state.rightStick.verticalPosition) > deadband || abs(state.leftStick.verticalPosition) > deadband || abs(state.rightStick.horizontalPosition) > deadband || abs(state.leftStick.horizontalPosition) > deadband || state.goHomeButton.isClicked.boolValue){
            // Notify DSS if there is input while in Joystick mode.
            if self.flightControllerState.flightModeString == "Joystick"{
                NotificationCenter.default.post(name: .didStickMove, object: self, userInfo: ["leftStick.horizontalPosition": Double(state.leftStick.horizontalPosition), "rightStick.horizontalPosition": Double(state.rightStick.horizontalPosition), "rightStick.verticalPosition": Double(state.rightStick.verticalPosition)])
            }
        }
    }
    
    //*************************************
    // Start listening for position updates
    func startListenToVel(){
        guard let key = DJIFlightControllerKey(param: DJIFlightControllerParamVelocity) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }

        keyManager.startListeningForChanges(on: key, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
            if let checkedNewValue = newValue{
                let vel = checkedNewValue.value as! DJISDKVector3D
                // Velocities are in NED coordinate system!
                let heading = self.loc.heading
                
                // Update NED Velocities
                self.loc.vel.north = vel.x
                self.loc.vel.east = vel.y
                self.loc.vel.down = vel.z
                
                // Velocities on the BODY coordinate system (dependent on heading)
                let beta = heading/180*Double.pi
                self.loc.vel.bodyX = vel.x * cos(beta) + vel.y * sin(beta)
                self.loc.vel.bodyY = -vel.x * sin(beta) + vel.y * cos(beta)
                self.loc.vel.bodyZ = vel.z

                
                NotificationCenter.default.post(name: .didVelUpdate, object: nil)
            }
        })
    }

    
    //**********************************************************************************************
    // Start listening for position updates. Correct relative alt for startAMSL and djiDatum Offset.
    func startListenToPos(){
        guard let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.startListeningForChanges(on: locationKey, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
            if let checkedNewValue = newValue{
                let pos = (checkedNewValue.value as! CLLocation)
                guard let heading = self.getHeading() else {
                   print("PosListener: Error updating heading")
                   return}
                
                let lat = pos.coordinate.latitude
                let lon = pos.coordinate.longitude
                let alt = pos.altitude + self.loc.takeOffLocationAltitude
                
                self.loc.setPosition(lat: lat, lon: lon, alt: alt, heading: heading, gimbalYawRelativeToHeading: self.gimbal.yawRelativeToHeading, initLoc: self.initLoc) {
                        // The completionBock called upon succsessful update of pos.
                        NotificationCenter.default.post(name: .didPosUpdate, object: nil)
                    }
                
                // Run pos updated notification as a completion block. In the notification, look for subscriptions XYZ, NED and LLA
            }
        })
    }
    
    // ***************************
    // Monitor flight mode changes
    func startListenToFlightMode(){
        guard let flightModeKey = DJIFlightControllerKey(param: DJIFlightControllerParamFlightModeString) else {
            NSLog("Couldn't create the key")
           return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.startListeningForChanges(on: flightModeKey, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if let checkedNewValue = newValue{
                    let flightMode = checkedNewValue.value as! String
                    let printStr = "New Flight mode: " + flightMode
                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": printStr])
                    // If pilot takes off manually, set init point at take-off location.
//                    if flightMode == "TakeOff" && !self.initLoc.isInitLocation{
//                        self.setInitLocation(headingRef: "drone")
//                    }
                    // Trigger completed take-off to climb to correct take-off altitude
                    if self.flightMode == "TakeOff" && flightMode == "GPS"{
                        // Protect the climt to altitude with takingOffToAlt - flag
                        self.takingOffToAlt = true
                        let height = self.toHeight
                        if height != -1{
                            Dispatch.main{
                                self.setAlt(targetAlt: self.initLoc.altitude + height)
                                // Launch thread to monitor when take-off alt is reached.
                                //self.monitorToAltReached()
                            }
                            // Reset take off height
                            self.toHeight = -1
                        }
                    }
                    // Look for landing, it triggers unRegister
                    else if self.flightMode == "Landing" && flightMode == "GPS"{
                        // Unregister from CRM
                        // NotificationCenter.default.post(name: .doUnregister, object: self, userInfo: ["Foo": "unregister due to landing"])
                    }
                    self.flightMode = flightMode
                }
        })
    }
    
    
    //**************************************
    // Start listen to home position updates
    func startListenToHomePosUpdated(){
        guard let homeKey = DJIFlightControllerKey(param: DJIFlightControllerParamHomeLocation) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.startListeningForChanges(on: homeKey, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
            if let checkedNewValue = newValue{
                self.homeHeading = self.getHeading()
                self.homeLocation = (checkedNewValue.value as! CLLocation)
                print("HomePosListener: DJI home location was updated. Altitude: ", self.homeLocation!.altitude)
            }
        })
    }
    
    //****************************
    // Start listen to armed state
    func startListenToMotorsOn(){
        guard let areMotorsOnKey = DJIFlightControllerKey(param: DJIFlightControllerParamAreMotorsOn) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.startListeningForChanges(on: areMotorsOnKey, withListener: self, andUpdate: {(oldState: DJIKeyedValue?, newState: DJIKeyedValue?) in
            if let checkedValue = newState {
                let motorsOn = checkedValue.value as! Bool
                if motorsOn {
                    self.flightState = "flying"
                }
                else{
                    self.flightState = "landed"
                }
                // If motors are armed without Init point has been initiated, initiate it
                if motorsOn && !self.initLoc.isInitLocation {
                    // TODO test robustness.
                    _ = self.setInitLocation(headingRef: "drone")
                    // Also set stream default to avoid flying to Arfica
                    // Get the optional lat, lon, alt to init gps stream to current location.
                    let (optLat, optLon, optAlt) = self.getCurrentLocation()
                    // Guard any nil values. Return false if nil.
                    guard let lat = optLat else {
                        return}
                    guard let lon = optLon else {
                        return}
                    guard let alt = optAlt else {
                        return}
                    guard let heading = self.getHeading() else {
                        print("StartListenToMotorsOn: Can't get current heading")
                        return}
                                        
                    self.pattern.streamUpdate(lat: lat, lon: lon, alt: alt, yaw: heading)
                    print("Stream default set to init point", lat)
                }
            }
        })
    }
    
    
    //*********************************
    // Start listen to takeoff altitude. Note this altitude is based on barometer only, guessing using QNH = 1013
    func startListenToTakeOffLocationAlt(){
        guard let takeoffLocationKey = DJIFlightControllerKey(param: DJIFlightControllerParamTakeoffLocationAltitude) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        
        keyManager.startListeningForChanges(on: takeoffLocationKey, withListener: self, andUpdate: {(oldState: DJIKeyedValue?, newState: DJIKeyedValue?) in
            if let checkedValue = newState {
                let takeOffPressureAlt = checkedValue.value as! Double
                self.loc.takeOffPressureAlt = Double(takeOffPressureAlt)
                print("Takeoff pressure altitude changed: ", self.loc.takeOffPressureAlt)
            }
        })
    }
    
    // *********************************
    // Get the takeOff location altitude
    func GetTakeOffLocationAlt()->Double?{
        guard let takeOffAltitudeKey = DJIFlightControllerKey(param: DJIFlightControllerParamTakeoffLocationAltitude) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
        
        if let altitudeValue = keyManager.getValueFor(takeOffAltitudeKey) {
            let toAltitude = altitudeValue.value as! Double
            return toAltitude
        }
        return nil
    }
    
    
    //*************************************************************************************
    // Generic func to stop listening for updates. Stop all listeners at exit (func xClose)
    func stopListenToParam(DJIFlightControllerKeyString: String){
        guard let key = DJIFlightControllerKey(param: DJIFlightControllerKeyString) else {
            NSLog("Couldn't create the key")
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return
        }
        keyManager.stopListening(on: key, ofListener: self)
    }
    
    // ****************************************************************************************************
    // Set the initLocation and orientation as a reference of the system. Can only be set once for safety!
    // old: setOriginXYZ
    func setInitLocation(headingRef: String)->Bool{
        
        if let takeoffalt = GetTakeOffLocationAlt(){
            print("The takeoff alt is: ", takeoffalt)
        }
        else{
            print("Takeoff alt is nil")
        }
        
        
        if self.initLoc.isInitLocation{
            print("setInitLocation Caution: Start location already set!")
            return false
        }
        // Get the optional lat, lon, alt.
        let (optLat, optLon, optAlt) = self.getCurrentLocation()
        // Gurad any nil values. Return false if nil.
        guard let lat = optLat else {
            print("setInitLocation: Can't get current location")
            return false}
        guard let lon = optLon else {
            print("setInitLocation: Can't get current location")
            return false}
        guard let alt = optAlt else {
            print("setInitLocation: Can't get current location")
            return false}
        guard let heading = getHeading() else {
            print("setInitLocation: Can't get current heading")
            return false}
        
        var startHeading = 0.0
        if headingRef == "camera"{
            // Include camera yaw in heading
            startHeading = heading + self.gimbal.yawRelativeToHeading
        }
        else if headingRef == "drone"{
            // Ignore camera yaw
            startHeading = heading
        }
        else{
            print("argument faulty")
            return false
        }
        
        
        // GimbalYawRelativeToHeading is forced to 0. If gimbal yaw shoulb be in cluded it is alreade added to heading.
        self.initLoc.setPosition(lat: lat, lon: lon, alt: alt, heading: startHeading, gimbalYawRelativeToHeading: 0, isInitLocation: true, initLoc: self.initLoc){}
        self.initLoc.printLocation(sentFrom: "setInitLocation")
        // Not sure if sleep is needed, but loc.setPosition uses initLoc. Completion handler could be used.
        usleep(200000)
        
        Dispatch.main {
            // Update the loc, this is first chance for it to calc XYZ and NED
            self.loc.setPosition(lat: lat, lon: lon, alt: alt, heading: heading, gimbalYawRelativeToHeading: self.gimbal.yawRelativeToHeading, initLoc: self.initLoc){
                NotificationCenter.default.post(name: .didPosUpdate, object: nil)
            }
                    
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "InitLocation set to here including gimbalYaw."])
        }
        
        return true
    }

    // **************************************************************
    // Caution: The strange altitude datum of dji shall be used here!
    func setAutoPilotHomeLocation(completionHandler: @escaping (Bool) -> Void){
        print(" NOT TESTED set autopilot home. Note dji altitude datum used")
        guard let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) else {
            NSLog("Couldn't create the key")
            completionHandler(false)
            return
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            completionHandler(false)
            return
        }
                
        if let locationValue = keyManager.getValueFor(locationKey) {
            let location = locationValue.value as! CLLocation
            self.flightController?.setHomeLocation(location, withCompletion:{(error) in
                if error != nil{
                    print("An error occured when setting home wp")
                    completionHandler(false)
                    return
                }
                else{
                    completionHandler(true)
                    return
                }
            })
        }
        completionHandler(false)
    }
        
    //**************************************************************************************************
    // Clears the DSS smart rtl list and adds current location as DSS home location, also saves heading.
    func resetDSSSRTLMission()->Bool{
        guard let heading = getHeading() else {
            return false
        }
        // Get the optional lat, lon, alt.
        let (optLat, optLon, optAlt) = self.getCurrentLocation()
        // Gurad any nil values. Return false if nil.
        guard let lat = optLat else {
            return false}
        guard let lon = optLon else {
            return false}
        guard let alt = optAlt else {
            return false}
        
        // Reset dssSmartRtlMission
        self.dssSmartRtlMission = JSON()
        let id = "id0"
        self.dssSmartRtlMission[id] = JSON()
        self.dssSmartRtlMission[id]["lat"] = JSON(lat)
        self.dssSmartRtlMission[id]["lon"] = JSON(lon)
        self.dssSmartRtlMission[id]["alt"] = JSON(alt)
        self.dssSmartRtlMission[id]["speed"] = JSON(5)
        self.dssSmartRtlMission[id]["heading"] = JSON(heading)
        self.dssSmartRtlMission[id]["action"] = JSON("land")
        
        if alt - self.initLoc.altitude < 2 {
            print("reserDSSSRTLMission: Forcing land altitude to 2m min")
            self.dssSmartRtlMission[id]["alt"].doubleValue = self.initLoc.altitude + 2
        }
        
        print("resetDSSSRTLMission: DSS SRTL reset: ", self.dssSmartRtlMission)
        return true
    }
    
    //******************************************************
    // Appends current location to the DSS smart rtl mission
    func appendLocToDssSmartRtlMission()->Bool{
        // TODO, should copy loc instead, but it is not supported yet..
        // Get the optional lat, lon, alt.
        let (optLat, optLon, optAlt) = self.getCurrentLocation()
        // Gurad any nil values. Return false if nil.
        guard let lat = optLat else {
            return false}
        guard let lon = optLon else {
            return false}
        guard let alt = optAlt else {
            return false}
        
        
        var wpCnt = 0
        // Find what wp id to add next. If mission is empty result will be id0
        for (_,_):(String, JSON) in self.dssSmartRtlMission {
            // Check wp-numbering
            if self.dssSmartRtlMission["id" + String(wpCnt)].exists() {
                wpCnt += 1
            }
        }
     
        print("appendLocToDssSmartRtlMission: id to add: ", wpCnt)
        let id = "id" + String(wpCnt)
        self.dssSmartRtlMission[id] = JSON()
        self.dssSmartRtlMission[id]["lat"] = JSON(lat)
        self.dssSmartRtlMission[id]["lon"] = JSON(lon)
        self.dssSmartRtlMission[id]["alt"] = JSON(alt)
        self.dssSmartRtlMission[id]["heading"] = JSON("course")
        self.dssSmartRtlMission[id]["speed"] = JSON(self.activeWP.speed)
        return true
    }

    
    //*************************************
    // Get current location as lat, lon, alt. Altitude is alt relative to takeoff (baro) + the takeoff alt from iPhone via Settings screen. Always guard the result before using it.
    func getCurrentLocation()->(Double?, Double?, Double?){
        guard let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) else {
            NSLog("Couldn't create the key")
            return (nil, nil, nil)
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return (nil, nil, nil)
        }
                
        if let locationValue = keyManager.getValueFor(locationKey) {
            let location = locationValue.value as! CLLocation
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude
            let alt = location.altitude + self.loc.takeOffLocationAltitude
            return (lat, lon, alt)
        }
     return (nil, nil, nil)
    }
    
    // ********************************
    // Get current heading as a Double?
    func getHeading()->Double?{
        guard let headingKey = DJIFlightControllerKey(param: DJIFlightControllerParamCompassHeading) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let headingValue = keyManager.getValueFor(headingKey) {
            let heading = headingValue.value as! Double
            return heading
        }
        return nil
    }
    
    //*****************************************
    // Get the isFlying parameter from the DJI.
    func getIsFlying()->Bool?{
        guard let flyingKey = DJIFlightControllerKey(param: DJIFlightControllerParamIsFlying) else {
            NSLog("Couldn't create the key")
            return nil
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
                
        if let flyingValue = keyManager.getValueFor(flyingKey) {
            let flying = flyingValue.value as! Bool
            // Handle takingOffToAlt as not flying
            return flying
        }
        return nil
    }

    
    //***************************************************************************
    // Get the areMotorsOn parameter from the DJI. Default to true, safest option
    func getAreMotorsOn()->Bool{
        guard let areMotorsOnKey = DJIFlightControllerKey(param: DJIFlightControllerParamAreMotorsOn) else {
            NSLog("Couldn't create the key")
            return true
        }

        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return true
        }
                
        if let areMotorsOnValue = keyManager.getValueFor(areMotorsOnKey) {
            let areMotorsOn = areMotorsOnValue.value as! Bool
            return areMotorsOn
        }
        return true
    }
    
        
    //*************************************************************************************
    // Makes sure that value is within -lim < value < lim, if not value is limited to limit
    func limitToMax(value: Float, limit: Float)-> Float{
        if value > limit {
            return limit
        }
        else if value < -limit {
            return -limit
        }
        else {
            return value
        }
    }
    
    //***************************************
    // Limit a value to lower and upper limit
    func withinLimit(value: Double, lowerLimit: Double, upperLimit: Double)->Bool{
        if value > upperLimit {
            //print(value, upperLimit, lowerLimit)
            return false
        }
        else if value < lowerLimit {
            //print(value, lowerLimit, upperLimit)
            return false
        }
        else {
            //print(value, lowerLimit, upperLimit)
            return true
        }
    }


    //**************************************************************************************************
    // Stop ongoing stick command, invalidate all related timers. TODO: handle all modes, stop is stop..
    func stop(exceptCA: Bool = true){
        _invalidateTimers(exceptCA: exceptCA)
        // This following causes an error if called during landing or takeoff for example. The copter is not in stick mode then.
        //sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
    }
    
    // *****************************************************
    // Invalidates the control timers, resets their counters
    func _invalidateTimers(exceptCA: Bool){
        // InvalidateTimers is called prior to any controller being activated. Idle will be activated when entering idleCtrl again
        idle = false
        stopTimer(timer: duttTimer)
        duttTimer = nil
        stopTimer(timer: posCtrlTimer)
        posCtrlTimer = nil
        stopTimer(timer: pattern.velCtrlTimer)
        pattern.velCtrlTimer = nil
        stopTimer(timer: idleCtrlTimer)
        idleCtrlTimer = nil

        // When do we want to stop it?
        // Stop collision avoidance timer and reset it
        if !exceptCA{
            self.setCollisionAvoidance(enable: false)
        }
        
        duttLoopCnt = 0
        posCtrlLoopCnt = 0
        pattern.velCtrlLoopCnt = 0
        
        yawErrorIntegrated = 0
    }
    

    
    //***********************************************************
    // Disable the virtual sticks mode, PILOT or DSS took control
    func stickDisable(){
        // Stop copter and all control timers
        self.stop(exceptCA: false)
        
        // Set flight controller mode
        self.flightController?.setVirtualStickModeEnabled(false, withCompletion: { (error: Error?) in
            if error == nil{
                //print("stickDisable: Sticks disabled")
            }
            else{
                print("stickDisable: Virtual stick mode change did not go through" + error.debugDescription)
            }
        })
    }

    //**************************************************************
    // Enable the virtual sticks mode and reset reference velocities
    func stickEnable(){
        // Reset any speed set
        self.refVelBodyX = 0
        self.refVelBodyY = 0
        self.refVelBodyZ = 0
        self.refYawRate = 0
        
        // Set flight controller mode
        self.flightController?.setVirtualStickModeEnabled(true, withCompletion: { (error: Error?) in
            if error == nil{
                //print("stickEnable: Sticks enabled")
                // Enable idleCtrl to make collision avoidance able to act on ctrl signals
                self.idleCtrl()
                // Enable collision avoidance
                self.setCollisionAvoidance(enable: true)
            }
            else{
                print("stickEnable: Virtual stick mode change did not go through" + error.debugDescription)
            }
        })
    }
    
    func setCollisionAvoidance(enable: Bool){
        // Enable or disable the caluclation of collision avoidance manouvers
        if enable{
            if caTimer == nil{
                print("Enabling collision avoidance")
                caTimer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(fireCaTimer), userInfo: nil, repeats: true)
            }
        }
        else{
            // Could/should be moved to invalidate timers
            print("Disabling collision avoidance")
            stopTimer(timer: caTimer)
            caTimer = nil
            }
        // Init collision avoidance to 0
        caVelBodyX = 0
        caVelBodyY = 0
        caVelBodyZ = 0
    }
    
    @objc func fireCaTimer(_ timer: Timer){
        // Calc induvidual CA vel components
        var caVelX: Float = 0
        var caVelY: Float = 0
        
        // Excempt take off from collision avoidance.
        // Don't calc CA if we are not flying or if we are climbing to alt during take-off
        let flying = getIsFlying() ?? false
        if flying == false || self.takingOffToAlt {
            // We are climbing to take off altitude, do not interfere
            self.caVelBodyX = 0
            self.caVelBodyY = 0
            return
        }
        
        for (dssId, loc) in clientLoc{
            // Distances and bearing from me to client
            let (_, _, dAlt, distance2D, _, bearing) = self.loc.distanceTo(wpLocation: loc)
            // Check if alt diff is critical
            if abs(dAlt) > self.relAltLimitCA{
                // No conflict
                continue
            }
            
            // Get Closest point of approach to dssId and calc collision avoidance speed
            let (tCPA, dCPA) = self.loc.closestPointOfApproachTo(wpLocation: loc)
            guard let caSpeed = calcCaSpeedCPA(tCPA: tCPA, dCPA: dCPA) else {
                continue
            }
            
            // CA has a speed contribution, nortify user, max 1Hz
            if CACurrentMediaTime() - self.lastCaNotification > 1{
                var logMessage = ""
                let distStr = String(round(distance2D*100)/100)
                if distance2D < 5{
                    logMessage = "Error: Too close to " + dssId + ": " + distStr + "m"
                    print(self.loc.printLocation(sentFrom: "My location"))
                    print(loc.printLocation(sentFrom: "Location of " + dssId))
                }
                else if distance2D < 15{
                    logMessage = "Warning: Avoiding collision: " + dssId + ": " + distStr + "m"
                }
                else{
                    logMessage = "Avoiding collision to : " + dssId + ": " + distStr + "m"
                }
                NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": logMessage])
                self.lastCaNotification = CACurrentMediaTime()
            }
            
            // Calc how to apply braking force, Rule: 'Look at the threat and move right or left'
            // Threat is in direction bearing
        
            // Evalute if turning right or left is best
            // Transform ca direction and speed to velN velE
                        
            let (rightTurnVelN, rightTurnVelE) = getVelNE(courseRef: bearing + 90, speed: caSpeed)
            let (leftTurnVelN, leftTurnVelE) = getVelNE(courseRef: bearing - 90, speed: caSpeed)
            
            // TODO min time should be smaller than 0.5
            let predictionWin = max(0.5, tCPA)
            // Make predictions with corrective actions
            let rightOption = self.loc.predictLocation(deltaT: Double(predictionWin), deltaVelN: rightTurnVelN, deltaVelE: rightTurnVelE)
            let leftOption = self.loc.predictLocation(deltaT: Double(predictionWin), deltaVelN: leftTurnVelN, deltaVelE: leftTurnVelE)
            let threatPoint = loc.predictLocation(deltaT: Double(predictionWin), deltaVelN: 0, deltaVelE: 0)
            
            // Compare predictions to each other
            let (_, _, _, rightOption2D,_ , _) = rightOption.distanceTo(wpLocation: threatPoint)
            let (_, _, _, leftOption2D,_ , _) = leftOption.distanceTo(wpLocation: threatPoint)
         
            var brakeDirection = bearing
            if rightOption2D >= leftOption2D{
                // Turn right
                brakeDirection += 90
                print("Avoiding right                          > > > > > > > > > > > > > > >")
            }
            else{
                // Turn left
                brakeDirection -= 90
                print("Avoiding left < < < < < < < < < < < < <                              ")

            }
            
            let (velX, velY) = getVelXY(courseRef: brakeDirection, heading: self.loc.heading, speed: caSpeed)
            caVelX += velX
            caVelY += velY
        }
        // Update global collistion avoidance velocities
        self.caVelBodyX = caVelX
        self.caVelBodyY = caVelY
    }
    
    func calcCaSpeedCPA(tCPA: Float, dCPA: Float)->Float?{
        // Refer to excel in droneSpace
        let dLim: Float = 10
        let tLim: Float = 4
        
        if dCPA > dLim {
            return nil
        }
        else if tCPA > tLim{
            return nil
        }

        // Collision avoidance needed
        // T/(dCPA + tA*tCPA) - T/N
        var tA: Float = 1
        var T: Float = 50
        var N: Float = 15
        if tCPA > 2{
            tA = dLim/tLim
            T = 70
            N = 20
        }
        
        let caSpeed = min(T/(dCPA + tA*tCPA) - T/N, self.caMaxbrake)
        // Protect bad function parameters returning negative speed
        return max(0,caSpeed)
    }

    
    // ***********************************************************************
    // Send velocity command 0 in idle to allow collision avoidance to operate
    func idleCtrl(){
        // This function is called from invalidate timers, do not call it again
        if self.getIsFlying() ?? false{
            // Since idleCtrl is used to trigger take-off completed, set takingOffToAlt to false if flying
            self.takingOffToAlt = false
            self.stop()
            self.idle = true
            if self.idleCtrlTimer == nil{
                self.idleCtrlTimer = Timer.scheduledTimer(timeInterval: self.sampleTime/1000, target: self, selector: #selector(self.fireIdleCtrlTimer), userInfo: nil, repeats: true)
            }
        }
    }
    
    //******************************************************************************
    // Sned a velocity command for a 2 second period, dutts the aircraft in x, y, z, yaw.
    func dutt(x: Float, y: Float, z: Float, yawRate: Float){
        // Stop any ongoing mission
        self.missionIsActive = false
        // limit to max
        self.refVelBodyX = limitToMax(value: x, limit: xyVelLimit/100)
        self.refVelBodyY = limitToMax(value: y, limit: xyVelLimit/100)
        self.refVelBodyZ = limitToMax(value: z, limit: zVelLimit/100)
        self.refYawRate = limitToMax(value: yawRate, limit: yawRateLimit)
        
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz. DuttTimer will execute control commands for a period of time
        stop()
        if duttTimer == nil{
            duttTimer = Timer.scheduledTimer(timeInterval: sampleTime/1000, target: self, selector: #selector(fireDuttTimer), userInfo: nil, repeats: true)
        }
    }
    
    //******************************************************************************************************************
    // Send controller data. Called from Timer that send commands every x ms. Stop timer to stop commands.
    func sendControlData(velX: Float, velY: Float, velZ: Float, yawRate: Float, speed: Float) {
        
        // Check desired horizontal speed towards limitations
        let horizontalVel = sqrt(velX*velX + velY*velY)
        let horizontalVelCa = min(sqrt(self.caVelBodyX*self.caVelBodyX + self.caVelBodyY*self.caVelBodyX), xyVelLimit/100)
        
        // Finds the most limiting speed constriant. Missions are checked for negative speed.
        let limitedVelRef = min(horizontalVel, speed, xyVelLimit/100-horizontalVelCa)
        // Calculate same reduction factor to x and y to maintain direction
        var factor: Float = 1
        if limitedVelRef < horizontalVel{
            factor = limitedVelRef/horizontalVel
        }
        
        // Make sure velocity limits are respected.
        let limitedVelRefX = factor * velX
        let limitedVelRefY = factor * velY
        let limitedVelRefZ = limitToMax(value: velZ, limit: zVelLimit/100)
        let limitedYawRateRef: Float = limitToMax(value: yawRate, limit: yawRateLimit)
        
        // Add any collision avoidance velocity - without limitations
        let caVelX = limitedVelRefX + self.caVelBodyX
        let caVelY = limitedVelRefY + self.caVelBodyY
        //let vZ = velZ + self.caVelBodyZ
        
        
        // Construct the flight control data object. Roll axis is pointing forwards but we use velocities..
        // The coordinate mapping:
        // controlData.verticalThrottle = velZ // in m/s
        // controlData.roll = velX
        // controlData.pitch = velY
        // controlData.yaw = yawRate
        var controlData = DJIVirtualStickFlightControlData()
        controlData.verticalThrottle = -limitedVelRefZ
        controlData.roll = caVelX
        controlData.pitch = caVelY
        controlData.yaw = limitedYawRateRef
        
        // Check that the heading mode is correct, it seems it has changed without explanation a few times.
        if (self.flightController?.yawControlMode.self == DJIVirtualStickYawControlMode.angularVelocity){
            self.flightController?.send(controlData, withCompletion: { (error: Error?) in
                if error != nil {
                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "sendControlData: Error:" + error.debugDescription])
                    // Disable the timer(s) and idle
                    self.idleCtrl()
                }
                else{
                    //_ = "flightContoller data sent ok"
                }
            })
        }
        else{
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: YawControllerMode is not correct"])
            print("DJIVirtualStickYawControlMode is not longer angularVelocity!")
            self.flightController?.yawControlMode = DJIVirtualStickYawControlMode.angularVelocity
        }
    }
    
    //****************************************************************************************
    // Set altitude function. Climbs/descends to the desired altitude at the current position.
    func setAlt(targetAlt: Double){
        print("setAlt: Target alt:", targetAlt, "current alt: ", self.loc.altitude)
        self.activeWP.altitude = targetAlt
        self.activeWP.heading = self.loc.heading
        self.activeWP.coordinate.latitude = self.loc.coordinate.latitude
        self.activeWP.coordinate.longitude = self.loc.coordinate.longitude
        self.activeWP.speed = 0
        self.activeWP.trackingPrecision = 3
        self.activeWP.action = ""
        goto()
    }

    
    func setHeading(targetHeading: Double){
        print("setHeading: Target heading:", targetHeading, "current heading: ", self.loc.heading)
        self.activeWP.altitude = self.loc.altitude
        self.activeWP.heading = targetHeading
        self.activeWP.coordinate.latitude = self.loc.coordinate.latitude
        self.activeWP.coordinate.longitude = self.loc.coordinate.longitude
        self.activeWP.speed = 0
        self.activeWP.trackingPrecision = 3
        goto()
    }
    
    // ***************************************************
    // Take off function, does not have reference altitude
    func takeOff(){
        print("TakeOff function")
        self.takingOffToAlt = true
        self.flightController?.startTakeoff(completion: {(error: Error?) in
            if error != nil{
                print("takeOff: Error, " + String(error.debugDescription))
            }
            else{
                //print("TakeOff else clause")
            }
        })
    }
    
    // *****************************
    // Land at the current location
    func land(){
        self.flightController?.startLanding(completion: {(error: Error?) in
            if error != nil{
                print("Landing error: " + String(error.debugDescription))
            }
            else{
                // _ = "Landing command accepted"
            }
            
        })
    }
    
    // **************************************************************************************************************
    // Activates the autopilot rtl, if it fails the completion handler is called with false, otherwise true
    func rtl(){
        // Stop any ongoing action
        self.stickDisable()
        self.takingOffToAlt = false
            
        // Check if we are flying first.
        // The nil-coalescing operator (a ?? b) unwraps an optional a if it contains a value, or returns a default value b if a is nil.
        // Condition is true if getIsFlying returns true. RTL can abort ongoing take-off
        if self.getIsFlying() ?? false {
            // Activate the autopilot rtl function
            self.flightController?.startGoHome(completion: {(error: Error?) in
                // Completion code runs when the method is invoked (right away)
                if error != nil {
                    print("rtl: error: ", String(describing: error))
                }
                else {
                    // It takes ~1s to get here, although the reaction is immidiate.
                    _ = "Command accepted by autopilot"
                }
            })
        }
    }
    
    // ******************************************************************************************************************
    // dssSrtl activates the DSS smart rtl function that backtracks the flow mission. It includes landing after hovertime
    func dssSrtl(hoverTime: Int){
        // Store hovertime globally. Should implement hovertime as parameter in action: "landing" and just update the smartRTL mission.
        self.hoverTime = hoverTime
        // Reverse the dssSmartRtlMission and activate it
        // Find the last element
        let last_wp = dssSmartRtlMission.count - 1
                
        // Build up a tempMission with reversed correct order
        var tempMission: JSON = JSON()
        let wps = Countdown(count: last_wp) // could use counter in for loop, but found this way of creating a sequence
        var dss_cnt = 0
        for wp in wps {
            let temp_id = "id" + String(wp)
            let dss_id = "id" + String(dss_cnt)
            tempMission[temp_id] = dssSmartRtlMission[dss_id]
            dss_cnt += 1
        }
        self.pendingMission = tempMission
        
        print("The inverted (corrected) DSSrtl mission: ", pendingMission)
        
        _ = self.gogo(startWp: 0, useCurrentMission: false, isDssSrtl: true)
        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "DSS Smart RTL activated"])
    }

    
    //*************************************************************************************************
    // Checks an uploaded mission. If ok it is stored as pending mission. Activate it by sending to wp.
    func uploadMission(mission: JSON)->(fenceOK: Bool, fenceDescr: String, numberingOK: Bool, numberingDescr: String, speedOK: Bool, speedDescr: String, actionOK: Bool, actionDescr: String, headingOK: Bool, headingDescr: String){
        // Init return values
        var fenceOK = true
        var fenceDescr = ""
        var numberingOK = true
        var numberingDescr = ""
        var speedOK = true
        var speedDescr = ""
        var actionOK = true
        var actionDescr = ""
        var headingOK = true
        var headingDescr = ""
        
        var wpCnt = 0
        let tempWP = MyLocation()

        // Check wp-numbering, and for each wp in mission check its properties, note the wpCnt and wpID are not in the same order!
        for (wpID,subJson):(String, JSON) in mission {
            // Temporarily parse from mission to MyLocation. StartWP is used to calc NED and XYZ to LLA, geofence etc
            tempWP.setUpFromJsonWp(jsonWP: subJson, defaultSpeed: self.defaultHVel, initLoc: self.initLoc)
            // Check wp numbering
            if mission["id" + String(wpCnt)].exists()
            {
                // Check for geofence violation
                if !self.initLoc.geofenceOK(wp: tempWP){
                    fenceOK = false
                    fenceDescr = "Geofence violation, " + wpID
                }
                
                // Check action ok, if there is an action
                if tempWP.action != ""{
                    if tempWP.action == "take_photo"{
                        _ = "ok"
                    }
                    else {
                        actionOK = false
                        actionDescr = "WP action not supported, " + wpID
                    }
                }
                
                // Check speed setting not too low
                if tempWP.speed < 0.1 {
                    speedOK = false
                    speedDescr = "Speed below 0.1, " + wpID
                }
                
                // Check for heading error
                if tempWP.heading == -99{
                    headingOK = false
                    headingDescr = "Heading faulty, " + wpID
                }
                
                // Continue the for loop
                wpCnt += 1
                continue
            }
            else{
                // Oops, wp numbering was faulty
                numberingOK = false
                numberingDescr = "Wp numbering faulty, missing id" + String(wpCnt)
            }
        }
        // Accept mission as pending mission if everything is ok
        if fenceOK && numberingOK && speedOK && actionOK && headingOK{
            self.pendingMission = mission
        }
        // Return results
        return (fenceOK, fenceDescr, numberingOK, numberingDescr, speedOK, speedDescr, actionOK, actionDescr, headingOK, headingDescr)
    }

    
    //**********************************
    // Returns the wp action of wp idNum
    func getAction(idNum: Int)->String{
        let id = "id" + String(idNum)
        if self.mission[id]["action"].exists(){
            return self.mission[id]["action"].stringValue
        }
        else{
            return ""
        }
    }
    
    // ******************************************************************************************************************************
    // Tests if some parameters are not nil. These parameters are used in the mission control and will not be checked each time there
    func isReadyForMission()->(Bool){
        // TODO - why not using isInitLocation?
        if self.initLoc.coordinate.latitude == 0 {
            print("readyForMission Error: No start location")
            return false
        }
        else if self.getHeading() == nil {
           print("readyForMission Error: Error updating heading")
           return false
        }
        else{
            return true
        }
    }
    
    //******************************************************************************************
    // Step up mission next wp if it exists, otherwise report -1 to indicate mission is complete
    func setMissionNextWp(num: Int){
        if mission["id" + String(num)].exists(){
            self.missionNextWp = num
            self.missionNextWpId = "id" + String(num)
        }
        else{
            self.missionNextWp = -1
            self.missionNextWpId = "id-1"
        }
        self.missionType = self.getMissionType()
    }
    
    
    // ****************************************************
    // Return the missionType string of the current mission
    func getMissionType()->String{
    if self.mission["id0"]["x"].exists() {return "XYZ"}
    if self.mission["id0"]["north"].exists() {return "NED"}
    if self.mission["id0"]["lat"].exists() {return "LLA"}
    return ""
    }

    // *************************************************************************************************
    // Prepare a MyLocation for mission execution, then call goto. New implementeation of gogo
    func gogo(startWp: Int, useCurrentMission: Bool, isDssSrtl: Bool = false)->Bool{
        // Set dssSrtlActive flag here since it is only missions that adds wp to dssSrtl. Check flag when reaching a wp.
        if isDssSrtl {
            dssSrtlActive = true
        }
        else{
            dssSrtlActive = false
        }
        
        // useCurrentMission?
        if useCurrentMission {
            self.setMissionNextWp(num: startWp)
            if self.missionNextWp == -1{
              NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["currentWP": String(self.missionNextWp), "finalWP": String(mission.count-1)])
                return true
            }
            else{
                self.missionIsActive = true
            }
        }
        // Check if there is a pending mission
        else{
            if self.pendingMission["id" + String(startWp)].exists(){
                self.mission = self.pendingMission
                self.missionNextWp = startWp
                self.missionType = self.getMissionType()
                self.missionIsActive = true
                print("gogo: missionIsActive is set to true")
            }
            else{
                print("gogo - Error: No such wp id in pending mission: id" + String(startWp))
                return false
            }

        }
        // Check if ready for mission, then setup the wp and gogo. Convert any coordinate system to LLA.
        if isReadyForMission(){
            // Reset the activeWP TODO - does this cause a memory leak? If so create a reset function. Test in playground.
            let id = "id" + String(self.missionNextWp)
            self.activeWP.setUpFromJsonWp(jsonWP: self.mission[id], defaultSpeed: self.defaultHVel, initLoc: self.initLoc)
            print(self.mission[id])
            self.activeWP.printLocation(sentFrom: "gogo")

            self.goto()
            //self.gotoXYZ(refPosX: x, refPosY: y, refPosZ: z, localYaw: yaw, speed: speed)

            // Notify about going to startWP
            NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["currentWP": String(self.missionNextWp), "finalWP": String(mission.count-1)])
            return true
        }
        else{
            print("gogo - Error: Aircraft or mission not ready for mission flight")
            return false
        }
    }
    
    // *********************************************************************************
    // Activate posCtrl towards a self.activeWP, independent of ref (LLA, NED, XYZ).
    func goto(){
        // Check some Geo fence stuff. Ask initLoc if the wp is within the geofence.
        if !initLoc.geofenceOK(wp: self.activeWP){
            print("The WP violates the geofence!")
            return
        }
        
        // Set gimbal if available in wp
        if let pitch = self.activeWP.refGimbalPitch{
            self.gimbal.gimbalPitchRef = pitch
        }
        // Fire posCtrl
        stop()
        if posCtrlTimer == nil{
            self.posCtrlTimer = Timer.scheduledTimer(timeInterval: sampleTime/1000, target: self, selector: #selector(self.firePosCtrlTimer), userInfo: nil, repeats: true)
        }
    }

    
    //
    // Algorithm for detemining if at WP is tracked. When tracked mission can continue.
    // Algorithm requires both position and yaw to be tracked according to globally defined tracking limits.
    func trackingWP()->Bool{
        var trackingRecordTarget: Int = 0
        var trackingPosLimit:Double = 0.0
        var trackingAltLimit:Double = 0.0
        var trackingYawLimit:Double = 0.0
        
        switch self.activeWP.trackingPrecision{
        case 1:
            // Note: Turn factor will make drone stop anyways
            trackingRecordTarget = 2
            trackingPosLimit = 15
            trackingAltLimit = 4
            trackingYawLimit = 10
        case 2:
            // Note: Turn factor will make drone stop anyways
            trackingRecordTarget = 2
            trackingPosLimit = 10
            trackingAltLimit = 3
            trackingYawLimit = 8
        case 3:
            // Note: Turn factor will make drone stop anyways
            trackingRecordTarget = 4
            trackingPosLimit = 3
            trackingAltLimit = 1
            trackingYawLimit = 6
        case 4:
            trackingRecordTarget = 6
            trackingPosLimit = 1
            trackingAltLimit = 0.6
            trackingYawLimit = 5
        case 5:
            trackingRecordTarget = 8
            trackingPosLimit = 0.3
            trackingAltLimit = 0.3
            trackingYawLimit = 4
        default:
            trackingRecordTarget = 8
            trackingPosLimit = 0.3
            trackingAltLimit = 0.3
            trackingYawLimit = 4
        }
        
        // Distance in meters
        let (_, _, dAlt, distance2D, _, _) = self.activeWP.distanceTo(wpLocation: self.loc)
        let yawError = abs(getDoubleWithinAngleRange(angle: self.loc.heading - self.refYawLLA))
        
        // Tracking?
        if distance2D < trackingPosLimit && abs(dAlt) < trackingAltLimit && yawError < trackingYawLimit {
            self.activeWP.trackingRecord += 1
        }
        else {
            self.activeWP.trackingRecord = 0
        }
        if self.activeWP.trackingRecord >= trackingRecordTarget{
            // WP is tracked!
            self.activeWP.trackingRecord = 0
            return true
        }
        else{
            return false
        }
    }
    
    // MARK: Start follow stream
    func startFollowStream(){
        print("startFollowStream")
        // Fire velCtrl towards stream and pattern
        stop()
        if self.pattern.velCtrlTimer == nil {
            self.pattern.velCtrlTimer = Timer.scheduledTimer(timeInterval: sampleTime/1000, target: self, selector: #selector(self.fireVelCtrlTimer), userInfo: nil, repeats: true)
        }
    }
    

    // ******************************************************************
    // Timer function that hovers and lets collision avoidance to operate
    @objc func fireIdleCtrlTimer(){
        print("...............................................................................idle")
        sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
    }
    
    //************************************************************************************************************
    // Timer function that loops every sampleTime ms until timer is invalidated. Each loop control data (joystick) is sent.
    @objc func fireDuttTimer() {
        duttLoopCnt += 1
        // Abort due to Maxtime for dutts
        if duttLoopCnt >= duttLoopTarget {
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            idleCtrl()
        }
        else {
            // Speed argument acts as an upper limit not intended for this way to call the function. Set it high. Vel limits will apply.
            sendControlData(velX: self.refVelBodyX, velY: self.refVelBodyY, velZ: self.refVelBodyZ, yawRate: self.refYawRate, speed: 999)
        }
    }
    
    // *****************************************************************************************
    // Timer function that executes the position controller. It flies towards the self.activeWP.
    @objc func firePosCtrlTimer(_ timer: Timer) {
        posCtrlLoopCnt += 1

        // Abort due to Maxtime for flying to wp
        if posCtrlLoopCnt >= posCtrlLoopTarget{
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)

            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: wp max time exeeded"])
            idleCtrl()
        }
        
        // Test if activeWP is tracked or not
        else if trackingWP(){
            print("firePosCtrlTimer: Wp", self.missionNextWp, " is tracked")
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
                
                // Add tracked wp to smartRTL if not on smartRTL mission.
            if self.missionNextWp != -1 && !dssSrtlActive && self.activeWP.action != "calibrate"{
                    if self.appendLocToDssSmartRtlMission(){
                        //NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Location was added to DSS smart RTL mission"])
                    }
                    else {
                        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Caution: Current location was NOT added to DSS smart rtl"])
                    }
                }
                
                // activeWP is tracked. Now, if we are on a mission:
            if self.missionIsActive{
                // check for wp action
                let action = self.activeWP.action
                if action == "take_photo"{
                    // Notify action to be executed
                    NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
                    // Stop mission, Notifier function will re-activate the mission and send gogo with next wp as reference
                    self.missionIsActive = false
                    stop()
                    return
                }
                if action == "land"{
                    let secondsSleep: UInt32 = UInt32(self.hoverTime*1000000)
                    usleep(secondsSleep)
                    NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
                    self.missionIsActive = false
                    stop()
                    return
                }
                if action == "calibrate"{
                    NotificationCenter.default.post(name: .didWPAction, object: self, userInfo: ["wpAction": action])
                    // Stop mission, notifier gives control to pilot who can reactivate the mission by the calibrate cursor
                    stop()
                    return
                }
                // Note that the current mission is stoppped (paused) if there is a wp action.
                self.setMissionNextWp(num: self.missionNextWp + 1)
                if self.missionNextWp != -1{
                    let id = "id" + String(self.missionNextWp)
                    self.activeWP.setUpFromJsonWp(jsonWP: self.mission[id], defaultSpeed: self.defaultHVel, initLoc: self.initLoc)
                    
                    self.activeWP.printLocation(sentFrom: "firePosCtrlTimer")
                    goto()
                }
                else{
                    print("id is -1")
                    self.missionIsActive = false
                    idleCtrl()
                }
                NotificationCenter.default.post(name: .didNextWp, object: self, userInfo: ["currentWP": String(self.missionNextWp), "finalWP": String(mission.count-1)])
            }
            else {
                print("No mission is active")
                idleCtrl()
            }
        } // end if trackingWP

        // The controller: Calculate BODY control commands from lat long reference frame:
        // Get distance and bearing from here to wp
        let (northing, easting, dAlt, distance2D, _, bearing) = self.loc.distanceTo(wpLocation: self.activeWP)
        
        // Set reference Yaw. Heading equals bearing or manually set? Only check once per wp. If bearing becomes exactly -1 it will be evaluated agian, that is ok.
        if self.activeWP.heading == -1{
            self.activeWP.heading = bearing
        }
        self.refYawLLA = self.activeWP.heading
        
        // Calculate yaw-error, use shortest way (right or left?)
        let yawError = getFloatWithinAngleRange(angle: (Float(self.loc.heading - self.refYawLLA)))
        // P-controller for Yaw
        self.refYawRate = -yawError*yawKP
        // Feedforward TBD
        //let yawFF = self.refYawRate*yawFFKP*0
        
        //print("bearing: ", bearing, "reYawLLa: ", self.refYawLLA, "refYawRate: ", self.refYawRate)
        
        // Punish horizontal velocity on yaw error. Otherwise drone will not fly in straight line
        var turnFactor: Float = 1                    //let turnFactor2 = pow(180/(abs(yawError)+180),2) - did not work without feed forward
        if abs(yawError) > 10 {
            turnFactor = 0
        }
        else{
            turnFactor = 1
        }
        
        guard let checkedHeading = self.getHeading() else {return}
        //let alphaRad = (checkedHeading + Double(yawFF))/180*Double.pi
        
        // Rotate from NED to Body
        let alphaRad = checkedHeading/180*Double.pi
        // xDiffBody is in body coordinates
        let xDiffBody = Float(northing * cos(alphaRad) + easting * sin(alphaRad))
        let yDiffBody = Float(-northing * sin(alphaRad) + easting * cos(alphaRad))

        // If ETA is low, reduce speed (brake in time)
        var speed = self.activeWP.speed
        let vel = Float(sqrt(pow(self.loc.vel.bodyX,2)+pow(self.loc.vel.bodyY ,2)))
        
        //hdrpano:
        //decellerate at 2m/s/s
        // at distance_to_wp = Speed/2 -> brake
        if Float(distance2D) < etaLimit * vel {
            // Slow down to half speed (dont limit more than to 1.5 though) or use wp speed if it is lower.
            speed = min(max(vel/2,1.5), speed)
            //print("Braking!")
        }
        // Calculate a divider for derivative part used close to target, avoid zero..
        var xDivider = abs(xDiffBody) + 1
        if xDiffBody < 0 {
            xDivider = -xDivider
        }
        var yDivider = abs(yDiffBody) + 1
        if yDiffBody < 0 {
            yDivider = -yDivider
        }

        // Calculate the horizontal reference speed. (Proportional - Derivative)*turnFactor
        self.refVelBodyX = (xDiffBody*hPosKP - hPosKD*Float(self.loc.vel.bodyX)/xDivider)*turnFactor
        self.refVelBodyY = (yDiffBody*hPosKP - hPosKD*Float(self.loc.vel.bodyY)/yDivider)*turnFactor
        
        // Calc refVelZ
        self.refVelBodyZ = Float(-dAlt) * vPosKP
    
        // TODO, do not store reference values globally?
        self.sendControlData(velX: self.refVelBodyX, velY: self.refVelBodyY, velZ: self.refVelBodyZ, yawRate: self.refYawRate, speed: speed)
    }
    
    
    
    // **************************************************************************************************************************************************************************
    // Timer function that executes the velocity controller in pattern mode. It flies towards the stream plus the self.pattern. (Stream is updating the pattern property .stream)
    @objc func fireVelCtrlTimer(_ timer: Timer) {
        
        let pattern = self.pattern.pattern.name
        let desAltDiff = self.pattern.pattern.relAlt
        let headingMode = self.pattern.pattern.headingMode
        let desHeading = self.pattern.pattern.heading
        let desYawRate = self.pattern.pattern.yawRate
        let radius = self.pattern.pattern.radius
        var refYaw: Double = 0
        var refCourse: Double = 0
        var _refYawRate: Double = 0
        var refXVel: Double = 0
        var refYVel: Double = 0
        var refZVel: Double = 0
        let headingRangeLimit: Double = 4
        let yawRateFF: Double = 0
        var useYawIGain: Bool = false
        
        // To protect from fileter being nil during operation, guard let the info needed from the filter.
        // get filter reset needed
        guard let resetNeeded = self.pattern.stream.posFilter?.resetNeeded() else {
            // PosFilter is nil
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            return
        }
        // Get the filter state as a CLLocation object and to update stream
        guard let streamFiltered = self.pattern.stream.posFilter?.getLlaState() else {
            // PosFilter is nil
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            return
        }
        // Get stream velocities
        guard let (streamNorthVel, streamEastVel, streamAltVel) = self.pattern.stream.posFilter?.getVelocities() else {
            // PosFilter is nil
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            return
        }
        

        // If a reset is needed the stream does not update, stop
        if resetNeeded{
            // Stop until the stream is recovered
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            idleCtrl()
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Stream does not update, stopping"])
            // This timer will be invaliadated by idleCtrl. DSSViewController will notice and stop disable follow stream subscription
        }
        
        // Check if max time following is reached
        self.pattern.velCtrlLoopCnt += 1
        if self.pattern.velCtrlLoopCnt >= self.pattern.velCtrlLoopTarget{
            sendControlData(velX: 0, velY: 0, velZ: 0, yawRate: 0, speed: 0)
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "VelocityController max time exeeded"])
            idleCtrl()
        }

        // Insert the lat, lon, alt in MyLocation object
        self.pattern.streamUpdate(lat: streamFiltered.coordinate.latitude, lon: streamFiltered.coordinate.longitude, alt: streamFiltered.altitude, yaw: self.pattern.stream.heading)

        // Extract the stream location
        // Get distance and bearing from here to stream, e = r - y
        let (northing, easting, dAlt, distance2D, _, bearing) = self.loc.distanceTo(wpLocation: self.pattern.stream)
        let radiusError = distance2D - radius
        
        // TODO extract streamAltVel aand use it too
    //    let (streamNorthVel, streamEastVel, streamAltVel) = self.pattern.stream.posFilter!.getVelocities()
        let streamSpeed = sqrt(pow(streamNorthVel,2)+pow(streamEastVel,2))
        let streamCourse = calcDirection(northing: streamNorthVel, easting: streamEastVel)

        // Print distance to stream sometimes (time between prints: sampleTime/1000*40)
        if self.pattern.velCtrlLoopCnt % 40 == 0{
            let distStr: String = String(round(distance2D*100)/100)
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Distance to stream: " + distStr])
        }
        
        //Follow the stream

        // MARK: Circle pattern
        switch pattern{
        case "circle":
            // Desired yaw rate and radius gives the speed.
            let speed = abs(0.01745 * radius * desYawRate)// 2*math.pi*radius*desYawRate/360 ~ 0.01745* r* desYawRate
            var CCW = false     // CounterClockWise rotation true or false?
            if desYawRate < 0{
                CCW = true
            }
            
            // For each headingMode, calculate the refYaw, refXVel and refYVel
            switch headingMode{
            case "poi":
                // refYaw towards poi
                refYaw = bearing
                // Yawrate is non-zero in steady state, enable YawIntegreator
                useYawIGain = true
                
                // calc refCourse.
                // If far away, fly straight towards stream (8m orevious setting)
                if radiusError > 16 {
                    refCourse = bearing
                }
                else if CCW {
                    refCourse = bearing + 90
                }
                else{
                    refCourse = bearing - 90
                }
                
                // Calc body velocitites to follow refCourse (parallell to course)
                let alphaRad = (refCourse - self.loc.heading)/180*Double.pi
                refXVel = speed*cos(alphaRad)
                refYVel = speed*sin(alphaRad)

                // Radius tracking, add components to x and y
                let betaRad = (bearing - self.loc.heading)/180*Double.pi
                refXVel += radKP*radiusError*cos(betaRad)
                refYVel += radKP*radiusError*sin(betaRad)
                                
                // Gimbla control
                let gPitch = atan(dAlt/distance2D)/Double.pi*180
                self.gimbal.gimbalPitchRef = gPitch
                
            case "absolute":
                // Ref yaw defined in pattern
                refYaw = desHeading
                // Yawrate is zero oin steady state, disable YawIntegreator
                useYawIGain = false

                // Calc direction of travel as perpedicular to bearing towards poi.
                //var direction: Double = 0
                if CCW {
                    refCourse = bearing + 90.0
                }
                else {
                    refCourse = bearing - 90.0
                }

                // Calc body velocitites to follow refCourse (parallell to course)
                let alphaRad = (refCourse - self.loc.heading)/180*Double.pi
                refXVel = speed*cos(alphaRad)
                refYVel = speed*sin(alphaRad)

                // Radius tracking, add components to x and y
                let betaRad = (bearing - self.loc.heading)/180*Double.pi
                refXVel += radKP*radiusError*cos(betaRad)
                refYVel += radKP*radiusError*sin(betaRad)
                
            case "course":
                // Special case of absolute where heading is same as direction of travel.
                // Calc direction of travel as perpedicular to bearing towards poi.
                
                // Calc refCourse
                if radiusError > 8 {
                    refCourse = bearing
                }
                else if CCW {
                    refCourse = bearing + 90.0
                }
                else {
                    refCourse = bearing - 90.0
                }
                // Ref yaw is refCourse. Or should i be course..
                refYaw = refCourse
                // Yawrate is non-zero in steady state, enable YawIntegreator
                useYawIGain = true

                // Calc body velocitites to follow refCourse (parallell to course)
                let alphaRad = (refCourse - self.loc.heading)/180*Double.pi
                refXVel = speed*cos(alphaRad)
                refYVel = speed*sin(alphaRad)

                // Radius tracking, add components to x and y
                let betaRad = (bearing - self.loc.heading)/180*Double.pi
                refXVel += radKP*radiusError*cos(betaRad)
                refYVel += radKP*radiusError*sin(betaRad)
                
            default:
                print("Circle heading mode not known. Stopping follower")
                refYaw = 180
                idleCtrl()
            }
        // MARK: Above pattern
        case "above":
            // For each headingMode, calculate the refYaw, refXVel and refYVel
            switch headingMode{
            case "poi":
                // If 'far' away, set heading to bearing
                if distance2D > headingRangeLimit{
                    refYaw = bearing
                }
                // Else, maintain heading
                else{
                    refYaw = self.loc.heading
                }
                // Yawrate is zero in steady state, disable YawIntegreator
                useYawIGain = false
                
                // P-Controller with feed forward on stream vel
                let refVelNorth = streamNorthVel*kFF + northing * kP
                let refVelEast = streamEastVel*kFF + easting * kP

                // Given current heading, transform to bodyfix
                let alphaRad = self.loc.heading/180*Double.pi
                refXVel = refVelNorth * cos(alphaRad) + refVelEast * sin(alphaRad)
                refYVel = -refVelNorth * sin(alphaRad) + refVelEast * cos(alphaRad)
                
                // Gimbla control
                let gPitch = atan(dAlt/distance2D)/Double.pi*180
                self.gimbal.gimbalPitchRef = gPitch
                
            case "absolute":
                // Heading is defined in pattern
                refYaw = desHeading
                // Yawrate is zero in steady state, disable YawIntegreator
                useYawIGain = false

                // P-Controller with feed forward on stream vel, P gain on control error
                let refVelNorth = streamNorthVel*kFF + northing * kP
                let refVelEast = streamEastVel*kFF + easting * kP
                
                // Given current heading, transform to bodyfix
                let alphaRad = self.loc.heading/180*Double.pi
                refXVel = refVelNorth * cos(alphaRad) + refVelEast * sin(alphaRad)
                refYVel = -refVelNorth * sin(alphaRad) + refVelEast * cos(alphaRad)
                                
                // Gimbal control
                let gPitch = atan(dAlt/distance2D)/Double.pi*180
                self.gimbal.gimbalPitchRef = gPitch
                
            // MARK: The new COURSE implementation
            case "course":
                
                // If 'far' away, set headingRef to bearing
                if distance2D > headingRangeLimit{
                    refYaw = bearing
                }
                // We are close to target, is stream moving?
                else if streamSpeed > 1.2{
                    refYaw = streamCourse
                }
                // We are close and target and stream is stationary
                else{
                    refYaw = self.loc.heading
                }
                // Yawrate is zero in steady state, disable YawIntegreator
                useYawIGain = false
  
                // P-Controller with feed forward on stream vel
                let refVelNorth = streamNorthVel*kFF + northing * kP
                let refVelEast = streamEastVel*kFF + easting * kP
                
                // Given current heading, transform to bodyfix
                let alphaRad = self.loc.heading/180*Double.pi
                refXVel = refVelNorth * cos(alphaRad) + refVelEast * sin(alphaRad)
                refYVel = -refVelNorth * sin(alphaRad) + refVelEast * cos(alphaRad)
                                
                // Gimbal control
                let gPitch = atan(dAlt/distance2D)/Double.pi*180
                self.gimbal.gimbalPitchRef = gPitch
                
            default:
                print("Above heading mode not supported. Stopping follower")
                idleCtrl()
            }
        default:
            print("Pattern not supported Stopping follower")
            idleCtrl()
        }
        
        // MARK: Yaw controller
        // Calculate yaw-error, use shortest way (right or left?)
        let yawError = getDoubleWithinAngleRange(angle: (self.loc.heading - refYaw))
        // P-controller for Yaw
        _refYawRate = yawRateFF - yawError*Double(yawKP)
        
        // PI-controller for Yaw
        // Wind up protection, big yawErrors probably depends on steps in reference
        if abs(yawError) < 30 && useYawIGain {
            yawErrorIntegrated += yawError
        }
        else{
            yawErrorIntegrated = 0
        }
        
        _refYawRate = -yawErrorIntegrated*Double(yawKI) - yawError*Double(yawKP)
        //print("Integral part: ", -yawErrorIntegrated*Double(yawKI))
        //print("refYawReate: ", _refYawRate, "yawError: ", yawError)
        
        // MARK: Altitude controller
        // Altitude trackign, zError positive downwards, current - ref
        // dAlt is from copter to stream device (positive DOWNWARDS), desAltDiff is above stream device (positive UPWARDS)
        
        // Make an example and get sign right
        let zError = (dAlt - (-desAltDiff))
        // Negative feedback loop
        refZVel = -zError*Double(vPosKP) - streamAltVel * kFF

        // MARK: Horizontal controller
        // Set up a speed limit. Use global limit for now, it is given in cm/s..
        let speed = xyVelLimit/100
        
        self.sendControlData(velX: Float(refXVel), velY: Float(refYVel), velZ: Float(refZVel), yawRate: Float(_refYawRate), speed: speed)
        //self.sendControlData(velX: Float(refVelXFilt), velY: Float(refVelYFilt), velZ: Float(refZVel), yawRate: Float(_refYawRate), speed: speed)
    }
}
