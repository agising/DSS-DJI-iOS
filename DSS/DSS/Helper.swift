//
//  Helper.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-28.
//

import Foundation
import UIKit
import Photos
import DJIUXSDK
import SwiftyJSON
import SystemConfiguration
import CoreTelephony


class MyLocation: NSObject, NSCopying{
    var speed: Float = 0
    var altitude: Double = 0
    var heading: Double = 0
    var gimbalYaw: Double = 0
    var gimbalYawRelativeToHeading: Double = 0
    var action: String = ""
    var refGimbalPitch: Double?
    var isInitLocation: Bool = false
    var coordinate = MyCoordinate()
    var geoFence = GeoFence()
    var vel = Vel()
    var pos = Pos()
    var isSetAlt = false
    var takeOffPressureAlt: Double = 0                          // Altitude from barometer at takeoff, probably using QNH = 1013
    var takeOffLocationAltitude: Double = 0                     // From iOS and settingsscreen
    var trackingPrecision: Int = 5                              // How precise wp is tracked, 1-5. 5 is most precise
    var trackingRecord: Int = 0                                 // Current tracking record for wp
    //var posFilter: HCKalmanAlgorithm?                         // Faulty Kalman filter for filtering position
    var posFilter: GPSKalmanFilterAcc?                          // Kalman contant acc filter
    
    func copy(with zone: NSZone? = nil)->Any{
        let copy = MyLocation()
        copy.speed = speed
        copy.altitude = altitude
        copy.heading = heading
        copy.gimbalYaw = gimbalYaw
        copy.gimbalYawRelativeToHeading = gimbalYawRelativeToHeading
        copy.action = action
        copy.refGimbalPitch = refGimbalPitch
        copy.isInitLocation = isInitLocation
        copy.coordinate = coordinate.copy() as! MyCoordinate
        copy.geoFence = geoFence.copy() as! GeoFence
        copy.vel = vel.copy() as! Vel
        copy.pos = pos.copy() as! Pos
        copy.isSetAlt = isSetAlt
        copy.takeOffPressureAlt = takeOffPressureAlt
        copy.takeOffLocationAltitude = takeOffLocationAltitude
        copy.trackingPrecision = trackingPrecision
        copy.trackingRecord = trackingPrecision
        //copy.GPSKalmanFilter = GPSKalmanFilter?
        return copy
    }
    // Reset all values.
    func reset(){
        self.speed = 0
        self.altitude = 0
        self.heading = 0
        self.gimbalYaw = 0
        self.gimbalYawRelativeToHeading = 0
        self.action = ""
        self.refGimbalPitch = nil
        self.isInitLocation = false
        self.coordinate.latitude = 0
        self.coordinate.longitude = 0
        self.geoFence.radius = 0
        // self.geoFence.height = [0, 0]
        self.vel.bodyX = 0
        self.vel.bodyY = 0
        self.vel.bodyZ = 0
        self.vel.yawRate = 0
        self.pos.x = 0
        self.pos.y = 0
        self.pos.z = 0
        self.pos.north = 0
        self.pos.east = 0
        self.pos.down = 0
        self.isSetAlt = false
        self.takeOffPressureAlt = 0
        self.takeOffLocationAltitude = 0
        self.trackingPrecision = 5
        self.trackingRecord = 0
    }
    
    
    /**
     Calculates distance to the wpLocation from the MyLocation it is called from.
     - Parameter wpLocation: A MyLocation object to calc distance to
     - Returns: northing, easting, dAlt, distance2D, distance3D, bearing (degrees)
     */
    func distanceTo(wpLocation: MyLocation)->(Double, Double, Double, Double, Double, Double){
        // Lat lon alt deltas
        let dAlt = wpLocation.altitude - self.altitude
        // Calc northing easting from difference in lat long
        let (northing, easting) = self.northingEastingTo(wpLocation: wpLocation)
        
        // Square
        let northing2 = pow(northing, 2)
        let easting2 = pow(easting, 2)
        let dAlt2 = pow(dAlt, 2)
        
        // Calc distances
        let distance2D = sqrt(northing2 + easting2)
        let distance3D = sqrt(northing2 + easting2 + dAlt2)
        
        // Calc bearing (ref to CopterHelper -> getCourse)
        // Guard division by 0 and calculate: Bearing given northing and easting
        // Case easting == 0, i.e. bearing == 0 or -180
        var bearing: Double = 0
        if easting == 0 {
            if northing > 0 {
                bearing = 0
            }
            else {
                bearing = 180
            }
        }
        else if easting > 0 {
            bearing = (Double.pi/2 - atan(northing/easting))/Double.pi*180
        }
        else if easting < 0 {
            bearing = -(Double.pi/2 + atan(northing/easting))/Double.pi*180
        }
        
        return (northing, easting, dAlt, distance2D, distance3D, bearing)
    }
    
    // Time to closes point of approach
    func closestPointOfApproachTo(wpLocation: MyLocation)->(Float, Float){
        var tCPA = 0.0
        // Norm of velocity
        let myNVel = self.vel.north
        let myEVel = self.vel.east
        
        let herNVel = wpLocation.vel.north
        let herEVel = wpLocation.vel.east
                
        let dNVel = myNVel - herNVel
        let dEVel = myEVel - herEVel
        
        // Calc norm, at what speed are we approaching each other
        let velNorm = sqrt(pow((dNVel),2) + pow((dEVel),2))
        
        let (northing, easting) = self.northingEastingTo(wpLocation: wpLocation)

        // If quick approach, calc time to closest point of approach
        if velNorm > 0.1{
            let calcTCPA = (northing*dNVel + easting*dEVel)/pow(velNorm,2)
            tCPA = max(0, calcTCPA)
        }
        
        // Where is this closes point?
        let myNCPA = tCPA * myNVel
        let myECPA = tCPA * myEVel
        //print("In tCPA, I will be n: ", myNCPA, " e: ", myECPA, " relative to me")
        
        // Starging from her position, calc where she will be (in relation to me, North East)
        let herNCPA = northing + tCPA * herNVel
        let herECPA = easting + tCPA * herEVel
        //print("In tCPA, she will be n: ", herNCPA, " e: ", herECPA, " relative to me")

        let dNCPA = myNCPA - herNCPA
        let dECPA = myECPA - herECPA
        //print("The distance between us will be n: ", dNCPA, " e: ", dECPA)
        
        let dCPA = sqrt(pow((dNCPA),2) + pow((dECPA),2))
        
        return (Float(tCPA), Float(dCPA))
    }
    
    
    func northingEastingTo(wpLocation: MyLocation)->(Double, Double){
        // Lat lon alt deltas
        let dLat = wpLocation.coordinate.latitude - self.coordinate.latitude
        let dLon = wpLocation.coordinate.longitude - self.coordinate.longitude
            
        // Convert to meters
        let northing = dLat * 1852 * 60
        let easting =  dLon * 1852 * 60 * cos(wpLocation.coordinate.latitude/180*Double.pi)
        return (northing, easting)
    }
   
   
    // This function should be used from the initLoc object
    func geofenceOK(wp: MyLocation)->Bool{
        // To make sure function is only used from initLoc.
        if !self.isInitLocation {
            print("geofence: WP used for reference is not init location.")
            return false
        }
        let (_, _, dAlt, dist2D, _, _) = self.distanceTo(wpLocation: wp)
        print("geofenceOK: dAlt:", dAlt," dist2D: ", dist2D)

        if dist2D > self.geoFence.radius {
            printToScreen("geofence: Radius violation")
            return false
        }
        if dAlt < self.geoFence.height[0] || self.geoFence.height[1] < dAlt {
            printToScreen("geofence: Height violation")
            return false
        }
        return true
    }
    
    // Set up a MyLocation given a CLLocation and other properties
//    func setPosition(pos: CLLocation, heading: Double, gimbalYawRelativeToHeading: Double, isInitLocation: Bool=false, initLoc: MyLocation, completionBlock: ()->Void){
    func setPosition(lat: Double, lon: Double, alt: Double, heading: Double, gimbalYawRelativeToHeading: Double, isInitLocation: Bool=false, initLoc: MyLocation, completionBlock: ()->Void){
        if self.isInitLocation{
            print("setPosition: Init point already set")
            return
        }
        self.altitude = alt
        //print("takeOffLocationDJIAMSL: ", self.takeOffLocationDjiAMSL)
        self.heading = heading
        self.gimbalYawRelativeToHeading = gimbalYawRelativeToHeading
        self.gimbalYaw = heading + gimbalYawRelativeToHeading
        self.coordinate.latitude = lat
        self.coordinate.longitude = lon
        self.isInitLocation = isInitLocation
        
        // Dont set up local coordinates for the InitLoc it self.
        if self.isInitLocation{
            return
        }
        
        // If initLoc is not setup, local coordinates cannot be calculated - return
        if !initLoc.isInitLocation {
            completionBlock()
            print("setPosition: Local coordinates not set, init point not set")
            return
        }
        
        // Lat-, lon-, alt-diff
        let latDiff = lat - initLoc.coordinate.latitude
        let lonDiff = lon - initLoc.coordinate.longitude
        let altDiff = alt - initLoc.altitude
        
        
        // posN, posE
        let posN = latDiff * 1852 * 60
        let posE = lonDiff * 1852 * 60 * cos(initLoc.coordinate.latitude/180*Double.pi)
        self.pos.north = posN
        self.pos.east = posE
        self.pos.down = -altDiff
        
        // X direction definition
        let alpha = (initLoc.gimbalYaw)/180*Double.pi

        // Coordinate transformation, from (N, E) to (X,Y)
        self.pos.x =  posN * cos(alpha) + posE * sin(alpha)
        self.pos.y = -posN * sin(alpha) + posE * cos(alpha)
        self.pos.z = -altDiff  // Same as pos.down..
             
        // Check for geofence violation
        if -self.pos.z > initLoc.geoFence.height[1]{
            print("GeoFence: Breaching geo fence high")
            // Set alt 2m below?
        }
        if sqrt(pow(self.pos.x,2)+pow(self.pos.y,2)) > initLoc.geoFence.radius{
            print("Geofence: Breaching geo fence radius")
            // Fly mission towards init?
        }
        
        
        completionBlock()
        // Suitable completionblock:
        // {NotificationCenter.default.post(name: .didPosUpdate, object: nil)}
    }
    
    func setGeoFence(radius: Double, height: [Double]){
        self.geoFence.radius = radius
        self.geoFence.height = height
    }
    
    func updateSTATEFromJsonWp(jsonWP: JSON){
        self.coordinate.latitude = jsonWP["lat"].doubleValue
        self.coordinate.longitude = jsonWP["lon"].doubleValue
        self.altitude = jsonWP["alt"].doubleValue
        self.heading = parseHeading(json: jsonWP)
        
        self.vel.north = jsonWP["vel_n"].doubleValue
        self.vel.east = jsonWP["vel_e"].doubleValue
        self.vel.down = jsonWP["vel_d"].doubleValue
    }
    
    func setUpFromJsonWp(jsonWP: JSON, defaultSpeed: Float, initLoc: MyLocation){
        // Reset all properties
        self.reset()
        
        // Test if mission is LLA
        if jsonWP["lat"].exists(){
            // Mission is LLA
            self.coordinate.latitude = jsonWP["lat"].doubleValue
            self.coordinate.longitude = jsonWP["lon"].doubleValue
            self.altitude = jsonWP["alt"].doubleValue
            if jsonWP["alt_type"].exists(){
                if jsonWP["alt_type"].stringValue == "relative"{
                    self.altitude += initLoc.altitude
                }
            }
            self.heading = parseHeading(json: jsonWP)
        }
        
        
        // Test if mission NED
        else if jsonWP["north"].exists(){
            // Mission is NED
            let north = jsonWP["north"].doubleValue
            let east = jsonWP["east"].doubleValue
            let down = jsonWP["down"].doubleValue
            // Calc dLat, dLon from north east. Add to start location.
            let dLat = initLoc.coordinate.latitude + north/(1852 * 60)
            let dLon = initLoc.coordinate.longitude + east/(1852 * 60 * cos(initLoc.coordinate.latitude/180*Double.pi))
            self.coordinate.latitude = dLat
            self.coordinate.longitude = dLon
            self.altitude = initLoc.altitude - down
            self.heading = parseHeading(json: jsonWP)
            
        }
        else if jsonWP["x"].exists(){
            // Mission is XYZ
            let x = jsonWP["x"].doubleValue
            let y = jsonWP["y"].doubleValue
            let z = jsonWP["z"].doubleValue
            // First calculate northing and easting.
            let XYZstartHeading = initLoc.gimbalYaw
            let beta = -XYZstartHeading/180*Double.pi
            let north = x * cos(beta) + y * sin(beta)
            let east = -x * sin(beta) + y * cos(beta)
            // Calc dLat, dLon from north east. Add to start location
            let dLat = initLoc.coordinate.latitude + north/(1852 * 60)
            let dLon = initLoc.coordinate.longitude + east/(1852 * 60 * cos(initLoc.coordinate.latitude/180*Double.pi))
            self.coordinate.latitude = dLat
            self.coordinate.longitude = dLon
            self.altitude = initLoc.altitude - z
            self.heading = parseHeading(json: jsonWP)
            // Transform to XYZ
            if self.heading != -1 && self.heading != -99{
                self.heading += initLoc.gimbalYaw
                // Make sure heading is within 0-360 range (to avoid -1 and -99 which has other meaning)
                if self.heading < 0 {
                    self.heading += 360
                }
                if self.heading > 360 {
                    self.heading -= 360
                }
            }
        }
        
        // Extract speed
        if jsonWP["speed"].exists(){
            self.speed = jsonWP["speed"].floatValue
        }
        else {
            self.speed = defaultSpeed
        }
        
        // Extract action
        if jsonWP["action"].exists() {
            self.action = jsonWP["action"].stringValue
            if jsonWP["gimbal_pitch"].exists(){
                self.refGimbalPitch = jsonWP["gimbal_pitch"].doubleValue
            }
        }
        
        // Set WP tracking precision if given
        if jsonWP["tracking_precision"].exists(){
            self.trackingPrecision = jsonWP["tracking_precision"].intValue
        }
    }
    
    // Prints text to both statusLabel and error output
    func printToScreen(_ string: String){
        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": string])
    }

    func printLocation(sentFrom: String){
        print(sentFrom + ": ",
              "lat: ", self.coordinate.latitude,
              " lon: ", self.coordinate.longitude,
              " alt: ", self.altitude,
              " heading: ", self.heading,
              " gimbalYaw: ", self.gimbalYaw,
              " gimbalYawRelativeToHeading: ", self.gimbalYawRelativeToHeading)
    }
    
    func predictLocation(deltaT: Double, deltaVelN: Float, deltaVelE: Float)->MyLocation{
        let prediction = self.copy() as! MyLocation
        
        // Need to update vel.north, vel.east and coodinate.lat and coordinate.long
        // Update vel north, east
        prediction.vel.north += Double(deltaVelN)
        prediction.vel.east += Double(deltaVelE)
        
        // Predict movement in north east during deltaT
        let dN = deltaT*prediction.vel.north
        let dE = deltaT*prediction.vel.east
        
        // Convert meters to lat long.
        prediction.coordinate.latitude += dN / (1852 * 60)
        prediction.coordinate.longitude += dE / (1852 * 60 * cos(self.coordinate.latitude/180*Double.pi))
        return prediction
    }
}

// Subclass to MyLocation. Coordinates influenced by CLLocation
class MyCoordinate:NSObject, NSCopying{
    var latitude: Double = 0
    var longitude: Double = 0
    
    func copy(with zone: NSZone? = nil)->Any{
        let copy = MyCoordinate()
        copy.latitude = latitude
        copy.longitude = longitude
        return copy
    }
}

// SubClass to MyLocation. Geofence properties that are stored in the initLoc. Geofence is checked relative to initLoc, from initLoc object.
class GeoFence: NSObject, NSCopying{
    var radius: Double = 50                 // Geofence radius relative initLoc location
    var height: [Double] = [2, 20]          // Geofence height relative initLoc location
    
    func copy(with zone: NSZone? = nil)->Any{
        let copy = GeoFence()
        copy.radius = radius
        copy.height = height
        return copy
    }
}
// SubClass to MyLocation. Class for body and NED velocities
class Vel: NSObject, NSCopying{
    var bodyX: Double = 0
    var bodyY: Double = 0
    var bodyZ: Double = 0
    var north: Double = 0
    var east: Double = 0
    var down: Double = 0
    var yawRate: Double = 0

    func copy(with zone: NSZone? = nil)->Any{
        let copy = Vel()
        copy.bodyX = bodyX
        copy.bodyY = bodyY
        copy.bodyZ = bodyZ
        copy.north = north
        copy.east = east
        copy.down = down
        copy.yawRate = yawRate
        return copy
    }
}

// SubClass to MyLocation.
class Pos: NSObject, NSCopying {
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var north: Double = 0
    var east: Double = 0
    var down: Double = 0
    
    func copy(with zone: NSZone? = nil)->Any{
        let copy = Pos()
        copy.x = x
        copy.y = y
        copy.z = z
        copy.north = north
        copy.east = east
        copy.down = down
        return copy
    }
}

// An object to carry any flight pattern
class PatternHolder: NSObject{
    let radiusLimit: Double = 2
    var pattern: Pattern = Pattern()
    var stream: MyLocation = MyLocation()
    var reference: MyLocation = MyLocation()
    var velCtrlTimer: Timer?                        // Velocity control Timer
    var velCtrlLoopCnt: Int = 0                     // Velocity control loop counter
    var velCtrlLoopTarget: Int = 25099999                // Velocity control loop counter max

    
    func streamUpdate(lat: Double, lon: Double, alt: Double, yaw: Double){
        self.stream.coordinate.latitude = lat
        self.stream.coordinate.longitude = lon
        self.stream.altitude = alt
        self.stream.heading = yaw
    }
    
    //
    // Set a new pattern
    func setPattern(pattern: String, relAlt: Double, heading: Double, radius: Double? = nil, yawRate: Double? = nil){
        self.pattern.name = pattern
        self.pattern.relAlt = relAlt
        // If not default value
        if radius != nil{
            self.pattern.radius = radius!
        }
        // If not default value
        if yawRate != nil{
            self.pattern.yawRate = yawRate!
        }
        // Identify heading mode
        switch heading {
        case -1:
            self.pattern.headingMode = "course"
            self.pattern.heading = -1
        case -2:
            self.pattern.headingMode = "poi"
            // Heading is updated when stream.updateReference
        default:
            self.pattern.headingMode = "absolute"
            self.pattern.heading = heading
        }
    }
}

class Pattern: NSObject {
    var name: String = "above"
    var relAlt: Double = 10
    var headingMode: String = "course"        // Absolute/course/poi
    var heading: Double = 10
    var radius: Double = 10
    var yawRate: Double = 0
    var startTime = CACurrentMediaTime()

}

//
// Class to use for allocation of resources, like camera, gimbal, etc.
class Allocator: NSObject{
    var allocated = false
    var owner = ""
    var name = ""
    var dateAllocated = Date()
    var maxTime = Double(0)
    var auxOccupier = false // Monitor reading to sdCard, update auxOccupier. Allocator will not deallocate until auxOccupier is true.
    
    init(name: String){
        self.name = name
    }
    
    // **********************************************************************************************************************************************************
    // Set additional lock prevent the lock from beeing released prior to all clients that are using the resource has let go. Specifically made for sdCard access
    func setAuxOccopier(occupied: Bool){
        self.auxOccupier = occupied
    }
    
    // *****************************************************************
    // Allocate a resource, if it is available or if max-time has passed
    func allocate(_ owner: String, maxTime: Double)->Bool{
        // Check if it is rightfully allocated
        if self.allocated{
            if self.maxTime > self.timeAllocated(){
                // Resource is rightfully allocated
                let tempStr = self.name + "Allocator : Resource occupied by " + self.owner + ", " + owner + " tried to occupy"
                print(tempStr)
                return false
            }
            print(self.name + "Allocator : Forcing allocation from " + self.owner)
        }
        // Resource is not rightfully allocated -> Allocate it!
        self.allocated = true
        self.owner = owner
        self.dateAllocated = Date()
        self.maxTime = maxTime
        self.auxOccupier = false
        return true
    }
    
    
    func deallocate(){
        if self.auxOccupier {
            Dispatch.background{
                do{
                    //print("Sleeping for 0.1s")
                    usleep(100000)
                }
                self.deallocate() // How to break endless loop? Include attemts: int?
            }
        }
        else{
            //print("Resource was busy for " + String(self.timeAllocated()) + "by: " + self.owner)
            self.allocated = false
            self.owner = ""
            
        }
    }

    func timeAllocated()->Double{
        if self.allocated{
            // timeIntervalSinceNow returns a negative time in seconds. This function returns positive value.
            return -dateAllocated.timeIntervalSinceNow
        }
        else{
            return Double(0)
        }
    }
}

class Subscriptions: NSObject{
    var ATT = false
    var XYZ = false
    var photoXYZ = false
    var LLA = false
    var photoLLA = false
    var NED = false
    var WpId = false
    var battery = false
    var STATE = false

    func setATT(bool: Bool){
        ATT = bool
        print("Subscription ATT set to: " + String(describing: bool))
    }

    func setXYZ(bool: Bool){
        XYZ = bool
        print("Subscription XYZ set to: " + String(describing: bool))
    }

    func setPhotoXYZ(bool: Bool){
        photoXYZ = bool
        print("Subscription photoXYZ set to: " + String(describing: bool))
    }

    func setLLA(bool: Bool){
        LLA = bool
        print("Subscription LLA set to: " + String(describing: bool))
    }

    func setPhotoLLA(bool: Bool){
        photoLLA = bool
        print("Subscription photoLLA set to: " + String(describing: bool))
    }

    func setNED(bool: Bool){
        NED = bool
        print("Subscription NED set to: " + String(describing: bool))
    }

    func setWpId(bool: Bool){
        WpId = bool
        print("Subscription WP_ID set to: " + String(describing: bool))
    }
    
    func setBattery(bool: Bool){
        print("Subscription battery set to: "  + String(describing: bool))
        battery = bool
    }
    
    func setSTATE(bool: Bool){
        print("Subscription STATE set to: "  + String(describing: bool))
        STATE = bool
    }
}

class Tictoc: NSObject{
    var lasttic = CACurrentMediaTime()
    var lastsubtic = CACurrentMediaTime()
    
    // Reset both timers
    func tic(){
        lasttic = CACurrentMediaTime()
        lastsubtic = CACurrentMediaTime()
    }
    
    // Get time from main tic
    func toc()->String{
        let elapsed = CACurrentMediaTime() - self.lasttic
        return String(elapsed)
    }
    
    // Create subtic
    func subtic(){
        lastsubtic = CACurrentMediaTime()
    }
    
    // Get time from subtoc
    func subtoc()->String{
        let elapsed = CACurrentMediaTime() - self.lastsubtic
        return String(elapsed)
    }
}

class HeartBeat: NSObject{
    var lastBeat = CACurrentMediaTime()
    var degradedLimit: Double = 5               // Time limit for link to be considered degraded
    var lostLimit: Double = 10                  // Time limit for link to be considered lost
    var beatDetected = false                    // Flag for first received heartBeat
    var lostOnce = false                        // Link has been lost once and no heartbeats since
    var disconnected = false                    // Flag to not allow mission continuation after disconnect
    
    func newBeat(){
        if !beatDetected{
            beatDetected = true
            lostOnce = false
            disconnected = false
        }
        self.lastBeat = CACurrentMediaTime()
    }
    
    func elapsed()->Double{
        return CACurrentMediaTime() - self.lastBeat
    }
    
    func alive()->Bool{
        let elapsedTime = self.elapsed()
        if elapsedTime < degradedLimit{
            return true
        }
        else if elapsedTime < lostLimit{
            print("Link degraded, elapsed time since last heartBeat: ", elapsedTime)
            return true
        }
        else{
            print("Link lost, elapsed time since last heartBeat: ", elapsedTime)
            return false
        }
    }
    
}


// https://www.hackingwithswift.com/books/ios-swiftui/how-to-save-images-to-the-users-photo-library
class imageSaver: NSObject {
    func writeToPhotoAlbum(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveError), nil)
    }
    @objc func saveError(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        print("Save Finished")
    }
}

// Inspired from https://stackoverflow.com/questions/27379900/how-to-determine-the-ios-connection-type-edge-3g-4g-wifi
// Identify carrier connection type
func getConnectionType() -> String {
    guard let reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, "www.google.com") else {
        return "NO INTERNET"
    }

    var flags = SCNetworkReachabilityFlags()
    SCNetworkReachabilityGetFlags(reachability, &flags)

    let isReachable = flags.contains(.reachable)
    let isWWAN = flags.contains(.isWWAN)

    if isReachable {
        if isWWAN {
            let networkInfo = CTTelephonyNetworkInfo()
            let carrierType = networkInfo.serviceCurrentRadioAccessTechnology

            guard let carrierTypeName = carrierType?.first?.value else {
                return "UNKNOWN"
            }

            // Sleep 10000us before returning. Otherwise an unharmful error is thrown.
            switch carrierTypeName {
            case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyCDMA1x:
                usleep(10000)
                return "2G"
            case CTRadioAccessTechnologyLTE:
                usleep(10000)
                print("4G")
                return "4G"
            case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyeHRPD:
                usleep(10000)
                return "3G"
            case CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA, CTRadioAccessTechnologyCDMAEVDORevB:
                usleep(10000)
                return "3G"
            default:
                return "Unknown Carrier Type"
            }
        } else {
            return "WIFI"
        }
    } else {
        return "NO INTERNET"
    }
}


// ************************************************************************************************************************Ä*********************************************
// pasteHeading parses heading that can have valid inputs 0-360 and "course". Valid heading returns the heading, "course" returns -1 and any everything else returns -99.
func parseHeading(json: JSON)->Double{
    // If it is not a string its a double..
    if json["heading"].string == nil{
        // Check the value for limits
        let wpHeading = json["heading"].doubleValue
        if 0 <= wpHeading && wpHeading < 360{
            return wpHeading
        }
        else {
            // Internal code for handling error.
            return -99
        }
    }
    // It must be a string, check it
    else if json["heading"].stringValue == "course"{
            return -1
    }
    else if json["heading"].stringValue == "poi"{
        return -2
    }
    // Probably misspelled string
    else {
        return -99
    }
}

// ****************************************
// Parse index and test if it is ok or not.
func parseIndex(json: JSON, sessionLastIndex: Int)->Int{
    // Check for cmd download - Not used? Commenting for now
    if json["cmd"].exists(){
        if json["cmd"].stringValue != "download"{
            // Its not a photo download command, index is not used
            return 0
        }
    }

    // Check if reference is ok
    if json["ref"].exists(){
        if !(json["ref"].stringValue == "LLA" || json["ref"].stringValue == "NED" || json["ref"].stringValue == "XYZ"){
            // Wrong reference, mistyped?
            return -10
        }
    }

    // Parse the index, can be int or string. If it is not a string its an int..
    if json["index"].string == nil{
        // Check the value for limits
        let cmdIndex = json["index"].intValue
        if 0 < cmdIndex && cmdIndex <= sessionLastIndex {
            return cmdIndex
        }
        else {
            // Index out of range, return error code.
            return -11
        }
    }
    // It must be a string, check it
    else if json["index"].stringValue == "all"{
        // Return code for 'all'
        return -1
    }
    else if json["index"].stringValue == "latest"{
        // Return latest index
        return sessionLastIndex
    }
    // Probalby misspelled string
    else {
        // Return index error
        return -12
    }
}




//*****************************************************************************
// Load an image from the photo library. Seems to be loaded with poor resolution
func loadUIImageFromPhotoLibrary() -> UIImage? {
    // https://stackoverflow.com/questions/29009621/url-of-image-after-uiimagewritetosavedphotosalbum-in-swift
    // https://www.hackingwithswift.com/forums/swiftui/accessing-image-exif-data-creation-date-location-of-an-image/1429
    let fetchOptions: PHFetchOptions = PHFetchOptions()
    fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
    let fetchResult = PHAsset.fetchAssets(with: PHAssetMediaType.image, options: fetchOptions)
    if (fetchResult.firstObject != nil) {
        let lastAsset: PHAsset = fetchResult.lastObject!
        print("Previewing image from path")
        return lastAsset.image // use result: self.previewImageView.image = loadUIImageFromPhotoLibrary()
    }
    else{
        return nil
    }
}

//********************************
// Save an UIImage to Photos album
func saveUIImageToPhotosAlbum(image: UIImage){
    let imageSaverHelper = imageSaver()
    imageSaverHelper.writeToPhotoAlbum(image: image)
}


// *************************************
// Returns Int angle in range [-180 180]
func getIntWithinAngleRange(angle: Int)->Int{
    var angle2 = angle % 360
    if angle2 > 180 {
        angle2 -= 360
    }
    if angle2 < -180 {
        angle2 += 360
    }
    return angle2
}

// *************************************
// Returns Int angle in range [-180 180]
func getDoubleWithinAngleRange(angle: Double)->Double{
    var angle2 = angle.truncatingRemainder(dividingBy: 360)
    if angle2 > 180 {
        angle2 -= 360
    }
    if angle2 < -180 {
        angle2 += 360
    }
    return angle2
}

// ***************************************
// Returns Float angle in range [-180 180]
func getFloatWithinAngleRange(angle: Float)->Float{
    var angle2 = angle.truncatingRemainder(dividingBy: 360)
    if angle2 > 180 {
        angle2 -= 360
    }
    if angle2 < -180 {
        angle2 += 360
    }
    return angle2
}


// Struct for declared conformance for squence and following iterator protocol. Returns sequence n, n-1, ... 0
struct Countdown: Sequence, IteratorProtocol {
    var count: Int

    mutating func next() -> Int? {
        if count == -1 {
            return nil
        } else {
            defer { count -= 1 }  // defer: Fancy way of reducing counter after count has been returned, can be used to guarantee things are not forgotten. Google it :)
            return count
        }
    }
}

// Calc direction given north/east velocities or distances. Return deg
func calcDirection(northing: Double, easting: Double)-> Double {
    var course: Double = 0
    if easting == 0 {
        if northing > 0 {
            course = 0
        }
        else {
            course = 180
        }
    }
    else if easting > 0 {
        course = (Double.pi/2 - atan(northing/easting))/Double.pi*180
    }
    else if easting < 0 {
        course = -(Double.pi/2 + atan(northing/easting))/Double.pi*180
    }
    return course
}

func getVelNE(courseRef: Double, speed: Float)->(Float,Float){
    let courseRad = courseRef/180*Double.pi
    let velN = speed * Float(cos(courseRad))
    let velE = speed * Float(sin(courseRad))
    return (velN, velE)
}

func getVelXY(courseRef: Double, heading: Double, speed: Float)->(Float,Float){
    let alphaRad = (courseRef - heading)/180*Double.pi
    let velX = speed * Float(cos(alphaRad))
    let velY = speed * Float(sin(alphaRad))
    return (velX, velY)
}

func stopTimer(timer: Timer?){
    if timer != nil{
        timer?.invalidate()
    }
}


// Map GNSS state to ardupilot description
// https://developer.dji.com/api-reference/ios-api/Components/FlightController/DJIFlightController_DJIFlightControllerCurrentState.html#djiflightcontroller_djigpssignalstatus_inline

func getStateGNSS(state: DJIFlightControllerState)->Int{
    let djiState = state.gpsSignalLevel.rawValue
    switch djiState{
    case 0 :
        return 0
    case 1:
        return 0
    case 2:
        return 1
    case 3:
        return 1
    case 4:
        return 2
    case 5:
        return 3
    case 6:
        return 4
    case 7:
        return 4
    case 8:
        return 5
    case 9:
        return 5
    case 10:
        return 6
    default:
        return 0
    }
}

struct Queue<T> {
  private var elements: [T] = []

  mutating func enqueue(_ value: T) {
    elements.append(value)
  }

  mutating func dequeue() -> T? {
    guard !elements.isEmpty else {
      return nil
    }
    return elements.removeFirst()
  }

  var head: T? {
    return elements.first
  }

  var tail: T? {
    return elements.last
  }
}
