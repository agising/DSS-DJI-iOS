//
//  Storyboarded.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-16.
//

import Foundation
import UIKit

protocol Storyboarded {
    static func instantiate() -> Self
}

extension Storyboarded where Self: UIViewController {
    //Make sure the storyBoard ID is the same as the class name to make this work.
    static func instantiate()-> Self {
        let id = String(describing: self)
        let storyboard = UIStoryboard(name: "Main", bundle:Bundle.main)
        //print("id: ", id)
        return storyboard.instantiateViewController(withIdentifier: id) as! Self
    }
}
