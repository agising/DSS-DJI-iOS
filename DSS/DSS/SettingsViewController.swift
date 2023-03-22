//
//  ViewController.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-15.
//

import Foundation
import UIKit
import DJISDK
import SwiftyJSON

//func simulatorLocationNumberFormatter() -> NumberFormatter {
//    let nf = NumberFormatter()
//    
//    nf.usesSignificantDigits = true
//    nf.minimumSignificantDigits = 8
//    nf.alwaysShowsDecimalSeparator = true
//    
//    return nf
//}

class SettingsViewController: UIViewController, UITextFieldDelegate, CLLocationManagerDelegate, Storyboarded {

    // TODO appDelegate is used or not?
    var appDelegate = UIApplication.shared.delegate as! AppDelegate
    
    // My coordinator
    weak var coordinator: MainCoordinator?
    
    
    
    // Location manager for retreiving the device location
    var locationManager = CLLocationManager()
    var crmDefaultIp = "10.44.160.10"                      // Default ip set when Default button is pressed
    var crmIp: String = ""                                // User set crm ip
    var useCRM = false
    var toAlt: Double?                                // The take-off altitude taken from the pilot instead of DJI..
    var dssErrorText = ""                                  // Variable to carry errors from dss screen
    
    // Label outlets
    @IBOutlet weak var regErrorLabel: UILabel!
    @IBOutlet weak var version: UILabel!
    @IBOutlet weak var registered: UILabel!
    @IBOutlet weak var register: UIButton!
    @IBOutlet weak var connected: UILabel!
    @IBOutlet weak var connect: UIButton!
    @IBOutlet weak var dssVersion: UILabel!
    @IBOutlet weak var toAltLabel: UILabel!
    @IBOutlet weak var dssErrorLabel: UILabel!
    
    // Simulator Controls
    @IBOutlet weak var simulatorOnOrOff: UILabel!
    @IBOutlet weak var startOrStopSimulator: UIButton!
    
    // Buttons for layout
    @IBOutlet weak var greenSafeButton: UIButton!
    @IBOutlet weak var orangeThinkButton: UIButton!
    @IBOutlet weak var greyDisabledButton: UIButton!
    
    
    // DSS button outlet
    @IBOutlet weak var CRMButton: UIButton!
    @IBOutlet weak var startDSSButton: UIButton!
    @IBOutlet weak var crmIpTextField: UITextField!
    @IBOutlet weak var DSSIpButton: UIButton!
    @IBOutlet weak var takeOffAltTextField: UITextField!
    
    
    @IBAction func CRMButtonPressed(_ sender: UIButton) {
        useCRM.toggle()
        // Update button graphics
        CRMEnable(enable: useCRM)
       
        if useCRM{
            crmIp = crmDefaultIp
            crmIpTextField.text = crmIp
        }
        else{
            crmIp = ""
            crmIpTextField.text = crmIp
        }
    }
    
    //
    // Updates the CRM button layout
    func CRMEnable(enable: Bool){
        if enable{
            CRMButton.backgroundColor = UIColor.systemGreen
            CRMButton.setTitle("CRM: YES", for: .normal)
        }
        else{
            CRMButton.backgroundColor = UIColor.systemGreen
            CRMButton.setTitle("CRM: NO", for: .normal)
        }
    }
    
    @IBAction func startDSSButtonPressed(_ sender: UIButton) {
        locationManager.stopUpdatingLocation()
        coordinator?.gotoDSS(str: crmIp, toAlt: self.toAlt!, sim: ProductCommunicationService.shared.isSimulatorActive)
    }
    
    @IBAction func crmIpTextFieldOK(_ sender: UITextField) {
        print("Editing did end, the entered IP is: ", crmIpTextField.text!)
        self.crmIp = crmIpTextField.text!
        // Easter egg! Enable the greenSafeButton to be able to go to DUXDefault
        self.greenSafeButton.isEnabled = true
    }
    
    @IBAction func takeOffAltTextFieldOK(_ sender: UITextField) {
        self.toAlt = CFStringGetDoubleValue(takeOffAltTextField.text as CFString?)
        // Gray out automatic take off alt to not confuse the user
        self.toAltLabel.textColor = UIColor.darkGray
    }
    
    
    @IBAction func DSSIpButtonAction(_ sender: UIButton) {
        let strIPAddress : String = getIPAddress()
        print("IPAddress :: \(strIPAddress)")
        DSSIpButton.setTitle(strIPAddress, for: .normal)
    }
    
    // Easter egg button, protected by CRM IP field..
    @IBAction func greenSafeButtonPressed(_ sender: UIButton) {
        // Secret button to go to default view for checking settings.
        // DCS IP has to be filled out prior to button activation.
        coordinator?.gotoMyDUXDefault()
    }
    
    
    // *********************************
    // CLLocation delegate update method
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Get the location
        let loc :CLLocation = locations[0] as CLLocation

        // Checki if vertical alt is valid, if not return
        if loc.verticalAccuracy < 0 {
            print("Altitude not valid", loc.verticalAccuracy)
            self.toAltLabel.text = "N/A"
            return
        }
        
        // Offset altitude by iPhoneAGL, assume controller is in Pilots hands
        let iPhoneAGL = 1.0
        // Save toAlt if is not manually set, coordinator will send toAlt to DSS when started.
        if self.takeOffAltTextField.text == "" {
            self.toAlt = round((loc.altitude - iPhoneAGL)*10)/10
        }
        // Round to 1 decimal and print to screen
        //let roundedAlt = round(loc.altitude*10)/10 - iPhoneAGL
       
        
        // let vertAcc = round(loc.verticalAccuracy*100)/100
        self.toAltLabel.text = String(self.toAlt!) // + ", q:" + String(vertAcc)
        
        // Remove print after debugging
        // print("Take-off altitude: ", self.toAlt!, " accuracy: ", String(vertAcc))
    }
    
    // ********************************
    // CLLocation delegate error method
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error \(error)")
        // TODO smart handling
        //locationManager.stopUpdatingLocation()
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Set up layout of the DSS Button
        let radius: CGFloat = 5
        CRMButton.layer.cornerRadius = radius
        
        startDSSButton.isEnabled = true
        startDSSButton.backgroundColor = UIColor.lightGray
        startDSSButton.isEnabled = false
        
        // Set corner radiuses to buttons
        startDSSButton.layer.cornerRadius = radius
        startDSSButton.backgroundColor = UIColor.lightGray
        startDSSButton.isEnabled = false
        
        DSSIpButton.layer.cornerRadius = radius
        DSSIpButton.backgroundColor = UIColor.systemGreen
        greenSafeButton.layer.cornerRadius = radius
        orangeThinkButton.layer.cornerRadius = radius
        greyDisabledButton.layer.cornerRadius = radius
        
        greenSafeButton.isEnabled = false
        orangeThinkButton.isEnabled = false
        greyDisabledButton.isEnabled = false
        
        // crm input field
        crmIpTextField.layer.cornerRadius = radius
        crmIpTextField.returnKeyType = .done
        crmIpTextField.keyboardType = .numbersAndPunctuation
        crmIpTextField.autocorrectionType = .no
        crmIpTextField.clearButtonMode = .whileEditing
        crmIpTextField.clearsOnBeginEditing = true
        crmIpTextField.delegate = self
        // Hide unhude crm IP. TODO Default to this decvice ip instead of RISE crm default.
        crmIpTextField.isHidden = false
        
        // takeOffAltitude field
        takeOffAltTextField.layer.cornerRadius = radius
        takeOffAltTextField.returnKeyType = .done
        takeOffAltTextField.keyboardType = .numbersAndPunctuation
        takeOffAltTextField.autocorrectionType = .no
        takeOffAltTextField.clearButtonMode = .whileEditing
        takeOffAltTextField.clearsOnBeginEditing = true
        takeOffAltTextField.delegate = self
        takeOffAltTextField.isHidden = false
        
        // Press CRMButton for defaulting to use CRM
        CRMButtonPressed(CRMButton)
        CRMButton.isHidden = true
        // Press DSSip button to display dssIp
        DSSIpButtonAction(DSSIpButton)
        
        self.dssErrorLabel.text = self.dssErrorText
        
        if let alt = self.toAlt {
            takeOffAltTextField.text = String(alt)
            // Gray out automatic take off alt to not confuse the user
            self.toAltLabel.textColor = UIColor.darkGray
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(productCommunicationDidChange), name: Notification.Name(rawValue: ProductCommunicationServiceStateDidChange), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFlightControllerSimulatorDidStart), name: Notification.Name(rawValue: FligntControllerSimulatorDidStart), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFlightControllerSimulatorDidStop), name: Notification.Name(rawValue: FligntControllerSimulatorDidStop), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(productRegisterDidError), name: Notification.Name(rawValue: ProductRegisterDidError), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(productRegisterOk), name: Notification.Name(rawValue: ProductRegisterOk), object: nil)
        
        // Notification for keyboard appearing and dissappearing. Used to move the textfield such as input can be seen as editing
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(sender:)), name: UIResponder.keyboardWillShowNotification, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(sender:)), name: UIResponder.keyboardWillHideNotification, object: nil);
    
        // Location manager
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestAlwaysAuthorization()
        
        // A privacy check appriciated by Apple
        if CLLocationManager.locationServicesEnabled(){
            locationManager.startUpdatingLocation()
        }
        
        // Make sure the register is evaluated when jumping back in the hierachy
        registerAction()
    }
    
//    func requestWhenInUseAuthorization(){
//
//    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        var version = DJISDKManager.sdkVersion()
        if version == "" {
            version = "N/A"
        }
        
        // DSS version
        self.dssVersion.text = UIApplication.version
        NSLog("DSS version: " + UIApplication.version)
        
        //SDK version
        self.version.text = "Version \(version)"
        NSLog("UXSDK version: " + version)
      
          
        self.updateSimulatorControls(isSimulatorActive: ProductCommunicationService.shared.isSimulatorActive)
    }
    
    
    @IBAction func registerAction() {
        ProductCommunicationService.shared.registerWithProduct()
    }
    
    @objc func productRegisterDidError() {
        // Look for errors at shared string
        let regError = ProductCommunicationService.shared.regError
        if regError != ""{
            //if let theError = regError {
                self.regErrorLabel.text = regError
            //}
            self.regErrorLabel.backgroundColor = UIColor.white
            //self.registered.text = String(substring)
            self.registered.textColor = UIColor.systemRed

            // Exctract the error code and show on other label.
            if let firstRange = regError.range(of: "code:"){
                if let secondRange = regError.range(of: ")") {
                    let substring = regError[firstRange.upperBound...secondRange.lowerBound]
                    var theCode = String(substring)
                    theCode.removeLast()
                    self.registered.text = theCode
                }
            }

        }
    }
    
    @objc func productRegisterOk(){
        print("Product registration Ok, clear error text")
        self.regErrorLabel.text = ""
        self.regErrorLabel.backgroundColor = UIColor.black
    }
    
    
    @IBAction func connectAction() {
        ProductCommunicationService.shared.connectToProduct()
    }
    
    
    @objc func productCommunicationDidChange() {
        
        // If this demo is used in China, it's required to login to your DJI account to activate the application.
        // Also you need to use DJI Go app to bind the aircraft to your DJI account. For more details, please check this demo's tutorial.
        
        if ProductCommunicationService.shared.registered {
            self.registered.text = "YES"
            self.register.isHidden = true
        } else {
            self.registered.text = "NO"
            self.register.isHidden = false
        }
        
        if ProductCommunicationService.shared.connected {
            self.connected.text = "YES"
            self.connect.isHidden = true
            startDSSButton.backgroundColor = UIColor.systemOrange
            startDSSButton.setTitleColor(UIColor.white, for: .normal)
            startDSSButton.isEnabled = true
        } else {
            self.connected.text = "NO"
            self.connect.isHidden = false
            startDSSButton.backgroundColor = UIColor.lightGray
            startDSSButton.isEnabled = false
        }
    }

    
    // MARK: - UITextFieldDelegate
    func textFieldDidEndEditing(_ textField: UITextField) {
        //if textField == self.bridgeModeIPField {
        //    ProductCommunicationService.shared.bridgeAppIP = textField.text!
        //}
        if textField == self.crmIpTextField {
            print("CRM IP text field did end editing") // Did end
        }
        else if textField == self.takeOffAltTextField {
            print("Take off altitude was edited")
        }
    }
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField == self.crmIpTextField {
            crmIpTextField.text = self.crmDefaultIp
        }
        else if textField == self.takeOffAltTextField {
            // Populate textfield with othing (prev: self.toAltLabel.text)
            takeOffAltTextField.text = ""
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField.canResignFirstResponder {
            textField.resignFirstResponder()
        }
        return true
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        if textField == self.crmIpTextField{
            if let text = textField.text{
                // Leave blank if not using crm
                if text == ""{
                    CRMEnable(enable: false)
                    return true
                }
                let dots = text.filter { $0 == "." }.count
                let colons = text.filter { $0 == ":"}.count
                
                print("number of dots: ", dots, "number of colons: ", colons)
                if dots == 3 && colons == 0{
                    CRMEnable(enable: true)
                    return true
                }
            }
            textField.text = "bad IP format"
            //ipInputField.backgroundColor = UIColor.systemRed
            CRMEnable(enable: false)
            return false
        }
        // Dont change behaviour of Bridgemode text field
        else{
            return true
        }
    }
    
    // Keyboard will hide and show move the entire view for visability.
    @objc func keyboardWillShow(sender: NSNotification) {
         self.view.frame.origin.y = -150 // Move view 150 points upward
    }

    @objc func keyboardWillHide(sender: NSNotification) {
         self.view.frame.origin.y = 0 // Move view to original position
    }
    
    
    // MARK: - Simulator Controls

    @objc func handleFlightControllerSimulatorDidStart() {
        self.updateSimulatorControls(isSimulatorActive: true)
        startDSSButton.backgroundColor = UIColor.systemGreen
        startDSSButton.setTitleColor(UIColor.white, for: .normal)
        startDSSButton.setTitle("SIMULATE", for: .normal)
        startDSSButton.isEnabled = true

    }
    
    @objc func handleFlightControllerSimulatorDidStop() {
        self.updateSimulatorControls(isSimulatorActive: false)
        startDSSButton.backgroundColor = UIColor.systemOrange
        startDSSButton.setTitleColor(UIColor.white, for: .normal)
        startDSSButton.setTitle("Start DSS", for: .normal)
        startDSSButton.isEnabled = true

    }
    
    @objc func updateSimulatorControls(isSimulatorActive:Bool) {
        self.simulatorOnOrOff.text = isSimulatorActive ? "ON" : "OFF"
        let simulatorControlTitle = isSimulatorActive ? "Stop" : "Start"
        self.startOrStopSimulator.setTitle(simulatorControlTitle, for: .normal)
        self.startOrStopSimulator.setTitle(simulatorControlTitle, for: .highlighted)
        self.startOrStopSimulator.setTitle(simulatorControlTitle, for: .disabled)
        self.startOrStopSimulator.setTitle(simulatorControlTitle, for: .selected)
    }
    
    // Simulator screen is not storyboarded, hence the coordinator cannot control it.. Lets stay with the dji sample implementation for this view
    @IBAction func handleStartOrStopSimulator() {
        if ProductCommunicationService.shared.isSimulatorActive == true {
            let didStartStoppingSimulator = ProductCommunicationService.shared.stopSimulator()
            self.dismiss(self)
            if !didStartStoppingSimulator {
                self.presentError("Could Not Begin Stopping Simulator")
            }
        } else {
            let viewController = SimulatorControlsViewController()
            
            let navigationController = UINavigationController(rootViewController: viewController)
        
            let dismissItem = UIBarButtonItem(barButtonSystemItem: .done,
                                              target: self,
                                              action: #selector(SettingsViewController.dismiss(_:)))
            viewController.navigationItem.rightBarButtonItem = dismissItem
            
            navigationController.modalPresentationStyle = .formSheet
            viewController.modalPresentationStyle = .formSheet
            
            self.present(navigationController,
                         animated: true,
                         completion: nil)
        }
    }
    
    @objc public func dismiss(_ sender: Any) {
        self.presentedViewController?.dismiss(animated: true,
                                            completion: nil)
    }
}

extension UIViewController {
    func presentError(_ errorDescription:String) {
        let alertController = UIAlertController(title: "Error",
                                              message: errorDescription,
                                              preferredStyle: .alert)
        let action = UIAlertAction(title: "Ok",
                                   style: .cancel,
                                 handler: nil)
        
        alertController.addAction(action)
        
        self.present(alertController,
                     animated: true,
                     completion: nil)
    }
}

