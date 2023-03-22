//
//  SpotLightHelper.swift
//  DSS
//
//  Created by Andreas Gising on 2021-11-15.
//

import Foundation
import DJIUXSDK
import CoreMIDI

class AccessoryController: NSObject, DJIAccessoryAggregationDelegate{
    var accessory: DJIAccessoryAggregation?
    var spotlight: spotlightClass?                // DSS spotlight class
    var beacon: beaconClass?                      // DSS beacon class
    var speaker: speakerClass?                    // DSS speaker class
    
    // Clean up when tested
    //  var spotlight: DJISpotlight?                  // The reference to the SpotlightDevice
    //    var beacon: DJIBeacon?                        // The reference to the BeaconDevice
    //    var speaker: DJISpeaker?                      // The reference to the SpeakerDevice
    var name: String?                             //
    var capabilities: [String] = []               // Build capabilities list
    
//    var spotEnable = false
    
    // Should move spotlght functions to spotlight class etc
    
    func initAccessory(){
        // Reset capabilites to support installing PL whil app is on
        self.capabilities = []
        // Update the internal states
        // Set the accessory delegate to self
        if accessory?.beacon != nil{
            print("Beacon is connected")
            self.beacon = beaconClass(theBeaconRef: accessory!.beacon)
            
            self.name = "Beacon"
            self.capabilities.append("BEACON")
            //self.beacon = accessory!.beacon
        }
        if accessory?.speaker != nil{
            print("Speaker connected")
            self.name = "Speaker"
            self.capabilities.append("SPEAKER")
            //self.speaker = accessory!.speaker
        }
        
        if accessory?.spotlight != nil {
            // Spotloight is connected, save the reference
            self.spotlight = spotlightClass(theSpotRef: accessory!.spotlight)
            self.spotlight!.setEnable(enable: false)
            self.spotlight!.setBrightness(brightness: 100)
            
//            self.spotlight = accessory!.spotlight
//            self.setEnable(enable: false)
//            self.setBrightness(brightness: 100)
            self.name = "Spotlight"
            self.capabilities.append("SPOTLIGHT")
            print("Spotlight connected and initiated")
        }
        accessory!.delegate = self
    }
    
    
    // Delegate method for accessory aggregation
    func accessoryAggregation(_ aggregation: DJIAccessoryAggregation, didUpdate state: DJIAccessoryAggregationState) {
        // Check connection status of accessories
        //state.isBeaconConnected
        //state.isSpeakerConnected
        if !state.isSpotlightConnected{
            print("The spotlight is no longer connected...")
        }
    }
    
//    func setEnable(enable: Bool){
//        self.spotlight?.setEnabled(enable, withCompletion: {(error: Error?) in
//            if error != nil{
//                print("Failt to set spotligt", String(describing: error))
//            }
//            // Update the state with thte last successful command
//            else{
//                // Let the spotlight state update the local state variable
//                self.spotEnable = enable
//                print("spotEnable from inside is :", String(enable))
//                //self.getEnabled()
//            }
//        })
//
//        print("The brightness state is: ", self.spotlight?.state?.brightness ?? 999)
//    }
//
//    func updateEnabled(){
//        self.spotlight?.getEnabledWithCompletion({(enabled, error) in
//            if error != nil{
//                print("There was an error calling for spotlight state")
//            }
//            else{
//                print("getEnables says that the spotlight enable is: ", String(enabled))
//                self.spotEnable = enabled
//            }
//        })
//    }
//
//    func setBrightness(brightness: UInt){
//        var target: UInt = brightness
//        if brightness < 1{
//            target = 1
//        }
//        else if brightness > 100{
//            target = 100
//        }
//        self.spotlight?.setBrightness(target, withCompletion: {(error: Error?) in
//            if error != nil{
//                print("Fail to set brightness", String(describing: error))
//            }
//            else{
//                // Successful command
//                print("The brightness is set to: ", self.getBrightness())
//            }
//        })
//    }
//
//    func getBrightness()->UInt{
//        guard let brightness: UInt = self.spotlight?.state?.brightness else {
//            return 0
//        }
//        return brightness
//    }
//
//    func getTemperature()->Float{
//        guard let temperature: Float = self.spotlight?.state?.temperature else {
//            return 0
//        }
//        return temperature
//    }
}

// The spotlight class
class spotlightClass: NSObject{
    var djiSpotlight: DJISpotlight
    var enabled: Bool = false
    init(theSpotRef: DJISpotlight){
        djiSpotlight = theSpotRef
    }
            
    func setEnable(enable: Bool){
        self.djiSpotlight.setEnabled(enable, withCompletion: {(error: Error?) in
            if error != nil{
                print("Failt to set spotligt", String(describing: error))
            }
            // Update the state with thte last successful command
            //else{
                // Let the spotlight state update the local state variable
                //enabled = enable
                //print("spotEnable from inside is :", String(enable))
                //self.getEnabled()
            //}
            // Update the locally stored spotlight state
            self.updateEnabled()
        })
        
        print("The brightness state is: ", self.djiSpotlight.state?.brightness ?? 999)
    }
        
    func updateEnabled(){
        self.djiSpotlight.getEnabledWithCompletion({(enabled, error) in
            if error != nil{
                print("There was an error calling for spotlight state")
            }
            else{
                print("getEnables says that the spotlight enable is: ", String(enabled))
                self.enabled = enabled
            }
        })
    }
    
    func setBrightness(brightness: UInt){
        var target: UInt = brightness
        if brightness < 1{
            target = 1
        }
        else if brightness > 100{
            target = 100
        }
        self.djiSpotlight.setBrightness(target, withCompletion: {(error: Error?) in
            if error != nil{
                print("Fail to set brightness", String(describing: error))
            }
            else{
                // Successful command
                print("The brightness is set to: ", self.getBrightness())
            }
        })
    }
    
    func getBrightness()->UInt{
        guard let brightness: UInt = self.djiSpotlight.state?.brightness else {
            return 0
        }
        return brightness
    }
    
    func getTemperature()->Float{
        guard let temperature: Float = self.djiSpotlight.state?.temperature else {
            return 0
        }
        return temperature
    }
}

// The Beacon class
class beaconClass: NSObject{
    var djiBeacon: DJIBeacon
    init(theBeaconRef: DJIBeacon){
        djiBeacon = theBeaconRef
    }
}

// The Speaker class
class speakerClass: NSObject{
    var djiSpeaker: DJISpeaker
    init(theSpeakerRef: DJISpeaker){
        djiSpeaker = theSpeakerRef
    }
}
