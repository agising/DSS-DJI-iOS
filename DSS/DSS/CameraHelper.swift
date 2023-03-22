//
//  CameraHelper.swift
//  DSS
//
//  Created by Andreas Gising on 2021-04-28.
//


import Foundation
import DJISDK
import SwiftyJSON

class CameraController: NSObject, DJICameraDelegate {
    var camera: DJICamera?
    var cameraAllocator = Allocator(name: "camera")
    var transferAllAllocator = Allocator(name: "transferAll")
    
    var dataPub: Publisher?                             // the data Publish socket
    
    var modeStr = ""                                    // State memory
    var isStoringPhoto = false                          // State memory
    var isRecording = false                             // State memory
    var cameraType = ""                                 // Connected camera type (Mavic Mini Camera, Mavic Mini 2 Camera, Mavic 2 Enterprise Dual-Visual)
    var connectionType = ""                             // String for conneciton type. Poor connection does not allow continous publish
    
    var continousPhotoEnabled = false                   // Flag for continous photo thread
    var photoPeriod: Double = 0                         // Period for continous photos (sec/photo)
    var photoPublish = "off"                            // Photo publish setting for continous photo
    
    var sessionLastIndex: Int = 0                       // Picture index of this session
    var sdFirstIndex: Int = -1                          // Start index of SDCard, updates at first download
    
    var jsonMetaDataXYZ: JSON = JSON()                  // All the photo metadata XYZ
    var jsonMetaDataNED: JSON = JSON()                  // All th photo metadata NED
    var jsonMetaDataLLA: JSON = JSON()                  // All the photo metadata LLA
    var jsonMetaDataXYZLow: JSON = JSON()               // All the preview metadata XYZ
    var jsonMetaDataNEDLow: JSON = JSON()               // All th preview metadata NED
    var jsonMetaDataLLALow: JSON = JSON()               // All the preview metadata LLA
    
    var jsonPhotos: JSON = JSON()                       // Photos filename and downloaded status
    var jsonPreviews: JSON = JSON()                     // Previews filename and downloaded status
    var capabilities:[String] = []                      // Build capabilities
    
    
    
    // ****************************
    // Delegates and core functions
    
    // ****
    // Init
    func initCamera(publisherSocket: Publisher){
        // Reset capabilites to support installing PL while app is on
        self.capabilities = []

        camera!.delegate = self
        dataPub = publisherSocket
        cameraType = getCameraType()
        print("Connected camera: ", cameraType)
        // Set capabilities
        switch cameraType{
        case "Mavic Mini Camera":
            self.capabilities.append("RGB")
            self.capabilities.append("C0")
        case "DJI Mini 2 Camera":
            self.capabilities.append("RGB")
            self.capabilities.append("C0")
        case "Mavic 2 Enterprise Dual-Visual":
            // Accessory capabilites detected in accessory helper
            self.capabilities.append("RGB")
            self.capabilities.append("IR")
        default:
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Warning: Unknown Camera, report line below"])
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": cameraType])
        }
        
//        // DJISDK 4.16.2
//        let camera = fetchCamera()
//        if camera?.displayName == DJICameraDisplayNameDJIMini2Camera{
//            print("It's a mini2")
//        }
        
    }
        
    // *****************************************************
    // Camera delegate function, monitor system state update
    func camera(_ camera: DJICamera, didUpdate systemState: DJICameraSystemState) {
        // Monitor camera mode change
        let modeStr = parseMode(mode: systemState.mode.rawValue)
        if modeStr != self.modeStr{
            // Mode changed
            print("Camera mode changed to: ", modeStr)
            self.modeStr = modeStr
        }

        // Monitor isStoringPhoto change. Note that takePhoto will set auxOccupier prior to SD-Card being occupied..
        if self.isStoringPhoto != systemState.isStoringPhoto{
            // Status changed
            self.isStoringPhoto = systemState.isStoringPhoto
            cameraAllocator.setAuxOccopier(occupied: systemState.isStoringPhoto)
            NotificationCenter.default.post(name: .didChangeSDStatus, object: self, userInfo: ["occupied": systemState.isStoringPhoto])
        }
        
        // Monitor isRecording change. Note that Recording will set auxOccupier prior to SD-Card being occupied..
        if self.isRecording != systemState.isRecording{
            // Status changed
            self.isRecording = systemState.isRecording
            cameraAllocator.setAuxOccopier(occupied: systemState.isRecording)
            NotificationCenter.default.post(name: .didChangeSDStatus, object: self, userInfo: ["occupied": systemState.isRecording])
        }
    }
    
    // *****************************
    // Get the connected camera type
    func getCameraType()->String{
        guard let cameraKey = DJICameraKey(param: DJICameraParamDisplayName ) else {
            NSLog("Couldn't create the key")
            return ""
        }
        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return ""
        }
        
        if let typeValue = keyManager.getValueFor(cameraKey){
            let type = typeValue.value as! String
            return type
        }
        else{
            return ""
        }
    }
    
    // ****************************
    // Check if SD-card is inserted
    func getSDCardInserted()->Bool{
        guard let cameraKey = DJICameraKey(param: DJICameraParamSDCardIsInserted) else {
            NSLog("Couldn't create the key")
            return false
        }
        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return false
        }
        
        if let insertedValue = keyManager.getValueFor(cameraKey){
            let inserted = insertedValue.value as! Bool
            return inserted
        }
        else{
            return false
        }
    }
    
    // ********************************
    // Check available space on SD-Card
    func getSDCardAvailableSpace()->Int?{
        guard let cameraKey = DJICameraKey(param: DJICameraParamSDCardRemainingSpaceInMB) else {
            NSLog("Couldn't create the key")
            return nil
        }
        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
        
        if let remainingSpaceValue = keyManager.getValueFor(cameraKey){
            let remainingSpace = remainingSpaceValue.value as! Int
            return remainingSpace
        }
        else{
            return nil
        }
    }
    
    // *********************
    // Chack SD-Card capacity
    func getSDCardCapacity()->Int?{
        guard let cameraKey = DJICameraKey(param: DJICameraParamSDCardTotalSpaceInMB) else {
            NSLog("Couldn't create the key")
            return nil
        }
        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
        
        if let capacityValue = keyManager.getValueFor(cameraKey){
            let capacity = capacityValue.value as! Int
            // Returns 0 even without SDCard..
            if capacity == 0{
                return nil
            }
            else{
                return capacity
            }
        }
        else{
            return nil
        }
    }
    
    // *********************************
    // Get SD-Card available photo count
    func getSDCardAvailablePhotoCount()->Int?{
        guard let cameraKey = DJICameraKey(param: DJICameraParamSDCardAvailablePhotoCount) else {
            NSLog("Couldn't create the key")
            return nil
        }
        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
        
        if let availablePhotoCountValue = keyManager.getValueFor(cameraKey){
            let availablePhotoCount = availablePhotoCountValue.value as! Int
            return availablePhotoCount
        }
        else{
            return nil
        }
    }
    
    // ***********************************************
    // Get SD-Card avaialble recording time in seconds
    func getSDCardAvailableRecordingTimeSeconds()->Int?{
        guard let cameraKey = DJICameraKey(param: DJICameraParamSDCardAvailableRecordingTimeInSeconds) else {
            NSLog("Couldn't create the key")
            return nil
        }
        guard let keyManager = DJISDKManager.keyManager() else {
            print("Couldn't get the keyManager, are you registered")
            return nil
        }
        
        if let availableRecTimeValue = keyManager.getValueFor(cameraKey){
            let availableRecTime = availableRecTimeValue.value as! Int
            return availableRecTime
        }
        else{
            return nil
        }
    }
    
    
    
    // MARK: Custom camera funcitons
    // ***********************
    // Custom camera functions
    // ***********************
    
    // Start/stop recoding and return completion as escaping bool (for completion code to pick up)
    func recording(enable: Bool, completion: @escaping (Bool) -> Void){
        // Disable recording
        if enable == false{
            self.camera?.stopRecordVideo(completion: {(error) in
                if error != nil{
                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Stop camera recording failed"])
                    completion(false)
                }
                else{
                    NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Stopped recording video"])
                    completion(true)
                }
            })
        }
        else{
            //Enable recording
            self.cameraSetMode(DJICameraMode.recordVideo, 2, completionHandler: {(succsess: Bool) in
                if succsess{
                    // Camera is set to recording
                    self.camera?.startRecordVideo(completion: {(error) in
                        if error != nil{
                            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Start camera recording failed"])
                            completion(false)
                        }
                        else{
                            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Started recording video"])
                            completion(true)
                        }
                    })
                }
            })
        }
    }
    
    // ***********************************************************************************************************************************************
    // cameraSetMode checks if the newCamera mode is the active mode, and if not it tries to set the mode 'attempts' times. TODO - is attemtps needed?
    func cameraSetMode(_ newCameraMode: DJICameraMode,_ attempts: Int, completionHandler: @escaping (Bool) -> Void) {
        
        // Don't exxed maximum number of tries
        if attempts <= 0{
            NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Error: Camera set mode - too many"])
            completionHandler(false)
            return
        }
        
        // Cameramode seems to automatically be reset to single photo. We cannot use local variable to store the mode. Hence getting and setting the current mode should intefere equally, it is better to set directly than first getting, checking and then setting.
        // Set mode to newCameraMode.
        self.camera?.setMode(newCameraMode, withCompletion: {(error: Error?) in
            if error != nil {
                self.cameraSetMode(newCameraMode, attempts - 1 , completionHandler: {(success: Bool) in
                    if success{
                        completionHandler(true)
                    }
                })
            }
            else{
                // Camera mode is successfully set
                completionHandler(true)
            }
        })
    }
    
    // Taking photos
    //*********************************************************
    //Function executed when a take_picture command is received
    func takePhotoCMD(){
        self.capturePhoto(completion: {(success) in
            if success{
                self.sessionLastIndex += 1
                // Write JSON meta data
                NotificationCenter.default.post(name: .doWriteMetaData, object: self, userInfo: ["sessionLastIndex": self.sessionLastIndex])
            }
            else{
                NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": "Take Photo failed to complete"])
            }
            // The camera has not started writing to sdCard yet, but lock the resource for now to prevent allocator from releasing.
            self.cameraAllocator.setAuxOccopier(occupied: true)
            // Deallocate as soon as SD-card has finished
            self.cameraAllocator.deallocate()
        })
    }
    
    //*************************************************************
    // Helper function to takePhoto .Sets up the camera if needed and takes a photo.
    func capturePhoto(completion: @escaping (Bool)-> Void ) {
        // Make sure camera is in the correct mode
        self.cameraSetMode(DJICameraMode.shootPhoto, 2, completionHandler: {(succsess: Bool) in
            if succsess{
                // Make sure shootPhotoMode is single, if so, go ahead startShootPhoto
                self.camera?.setShootPhotoMode(DJICameraShootPhotoMode.single, withCompletion: {(error: Error?) in
                    if error != nil{
                        print("Error setting ShootPhotoMode to single")
                        completion(false)
                    }
                    else{
                        // Take photo and save to sdCard
                        self.camera?.startShootPhoto(completion: { (error) in
                            // Camera is wrinting to sdCard AFTER photo is completed!
                            if error != nil {
                                // Errors like SD card errors for example
                                self.printHelp("Photo Error: " + String(describing: error))
                                completion(false)
                            }
                            else{
                                completion(true)
                            }
                        })
                    }
                })
            }
            else{
                print("cameraSetMode failed")
                completion(false)
            }
        })
    }
    
    
    // Transfer photos
    
    //********************************************
    // Save PhotoData to app, set URL to the object
    func savePhotoDataToApp(photoData: Data, filename: String, sessionIndex: Int){
        // Translate the sdCardIndex index to theSessionIndex numbering starting at 1.
        //let theSessionIndex = index - self.sdFirstIndex + 1
        //let theSessionIndex = sessionIndex
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let documentsURL = documentsURL {
            let fileURL = documentsURL.appendingPathComponent(filename)
            do {
                try photoData.write(to: fileURL, options: .atomicWrite)
                self.jsonPhotos[String(sessionIndex)]["stored"].boolValue = true
                //self.printDB("savePhotoDataToApp: The write fileURL points at: " + fileURL.description)
            } catch {
                self.printHelp("savePhotoDataToApp: Could not write photoData to App: " + String(describing: error))
            }
        }
    }
    
    // ***************************************************************************************************************
    // Transfers (publishes) all photos, downloads from sdCard if needed. transferAll allocates the rescource it self.
    func transferAll(res: String){
        // Check if there are any photos to transfer
        if self.sessionLastIndex == 0 {
            print("transferAll: No photos to transfer")
            self.transferAllAllocator.deallocate()
            return
        }
        self.transferAllHelper(sessionIndex: self.sessionLastIndex, res: res, attempt: 1, skipped: 0)
    }
    
    // *****************************************************************
    // Iterative nested calls, allows three download attempts per index.
    func transferAllHelper(sessionIndex: Int, res: String, attempt: Int, skipped: Int){
        // If too many attempts, skip this photo
        if attempt > 3{
            print("transferAllHelper: Difficulties downloading index: ", sessionIndex, " Skipping.")
            // If there are more photos in que, try with next one, add one to skipped.
            if sessionIndex > 1 {
                self.transferAllHelper(sessionIndex: sessionIndex - 1, res: res, attempt: 1, skipped: skipped + 1)
            }
            // If no more photos in que, report result to user, deallocate transferAll and return.
            else {
                self.printHelp("downloadAllHelper: Caution: " + String(skipped + 1) + " photos not transferred")
                self.transferAllAllocator.deallocate()
                return
            }
        }
        else {
            self.transferIndex(sessionIndex: sessionIndex, res: res, completionHandler: {(success) in
                if success{
                    // If no more photos in que, report result to user, deallocate transferAll and return
                    if sessionIndex == 1{
                        if skipped == 0 {
                            self.printHelp("downloadAllHelper: All photos transferred")
                        }
                        else {
                            self.printHelp("downloadAllHelper: Caution: " + String(skipped) + " photos not transferred")
                        }
                        self.transferAllAllocator.deallocate()
                        self.cameraSetMode(DJICameraMode.shootPhoto, 2, completionHandler: {(success: Bool) in
                            if success {
                                // Great, mode is shootPhoto again
                            }
                            else{
                                print("Failed to  reset cameraMode")
                            }
                        })
                        return
                    }
                    else {
                        self.transferAllHelper(sessionIndex: sessionIndex - 1, res: res, attempt: 1, skipped: skipped)
                    }
                }
                else{
                    // Sleep to give system a chance to recover..
                    usleep(200000)
                    self.transferAllHelper(sessionIndex: sessionIndex, res: res, attempt: attempt + 1, skipped: skipped)
                }
            })
        }
    }
    
    //
    // Uses transferIndex to download and transfer photo with index sessionIndex. I tries max three times.
    func transferSingle(sessionIndex: Int, res: String, attempt: Int){
        if attempt > 3{
            print("transferSingle: Difficulties downloading index: ", sessionIndex, " Skipping.")
            return
        }
        self.transferIndex(sessionIndex: sessionIndex, res: res, completionHandler: {(success) in
            if success{
                self.printHelp("downloadSingle: Photo index: " + String(sessionIndex) + ", transferred")
                self.cameraSetMode(DJICameraMode.shootPhoto, 2, completionHandler: {(success: Bool) in
                    if success {
                        // Great, mode is shootPhoto again
                    }
                    else{
                        print("Failed to  reset cameraMode")
                    }
                })
            }
            else{
                self.printHelp("downloadSingle: Failed to transfer index: " + String(sessionIndex))
                // Sleep to give user a chance to read the message..
                usleep(500000)
                self.transferSingle(sessionIndex: sessionIndex, res: res, attempt: attempt + 1)
            }
        })
    }
    
    
    
    
    // *********************************************
    // Transfer a photo with sessionIndex [1,2...n].
    // Fcn transferSigle and transferAll(helper) uses transferIndex to execute the media transfer.
    func transferIndex(sessionIndex: Int, res: String, completionHandler: @escaping (Bool) -> Void){
        //print("transferIndex: jsonPhotos: ", self.jsonPhotos)
        self.printHelp("Transfer index: " + String(sessionIndex))
        
        // Setup som variables for high or low resolution media
        var highRes: Bool
        var mediaTypeStr: String
        var maxTime: Double
        var metaData: JSON
        if res == "high"{
            highRes = true
            mediaTypeStr = "Photo"
            maxTime = 41
            metaData = jsonMetaDataXYZ
        }
        else{
            highRes = false
            mediaTypeStr = "Preview"
            maxTime = 5
            metaData = jsonMetaDataXYZLow
        }
        
        // Check if the index exists
        if self.jsonPhotos[String(sessionIndex)].exists(){
            // Check if the requested resolution is not already stored
            if (highRes && jsonPhotos[String(sessionIndex)]["stored"] == false) ||
                (!highRes && jsonPreviews[String(sessionIndex)]["stored"] == false){
                
                // Download the requested resolution
                // Allocate allocator
                while !self.cameraAllocator.allocate("download", maxTime: maxTime){
                    // Sleep 0.1s
                    let sleep = 0.1
                    usleep(UInt32(sleep*1000000))
                    maxTime -= sleep
                    if maxTime < 0 {
                        // Give up attempt to download index
                        self.printHelp("transferIndex: Error, could not allocate cameraAllocator")
                        completionHandler(false)
                    }
                }
                // Allocator allocated
                self.savePhoto(sessionIndex: sessionIndex, res: res, completionHandler: {(saveSuccess) in
                    // Download of media is complete, deallocate resource
                    self.cameraAllocator.deallocate()
                    if saveSuccess {
                        self.printHelp(mediaTypeStr + " " + String(sessionIndex) + " downloaded to App")
                        // Call the function again, this time the media is alreade stored
                        self.transferIndex(sessionIndex: sessionIndex, res: res, completionHandler: {(success: Bool) in
                            // Completion handler on first call depends on the second call, child process.
                            if success{
                                completionHandler(true)
                            }
                            else{
                                completionHandler(false)
                            }
                        })
                    }
                    else{
                        self.printHelp("transferIndex: Error, failed to download index " + String(sessionIndex))
                        completionHandler(false)
                    }
                })
            }
            
            // Media is already stored, load and transfer it!
            else{
                var topic = ""
                var filename: String
                if highRes{
                    filename = self.jsonPhotos[String(sessionIndex)]["filename"].stringValue
                    topic = "photo"
                }
                else{
                    filename = self.jsonPreviews[String(sessionIndex)]["filename"].stringValue
                    topic = "photo_low"
                }
                // Build up the full URLpath, then load photo and transfer
                if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let fileURL = documentsURL.appendingPathComponent(filename)
                    //self.printDB("The file url we try to publish: " + fileURL.description)
                    do{
                        let mediaData = try Data(contentsOf: fileURL)
                        self.printHelp(mediaTypeStr + " " + String(sessionIndex) + " published on PUB-socket")
                        var json_photo = JSON()
                        json_photo["photo"].stringValue = getBase64utf8(data: mediaData)
                        // What metadata to add, XYZ or LLA? High or low res
                        json_photo["metadata"] = metaData[String(sessionIndex)]
                        //print(topic, json_photo["photo"])
                        _ = self.dataPub!.publish(topic: topic, json: json_photo)
                        completionHandler(true)
                    }
                    catch{
                        print("transferIndex: Could not load data: ", filename)
                        completionHandler(false)
                    }
                }
            }
        }
        // There is no such index
        else{
            self.printHelp("Photo index has not been produced yet: " + String(sessionIndex))
            completionHandler(false)
        }
    }
    
    
    // Download photos
    
    
    //*******************************************************************************************************
    // Helper function to transferIndex. Save photo from sdCardto app memory. Setup camera then call getImage
    func savePhoto(sessionIndex: Int, res: String, completionHandler: @escaping (Bool) -> Void){
        // Setting camera mode takes ~ 0.8-1s
        cameraSetMode(DJICameraMode.mediaDownload, 2, completionHandler: {(success: Bool) in
            if success {
                // Getting image takes ~ 2s when on ground and 5GHz network.
                self.getImage(sessionIndex: sessionIndex, res: res, completionHandler: {(new_success: Bool) in
                    if new_success{
                        completionHandler(true)
                    }
                    else{
                        completionHandler(false)
                    }
                })
            }
            else{
                completionHandler(false)
            }
        })
    }
    
    
    //******************************************************************************************************
    // Helper function to savePhoto. Downloads an photoData from sdCard, high or low res. Saves data to app.
    func getImage(sessionIndex: Int, res: String, completionHandler: @escaping (Bool) -> Void){
        let manager = self.camera?.mediaManager
        
        // Refreshing file list takes 0.8 - 1s if file list has changed since last time, otherwise ~0s.
        manager?.refreshFileList(of: DJICameraStorageLocation.sdCard, withCompletion: {(error: Error?) in
            print("Refreshing file list...")
            if error != nil {
                completionHandler(false)
                self.printHelp("Refresh file list Failed")
                return
            }
            
            // Get file references TODO - only needed the first time? Could do dead reckoning assuming pilot will not take photos.
            guard let files = manager?.sdCardFileListSnapshot() else {
                self.printHelp("No photos on sdCard")
                completionHandler(false)
                return
            }
            // Print number of files on sdCard and note the first photo of the session if not already done
            print("Files on sdCard: ", String(describing: files.count))
            if self.sdFirstIndex == -1 {
                self.sdFirstIndex = files.count - self.sessionLastIndex
                print("sessionIndex 1 mapped to cameraIndex: ", self.sdFirstIndex)
                // The files[self.sdFirstIndex] is the first photo of this photosession, it maps to self.jsonMetaData[self.sessionLastIndex = 1]
            }
            
            // Update Metadata with filename for the n last pictures without a filename added already
            for i in stride(from: self.sessionLastIndex, to: 0, by: -1){
                if files.count < self.sdFirstIndex + i{
                    self.sessionLastIndex =  files.count - self.sdFirstIndex // In early bug photo was not always saved on SDcard, but sessionLastIndex is increased. This quickfix should not be needed now thanks to allocator.
                    // This is triggered if taking a photo during downloading all photos.
                    print("SessionIndex faulty. Some images were not saved on sdCard.. DEBUG if printed!")
                }
                
                // Check if filenames are updated for the metadata(s) - if not update it
                let indx = String(i)
                if self.jsonMetaDataXYZ[indx]["filename"] == ""{
                    let filename = files[self.sdFirstIndex + i - 1].fileName
                    let filenameLow = filename.replacingOccurrences(of: ".", with: "_low.")
                    // Hig and ow res metadata
                    self.jsonMetaDataXYZ[indx]["filename"].stringValue = filename
                    self.jsonMetaDataLLA[indx]["filename"].stringValue = filename
                    
                    self.jsonMetaDataXYZLow[indx]["filename"].stringValue = filenameLow
                    self.jsonMetaDataLLALow[indx]["filename"].stringValue = filenameLow
                    
                    // Download status JSON
                    self.jsonPhotos[indx]["filename"].stringValue = filename
                    self.jsonPreviews[indx]["filename"].stringValue = filenameLow
                    print("Added filename: " + filename + " to sessionIndex: " + indx)
                }
                else{
                    // Picture n has a filename -> so does n-1, -2, -3 etc -> break!
                    break
                }
            }
            
            // Translate session index (index of this session) to the cameraIndex and theSessionIndex - in case session index is coded for last index.
            var cameraIndex = 0
            var theSessionIndex = 0
            // Last image
            if sessionIndex == 0 {
                cameraIndex = files.count - 1
                theSessionIndex = self.sessionLastIndex
            }
            else{
                cameraIndex = sessionIndex + self.sdFirstIndex - 1
                theSessionIndex = sessionIndex
            }
            
            if res == "high"{
                // Download the high res photo
                // Create a photo container for this scope
                var photoData: Data?
                var i: Int?
                
                // Download batchhwise, append data. Closure is called each time data is updated.
                files[cameraIndex].fetchData(withOffset: 0, update: DispatchQueue.main, update: {(_ data: Data?, _ isComplete: Bool, error: Error?) -> Void in
                    if error != nil{
                        // This happens if download is triggered to close to taking a picture. Is the allocator used?
                        self.printHelp("Error, set camera mode first: " + String(error!.localizedDescription))
                        completionHandler(false)
                    }
                    else if isComplete {
                        if let photoData = photoData{
                            // Time to save downloaded photo to app ~0.015s
                            self.savePhotoDataToApp(photoData: photoData, filename: files[cameraIndex].fileName, sessionIndex: theSessionIndex)
                            completionHandler(true)
                        }
                        else{
                            self.printHelp("Fetch photo from sdCard Failed")
                            completionHandler(false)
                        }
                    }
                    else {
                        // If photo has been initialized, append the updated data to it
                        if let _ = photoData, let data = data {
                            // Data comes in shunks of 993 bytes, downloads can be done in steps
                            //print(String(data.count), String(i!))
                            //print(String(photoData!.count), String(i!))
                            photoData?.append(data)
                            i! += 1
                            // TODO - progress bar
                        }
                        else {// initialize the photo data
                            photoData = data
                            i = 1
                        }
                    }
                })
            }
            // Get the low res preview
            else{
                print("Fetching the preview")
                files[cameraIndex].fetchPreview(completion: {(error) in
                    if error != nil{
                        self.printHelp("Error downloading thumbnail")
                        completionHandler(false)
                    }
                    else{
                        // Get filename and snapshot (low res)
                        let filename = files[cameraIndex].fileName
                        let filenameLow = filename.replacingOccurrences(of: ".", with: "_low.")
                        let preview = files[cameraIndex].preview    // 960*720
                        // Save to App - Convert from UIImage to jpeg to be able to write file
                        if let data = preview!.jpegData(compressionQuality: 1){
                            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                            if let documentsURL = documentsURL {
                                let fileURL = documentsURL.appendingPathComponent(filenameLow)
                                do {
                                    try data.write(to: fileURL, options: .atomicWrite)
                                    self.jsonPreviews[String(theSessionIndex)]["stored"].boolValue = true
                                    //self.printDB("savePreviewToApp: The write fileURL points at: " + fileURL.description)
                                } catch {
                                    self.printHelp("savePreviewToApp: Could not write Preview to App: " + String(describing: error))
                                }
                            }
                            completionHandler(true)
                        }
                        else{
                            print("Could not convert preview to jpeg")
                        }
                    }
                })
            }
        })
    }

    
    func startContinousPhotoThread(enable: Bool, period: Double, publish: String){
        // Set photo period
        self.photoPeriod = period
        self.photoPublish = publish
        // If thread is already running
        if continousPhotoEnabled{
            // Thread is running, user wants to change period or publish strategy
            if enable{
                // period is updated already
                // Publish strategy updated already
                return
            }
            // Thread is running, user wants to stop
            else{
                self.continousPhotoEnabled = enable
            }
        }
        // Thread is not running
        else{
            // Update flag and try to start thread
            self.continousPhotoEnabled = enable
            // Will return directly if enable is false
            Dispatch.background{
                self.continousPhoto()
            }
        }
    }
    
    func continousPhoto(){
        var lastPhoto = CACurrentMediaTime() - photoPeriod
        while continousPhotoEnabled {
            // Wait for the period
            while CACurrentMediaTime() - lastPhoto < photoPeriod {
                // Sleep 0.05s
                usleep(50000)
                // Close thread?
                if !continousPhotoEnabled{
                    return
                }
            }
            // Try to allocate camera, wait for hardware if necessary
            while !cameraAllocator.allocate("continousPhoto", maxTime: 5){
                // Sleep 0.1s
                usleep(100000)
                // Close thread?
                if !continousPhotoEnabled{
                    return
                }
            }
            // Allocated, take photo
            takePhotoCMD()
            // takePhotoCMD deallocates the allocator
            lastPhoto = CACurrentMediaTime()

            // Prevent trensferSingle to fetch sessionLastIndex prior to it has been produced
            while cameraAllocator.allocated{
                // Sleep 0.1s
                usleep(100000)
            }
            
            // If user wants photo to be published
            if self.photoPublish != "off" && continousPhotoEnabled && connectionType != "3G"{
                if self.photoPublish == "high"{
                    // Download functions handles the allocator
                    self.transferSingle(sessionIndex: self.sessionLastIndex, res: "high", attempt: 1)
                }
                else if self.photoPublish == "low"{
                    self.transferSingle(sessionIndex: self.sessionLastIndex, res: "low", attempt: 1)
                }
                while cameraAllocator.allocated{
                    // Wait for transferSingle to let go of allocator to save some allocator prints..
                    // Sleep 0.1s
                    usleep(100000)
                }
            }
        }
    }
    
    //********************************************************************************
    // Writes metadata to json. If init point is not set, XYZ and NED are set to 999.0
    // writeMetaData is triggered from the camera, but it needs info from copter object
    // - A notification is sent to DSS VC to call this function with the req info.
    func writeMetaData(sessionLastIndex: Int, loc: MyLocation, initLoc: MyLocation, gimbalPitch: Float, gnssState: Int)->Bool{
        
        var jsonMedia = JSON()
        jsonMedia["filename"] = JSON("")
        jsonMedia["stored"].boolValue = false
        self.jsonPhotos[String(sessionLastIndex)] = jsonMedia
        self.jsonPreviews[String(sessionLastIndex)] = jsonMedia
        
        // LLA metadata
        var metaLLA = JSON()
        metaLLA["filename"] = JSON("")
        metaLLA["index"] = JSON(sessionLastIndex)
        metaLLA["lat"] = JSON(loc.coordinate.latitude)
        metaLLA["lon"] = JSON(loc.coordinate.longitude)
        metaLLA["alt"] = JSON(loc.altitude)
        metaLLA["agl"] = JSON(-1)
        metaLLA["heading"] = JSON(loc.gimbalYaw)
        metaLLA["pitch"] = JSON(gimbalPitch)
        metaLLA["gnss_state"] = JSON(gnssState)
        
        // Append metaLLA
        self.jsonMetaDataLLA[String(sessionLastIndex)] = metaLLA
        self.jsonMetaDataXYZLow[String(sessionLastIndex)] = metaLLA
        
        
        
        // Local coordinates requires init point.
        // If init point is set calc XYZ and NED, otherwise set to default
        if initLoc.isInitLocation {
            
            // XYZ metadata
            var metaXYZ = JSON()
            metaXYZ["filename"] = JSON("")
            metaXYZ["x"] = JSON(loc.pos.x)
            metaXYZ["y"] = JSON(loc.pos.y)
            metaXYZ["z"] = JSON(loc.pos.z)
            metaXYZ["agl"] = JSON(-1)
            // In sim loc.gimbalYaw does not update while on ground exept for first photo.
            metaXYZ["heading"] = JSON(loc.gimbalYaw - initLoc.gimbalYaw)
            metaXYZ["pitch"] = JSON(gimbalPitch)
            metaXYZ["index"] = JSON(sessionLastIndex)
            metaXYZ["gnssSignal"] = JSON(gnssState)
            
            // Append metaXYZ
            self.jsonMetaDataXYZ[String(sessionLastIndex)] = metaXYZ
            self.jsonMetaDataXYZLow[String(sessionLastIndex)] = metaXYZ
            
            
            
            // NED metadata
            var metaNED = JSON()
            metaNED["filename"] = JSON("")
            metaNED["north"] = JSON(loc.pos.north)
            metaNED["east"] = JSON(loc.pos.east)
            metaNED["down"] = JSON(loc.pos.down)
            metaNED["agl"] = JSON(-1)
            // In sim loc.gimbalYaw does not update while on ground exept for first photo.
            metaNED["heading"] = JSON(loc.gimbalYaw)
            metaNED["pitch"] = JSON(gimbalPitch)
            metaNED["index"] = JSON(sessionLastIndex)
            metaNED["gnssSignal"] = JSON(gnssState)
            
            // Append metaNED
            self.jsonMetaDataNED[String(sessionLastIndex)] = metaNED
            self.jsonMetaDataNEDLow[String(sessionLastIndex)] = metaNED
            
            // Dont check for subscriptiopns, NED is not subscirbeable.
        }
        // No init point, fill empty meta data to not have faulte sizes etc.
        else{
            // XYZ metadata
            var metaXYZ = JSON()
            metaXYZ["filename"] = JSON("")
            metaXYZ["x"] = JSON(999.0)
            metaXYZ["y"] = JSON(999.0)
            metaXYZ["z"] = JSON(999.0)
            metaXYZ["agl"] = JSON(-1)
            // In sim loc.gimbalYaw does not update while on ground exept for first photo.
            metaXYZ["heading"] = JSON(loc.gimbalYaw)
            metaXYZ["pitch"] = JSON(gimbalPitch)
            metaXYZ["index"] = JSON(sessionLastIndex)
            metaXYZ["gnssSignal"] = JSON(gnssState)
            
            // Append metaXYZ
            self.jsonMetaDataXYZ[String(sessionLastIndex)] = metaXYZ
            self.jsonMetaDataXYZLow[String(sessionLastIndex)] = metaXYZ
            
            
            
            // NED metadata
            var metaNED = JSON()
            metaNED["filename"] = JSON("")
            metaNED["north"] = JSON(999.0)
            metaNED["east"] = JSON(999.0)
            metaNED["down"] = JSON(999.0)
            metaNED["agl"] = JSON(-1)
            // In sim loc.gimbalYaw does not update while on ground exept for first photo.
            metaNED["heading"] = JSON(loc.gimbalYaw)
            metaNED["pitch"] = JSON(gimbalPitch)
            metaNED["index"] = JSON(sessionLastIndex)
            metaXYZ["gnssSignal"] = JSON(gnssState)
            
            // Append metaNED
            self.jsonMetaDataNED[String(sessionLastIndex)] = metaNED
            self.jsonMetaDataNEDLow[String(sessionLastIndex)] = metaNED
            
            if false{
                print(metaXYZ)
                print(metaNED)
            }
        }
        if cameraType == "Mavic 2 Enterprise Dual-Visual"{
            if sessionLastIndex % 2 == 1{
                self.sessionLastIndex += 1
                _ = writeMetaData(sessionLastIndex: self.sessionLastIndex, loc: loc, initLoc: initLoc, gimbalPitch: gimbalPitch, gnssState: gnssState)
            }
        }
        return true
    }
    
    

    
    
    // ****************
    // Helper funcitons
    
    func parseMode(mode:UInt)->String{
        switch mode {
        case 0:
            return "Shoot photo"
        case 1:
            return  "Record video"
        case 2:
            return "Playback"
        case 3:
            return "Media download"
        case 4:
            return "Broadcast"
        case 255:
            return "Unknown"
        default:
            return "Error"
        }
    }
    
    func printHelp(_ str: String){
        NotificationCenter.default.post(name: .didPrintThis, object: self, userInfo: ["printThis": str])
    }
}
