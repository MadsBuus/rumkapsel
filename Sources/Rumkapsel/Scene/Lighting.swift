import AppKit
import SceneKit

extension StationController {
    func light() {
        lights.forEach { $0.removeFromParentNode() }
        let mask = ~(Pick.planet | Pick.colony | Pick.onboard)
        func add(_ type: SCNLight.LightType, _ color: NSColor, _ intensity: CGFloat, from: SIMD3<Float>? = nil, under parent: SCNNode) -> SCNLight {
            let n = SCNNode(), l = SCNLight()
            l.type = type; l.color = color; l.intensity = intensity; l.categoryBitMask = mask
            n.light = l
            if let from { n.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(-from)) }
            parent.addChildNode(n)
            lights.append(n)
            return l
        }
        lights = []
        let camera = cameraNode.camera!
        guard ConfigStore.shared.current.dramaticLight == true else {
            camera.wantsHDR = false
            _ = add(.directional, .white, 700, under: scene.rootNode)
            lights.last!.eulerAngles = v3(-.pi / 3, .pi / 3, 0)
            _ = add(.ambient, .white, 550, under: scene.rootNode)
            return
        }
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -0.35
        camera.bloomThreshold = 1.6
        camera.bloomIntensity = 0.6
        camera.bloomBlurRadius = 10
        camera.vignettingIntensity = 0
        _ = add(.ambient, NSColor(rgb: (0.45, 0.55, 0.8)), 220, under: scene.rootNode)
        let key = add(.directional, NSColor(rgb: (1.0, 0.84, 0.66)), 1900, from: SIMD3(-6, 4.5, 2.2), under: rig)
        key.castsShadow = true
        key.shadowRadius = 5
        key.shadowSampleCount = 16
        key.shadowMapSize = CGSize(width: 4096, height: 4096)
        key.shadowColor = NSColor(white: 0, alpha: 0.65)
        _ = add(.directional, NSColor(rgb: (0.55, 0.8, 1.0)), 1400, from: SIMD3(2.9, 3.1, -5), under: rig)
    }
}
