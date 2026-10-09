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
        if shot.hasPrefix("wall") {
            // "wall" or "wall-close", with ":office", ":quarters" or ":yard" for a place other than a hallway.
            let parts = shot.split(separator: ":")
            let style = parts.count > 1 ? Bulkhead.Style(rawValue: String(parts[1])) ?? .hallway : .hallway
            walls(out: out, close: parts[0] == "wall-close", style: style)
        }
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
        render(scene, from: eye, to: out)
    }

    private static func render(_ scene: SCNScene, from eye: SCNNode, to out: String) -> Never {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = eye
        let image = renderer.snapshot(atTime: 1, with: CGSize(width: 1600, height: 1000), antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: out))
        exit(0)
    }

    /// A stretch of hallway at a minion's eye height, lit as the station is and seen through the walk's camera:
    /// two walls of the walk's sections either side, a turn at the far end, pilasters where they turn or stop.
    private static func walls(out: String, close: Bool, style: Bulkhead.Style) -> Never {
        Bulkhead.prepareNow()
        let scene = SCNScene()
        scene.background.contents = NSColor(rgb: (0.015, 0.02, 0.035))
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 700
        sun.eulerAngles = v3(-.pi / 3, .pi / 3, 0)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 550
        scene.rootNode.addChildNode(ambient)
        let floor = SCNNode(geometry: SCNPlane(width: 12, height: 3))
        floor.geometry!.firstMaterial = lit(NSColor(rgb: (0.42, 0.33, 0.27)))
        floor.eulerAngles.x = -.pi / 2
        floor.position = v3(2, 0, 0)
        scene.rootNode.addChildNode(floor)
        let t = 0.07, length = 5
        for side in [-1.0, 1.0] {
            for k in 0..<length where !(side > 0 && k == 3) {   // a doorway on the right
                let box = SCNBox(width: 1, height: Walker.wallHeight, length: t, chamferRadius: 0)
                let variant = (k * 3 + (side > 0 ? 1 : 0)) % Bulkhead.count
                var faces = Array(repeating: Bulkhead.steel, count: 6)
                faces[side > 0 ? 2 : 0] = Bulkhead.material(variant, style: style)
                faces[side > 0 ? 0 : 2] = Bulkhead.material((variant + 2) % Bulkhead.count, style: style)
                box.materials = faces
                let wall = SCNNode(geometry: box)
                wall.position = v3(Double(k) + 0.5, Walker.wallHeight / 2, side * 0.5)
                scene.rootNode.addChildNode(wall)
                let cap = Bulkhead.cap(length: 1, thickness: t, across: false)
                cap.position = v3(Double(k) + 0.5, 0, side * 0.5)
                scene.rootNode.addChildNode(cap)
            }
            for x in [0.0, 3.0, 4.0, 5.0] where side > 0 || x == 0 || x == 5 {
                let p = Bulkhead.pilaster(seed: Int(x) * 5)
                p.position = v3(x, 0, side * 0.5)
                scene.rootNode.addChildNode(p)
            }
        }
        let eye = SCNNode()
        let cam = SCNCamera()
        cam.fieldOfView = 68; cam.zNear = 0.02; cam.zFar = 200
        FlightCraft.film(cam)
        cam.exposureOffset = -0.45
        cam.bloomThreshold = 1.4
        eye.camera = cam
        if close {
            eye.position = v3(1.2, 0.42, 0.05)
            eye.look(at: v3(2.0, 0.36, -0.5), up: v3(0, 1, 0), localFront: v3(0, 0, -1))
        } else {
            eye.position = v3(-0.4, 0.4, 0.08)
            eye.look(at: v3(4, 0.3, -0.05), up: v3(0, 1, 0), localFront: v3(0, 0, -1))
        }
        scene.rootNode.addChildNode(eye)
        render(scene, from: eye, to: out)
    }
}
