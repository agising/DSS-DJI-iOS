//
//  MainCoordinator.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-16.
//

import Foundation
import UIKit

class MainCoordinator: Coordinator {
    var childCoordinators = [Coordinator]()
    var navigationController: UINavigationController
    
    init(navigationController: UINavigationController){
        self.navigationController = navigationController
        // Hide top bar and tabbar
        self.navigationController.setNavigationBarHidden(true, animated: false)
        self.navigationController.setToolbarHidden(true, animated: false)
    }
    
    func start(){
        //let vc = SettingsViewController.instantiate()
        let vc = SettingsViewController.instantiate()
        vc.modalPresentationStyle = .fullScreen
        // set coordinator to self in order for vc to be able to call back to coordinator correctly
        vc.coordinator = self
        navigationController.pushViewController(vc, animated: true)
    }
    
    // Method to switch to TYRAmoteViewController
    func gotoDSS(str: String, toAlt: Double, sim: Bool) {
        print("Going to DSS viewcontroller using CRM ip: ", str)
        let vc = DSSViewController.instantiate()
        vc.crm.ip = str
        if str != ""{
            // CRM is used, calc CRM port
            if let port = calcCRMPort(ipStr: getIPAddress()){
                vc.crmPort = port
            }
        }
        vc.copter.loc.takeOffLocationAltitude = Double(round(toAlt*10)/10)
        vc.sim = sim
        vc.coordinator = self
        vc.modalPresentationStyle = .fullScreen
        navigationController.pushViewController(vc, animated: true)
    }
    
    // Method to switch to Stettings Viewcontroller
    func gotoSettings(_ dssErrorText: String = "", toAlt: Double?) {
        print("Going to Settings")
        let vc = SettingsViewController.instantiate()
        vc.coordinator = self
        vc.dssErrorText = dssErrorText
        vc.toAlt = toAlt
        vc.modalPresentationStyle = .fullScreen
        navigationController.pushViewController(vc, animated: true)
    }
    
    func gotoMyDUXDefault(){
        print("Going to DUXDefaultViewContorller")
        let vc = MyDUXDefaultViewController.instantiate()
        vc.coordinator = self
        vc.modalPresentationStyle = .fullScreen
        navigationController.pushViewController(vc, animated: true)
    }

}
