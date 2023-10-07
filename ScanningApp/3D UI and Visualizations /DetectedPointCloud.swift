/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A visualization the 3D point cloud data in a detected object.
*/

import Foundation
import ARKit

class DetectedPointCloud: SCNNode, PointCloud {
    
    private let referenceObjectPointCloud: ARPointCloud
    private let center: SIMD3<Float>
    private let extent: SIMD3<Float>
    var sidesNode = SCNNode()
    
    private let MANY_CUBES = 15.0
    private let INCHES_15: Float = 0.381
    private let INCHES_5: Float = 0.127
    private var manyAnnotations = 0
    
    init(referenceObjectPointCloud: ARPointCloud, center: SIMD3<Float>, extent: SIMD3<Float>, sidesNodeObject: SCNNode?) {
        self.referenceObjectPointCloud = referenceObjectPointCloud
        self.center = center
        self.extent = extent
        super.init()
        
        self.sidesNode = sidesNodeObject ?? SCNNode()
        
        self.addChildNode(self.sidesNode)
        
        // Semitransparently visualize the reference object's points.
        //        let referenceObjectPoints = SCNNode()
        //        referenceObjectPoints.geometry = createVisualization(for: referenceObjectPointCloud.points, color: .appYellow, size: 12, type: .point)
        //        addChildNode(referenceObjectPoints)
        let minPt: SIMD3<Float> = simdPosition + center - extent / 2
        let maxPt: SIMD3<Float> = simdPosition + center + extent / 2
        
        let deltaX = maxPt.x - minPt.x
        let deltaY = maxPt.y - minPt.y
        let deltaZ = maxPt.z - minPt.z
        let diagDiameterM = sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)
        print("diagonal diameter meters: \(diagDiameterM)")
        var childCubeSize = SIMD3<Float>(x: INCHES_5, y: INCHES_5, z: INCHES_5)
        if(diagDiameterM < INCHES_15) {
            let volumeSize = maxPt - minPt
            childCubeSize = volumeSize / 4.0
        }
        let manyPerSide = diagDiameterM / childCubeSize
        

        func isPointInsideCube(point: simd_float3, min: simd_float3, max: simd_float3) -> Bool {
            return point.x >= min.x && point.x <= max.x &&
                   point.y >= min.y && point.y <= max.y &&
                   point.z >= min.z && point.z <= max.z
        }

        for x in 0..<Int(floor(manyPerSide.x)) {
            for y in 0..<Int(floor(manyPerSide.y)) {
                for z in 0..<Int(floor(manyPerSide.z)) {
                    let childCubeMin = SIMD3<Float>(
                        Float(x) * childCubeSize.x + minPt.x,
                        Float(y) * childCubeSize.y + minPt.y,
                        Float(z) * childCubeSize.z + minPt.z
                    )
                    
                    let childCubeMax = childCubeMin + childCubeSize
                    
                    var hasPointInside = false
                    
                    for point in referenceObjectPointCloud.points {
                        if isPointInsideCube(point: point, min: childCubeMin, max: childCubeMax) {
                            hasPointInside = true
                            break
                        }
                    }
                    
                    if hasPointInside {
                        let childCubeCenter = SIMD3<Float>(
                            childCubeMin.x + childCubeSize.x / 2,
                            childCubeMin.y + childCubeSize.y / 2,
                            childCubeMin.z + childCubeSize.z / 2
                        )
                        
                        let childCube = SCNBox(width: CGFloat(childCubeSize.x), height: CGFloat(childCubeSize.y), length: CGFloat(childCubeSize.z), chamferRadius: 0)
                        let childCubeNode = SCNNode(geometry: childCube)
                        childCubeNode.position = SCNVector3(childCubeCenter.x, childCubeCenter.y, childCubeCenter.z)
                        
                        let material = SCNMaterial()
                        material.diffuse.contents = UIColor.clear // change this to a color in order to see all child cubes
                        material.lightingModel = .constant
                        material.isDoubleSided = true
                        childCube.materials = [material]
                        
                        self.sidesNode.addChildNode(childCubeNode)
                    }
                }
            }
        }


        
//        addChildNode(CubeNode(position: SCNVector3(x: min.x, y: min.y, z: min.z)))
//        addChildNode(CubeNode(position: SCNVector3(x: max.x, y: max.y, z: max.z)))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func isPointInsideCube(point: simd_float3, min: simd_float3, max: simd_float3) -> Bool {
        return point.x >= min.x && point.x <= max.x &&
               point.y >= min.y && point.y <= max.y &&
               point.z >= min.z && point.z <= max.z
    }
    
    func updateVisualization(for currentPointCloud: ARPointCloud) {
//        guard !self.isHidden else { return }
//        
//        let min: SIMD3<Float> = simdPosition + center - extent / 2
//        let max: SIMD3<Float> = simdPosition + center + extent / 2
//        var inlierPoints: [SIMD3<Float>] = []
//        
//        for point in currentPointCloud.points {
//            let localPoint = self.simdConvertPosition(point, from: nil)
//            if (min.x..<max.x).contains(localPoint.x) &&
//                (min.y..<max.y).contains(localPoint.y) &&
//                (min.z..<max.z).contains(localPoint.z) {
//                inlierPoints.append(localPoint)
//            }
//        }
//        
//        let currentPointCloudInliers = inlierPoints
//        self.geometry = createVisualization(for: currentPointCloudInliers, color: .appGreen, size: 12, type: .point)
    }
    
    func updateCubes(sceneView: ARSCNView, screenPos: CGPoint) {
        let hitResults = sceneView.hitTest(screenPos, options: [
            .rootNode: sidesNode,
            .ignoreHiddenNodes: true,
            .backFaceCulling: true,
            .searchMode: SCNHitTestSearchMode.all.rawValue
        ])
        
        if !hitResults.isEmpty {
            print("Hit! \(hitResults.count)")
            let result = hitResults[0]
            let hitNode = result.node
            addAnnotation(node: hitNode)
//            let material = SCNMaterial()
//            material.diffuse.contents = UIColor(red:1.0, green:0.9, blue:0.9, alpha:0.7)
//            material.lightingModel = .constant
//            material.isDoubleSided = true
//            if let geometry = result.node.geometry, let material = geometry.firstMaterial {
//                material.diffuse.contents = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
//            }
        }
    }
    
    func addAnnotation(node: SCNNode) {
        manyAnnotations += 1
        let textGeometry = SCNText(string: "\(manyAnnotations)", extrusionDepth: 1)
        textGeometry.font = UIFont.systemFont(ofSize: 10)
        textGeometry.firstMaterial?.diffuse.contents = UIColor(red: 0.2588, green: 0.2824, blue: 0.4549, alpha: 1.0)
        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(0.01, 0.01, 0.01)
        let midX = (textGeometry.boundingBox.max.x + textGeometry.boundingBox.min.x) * 0.5
        let midY = (textGeometry.boundingBox.max.y + textGeometry.boundingBox.min.y) * 0.5
//        textNode.pivot = SCNMatrix4MakeTranslation(midX, midY, 0)
        
        let circleDiameter = CGFloat(max(textGeometry.boundingBox.max.x - textGeometry.boundingBox.min.x,
                                         textGeometry.boundingBox.max.y - textGeometry.boundingBox.min.y) * 1.5)  // Adjust as needed
        let circleGeometry = SCNPlane(width: circleDiameter, height: circleDiameter)
        circleGeometry.cornerRadius = 1
        circleGeometry.firstMaterial?.diffuse.contents = UIColor(red: 0.8627, green: 0.8392, blue: 0.9686, alpha: 1.0)
        let circleNode = SCNNode(geometry: circleGeometry)
        circleNode.position = SCNVector3(x: midX, y: midY, z: 0.1)
        
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.all
        textNode.constraints = [billboardConstraint]
        circleNode.constraints = [billboardConstraint]

        node.addChildNode(textNode)
        textNode.addChildNode(circleNode)
    }
    
    func getPoints() -> [SIMD3<Float>] {
        return referenceObjectPointCloud.points
    }
    
    func getCenter() -> SIMD3<Float> {
        return self.center
    }
}
