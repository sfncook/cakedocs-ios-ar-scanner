import SceneKit

class CubeNode: SCNNode {

    var size = 0.1
    
    init(position: SCNVector3) {
        super.init()
        setup()
        self.position = position
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let cubeGeometry = SCNBox(width: size, height: size, length: size, chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red:0.9, green:0.9, blue:1.0, alpha:0.7)
        material.lightingModel = .constant
        material.isDoubleSided = true
        cubeGeometry.materials = [material]
        self.geometry = cubeGeometry
        
        // Wire edges
        let childGeometry = cubeGeometry.copy() as! SCNGeometry
        let childCubeNode = SCNNode(geometry: childGeometry)
        let materialEdges = SCNMaterial()
        materialEdges.diffuse.contents = UIColor.yellow
        materialEdges.lightingModel = .constant
        materialEdges.isDoubleSided = false
        materialEdges.fillMode = .lines
        childGeometry.materials = [materialEdges]
        self.addChildNode(childCubeNode)
    }
}
