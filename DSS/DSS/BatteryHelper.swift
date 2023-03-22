//
//  BatteryHelper.swift
//  DSS
//
//  Created by Andreas Gising on 2021-09-14.
//

import Foundation
import DJIUXSDK

class BatteryController: NSObject, DJIBatteryDelegate{
    var battery: DJIBattery?                                   // The reference to the Battery
    var batteryState: DJIBatteryState = DJIBatteryState()       // Battery state updated by delegate funciton
    
    // ****************
    // Init the battery
    func initBattery(){
        // Range extension only seems to affect the pilot control pitch range. Range is not extended programatically
        // Set the gimbla delegate to self.
        battery!.delegate = self
    }
    
    //*****************************
    // The battery delegate function
    func battery(_ battery: DJIBattery, didUpdate state: DJIBatteryState) {
        self.batteryState = state
    }
}
