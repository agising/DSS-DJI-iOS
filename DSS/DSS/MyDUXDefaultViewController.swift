//
//  test.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-29.
//

import Foundation
import DJIUXSDK

class MyDUXDefaultViewController: DUXDefaultLayoutViewController, Storyboarded{
    //var appDelegate = UIApplication.shared.delegate as! AppDelegate
    weak var coordinator: MainCoordinator?
 
    
    @IBOutlet weak var backButton: UIButton!
    
    @IBAction func backButtonPressed(_ sender: Any) {
        coordinator?.gotoSettings(toAlt: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let radius: CGFloat = 5
        backButton.layer.cornerRadius = radius
    }
}
