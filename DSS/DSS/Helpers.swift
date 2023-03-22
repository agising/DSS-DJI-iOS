//
//  Helpers.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-15.
//

import UIKit

// Helper functions for DJI communication on Settings page
extension UIControl {
    func connect(controlAction:ControlAction, for event:UIControl.Event) {
        self.addTarget(controlAction,
                       action: #selector(ControlAction.performAction(_:)),
                       for: event)
    }
    
    func connect(controlAction:ControlAction, for events:[UIControl.Event]) {
        for event in events {
            self.addTarget(controlAction,
                           action: #selector(ControlAction.performAction(_:)),
                           for: event)
        }
    }
    
    func connect(action: @escaping () -> (), for event:UIControl.Event) -> ControlAction {
        let controlAction = ControlAction(action)
        
        self.connect(controlAction: controlAction,
                     for: event)
        
        return controlAction
    }
    
    func connect(action: @escaping () -> (), for events:[UIControl.Event]) -> ControlAction {
        let controlAction = ControlAction(action)
        
        self.connect(controlAction: controlAction,
                     for: events)
        
        return controlAction
    }
}

typealias ControlActionClosure = () -> Void

public final class ControlAction {
    let action: ControlActionClosure
    init(_ action: @escaping ControlActionClosure) {
        self.action = action
    }
    
    @objc func performAction(_ sender:Any) {
        action()
    }
}


