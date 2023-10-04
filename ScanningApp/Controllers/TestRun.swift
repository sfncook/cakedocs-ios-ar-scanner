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
        
        // Get the ray in 3D space corresponding to the user's tap
        guard let ray = sceneView.ray(through: hitLocationInView) else {
            return
        }

        // Get points from the referenceObjectPointCloud
        let points = self.detectedObject!.getPoints()

        // Find the point from the point cloud that is closest to the ray
        var closestPoint: SIMD3<Float>? = nil
        var smallestDistance = Float.infinity

        for i in 0..<points.count {
            let point = points[i]
            let ptVector = point.scnVector3
            let distance = distanceFromRay(rayOrigin: ray.origin, rayDirection: ray.direction, point: ptVector)
            if distance < smallestDistance {
                closestPoint = point
                smallestDistance = distance
            }
        }

        // Place a sphere node at the closest point
        if let closestPoint = closestPoint {
            let sphereNode = SCNNode(geometry: SCNSphere(radius: 0.005))  // Example radius
            sphereNode.position = SCNVector3(closestPoint)
            self.detectedObject?.addChildNode(sphereNode)
        }
    }

    // This function calculates the shortest distance from a point to a ray
    func distanceFromRay(rayOrigin: SCNVector3, rayDirection: SCNVector3, point: SCNVector3) -> Float {
        let w = point - rayOrigin
        let c1 = dot(w, rayDirection)
        let c2 = dot(rayDirection, rayDirection)
        let b = c1 / c2
        let pb = rayOrigin + (rayDirection * b)
        let delta = point - pb
        return delta.length
    }


    func dot(_ left: SCNVector3, _ right: SCNVector3) -> Float {
        return left.x * right.x + left.y * right.y + left.z * right.z
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

extension SIMD3 where Scalar == Float {
    var scnVector3: SCNVector3 {
        return SCNVector3(x: Float(self.x), y: Float(self.y), z: Float(self.z))
    }
}

extension SCNVector3 {
    static func -(left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        return SCNVector3Make(left.x - right.x, left.y - right.y, left.z - right.z)
    }
    
    static func +(left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        return SCNVector3Make(left.x + right.x, left.y + right.y, left.z + right.z)
    }
    
    static func *(vector: SCNVector3, scalar: Float) -> SCNVector3 {
        return SCNVector3Make(vector.x * scalar, vector.y * scalar, vector.z * scalar)
    }
    
    static func *(scalar: Float, vector: SCNVector3) -> SCNVector3 {
        return SCNVector3Make(vector.x * scalar, vector.y * scalar, vector.z * scalar)
    }
    
    var length: Float {
        return sqrtf(x * x + y * y + z * z)
    }
    
    public static func ==(lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
    
    public static func !=(lhs: SCNVector3, rhs: SCNVector3) -> Bool {
        return !(lhs == rhs)
    }
}

extension SCNView {
    func ray(through point: CGPoint) -> (origin: SCNVector3, direction: SCNVector3, farPoint: SCNVector3)? {
        let nearPoint = unprojectPoint(SCNVector3(x: Float(point.x), y: Float(point.y), z: 0))
        let farPoint = unprojectPoint(SCNVector3(x: Float(point.x), y: Float(point.y), z: 1))
        
        guard nearPoint != farPoint else { return nil }
        
        let direction = normalize(vector: farPoint - nearPoint)
        return (origin: nearPoint, direction: direction, farPoint: farPoint)
    }
    
    private func normalize(vector: SCNVector3) -> SCNVector3 {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        guard length != 0 else { return SCNVector3(0, 0, 0) }
        return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
    }
}

