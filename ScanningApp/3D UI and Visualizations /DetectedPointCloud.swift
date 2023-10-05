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
    
    init(referenceObjectPointCloud: ARPointCloud, center: SIMD3<Float>, extent: SIMD3<Float>) {
        self.referenceObjectPointCloud = referenceObjectPointCloud
        self.center = center
        self.extent = extent
        super.init()
        
        // Semitransparently visualize the reference object's points.
        //        let referenceObjectPoints = SCNNode()
        //        referenceObjectPoints.geometry = createVisualization(for: referenceObjectPointCloud.points, color: .appYellow, size: 12, type: .point)
        //        addChildNode(referenceObjectPoints)
        let extPartial = extent / 3
        let minPt: SIMD3<Float> = simdPosition + center - extent / 2
        let maxPt: SIMD3<Float> = simdPosition + center + extent / 2

        let volumeSize = maxPt - minPt
        let childCubeSize = volumeSize / 3.0

        for x in 0..<3 {
            for y in 0..<3 {
                for z in 0..<3 {
                    let childCubePosition = SIMD3<Float>(
                        Float(x) * childCubeSize.x + childCubeSize.x/2 + minPt.x,
                        Float(y) * childCubeSize.y + childCubeSize.y/2 + minPt.y,
                        Float(z) * childCubeSize.z + childCubeSize.z/2 + minPt.z
                    )
                    
                    let childCube = SCNBox(width: CGFloat(childCubeSize.x * 0.95), height: CGFloat(childCubeSize.y*0.95), length: CGFloat(childCubeSize.z*0.95), chamferRadius: 0)
                    let childCubeNode = SCNNode(geometry: childCube)
                    childCubeNode.position = SCNVector3(childCubePosition.x, childCubePosition.y, childCubePosition.z)
                    
                    let material = SCNMaterial()
                    material.diffuse.contents = UIColor(red:0.9, green:0.9, blue:1.0, alpha:0.7)
                    material.lightingModel = .constant
                    material.isDoubleSided = true
                    childCube.materials = [material]
                    
                    addChildNode(childCubeNode)
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
    
    func getPoints() -> [SIMD3<Float>] {
        return referenceObjectPointCloud.points
    }
    
    func getCenter() -> SIMD3<Float> {
        return self.center
    }
}
