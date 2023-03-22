//
//  Coordinator.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-16.
//
// Inspired from hacking with swift: https://www.hackingwithswift.com/articles/71/how-to-use-the-coordinator-pattern-in-ios-apps
// and to conform to SceneDelegate:
// https://markstruzinski.com/2019/08/using-coordinator-with-scene-delegates/

import Foundation
import UIKit


protocol Coordinator {
    var childCoordinators: [Coordinator] { get set}
    var navigationController: UINavigationController {get set}
    
    func start()
}
