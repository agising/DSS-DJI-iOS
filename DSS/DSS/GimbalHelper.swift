//
//  GimbalHelper.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-28.
//


import Foundation
import DJIUXSDK

class GimbalController: NSObject, DJIGimbalDelegate{
    var gimbal: DJIGimbal?                  // The reference to the Gimbal
    var gimbalPitchRef: Double = 0          // The reference gimbal pitch
    var gimbalPitch: Float = 0              // The current gimbal pitch, updated by delegate function
    var gimbalTrack: Bool = false           // Flag to enable/disable the APPLICATION gimbal pitch tracking.
    var yawRelativeToHeading: Double = 0    // The Gimbal yaw relativt to the aircraft heading
    var pitchRange: [Double] = [0,0]        // The programmatically valid pitch range
    var movingTime: Double = 1              // Time to move to desired pitch

    // *******************************************
    // Init the gimbal, set pitch range extension.
    func initGimbal(){
        // Range extension only seems to affect the pilot control pitch range. Range is not extended programatically
        setRangeExtension(enable: true)
        usleep(100000)
        updateGimbalPitchRange()
        print("Available gimbal pitchRange is: ", pitchRange)
        // Set the gimbla delegate to self.
        gimbal!.delegate = self
                
        // Should check of gimbal can be controlled aka selftest. getYawRelativeToAircaftHeading() returns nil of the init of gimbal fails (motor blocked?)
    }
    
    //**************************************************
    // The gimbal delegate function
    func gimbal(_ gimbal: DJIGimbal, didUpdate state: DJIGimbalState) {
        gimbalPitch = state.attitudeInDegrees.pitch
        yawRelativeToHeading = state.yawRelativeToAircraftHeading
        // If gimbal is not controlled by PILOT
        if gimbalTrack{
            if abs(gimbalPitchRef - Double(gimbalPitch))>1{
                _ = setPitch(pitch: gimbalPitchRef)
            }
        }
    }
    
    //***************************
    // Set the gimbal pitch value
    func setPitch(pitch: Double)->Bool{
        if !(pitchRange[0] <= pitch && pitch <= pitchRange[1]){
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Gimbal pitch out of range:"])
            return false
        }
        
        // Create a DJIGimbalRotaion object
        let gimbal_rotation = DJIGimbalRotation(pitchValue: pitch as NSNumber, rollValue: 0, yawValue: 0, time: self.movingTime, mode: DJIGimbalRotationMode.absoluteAngle, ignore: true)
        // Feed rotate object to Gimbal method rotate
        self.gimbal?.rotate(with: gimbal_rotation, completion: { (error: Error?) in
            if error != nil {
                NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Gimbal rotation :" + String(describing: error)])
            }
        })
        return true
    }
    
    // ******************************
    // Set the gimbal range extension
    func setRangeExtension(enable: Bool){
        self.gimbal?.setPitchRangeExtensionEnabled(enable, withCompletion: {(error: Error?) in
            if error != nil {
                NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Gimbal range extension :" + String(describing: error)])
            }
        })
    }
    
    // *************************************
    // Get the gimbal range extension status
    func getRangeExtensionSet()->Bool{
        var result = false
        self.gimbal?.getPitchRangeExtensionEnabled(completion: {(isExtended: Bool, error: Error?) in
            if error != nil{
                NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Get gimbal range extension :" + String(describing: error)])
            }
            print("Gimbal range is extended: ", isExtended)
            result = isExtended
        })
        return result
    }
    
    // *******************************************************************
    // Update the programmable pitch range (read current value from drone)
    func updateGimbalPitchRange(){
        let capabilities = self.gimbal?.capabilities
        if let range = capabilities!["AdjustPitch"] as? DJIParamCapabilityMinMax{
            pitchRange[0] = Double(truncating: range.min)
            pitchRange[1] = Double(truncating: range.max)
        }
    }

    
    // ****************************
    // Print the gimbal capabilites
    func printGimbalCapabilities(){
        let capabilities = self.gimbal?.capabilities
        for (key, value) in capabilities!{
            //print(key,value)
            let theType = type(of: value)
            if theType == DJIParamCapabilityMinMax.self{
                let minMax = value as! DJIParamCapabilityMinMax
                if minMax.max == nil{
                    print("Gimbal feature is not available: ", key)
                }
                else{
                    print("Gimbal feature is available: ", key, ", min: ", minMax.min.description, ", max: ", minMax.max.description)
                }
            }
            if theType == DJIParamCapability.self{
                let capability = value as! DJIParamCapability
                print("Status of gimbal feature ", key, "is :", capability.isSupported)
            }
        }
    }
}

