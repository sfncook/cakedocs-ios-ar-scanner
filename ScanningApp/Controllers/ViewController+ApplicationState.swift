/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Management of the UI steps for scanning an object in the main view controller.
*/

import Foundation
import ARKit
import SceneKit

extension ViewController {
    
    enum State {
        case startARSession
        case notReady
        case scanning
        case testing
    }
    
    /// - Tag: ARObjectScanningConfiguration
    // The current state the application is in
    var state: State {
        get {
            return self.internalState
        }
        set {
            // 1. Check that preconditions for the state change are met.
            var newState = newValue
            switch newValue {
            case .startARSession:
                break
            case .notReady:
                // Immediately switch to .ready if tracking state is normal.
                if let camera = self.sceneView.session.currentFrame?.camera {
                    switch camera.trackingState {
                    case .normal:
                        newState = .scanning
                    default:
                        break
                    }
                } else {
                    newState = .startARSession
                }
            case .scanning:
                // Immediately switch to .notReady if tracking state is not normal.
                if let camera = self.sceneView.session.currentFrame?.camera {
                    switch camera.trackingState {
                    case .normal:
                        break
                    default:
                        newState = .notReady
                    }
                } else {
                    newState = .startARSession
                }
            case .testing:
                guard scan?.boundingBoxExists == true || referenceObjectToTest != nil else {
                    print("Error: Scan is not ready to be tested.")
                    return
                }
            }
            
            // 2. Apply changes as needed per state.
            internalState = newState
            
            switch newState {
            case .startARSession:
                print("State: Starting ARSession")
                scan = nil
                testRun = nil
                modelURL = nil
                self.setNavigationBarTitle("")
                instructionsVisible = false
                showBackButton(false)
                nextButton.isEnabled = true
                scanModelButton.isHidden = false
                loadModelButton.isHidden = false
                loadModelButton.setTitle("Load", for: [])
//                flashlightButton.isHidden = true
                
                // Make sure the SCNScene is cleared of any SCNNodes from previous scans.
                sceneView.scene = SCNScene()
                
                let configuration = ARObjectScanningConfiguration()
                configuration.planeDetection = .horizontal
                sceneView.session.run(configuration, options: .resetTracking)
                cancelMaxScanTimeTimer()
                cancelMessageExpirationTimer()
            case .notReady:
                print("State: Not ready to scan")
                scan = nil
                testRun = nil
                self.setNavigationBarTitle("")
                scanModelButton.isHidden = true
                loadModelButton.isHidden = true
//                flashlightButton.isHidden = true
                showBackButton(false)
                nextButton.isEnabled = false
                nextButton.setTitle("Next", for: [])
//                displayInstruction(Message("Please wait for stable tracking"))
                cancelMaxScanTimeTimer()
            case .scanning:
                print("State: Scanning")
                if scan == nil {
                    self.scan = Scan(sceneView)
                    self.scan?.state = .ready
                }
                testRun = nil
                instructionsVisible = false
                
                startMaxScanTimeTimer()
            case .testing:
                print("State: Testing")
                self.setNavigationBarTitle("")
                scanModelButton.isHidden = true
                loadModelButton.isHidden = false
                loadModelButton.setTitle("Save", for: [])
//                flashlightButton.isHidden = false
//                showMergeScanButton()
//                nextButton.isEnabled = true
//                nextButton.setTitle("Share", for: [])
                instructionsVisible = false
                
                testRun = TestRun(sceneView: sceneView)
                testObjectDetection()
                cancelMaxScanTimeTimer()
            }
            
            NotificationCenter.default.post(name: ViewController.appStateChangedNotification,
                                            object: self,
                                            userInfo: [ViewController.appStateUserInfoKey: self.state])
        }
    }
    
    @objc
    func scanningStateChanged(_ notification: Notification) {
        guard self.state == .scanning, let scan = notification.object as? Scan, scan === self.scan else { return }
        guard let scanState = notification.userInfo?[Scan.stateUserInfoKey] as? Scan.State else { return }
        
        DispatchQueue.main.async {
            switch scanState {
            case .ready:
                print("State: Ready to scan")
//                self.setNavigationBarTitle("Find")
                self.showBackButton(false)
                self.nextButton.setTitle("Next", for: [])
                self.scanModelButton.isHidden = true
                self.scanModelButton.setTitle("Start", for: [])
                self.loadModelButton.isHidden = false
                self.loadModelButton.setTitle("Load", for: [])
                self.displayInstruction(Message("Initializing, please wait"))
//                self.flashlightButton.isHidden = true
            case .defineBoundingBox:
                print("State: Define bounding box")
                self.displayInstruction(Message("Adjust the yellow bounding box"))
                self.setNavigationBarTitle("")
                self.showBackButton(true)
                self.nextButton.isEnabled = scan.boundingBoxExists
                self.scanModelButton.isHidden = false
                self.scanModelButton.setTitle("Scan", for: [])
                self.loadModelButton.isHidden = true
//                self.flashlightButton.isHidden = true
                self.nextButton.setTitle("Scan", for: [])
            case .scanning:
//                self.displayInstruction(Message("Scan the object"))
                if let boundingBox = scan.scannedObject.boundingBox {
                    self.setNavigationBarTitle("Scan (\(boundingBox.progressPercentage)%)")
                } else {
                    self.setNavigationBarTitle("Scan 0%")
                }
                self.showBackButton(true)
                self.nextButton.isEnabled = true
                self.scanModelButton.isHidden = false
                self.scanModelButton.setTitle("Done", for: [])
                self.loadModelButton.isHidden = true
                self.instructionsVisible = false
                // Disable plane detection (even if no plane has been found yet at this time) for performance reasons.
                self.sceneView.stopPlaneDetection()
            case .adjustingOrigin:
                print("State: Adjusting Origin")
                self.displayInstruction(Message("Adjust origin using gestures.\n" +
                    "You can load a *.usdz 3D model overlay."))
                self.setNavigationBarTitle("Adjust origin")
                self.showBackButton(true)
                self.nextButton.isEnabled = true
                self.scanModelButton.isHidden = false
                self.loadModelButton.isHidden = false
//                self.flashlightButton.isHidden = true
                self.nextButton.setTitle("Test", for: [])
            }
        }
    }
    
    func switchToPreviousState() {
        switch state {
        case .startARSession:
            break
        case .notReady:
            state = .startARSession
        case .scanning:
            if let scan = scan {
                switch scan.state {
                case .ready:
                    restartButtonTapped(self)
                case .defineBoundingBox:
                    scan.state = .ready
                case .scanning:
                    scan.state = .defineBoundingBox
                case .adjustingOrigin:
                    scan.state = .scanning
                }
            }
        case .testing:
            state = .scanning
            scan?.state = .scanning
        }
    }
    
    func switchToNextState() {
        switch state {
        case .startARSession:
            state = .notReady
        case .notReady:
            state = .scanning
        case .scanning:
            if let scan = scan {
                switch scan.state {
                case .ready:
                    scan.state = .defineBoundingBox
                case .defineBoundingBox:
                    scan.state = .scanning
                case .scanning:
                    state = .testing
                case .adjustingOrigin:
                    state = .testing
                }
            }
        case .testing:
            // Testing is the last state, show the share sheet at the end.
            createAndShareReferenceObject()
        }
    }
    
    @objc
    func ghostBoundingBoxWasCreated(_ notification: Notification) {
        if let scan = scan, scan.state == .ready {
            DispatchQueue.main.async {
                self.displayInstruction(Message("Look at target object, click 'Start'"))
                self.scanModelButton.isHidden = false
//                self.nextButton.isEnabled = true
//                self.displayInstruction(Message("Tap 'Next' to create an approximate bounding box around the object you want to scan."))
            }
        }
    }
    
    @objc
    func ghostBoundingBoxWasRemoved(_ notification: Notification) {
        if let scan = scan, scan.state == .ready {
            DispatchQueue.main.async {
                self.displayInstruction(Message("Readjusting, one moment please"))
                self.scanModelButton.isHidden = true
//                self.nextButton.isEnabled = false
//                self.displayInstruction(Message("Point at a nearby object to scan."))
            }
        }
    }
    
    @objc
    func boundingBoxWasCreated(_ notification: Notification) {
        if let scan = scan, scan.state == .defineBoundingBox {
            DispatchQueue.main.async {
                self.nextButton.isEnabled = true
            }
        }
    }
}
