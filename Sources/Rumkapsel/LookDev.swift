// One still of the flight rocket, rendered offscreen in a second or two, for working on how it looks:
// `rumkapsel --look-dev <out.png> [shot]`. The shots: "down", the camera bolted to the lifter; from outside,
// "hull" close on the plating, "wide" the whole rocket, "base" the lifter's foot, "under" the tip from below
// burning, "feet" with its flaps out. The light and the
// camera's character are the flight's own.

import AppKit
import SceneKit
import Metal

enum LookDev {
    static func run(out: String, shot: String) -> Never {
        let scene = SCNScene()
        scene.background.contents = NSColor(rgb: (0.015, 0.02, 0.035))
        scene.lightingEnvironment.contents = FlightCraft.environment
        let (lifter, tip) = FlightCraft.build(color: NSColor(rgb: (0.86, 0.38, 0.42)), repo: "web", release: "#9002")
        FlightCraft.mountCameras(lifter: lifter, tip: tip)
        scene.rootNode.addChildNode(lifter)
        scene.rootNode.addChildNode(tip)
        // The planets' sun, low and from the side, and the bounce off everything else.
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1600
        sun.look(at: SCNVector3(-1, -0.3, -0.6))
        scene.rootNode.addChildNode(sun)
        let bounce = SCNNode(); bounce.light = SCNLight(); bounce.light!.type = .ambient; bounce.light!.intensity = 260
        scene.rootNode.addChildNode(bounce)

        let eye = SCNNode()
        let cam = SCNCamera()
        cam.fieldOfView = 58; cam.zNear = 0.005; cam.zFar = 200
        FlightCraft.film(cam)
        eye.camera = cam
        switch shot {
        case "hull":
            eye.position = SCNVector3(0.42, 1.72, 0.32)
            eye.look(at: SCNVector3(0, 1.66, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        case "wide":
            eye.position = SCNVector3(2.4, 1.5, 1.9)
            eye.look(at: SCNVector3(0, 1.2, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        default:
            let name = shot + " cam"
            guard let mount = (tip.childNode(withName: name, recursively: true) ?? lifter.childNode(withName: name, recursively: true)) else {
                FileHandle.standardError.write("no shot \(shot)\n".data(using: .utf8)!); exit(1)
            }
            eye.simdTransform = mount.simdWorldTransform
        }
        scene.rootNode.addChildNode(eye)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = eye
        let image = renderer.snapshot(atTime: 1, with: CGSize(width: 1600, height: 1000), antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: out))
        exit(0)
    }
}
