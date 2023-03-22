//
//  CleanUpHelpers.swift
//  DSS
//
//  Created by Andreas Gising on 2022-02-14.
//

import Foundation

// Return a short name for the connected drone based on the camera detected
func getShortName(cameraName: String)->String{
    var drone: String
    switch cameraName{
    case "Mavic 2 Enterprise Dual-Visual":
        drone = "DJI-M2ED"
    case "Mavic Mini Camera":
        drone =  "DJI-MM1"
    default:
        drone = "DJI"
    }
    return drone
}

// Return a descriptive name of the drone based on the detacted camera and accessories
func getDescription(sim: Bool, camera: String, accessory: String?)-> String{
    var str = ""
    if sim{
        str = "[SIM] - "
    }
    str += camera
    if accessory != nil{
        str += " - " + accessory!
    }
    return str
}
