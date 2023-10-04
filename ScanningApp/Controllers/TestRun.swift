/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Manages the process of testing detection after scanning an object.
*/

import Foundation
import ARKit

// This class represents a test run of a scanned object.
class TestRun {
    
    // The ARReferenceObject to be tested in this run.
    var referenceObject: ARReferenceObject?
    
    private(set) var detectedObject: DetectedObject?
    
    var detections = 0
    var lastDetectionDelayInSeconds: Double = 0
    var averageDetectionDelayInSeconds: Double = 0
    
    var resultDisplayDuration: Double {
        // The recommended display duration for detection results
        // is the average time it takes to detect it, plus 200 ms buffer.
        return averageDetectionDelayInSeconds + 0.2
    }
    
    private var lastDetectionStartTime: Date?
    
    private var sceneView: ARSCNView
    
    private(set) var previewImage = UIImage()
    
    init(sceneView: ARSCNView) {
        self.sceneView = sceneView
    }
    
    deinit {
        self.detectedObject?.removeFromParentNode()
        
        if self.sceneView.session.configuration as? ARWorldTrackingConfiguration != nil {
            // Make sure we switch back to an object scanning configuration & no longer
            // try to detect the object.
            let configuration = ARObjectScanningConfiguration()
            configuration.planeDetection = .horizontal
            self.sceneView.session.run(configuration, options: .resetTracking)
        }
    }
    
    var statistics: String {
        let lastDelayMilliseconds = String(format: "%.0f", lastDetectionDelayInSeconds * 1000)
        let averageDelayMilliseconds = String(format: "%.0f", averageDetectionDelayInSeconds * 1000)
        return "Detected after: \(lastDelayMilliseconds) ms. Avg: \(averageDelayMilliseconds) ms"
    }
    
    func setReferenceObject(_ object: ARReferenceObject, screenshot: UIImage?) {
        referenceObject = object
        if let screenshot = screenshot {
            previewImage = screenshot
        }
        detections = 0
        lastDetectionDelayInSeconds = 0
        averageDetectionDelayInSeconds = 0
        
        self.detectedObject = DetectedObject(referenceObject: object)
        self.sceneView.scene.rootNode.addChildNode(self.detectedObject!)
        
        self.lastDetectionStartTime = Date()
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.detectionObjects = [object]
        self.sceneView.session.run(configuration)
        
        startNoDetectionTimer()
    }
    
    func didTapWhileTesting(_ gesture: UITapGestureRecognizer) {
        print("didTapWhileTesting")
        let hitLocationInView = gesture.location(in: sceneView)
        let hitTestResults = sceneView.hitTest(hitLocationInView, types: [.featurePoint])
        if let result = hitTestResults.first {
            print("Hooray! Points FOUND")
            
            // Add a new anchor at the tap location.
            let anchor = ARAnchor(transform: result.worldTransform)
            sceneView.session.add(anchor: anchor)
            
            // 1. Create an SCNText object
            let textGeometry = SCNText(string: "Hello", extrusionDepth: 0.1)

            // Set properties of the text (like font, color, etc.)
            textGeometry.font = UIFont(name: "Arial", size: 0.5)
            textGeometry.firstMaterial?.diffuse.contents = UIColor.red

            // 2. Create an SCNNode with the text geometry
            let textNode = SCNNode(geometry: textGeometry)

            // Adjust the position or scale if necessary
            print("\(anchor.transform.position.x),\(anchor.transform.position.y),\(anchor.transform.position.z)")
//            textNode.position = SCNVector3(x: 0, y: 0, z: 0)
            textNode.position = SCNVector3(x: anchor.transform.position.x, y: anchor.transform.position.y, z: anchor.transform.position.z)
//            textNode.transform = SCNMatrix4(anchor.transform)
            textNode.scale = SCNVector3(x: 0.1, y: 0.1, z: 0.1)

            self.sceneView.scene.rootNode.addChildNode(textNode)
            
            // Track anchor ID to associate text with the anchor after ARKit creates a corresponding SKNode.
//            anchorLabels[anchor.identifier] = identifierString
        } else {
            print("Point not found")
        }
    }
    
    func successfulDetection(_ objectAnchor: ARObjectAnchor) {
        
        // Compute the time it took to detect this object & the average.
        lastDetectionDelayInSeconds = Date().timeIntervalSince(self.lastDetectionStartTime!)
        detections += 1
        averageDetectionDelayInSeconds = (averageDetectionDelayInSeconds * Double(detections - 1) + lastDetectionDelayInSeconds) / Double(detections)
        
        // Update the detected object's display duration
        self.detectedObject?.displayDuration = resultDisplayDuration
        
        // Immediately remove the anchor from the session again to force a re-detection.
        self.lastDetectionStartTime = Date()
        self.sceneView.session.remove(anchor: objectAnchor)
        
        if let currentPointCloud = self.sceneView.session.currentFrame?.rawFeaturePoints {
            self.detectedObject?.updateVisualization(newTransform: objectAnchor.transform,
                                                     currentPointCloud: currentPointCloud)
        }
        
        startNoDetectionTimer()
    }
    
    func updateOnEveryFrame() {
        if let detectedObject = self.detectedObject {
            if let currentPointCloud = self.sceneView.session.currentFrame?.rawFeaturePoints {
                detectedObject.updatePointCloud(currentPointCloud)
            }
        }
    }
    
    var noDetectionTimer: Timer?
    
    func startNoDetectionTimer() {
        cancelNoDetectionTimer()
        noDetectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            self.cancelNoDetectionTimer()
            ViewController.instance?.displayMessage("""
                Shift the phone's position, please
                """, expirationTime: 3.0)
        }
    }
    
    func cancelNoDetectionTimer() {
        noDetectionTimer?.invalidate()
        noDetectionTimer = nil
    }
}
