/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the object scanning UI.
*/

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, UIDocumentPickerDelegate {
    
    static let appStateChangedNotification = Notification.Name("ApplicationStateChanged")
    static let appStateUserInfoKey = "AppState"
    
    static var instance: ViewController?
    
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var blurView: UIVisualEffectView!
    @IBOutlet weak var nextButton: RoundedButton!
    var backButton: UIBarButtonItem!
    var mergeScanButton: UIBarButtonItem!
    @IBOutlet weak var instructionView: UIVisualEffectView!
    @IBOutlet weak var instructionLabel: MessageLabel!
    @IBOutlet weak var loadModelButton: RoundedButton!
    @IBOutlet weak var scanModelButton: RoundedButton!
    @IBOutlet weak var flashlightButton: FlashlightButton!
    @IBOutlet weak var navigationBar: UINavigationBar!
    @IBOutlet weak var sessionInfoView: UIVisualEffectView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var toggleInstructionsButton: RoundedButton!
    
    internal var internalState: State = .startARSession
    
    internal var scan: Scan?
    
    var referenceObjectToMerge: ARReferenceObject?
    var referenceObjectToTest: ARReferenceObject?
    var sidesNodeObjectToTest: SCNNode?
    
    internal var testRun: TestRun?
    
    internal var messageExpirationTimer: Timer?
    internal var startTimeOfLastMessage: TimeInterval?
    internal var expirationTimeOfLastMessage: TimeInterval?
    
    internal var screenCenter = CGPoint()
    
    var modelURL: URL? {
        didSet {
            if let url = modelURL {
                displayMessage("3D model \"\(url.lastPathComponent)\" received.", expirationTime: 3.0)
            }
            if let scannedObject = self.scan?.scannedObject {
                scannedObject.set3DModel(modelURL)
            }
            if let dectectedObject = self.testRun?.detectedObject {
                dectectedObject.set3DModel(modelURL)
            }
        }
    }
    
    var instructionsVisible: Bool = true {
        didSet {
            instructionView.isHidden = !instructionsVisible
            toggleInstructionsButton.toggledOn = instructionsVisible
        }
    }
    
    // MARK: - Application Lifecycle
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ViewController.instance = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        // Prevent the screen from being dimmed after a while.
        UIApplication.shared.isIdleTimerDisabled = true
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(scanningStateChanged), name: Scan.stateChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(ghostBoundingBoxWasCreated),
                                       name: ScannedObject.ghostBoundingBoxCreatedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(ghostBoundingBoxWasRemoved),
                                       name: ScannedObject.ghostBoundingBoxRemovedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(boundingBoxWasCreated),
                                       name: ScannedObject.boundingBoxCreatedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(scanPercentageChanged),
                                       name: BoundingBox.scanPercentageChangedNotification, object: nil)
//        notificationCenter.addObserver(self, selector: #selector(boundingBoxPositionOrExtentChanged(_:)),
//                                       name: BoundingBox.extentChangedNotification, object: nil)
//        notificationCenter.addObserver(self, selector: #selector(boundingBoxPositionOrExtentChanged(_:)),
//                                       name: BoundingBox.positionChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(objectOriginPositionChanged(_:)),
                                       name: ObjectOrigin.positionChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(displayWarningIfInLowPowerMode),
                                       name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        
        setupNavigationBar()
        
        displayWarningIfInLowPowerMode()
        
        // Make sure the application launches in .startARSession state.
        // Entering this state will run() the ARSession.
        state = .startARSession
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Store the screen center location after the view's bounds did change,
        // so it can be retrieved later from outside the main thread.
        screenCenter = sceneView.center
    }
    
    // MARK: - UI Event Handling
    
    @IBAction func restartButtonTapped(_ sender: Any) {
        if let scan = scan, scan.boundingBoxExists {
            let title = "Start over?"
            let message = "Discard the current scan and start over?"
            self.showAlert(title: title, message: message, buttonTitle: "Yes", showCancel: true) { _ in
                self.state = .startARSession
            }
        } else if testRun != nil {
            let title = "Start over?"
            let message = "Discard this scan and start over?"
            self.showAlert(title: title, message: message, buttonTitle: "Yes", showCancel: true) { _ in
                self.state = .startARSession
            }
        } else {
            self.state = .startARSession
        }
    }
    
    func backFromBackground() {
        if state == .scanning {
            let title = "Warning: Scan may be broken"
            let message = "The scan was interrupted. It is recommended to restart the scan."
            let buttonTitle = "Restart Scan"
            self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: true) { _ in
                self.state = .notReady
            }
        }
    }
    
    @IBAction func previousButtonTapped(_ sender: Any) {
        switchToPreviousState()
    }
    
    @IBAction func nextButtonTapped(_ sender: Any) {
        guard !nextButton.isHidden && nextButton.isEnabled else { return }
        switchToNextState()
    }
    
    @IBAction func scanButtonTapped(_ sender: Any) {
        guard !scanModelButton.isHidden else { return }
        switchToNextState()
    }
    
    @IBAction func addScanButtonTapped(_ sender: Any) {
        guard state == .testing else { return }

        let title = "Merge another scan?"
        let message = """
            Merging multiple scan results improves detection.
            You can start a new scan now to merge into this one, or load an already scanned *.arobject file.
            """
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Merge New Scan…", style: .default) { _ in
            // Save the previously scanned object as the object to be merged into the next scan.
            self.referenceObjectToMerge = self.testRun?.referenceObject
            self.state = .startARSession
        })
        alertController.addAction(UIAlertAction(title: "Merge ARObject File…", style: .default) { _ in
            // Show a document picker to choose an existing scan
            self.showFilePickerForLoadingScan()
        })
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func showFilePickerForLoadingScan() {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["com.apple.arobject"], in: .import)
        documentPicker.delegate = self
        
        documentPicker.modalPresentationStyle = .overCurrentContext
        documentPicker.popoverPresentationController?.barButtonItem = mergeScanButton
        
        DispatchQueue.main.async {
            self.present(documentPicker, animated: true, completion: nil)
        }
    }

    
    @IBAction func loadModelButtonTapped(_ sender: Any) {
        guard !loadModelButton.isHidden && loadModelButton.isEnabled else { return }
        
        if(state == .testing) {
            createAndShareReferenceObject()
        } else {
            loadProcedure()
            
            
//            let documentPicker = UIDocumentPickerViewController(documentTypes: ["com.apple.arobject"], in: .import)
//            documentPicker.delegate = self
//            
//            documentPicker.modalPresentationStyle = .overCurrentContext
//            documentPicker.popoverPresentationController?.sourceView = self.loadModelButton
//            documentPicker.popoverPresentationController?.sourceRect = self.loadModelButton.bounds
//            
//            DispatchQueue.main.async {
//                self.present(documentPicker, animated: true, completion: nil)
//            }
        }
    }
    
    @IBAction func leftButtonTouchAreaTapped(_ sender: Any) {
        // A tap in the extended hit area on the lower left should cause a tap
        //  on the button that is currently visible at that location.
        if !loadModelButton.isHidden {
            loadModelButtonTapped(self)
        } else if !flashlightButton.isHidden {
            toggleFlashlightButtonTapped(self)
        }
    }
    
    @IBAction func toggleFlashlightButtonTapped(_ sender: Any) {
        guard !flashlightButton.isHidden && flashlightButton.isEnabled else { return }
        flashlightButton.toggledOn = !flashlightButton.toggledOn
    }
    
    @IBAction func toggleInstructionsButtonTapped(_ sender: Any) {
        guard !toggleInstructionsButton.isHidden && toggleInstructionsButton.isEnabled else { return }
        instructionsVisible.toggle()
    }
    
    func displayInstruction(_ message: Message) {
        instructionLabel.display(message)
        instructionsVisible = true
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        print("====> \(url.absoluteString)")
        readFile(url)
    }
    
    func showAlert(title: String, message: String, buttonTitle: String? = "OK", showCancel: Bool = false, buttonHandler: ((UIAlertAction) -> Void)? = nil) {
        print(title + "\n" + message)
        
        var actions = [UIAlertAction]()
        if let buttonTitle = buttonTitle {
            actions.append(UIAlertAction(title: buttonTitle, style: .default, handler: buttonHandler))
        }
        if showCancel {
            actions.append(UIAlertAction(title: "Cancel", style: .cancel))
        }
        self.showAlert(title: title, message: message, actions: actions)
    }
    
    func showAlert(title: String, message: String, actions: [UIAlertAction]) {
        let showAlertBlock = {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            actions.forEach { alertController.addAction($0) }
            DispatchQueue.main.async {
                self.present(alertController, animated: true, completion: nil)
            }
        }
        
        if presentedViewController != nil {
            dismiss(animated: true) {
                showAlertBlock()
            }
        } else {
            showAlertBlock()
        }
    }
    
    func testObjectDetection() {
        // In case an object for testing has been received, use it right away...
        if let object = referenceObjectToTest {
            testObjectDetection(of: object)
            referenceObjectToTest = nil
            return
        }
        
        // ...otherwise attempt to create a reference object from the current scan.
        guard let scan = scan, scan.boundingBoxExists else {
            print("Error: Bounding box not yet created.")
            return
        }
        
        scan.createReferenceObject { scannedObject in
            if let object = scannedObject {
                self.testObjectDetection(of: object)
            } else {
                let title = "Scan failed"
                let message = "Saving the scan failed."
                let buttonTitle = "Restart Scan"
                self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: false) { _ in
                    self.state = .startARSession
                }
            }
        }
    }
    
    func testObjectDetection(of object: ARReferenceObject) {
        self.testRun?.setReferenceObject(object, screenshot: scan?.screenshot, sidesNodeObject: self.sidesNodeObjectToTest)
        
        // Delete the scan to make sure that users cannot go back from
        // testing to scanning, because:
        // 1. Testing and scanning require running the ARSession with different configurations,
        //    thus the scanned environment is lost when starting a test.
        // 2. We encourage users to move the scanned object during testing, which invalidates
        //    the feature point cloud which was captured during scanning.
        self.scan = nil
//        self.displayInstruction(Message("""
//                    Test detection of the object from different angles. Consider moving the object to different environments and test there.
//                    """))
    }
    
    func uploadFile(url: URL, fileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var data = Data()
        
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        data.append(try! Data(contentsOf: fileURL))
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let task = URLSession.shared.uploadTask(with: request, from: data) { (data, response, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                completion(.success(responseString))
            }
        }
        task.resume()
    }
    
    func getProcedureTitle(completionHandler: @escaping (String?) -> Void) {
        let alertController = UIAlertController(title: "Input Procedure Title", message: nil, preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = "Procedure Title"
        }
        
        let submitAction = UIAlertAction(title: "Submit", style: .default) { _ in
            let userInput = alertController.textFields?.first?.text
            completionHandler(userInput)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        alertController.addAction(submitAction)
        alertController.addAction(cancelAction)
        
        self.present(alertController, animated: true, completion: nil)
    }
    
//    func saveArModelAndUpload(completionHandler: @escaping (String) -> Void) {
    func saveArModelAndUpload() {
        print("Saving testing file")

        // Save referenceObject w/out annotations - WORKING
        do {
            guard let testRun = self.testRun, let object = testRun.referenceObject
                else { print("can't get refObject"); return }
            let data = try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
            let url = URL(string: "https://us-central1-cook-250617.cloudfunctions.net/ar-model/referenceObject1")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let task = URLSession.shared.uploadTask(with: request, from: data) { data, response, error in
                if let error = error {
                    print("Error uploading data:", error)
                } else if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("Received response:", responseString)
                }
            }
            task.resume()
        } catch {
            fatalError("Can't save referenceObject: \(error.localizedDescription)")
        }

        // Save sidesNode (annotations)
        do {
            guard let testRun = self.testRun, let object = testRun.detectedObject?.pointCloudVisualization.sidesNode
                else { print("can't get sidesNode"); return }
            let data = try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
            let url = URL(string: "https://us-central1-cook-250617.cloudfunctions.net/ar-model/sidesNode1")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let task = URLSession.shared.uploadTask(with: request, from: data) { data, response, error in
                if let error = error {
                    print("Error uploading data:", error)
                } else if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("Received response:", responseString)
                }
            }
            task.resume()
        } catch {
            fatalError("Can't save sidesNode: \(error.localizedDescription)")
        }
        
        // Save World map - WORKING
//        sceneView.session.getCurrentWorldMap { worldMap, error in
//            guard let map = worldMap
//                else { self.showAlert(title: "Can't get current world map", message: error!.localizedDescription); return }
//
//            do {
//                let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
//                let url = URL(string: "https://us-central1-cook-250617.cloudfunctions.net/ar-model/testing4")!
//                var request = URLRequest(url: url)
//                request.httpMethod = "POST"
//                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
//                let task = URLSession.shared.uploadTask(with: request, from: data) { data, response, error in
//                    if let error = error {
//                        print("Error uploading data:", error)
//                    } else if let data = data, let responseString = String(data: data, encoding: .utf8) {
//                        print("Received response:", responseString)
//                    }
//                }
//                task.resume()
//            } catch {
//                fatalError("Can't save map: \(error.localizedDescription)")
//            }
//        }
    }
    
    func saveProcedure(procedureTitle: String, arModelFilename: String, completionHandler: @escaping () -> Void) {
        let url = URL(string: "https://us-central1-cook-250617.cloudfunctions.net/procedures")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let json: [String: Any] = [
            "name": procedureTitle,
            "ar_model": arModelFilename,
            "steps": []
        ]

        let jsonData = try? JSONSerialization.data(withJSONObject: json)
        request.httpBody = jsonData

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print(error?.localizedDescription ?? "No data")
                return
            }
            
            let responseJSON = try? JSONSerialization.jsonObject(with: data, options: [])
            if let responseJSON = responseJSON as? [String: Any] {
                print(responseJSON)
            }
        }

        task.resume()
    }
    
    func createAndShareReferenceObject() {
        saveArModelAndUpload()
//        getProcedureTitle() { userInput in
//            if let procedureTitle = userInput, !procedureTitle.isEmpty {
//                print("Procedure Title: \(procedureTitle)")
//                self.saveArModelAndUpload() { arModelFilename in
//                    print("ARModel Filename: \(arModelFilename)")
//                    self.saveProcedure(procedureTitle: procedureTitle, arModelFilename: arModelFilename) {
//                        print("Save Complete.")
//                    }
//                }
//            }
//        }
    }
    
    func fetchProcedure(procedureTitle: String, completionHandler: @escaping (String, String) -> Void) {
        let url = URL(string: "https://us-central1-cook-250617.cloudfunctions.net/procedures/\(procedureTitle)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        print("Sending fetch request")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            print("Fetch response received")
            guard let data = data, error == nil else {
                print(error?.localizedDescription ?? "No data")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let procedureName = json["name"] as! String
                    let arModelFilename = json["ar_model"] as! String
                    completionHandler(procedureName, arModelFilename)
                } else {
                    print("Unable to parse JSON")
                }
            } catch {
                print("Error parsing JSON: \(error)")
            }
        }

        task.resume()
    }
    
    func loadProcedure() {
        print("loading testing file")
        
        // Load referenceObject w/out annotations - WORKING
        let url = URL(string: "https://us-central1-cook-250617.cloudfunctions.net/ar-model/referenceObject1")!
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            guard error == nil else {
                print("Error downloading test file: \(error!)")
                return
            }

            guard let data = data else {
                print("No data returned from the server!")
                return
            }

            do {
                guard let referenceObject = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARReferenceObject.self, from: data) else {
                    fatalError("No ARReferenceObject in archive.")
                }
                
                // Use the worldMap object here
                print("Successfully unarchived ARReferenceObject!")
                
                
                
                // Load sidesNode - WORKING
                let url = URL(string: "https://us-central1-cook-250617.cloudfunctions.net/ar-model/sidesNode1")!
                let taskSidesNode = URLSession.shared.dataTask(with: url) { (data, response, error) in
                    guard error == nil else {
                        print("Error downloading sidesNode file: \(error!)")
                        return
                    }

                    guard let data = data else {
                        print("No sidesNode data returned from the server!")
                        return
                    }

                    do {
                        guard let sidesNodeObject = try NSKeyedUnarchiver.unarchivedObject(ofClass: SCNNode.self, from: data) else {
                            fatalError("No SCNNode sidesNode in archive.")
                        }
                        
                        print("Successfully unarchived sidesNodeObject!")
                        
                        DispatchQueue.main.async {
                            self.referenceObjectToTest = referenceObject
                            self.sidesNodeObjectToTest = sidesNodeObject
                            self.state = .testing
                            print("3. Done.")
                        }

                    } catch {
                        print("Error unarchiving ARReferenceObject: \(error)")
                    }
                }
                taskSidesNode.resume()

            } catch {
                print("Error unarchiving ARReferenceObject: \(error)")
            }
        }

        task.resume()
        
        // Load world file
//        let url = URL(string: "https://us-central1-cook-250617.cloudfunctions.net/ar-model/testing4")!
//        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
//            guard error == nil else {
//                print("Error downloading ARWorldMap: \(error!)")
//                return
//            }
//
//            guard let data = data else {
//                print("No data returned from the server!")
//                return
//            }
//
//            do {
//                guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
//                    fatalError("No ARWorldMap in archive.")
//                }
//                
//                // Use the worldMap object here
//                print("Successfully unarchived ARWorldMap!")
//
//            } catch {
//                print("Error unarchiving ARWorldMap: \(error)")
//            }
//        }
//
//        task.resume()

        
//        getProcedureTitle() { userInput in
//            if let procedureTitle = userInput, !procedureTitle.isEmpty {
//                let procedureTitle = "plant1"
//                print("Procedure Title: \(procedureTitle)")
//                self.fetchProcedure(procedureTitle: procedureTitle) { procedureName, arModelFilename in
//                    let urlStr = "https://storage.cloud.google.com/swift-ar-uploads/\(arModelFilename)"
//                    print("1. Done Fetching: procedureName:\(procedureName) arModelFilename:\(arModelFilename) url:\(urlStr)")
////                    self.readFile(URL(string: url)!)
//                    
//                    let urlObj = URL(string: urlStr)
//                    
//                    do {
//                        let receivedReferenceObject = try ARReferenceObject(archiveURL: urlObj!)
//                    } catch {
//                        print("error")
//                    }
                    
//                    do {
//                        let receivedReferenceObject = try ARReferenceObject(archiveURL: urlObj!)
//                        print("Done")
//                    } catch {
//                        print("Error handling file:", error)
//                    }
                    
//                    let session = URLSession.shared
//                    let downloadTask = session.downloadTask(with: urlObj!) { (temporaryURL, response, error) in
//                        guard let temporaryURL = temporaryURL else {
//                            print("Error downloading file:", error ?? "Unknown error")
//                            return
//                        }
//                        
//                        // Define the destination URL in the app's Documents directory
//                        let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//                        let destinationURL = documentsDirectoryURL.appendingPathComponent(arModelFilename)
//                        
//
                        
//                        // Define the destination URL to save the file with the original name
//                        let destinationURL = temporaryURL.deletingLastPathComponent().appendingPathComponent(arModelFilename)
//                        
//                        do {
//                            // Check if the file already exists, if it does, delete it
//                            if FileManager.default.fileExists(atPath: destinationURL.path) {
//                                try FileManager.default.removeItem(at: destinationURL)
//                            }
//                            
//                            // Move (or rename) the file from the temporary URL to the desired destination URL
//                            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
//                            print("2. File renamed and moved to:", destinationURL)
//                            
//                            if FileManager.default.fileExists(atPath: destinationURL.path) {
//                                print("3. It IS THERE")
//                                let receivedReferenceObject = try ARReferenceObject(archiveURL: destinationURL)
//                                self.referenceObjectToTest = receivedReferenceObject
//                                self.state = .testing
//                                print("3. Done.")
//                            } else {
//                                print("3. It's NOT there.")
//                            }
//                        } catch {
//                            print("Error renaming and moving file:", error)
//                        }
//                    }
//                    let downloadTask = URLSession.shared.downloadTask(with: urlObj!) { localURL, response, error in
////                        print("2. localURL:\(localURL) response:\(response) error:\(error)")
//                        if let error = error {
//                            print("2. File download failed: \(error)")
//                        } else if let localURL = localURL {
//                            // Save or move localURL to your desired location
//                            print("2. File downloaded to: \(localURL)")
//                            do {
//                                let receivedReferenceObject = try ARReferenceObject(archiveURL: localURL)
//                                self.referenceObjectToTest = receivedReferenceObject
//                                self.state = .testing
//                            } catch {
//                                print("Error creating ARReferenceObject: \(error)")
//                            }
//                        }
//                    }
//                    downloadTask.resume()
//                }
//            }
//        }
    }
    
    var limitedTrackingTimer: Timer?
    
    func startLimitedTrackingTimer() {
        guard limitedTrackingTimer == nil else { return }
        
        limitedTrackingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            self.cancelLimitedTrackingTimer()
            guard let scan = self.scan else { return }
            if scan.state == .defineBoundingBox || scan.state == .scanning || scan.state == .adjustingOrigin {
                let title = "Limited Tracking"
                let message = "Low tracking quality - it is unlikely that a good reference object can be generated from this scan."
                let buttonTitle = "Restart Scan"
                
                self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: true) { _ in
                    self.state = .startARSession
                }
            }
        }
    }
    
    func cancelLimitedTrackingTimer() {
        limitedTrackingTimer?.invalidate()
        limitedTrackingTimer = nil
    }
    
    var maxScanTimeTimer: Timer?
    
    func startMaxScanTimeTimer() {
        guard maxScanTimeTimer == nil else { return }
        
        let timeout: TimeInterval = 60.0 * 5
        
        maxScanTimeTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            self.cancelMaxScanTimeTimer()
            guard self.state == .scanning else { return }
            let title = "Scan is taking too long"
            let message = "Scanning consumes a lot of resources. This scan has been running for \(Int(timeout)) s. Consider closing the app and letting the device rest for a few minutes."
            let buttonTitle = "OK"
            self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: true)
        }
    }
    
    func cancelMaxScanTimeTimer() {
        maxScanTimeTimer?.invalidate()
        maxScanTimeTimer = nil
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        
        updateSessionInfoLabel(for: camera.trackingState)
        
        switch camera.trackingState {
        case .notAvailable:
            state = .notReady
        case .limited(let reason):
            switch state {
            case .startARSession:
                state = .notReady
            case .notReady, .testing:
                break
            case .scanning:
                if let scan = scan {
                    switch scan.state {
                    case .ready:
                        state = .notReady
                    case .defineBoundingBox, .scanning, .adjustingOrigin:
                        if reason == .relocalizing {
                            // If ARKit is relocalizing we should abort the current scan
                            // as this can cause unpredictable distortions of the map.
                            print("Warning: ARKit is relocalizing")
                            
                            let title = "Warning: Scan may be broken"
                            let message = "A gap in tracking has occurred. It is recommended to restart the scan."
                            let buttonTitle = "Restart Scan"
                            self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: true) { _ in
                                self.state = .notReady
                            }
                            
                        } else {
                            // Suggest the user to restart tracking after a while.
                            startLimitedTrackingTimer()
                        }
                    }
                }
            }
        case .normal:
            if limitedTrackingTimer != nil {
                cancelLimitedTrackingTimer()
            }
            
            switch state {
            case .startARSession, .notReady:
                state = .scanning
            case .scanning, .testing:
                break
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let frame = sceneView.session.currentFrame else { return }
        scan?.updateOnEveryFrame(frame)
        testRun?.updateOnEveryFrame()
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let objectAnchor = anchor as? ARObjectAnchor {
            if let testRun = self.testRun, objectAnchor.referenceObject == testRun.referenceObject {
                testRun.successfulDetection(objectAnchor)
//                let messageText = """
//                    Object successfully detected from this angle.
//
//                    """ + testRun.statistics
//                displayMessage(messageText, expirationTime: testRun.resultDisplayDuration)
            }
        } else if state == .scanning, let planeAnchor = anchor as? ARPlaneAnchor {
            scan?.scannedObject.tryToAlignWithPlanes([planeAnchor])
            
            // After a plane was found, disable plane detection for performance reasons.
            sceneView.stopPlaneDetection()
        }
    }
    
    func readFile(_ url: URL) {
        if url.pathExtension == "arobject" {
            loadReferenceObjectToMerge(from: url)
        } else if url.pathExtension == "usdz" {
            modelURL = url
        }
    }
    
    fileprivate func mergeIntoCurrentScan(referenceObject: ARReferenceObject, from url: URL) {
        if self.state == .testing {
            
            // Show activity indicator during the merge.
            ViewController.instance?.showAlert(title: "", message: "Merging other scan into this scan...", buttonTitle: nil)
            
            // Try to merge the object which was just scanned with the existing one.
            self.testRun?.referenceObject?.mergeInBackground(with: referenceObject, completion: { (mergedObject, error) in
                let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
                
                if let mergedObject = mergedObject {
                    self.testRun?.setReferenceObject(mergedObject, screenshot: nil, sidesNodeObject: nil)
                    self.showAlert(title: "Merge successful", message: "The other scan has been merged into this scan.",
                                   buttonTitle: "OK", showCancel: false)
                    
                } else {
                    print("Error: Failed to merge scans. \(error?.localizedDescription ?? "")")
                    alertController.title = "Merge failed"
                    let message = """
                            Merging the other scan into the current scan failed. Please make sure
                            that there is sufficient overlap between both scans and that the
                            lighting environment hasn't changed drastically.
                            Which scan do you want to use to proceed testing?
                            """
                    let currentScan = UIAlertAction(title: "Use Current Scan", style: .default)
                    let otherScan = UIAlertAction(title: "Use Other Scan", style: .default) { _ in
                        self.testRun?.setReferenceObject(referenceObject, screenshot: nil, sidesNodeObject: nil)
                    }
                    self.showAlert(title: "Merge failed", message: message, actions: [currentScan, otherScan])
                }
            })
            
        } else {
            // Upon completion of a scan, we will try merging
            // the scan with this ARReferenceObject.
            self.referenceObjectToMerge = referenceObject
            self.displayMessage("Scan \"\(url.lastPathComponent)\" received. " +
                "It will be merged with this scan before proceeding to Test mode.", expirationTime: 3.0)
        }
    }
    
    func loadReferenceObjectToMerge(from url: URL) {
        do {
            let receivedReferenceObject = try ARReferenceObject(archiveURL: url)
            self.referenceObjectToTest = receivedReferenceObject
            self.state = .testing
            
            
//            // Ask the user if the received object should be merged into the current scan,
//            // or if the received scan should be tested (and the current one discarded).
//            let title = "\"\(url.lastPathComponent)\" loaded"
//            let message = """
//                Do you want to merge and improve the current object?
//                """
//            let merge = UIAlertAction(title: "Improve current object", style: .default) { _ in
//                self.mergeIntoCurrentScan(referenceObject: receivedReferenceObject, from: url)
//            }
//            let test = UIAlertAction(title: "Load this from scratch", style: .default) { _ in
//                self.referenceObjectToTest = receivedReferenceObject
//                self.state = .testing
//            }
//            self.showAlert(title: title, message: message, actions: [merge, test])
            
        } catch {
            self.showAlert(title: "File invalid", message: "Loading the scanned object file failed.",
                           buttonTitle: "OK", showCancel: false)
        }
    }
    
    @objc
    func scanPercentageChanged(_ notification: Notification) {
        guard let percentage = notification.userInfo?[BoundingBox.scanPercentageUserInfoKey] as? Int else { return }
        
        // Switch to the next state if the scan is complete.
        if percentage >= 100 {
            switchToNextState()
            return
        }
        DispatchQueue.main.async {
            self.setNavigationBarTitle("Scan (\(percentage)%)")
        }
    }
    
    @objc
    func boundingBoxPositionOrExtentChanged(_ notification: Notification) {
        guard let box = notification.object as? BoundingBox,
            let cameraPos = sceneView.pointOfView?.simdWorldPosition else { return }
        
        let xString = String(format: "width: %.2f", box.extent.x)
        let yString = String(format: "height: %.2f", box.extent.y)
        let zString = String(format: "length: %.2f", box.extent.z)
        let distanceFromCamera = String(format: "%.2f m", distance(box.simdWorldPosition, cameraPos))
        displayMessage("Current bounding box: \(distanceFromCamera) away\n\(xString) \(yString) \(zString)", expirationTime: 1.5)
    }
    
    @objc
    func objectOriginPositionChanged(_ notification: Notification) {
        guard let node = notification.object as? ObjectOrigin else { return }
        
        // Display origin position w.r.t. bounding box
        let xString = String(format: "x: %.2f", node.position.x)
        let yString = String(format: "y: %.2f", node.position.y)
        let zString = String(format: "z: %.2f", node.position.z)
        displayMessage("Current local origin position in meters:\n\(xString) \(yString) \(zString)", expirationTime: 1.5)
    }
    
    @objc
    func displayWarningIfInLowPowerMode() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            let title = "Low Power Mode is enabled"
            let message = "Performance may be impacted. For best scanning results, disable Low Power Mode in Settings > Battery, and restart the scan."
            let buttonTitle = "OK"
            self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: false)
        }
    }
    
    override var shouldAutorotate: Bool {
        // Lock UI rotation after starting a scan
        if let scan = scan, scan.state != .ready {
            return false
        }
        return true
    }
}
