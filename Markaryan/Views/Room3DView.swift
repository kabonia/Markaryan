import SwiftUI
import SceneKit
import Metal
#if canImport(ImagePlayground)
import ImagePlayground
#endif

// MARK: - On-device 3D visualisation of a plan and its AI concept (no server, no paid image AI)

enum Room3DViewMode: String, CaseIterable, Identifiable {
    case interior, top, overhead
    var id: String { rawValue }
    var title: String {
        switch self { case .interior: return "Интерьер"; case .top: return "Изометрия"; case .overhead: return "План 3D" }
    }
}

/// A camera shot inside the room: where the eye stands and where it looks (plan coordinates).
struct InteriorShot {
    let title: String
    let eye: PlanPoint
    let target: PlanPoint
}

/// Builds a furnished interior (walls, ceiling, skirting, wooden floor, doors, windows and real furniture shapes)
/// from a plan and the AI concept. Two cameras: eye level inside the room, or a dollhouse view from above.
enum Room3DBuilder {
    // MARK: Materials

    static func material(_ color: UIColor, roughness: CGFloat = 0.8, metalness: CGFloat = 0) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = metalness
        return material
    }

    /// Procedural wooden planks for the floor.
    static func woodTexture(base: UIColor) -> UIImage {
        let size = CGSize(width: 512, height: 512)
        return UIGraphicsImageRenderer(size: size).image { context in
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
            base.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            let plankHeight: CGFloat = 64
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : -160
                while x < size.width {
                    let shade = CGFloat((row * 7 + Int(x) / 37) % 5) * 0.025
                    UIColor(hue: hue, saturation: sat, brightness: max(0, min(1, bri - 0.05 + shade)), alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 318, height: plankHeight - 2))
                    UIColor(hue: hue, saturation: sat, brightness: max(0, bri - 0.25), alpha: 0.18).setFill()
                    for line in stride(from: y + 9, to: y + plankHeight - 4, by: 11) { context.fill(CGRect(x: x, y: line, width: 318, height: 1)) }
                    x += 320
                }
                row += 1
                y += plankHeight
            }
        }
    }

    /// Procedural porcelain tiles for the floor: 4 × 4 tiles with grout lines and a slight shade per tile.
    static func tileTexture(base: UIColor) -> UIImage {
        let size = CGSize(width: 512, height: 512)
        return UIGraphicsImageRenderer(size: size).image { context in
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
            base.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            UIColor(hue: hue, saturation: sat * 0.6, brightness: max(0, min(1, bri * 0.82)), alpha: 1).setFill() // grout
            context.fill(CGRect(origin: .zero, size: size))
            let tile: CGFloat = 128, joint: CGFloat = 3
            for row in 0..<4 {
                for column in 0..<4 {
                    let shade = CGFloat((row * 3 + column * 5) % 4) * 0.012
                    UIColor(hue: hue, saturation: sat, brightness: max(0, min(1, bri - 0.02 + shade)), alpha: 1).setFill()
                    context.fill(CGRect(x: CGFloat(column) * tile + joint / 2, y: CGFloat(row) * tile + joint / 2, width: tile - joint, height: tile - joint))
                }
            }
        }
    }

    private static func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ m: SCNMaterial, at position: SCNVector3, chamfer: CGFloat = 0.01) -> SCNNode {
        let geometry = SCNBox(width: max(0.01, w), height: max(0.01, h), length: max(0.01, d), chamferRadius: min(chamfer, min(w, h, d) / 2))
        geometry.materials = [m]
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    private static func cylinder(_ radius: CGFloat, _ height: CGFloat, _ m: SCNMaterial, at position: SCNVector3) -> SCNNode {
        let geometry = SCNCylinder(radius: radius, height: height)
        geometry.materials = [m]
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    /// Fine plaster relief (normal map) for walls.
    static let plasterNormal: UIImage = {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.5, green: 0.5, blue: 1, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size))
            var seed: UInt64 = 42
            func random() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1) }
            for _ in 0..<1800 {
                let r = 1 + random() * 5
                UIColor(red: 0.5 + (random() - 0.5) * 0.12, green: 0.5 + (random() - 0.5) * 0.12, blue: 1, alpha: 0.5).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: random() * size.width, y: random() * size.height, width: r, height: r))
            }
        }
    }()

    // MARK: Furniture models (local x = width, z = depth, y = up, origin at the floor centre)

    static func furniture(kind: String, name: String, width w: CGFloat, depth d: CGFloat, color: UIColor, accent: UIColor, ceiling: CGFloat = 2.7, withMirror: Bool = true) -> SCNNode {
        let node = SCNNode()
        let fabric = material(color, roughness: 0.95)
        let wood = material(UIColor(red: 0.55, green: 0.40, blue: 0.27, alpha: 1), roughness: 0.6)
        let dark = material(UIColor(white: 0.12, alpha: 1), roughness: 0.4, metalness: 0.3)
        let white = material(UIColor(white: 0.95, alpha: 1), roughness: 0.9)
        let ceramic = material(UIColor(white: 0.97, alpha: 1), roughness: 0.12)
        let chrome = material(UIColor(white: 0.86, alpha: 1), roughness: 0.15, metalness: 1)
        let mirror = material(UIColor(red: 0.80, green: 0.84, blue: 0.86, alpha: 1), roughness: 0.04, metalness: 1)
        let lower = name.lowercased()
        func add(_ child: SCNNode) { node.addChildNode(child) }
        func light(_ intensity: CGFloat, at position: SCNVector3, reach: CGFloat) {
            let bulb = SCNNode(); bulb.light = SCNLight(); bulb.light?.type = .omni; bulb.light?.intensity = intensity
            bulb.light?.color = UIColor(red: 1, green: 0.88, blue: 0.72, alpha: 1)
            bulb.light?.attenuationStartDistance = 0.3; bulb.light?.attenuationEndDistance = reach
            bulb.position = position; add(bulb)
        }

        switch FixtureModel.resolve(kind: kind, name: name) {
        case "sofa":
            add(box(w, 0.42, d, fabric, at: SCNVector3(0, 0.21, 0), chamfer: 0.04))
            add(box(w, 0.45, 0.2, fabric, at: SCNVector3(0, 0.62, Float(-d / 2 + 0.1)), chamfer: 0.06))
            add(box(0.18, 0.22, d, fabric, at: SCNVector3(Float(-w / 2 + 0.09), 0.53, 0), chamfer: 0.06))
            add(box(0.18, 0.22, d, fabric, at: SCNVector3(Float(w / 2 - 0.09), 0.53, 0), chamfer: 0.06))
            let seats = max(1, Int((w - 0.36) / 0.7))
            let seatWidth = (w - 0.36) / CGFloat(seats)
            for index in 0..<seats {
                let x = -w / 2 + 0.18 + seatWidth * (CGFloat(index) + 0.5)
                add(box(seatWidth - 0.02, 0.12, d - 0.24, fabric, at: SCNVector3(Float(x), 0.48, 0.06), chamfer: 0.05))
            }
            add(box(0.4, 0.3, 0.12, material(accent, roughness: 0.9), at: SCNVector3(Float(-w / 2 + 0.45), 0.66, Float(-d / 2 + 0.28)), chamfer: 0.05))
        case "bed":
            add(box(w, 0.3, d, wood, at: SCNVector3(0, 0.15, 0), chamfer: 0.02))
            add(box(w - 0.06, 0.22, d - 0.08, white, at: SCNVector3(0, 0.41, 0.02), chamfer: 0.06))
            add(box(w, 0.9, 0.08, fabric, at: SCNVector3(0, 0.75, Float(-d / 2 + 0.04)), chamfer: 0.04))
            add(box(w - 0.1, 0.06, d * 0.55, fabric, at: SCNVector3(0, 0.55, Float(d * 0.2)), chamfer: 0.03))
            for x in [-w / 4, w / 4] { add(box(w / 2 - 0.15, 0.12, 0.35, white, at: SCNVector3(Float(x), 0.58, Float(-d / 2 + 0.3)), chamfer: 0.05)) }
        case "table", "desk":
            let top = material(color, roughness: 0.5)
            add(box(w, 0.04, d, top, at: SCNVector3(0, 0.74, 0), chamfer: 0.01))
            for sx in [-1.0, 1.0] { for sz in [-1.0, 1.0] {
                add(box(0.05, 0.72, 0.05, wood, at: SCNVector3(Float(sx * Double(w / 2 - 0.06)), 0.36, Float(sz * Double(d / 2 - 0.06)))))
            } }
        case "chair":
            add(box(w, 0.05, d, fabric, at: SCNVector3(0, 0.45, 0), chamfer: 0.02))
            add(box(w, 0.42, 0.05, fabric, at: SCNVector3(0, 0.68, Float(-d / 2 + 0.03)), chamfer: 0.02))
            for sx in [-1.0, 1.0] { for sz in [-1.0, 1.0] {
                add(box(0.035, 0.44, 0.035, wood, at: SCNVector3(Float(sx * Double(w / 2 - 0.04)), 0.22, Float(sz * Double(d / 2 - 0.04)))))
            } }
        case "storage":
            let wallHung = lower.contains("навесн") || lower.contains("подвесн")
            let height: CGFloat = lower.contains("тумб") || lower.contains("комод") ? 0.85 : (lower.contains("полк") ? 0.4 : (lower.contains("пенал") ? 1.6 : 2.2))
            let base: CGFloat = wallHung || lower.contains("полк") ? 1.3 : (lower.contains("пенал") ? 0.25 : 0)
            let body = material(color, roughness: 0.55)
            add(box(w, height, d, body, at: SCNVector3(0, Float(base + height / 2), 0), chamfer: 0.01))
            let doors = max(1, Int(w / 0.5))
            for index in 1..<doors {
                let x = -w / 2 + w * CGFloat(index) / CGFloat(doors)
                add(box(0.006, height - 0.06, 0.01, dark, at: SCNVector3(Float(x), Float(base + height / 2), Float(d / 2 + 0.003))))
            }
            if !lower.contains("полк") {
                for index in 0..<doors {
                    let x = -w / 2 + w * (CGFloat(index) + 0.5) / CGFloat(doors) + 0.18
                    add(box(0.015, 0.18, 0.02, dark, at: SCNVector3(Float(min(w / 2 - 0.05, x)), Float(base + min(1.0, height / 2)), Float(d / 2 + 0.015))))
                }
            }
        case "kitchen":
            let fronts = material(color, roughness: 0.5)
            let stone = material(UIColor(white: 0.88, alpha: 1), roughness: 0.25)
            add(box(w, 0.1, d - 0.05, dark, at: SCNVector3(0, 0.05, -0.02)))
            add(box(w, 0.76, d, fronts, at: SCNVector3(0, 0.48, 0), chamfer: 0.005))
            add(box(w + 0.02, 0.04, d + 0.03, stone, at: SCNVector3(0, 0.88, 0.01), chamfer: 0.005))
            add(box(w, 0.7, 0.35, fronts, at: SCNVector3(0, 1.85, Float(-d / 2 + 0.175)), chamfer: 0.005))
            let modules = max(1, Int(w / 0.6))
            for index in 1..<modules {
                let x = -w / 2 + w * CGFloat(index) / CGFloat(modules)
                add(box(0.006, 0.7, 0.01, dark, at: SCNVector3(Float(x), 0.48, Float(d / 2 + 0.003))))
            }
            if lower.contains("мойк") { add(box(min(0.5, w * 0.6), 0.02, 0.4, chrome, at: SCNVector3(0, 0.905, 0))) }
            if lower.contains("плит") || lower.contains("вароч") { add(box(min(0.58, w * 0.8), 0.01, 0.5, dark, at: SCNVector3(0, 0.905, 0))) }
        case "appliance":
            let steel = material(UIColor(white: 0.78, alpha: 1), roughness: 0.25, metalness: 0.85)
            let tall = lower.contains("холод") || lower.contains("колонн") || lower.contains("духов")
            let height: CGFloat = tall ? 2.0 : 0.85
            add(box(w, height, d, steel, at: SCNVector3(0, Float(height / 2), 0), chamfer: 0.02))
            add(box(0.02, min(0.6, height * 0.4), 0.03, dark, at: SCNVector3(Float(w / 2 - 0.08), Float(height * 0.6), Float(d / 2 + 0.015))))

        // Bathroom: real fixtures instead of boxes (back of the item = local -z, against the wall)
        case "toilet":
            let back = min(0.14, d * 0.25)
            add(box(min(w, 0.5), 0.82, back, ceramic, at: SCNVector3(0, 0.41, Float(-d / 2 + back / 2)), chamfer: 0.01))
            add(box(0.24, 0.15, 0.012, chrome, at: SCNVector3(0, 0.66, Float(-d / 2 + back + 0.006)), chamfer: 0.004))
            let bowlDepth = max(0.3, d - back)
            let bowl = SCNNode(geometry: SCNSphere(radius: 0.5)); bowl.geometry?.materials = [ceramic]
            bowl.scale = SCNVector3(Float(min(w, 0.42) * 0.92), 0.32, Float(bowlDepth * 0.95))
            bowl.position = SCNVector3(0, 0.27, Float(-d / 2 + back + bowlDepth / 2))
            add(bowl)
            add(box(min(w, 0.42) * 0.9, 0.025, bowlDepth * 0.88, ceramic, at: SCNVector3(0, 0.43, Float(-d / 2 + back + bowlDepth / 2)), chamfer: 0.012))
        case "sink":
            let fronts = material(color, roughness: 0.55)
            add(box(w, 0.5, max(0.2, d - 0.03), fronts, at: SCNVector3(0, 0.55, -0.015), chamfer: 0.006))
            add(box(w * 0.5, 0.012, 0.012, dark, at: SCNVector3(0, 0.72, Float(d / 2 - 0.02))))
            add(box(w + 0.01, 0.06, d, ceramic, at: SCNVector3(0, 0.83, 0), chamfer: 0.02))
            add(box(min(w * 0.62, 0.55), 0.01, d * 0.55, material(UIColor(white: 0.86, alpha: 1), roughness: 0.1), at: SCNVector3(0, 0.862, 0.03), chamfer: 0.004))
            add(cylinder(0.016, 0.2, chrome, at: SCNVector3(0, 0.96, Float(-d / 2 + 0.07))))
            add(box(0.03, 0.025, 0.15, chrome, at: SCNVector3(0, 1.06, Float(-d / 2 + 0.13)), chamfer: 0.008))
            if withMirror { add(box(min(max(0.5, w * 0.85), 1.2), 0.8, 0.025, mirror, at: SCNVector3(0, 1.5, Float(-d / 2 + 0.0125)), chamfer: 0.005)) }
        case "shower":
            let glass = material(UIColor(red: 0.86, green: 0.93, blue: 0.95, alpha: 1), roughness: 0.04)
            glass.transparency = 0.2; glass.transparencyMode = .dualLayer; glass.isDoubleSided = true; glass.writesToDepthBuffer = false
            add(box(w, 0.04, d, ceramic, at: SCNVector3(0, 0.02, 0), chamfer: 0.01))
            add(box(min(0.6, w * 0.7), 0.005, 0.06, chrome, at: SCNVector3(0, 0.043, Float(-d / 2 + 0.1))))
            add(box(w, 1.95, 0.008, glass, at: SCNVector3(0, 1.015, Float(d / 2 - 0.004))))
            add(box(w, 0.025, 0.025, dark, at: SCNVector3(0, 2.0, Float(d / 2 - 0.004))))
            for side in [-1.0, 1.0] { add(box(0.022, 1.96, 0.022, dark, at: SCNVector3(Float(side * Double(w / 2 - 0.011)), 1.02, Float(d / 2 - 0.004)))) }
            let headY = Float(min(2.12, ceiling - 0.15))
            add(cylinder(0.12, 0.012, chrome, at: SCNVector3(0, headY, Float(-d / 2 + 0.28))))
            add(box(0.02, 0.02, 0.28, chrome, at: SCNVector3(0, headY + 0.015, Float(-d / 2 + 0.14))))
            add(box(0.1, 0.13, 0.05, chrome, at: SCNVector3(0, 1.1, Float(-d / 2 + 0.025)), chamfer: 0.01))
        case "bathtub":
            add(box(w, 0.56, d, ceramic, at: SCNVector3(0, 0.28, 0), chamfer: 0.04))
            add(box(w - 0.14, 0.03, d - 0.14, material(UIColor(red: 0.86, green: 0.93, blue: 0.97, alpha: 1), roughness: 0.08), at: SCNVector3(0, 0.55, 0), chamfer: 0.04))
            add(cylinder(0.018, 0.2, chrome, at: SCNVector3(Float(w / 2 - 0.15), 0.66, Float(-d / 2 + 0.05))))
            add(box(0.03, 0.025, 0.14, chrome, at: SCNVector3(Float(w / 2 - 0.15), 0.76, Float(-d / 2 + 0.11))))
        case "washer":
            let height: CGFloat = 0.85
            add(box(w, height, d, material(UIColor(white: 0.96, alpha: 1), roughness: 0.3), at: SCNVector3(0, Float(height / 2), 0), chamfer: 0.02))
            let radius = min(w, height) * 0.3
            let ring = cylinder(radius, 0.03, chrome, at: SCNVector3(0, Float(height * 0.44), Float(d / 2 + 0.012)))
            ring.eulerAngles.x = .pi / 2; add(ring)
            let door = cylinder(radius * 0.76, 0.036, material(UIColor(white: 0.18, alpha: 1), roughness: 0.08, metalness: 0.2), at: SCNVector3(0, Float(height * 0.44), Float(d / 2 + 0.014)))
            door.eulerAngles.x = .pi / 2; add(door)
            add(box(w * 0.9, 0.07, 0.01, material(UIColor(white: 0.9, alpha: 1), roughness: 0.4), at: SCNVector3(0, Float(height - 0.07), Float(d / 2 + 0.005))))
        case "mirror":
            let thickness = max(0.02, min(d, 0.04))
            add(box(w, w > 1 ? 0.9 : 0.8, thickness, mirror, at: SCNVector3(0, 1.48, 0), chamfer: 0.005))
        case "towel":
            for side in [-1.0, 1.0] { add(cylinder(0.012, 0.75, chrome, at: SCNVector3(Float(side * Double(w / 2 - 0.02)), 1.22, 0))) }
            for index in 0..<6 { add(box(w, 0.016, 0.016, chrome, at: SCNVector3(0, Float(0.9 + Double(index) * 0.12), 0), chamfer: 0.008)) }
        case "boiler":
            add(cylinder(max(0.15, min(w, d) / 2), 0.8, ceramic, at: SCNVector3(0, Float(min(1.75, ceiling - 0.45)), 0)))
        case "accessory":
            add(box(0.08, 0.14, 0.06, chrome, at: SCNVector3(0, 0.75, 0), chamfer: 0.01))

        case "tv":
            add(box(max(w, 1.2), 0.45, 0.4, material(color, roughness: 0.6), at: SCNVector3(0, 0.225, 0), chamfer: 0.01))
            add(box(min(max(w, 1.0), 1.6), 0.75, 0.04, dark, at: SCNVector3(0, 0.95, Float(-d / 2 + 0.05)), chamfer: 0.01))
        case "plant":
            let pot = material(UIColor(red: 0.85, green: 0.82, blue: 0.76, alpha: 1), roughness: 0.8)
            let size = min(max(min(w, d), 0.3), 0.6)
            add(cylinder(size * 0.3, 0.4, pot, at: SCNVector3(0, 0.2, 0)))
            let leaves = material(UIColor(red: 0.27, green: 0.47, blue: 0.27, alpha: 1), roughness: 0.9)
            for (index, offset) in [(0.0, 0.0), (0.12, 0.08), (-0.1, -0.06)].enumerated() {
                let sphere = SCNSphere(radius: size * 0.42 - CGFloat(index) * 0.04)
                sphere.materials = [leaves]
                let leaf = SCNNode(geometry: sphere)
                leaf.position = SCNVector3(Float(offset.0), Float(0.75 + Double(index) * 0.2), Float(offset.1))
                add(leaf)
            }

        // Lights: where they really hang — never a 1.5 m lamp in the middle of a bathroom
        case "pendant":
            let drop = min(0.7, max(0.3, ceiling - 2.05))
            add(cylinder(0.004, drop, dark, at: SCNVector3(0, Float(ceiling - drop / 2), 0)))
            let shade = SCNCone(topRadius: 0.05, bottomRadius: 0.16, height: 0.2)
            shade.materials = [dark]
            let shadeNode = SCNNode(geometry: shade); shadeNode.position = SCNVector3(0, Float(ceiling - drop - 0.1), 0)
            add(shadeNode)
            light(90, at: SCNVector3(0, Float(ceiling - drop - 0.18), 0), reach: 3)
        case "sconce":
            add(box(0.1, 0.16, 0.04, dark, at: SCNVector3(0, 1.85, 0), chamfer: 0.01))
            let glow = cylinder(0.05, 0.12, material(UIColor(white: 1, alpha: 1), roughness: 0.9), at: SCNVector3(0, 1.85, 0.06))
            glow.geometry?.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.9, blue: 0.75, alpha: 1)
            glow.geometry?.firstMaterial?.emission.intensity = 0.6
            add(glow)
            light(45, at: SCNVector3(0, 1.85, 0.15), reach: 2.2)
        case "floorlamp":
            add(cylinder(0.15, 0.03, dark, at: SCNVector3(0, 0.015, 0)))
            add(cylinder(0.012, 1.5, dark, at: SCNVector3(0, 0.75, 0)))
            let shade = SCNCone(topRadius: 0.12, bottomRadius: 0.22, height: 0.3)
            shade.materials = [material(UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1), roughness: 0.9)]
            let shadeNode = SCNNode(geometry: shade); shadeNode.position = SCNVector3(0, 1.55, 0)
            add(shadeNode)
            light(80, at: SCNVector3(0, 1.45, 0), reach: 3)
        case "hiddenlight":
            break // LED strips and spots: the ceiling spot grid already lights the room
        default: // decor, rug, anything else
            if lower.contains("ковёр") || lower.contains("ковер") || lower.contains("коврик") || kind == "decor" {
                add(box(w, 0.015, d, material(accent, roughness: 1), at: SCNVector3(0, 0.0075, 0), chamfer: 0.005))
            } else {
                add(box(w, 0.5, d, material(color, roughness: 0.7), at: SCNVector3(0, 0.25, 0), chamfer: 0.03))
            }
        }
        return node
    }

    // MARK: Scene

    private static func pointInPolygon(_ point: PlanPoint, _ polygon: [PlanPoint]) -> Bool {
        guard polygon.count >= 3 else { return true }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    static func scene(plan: FloorPlan, proposal original: DesignProposal?, mode: Room3DViewMode = .interior, viewpoint: Int = 0, shot: InteriorShot? = nil) -> SCNScene {
        let scene = SCNScene()
        // Items are always placed inside the scanned outline (no furniture behind a wall).
        let proposal = original?.placed(in: plan)
        // Interior: dark neutral background — a bright "sky" seen through a corner gap makes the image AI invent windows.
        scene.background.contents = mode == .interior ? UIColor(white: 0.18, alpha: 1) : UIColor(red: 0.90, green: 0.90, blue: 0.89, alpha: 1)
        scene.lightingEnvironment.contents = UIColor(white: 0.6, alpha: 1)
        scene.lightingEnvironment.intensity = mode == .interior ? 0.55 : 0.8
        let palette = proposal?.palette.compactMap { Color(hex: $0) }.map { UIColor($0) } ?? []
        let wallColor = UIColor(hexString: proposal?.walls.color ?? "") ?? palette.first ?? UIColor(red: 0.93, green: 0.91, blue: 0.87, alpha: 1)
        let floorBase = UIColor(hexString: proposal?.floor.color ?? "") ?? (palette.count > 1 ? palette[1] : UIColor(red: 0.74, green: 0.60, blue: 0.45, alpha: 1))
        let ceilingColor = UIColor(hexString: proposal?.ceiling.color ?? "") ?? UIColor(white: 0.97, alpha: 1)
        let accent = palette.count > 3 ? palette[3] : UIColor(Theme.orange)

        // Floor with wooden planks
        let b = plan.bounds
        let outline = plan.floorPolygon.count >= 3 ? plan.floorPolygon : [PlanPoint(x: b.minX, y: b.minY), PlanPoint(x: b.maxX, y: b.minY), PlanPoint(x: b.maxX, y: b.maxY), PlanPoint(x: b.minX, y: b.maxY)]
        let path = UIBezierPath()
        path.move(to: CGPoint(x: outline[0].x, y: outline[0].y))
        for point in outline.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
        path.close()
        path.flatness = 0.01
        let floorShape = SCNShape(path: path, extrusionDepth: 0.04)
        let floorMaterial = material(.white, roughness: 0.55)
        // The floor of the concept: porcelain tiles (bathroom, kitchen, stone) or wooden planks — the photo AI keeps what it sees.
        let tiledFloor = DrawingsPDF.isTiledFloor(RoomKind.detect(plan: plan, proposal: proposal), proposal?.floor)
        floorMaterial.diffuse.contents = tiledFloor ? tileTexture(base: floorBase) : woodTexture(base: floorBase)
        floorMaterial.diffuse.wrapS = .repeat; floorMaterial.diffuse.wrapT = .repeat
        // SCNShape maps the texture once over the whole floor: repeat it so one texture ≈ 1.6 m of planks (≈ 20 cm wide)
        // or 2.4 m of tiles (4 × 600 mm).
        let tiles = Float(max(1, max(b.maxX - b.minX, b.maxY - b.minY) / (tiledFloor ? 2.4 : 1.6)))
        floorMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(tiles, tiles, 1)
        floorShape.materials = [floorMaterial]
        let floor = SCNNode(geometry: floorShape)
        floor.eulerAngles.x = .pi / 2
        scene.rootNode.addChildNode(floor)

        // Ceiling (interior view only)
        let wallHeight = CGFloat(max(2.4, min(plan.ceilingHeight, 3.5)))
        if mode == .interior {
            let ceilingShape = SCNShape(path: path, extrusionDepth: 0.02)
            ceilingShape.materials = [material(ceilingColor, roughness: 1)]
            let ceiling = SCNNode(geometry: ceilingShape)
            ceiling.eulerAngles.x = .pi / 2
            ceiling.position.y = Float(wallHeight + 0.02)
            scene.rootNode.addChildNode(ceiling)
        }

        // Walls, skirting, doors, windows
        let height = mode == .interior ? wallHeight : wallHeight * (mode == .overhead ? 0.4 : 0.45)
        let wallMaterial = material(wallColor, roughness: 0.95)
        wallMaterial.normal.contents = plasterNormal // subtle plaster relief, visible in raking light
        wallMaterial.normal.intensity = 0.25
        wallMaterial.normal.wrapS = .repeat; wallMaterial.normal.wrapT = .repeat
        wallMaterial.normal.contentsTransform = SCNMatrix4MakeScale(4, 4, 1)
        let skirting = material(UIColor(white: 0.96, alpha: 1), roughness: 0.6)
        // The scanned line is the inner face of the wall: the wall goes outward with mitred corners (`WallBody`), the same
        // as on the drawings, so furniture stands against the wall and not inside it. Doors and windows are real
        // openings with reveals; the glass and the door leaf sit inside the wall.
        let body = WallBody(plan: plan)
        func prism(_ polygon: [PlanPoint], from bottom: CGFloat, to top: CGFloat, _ materialValue: SCNMaterial) {
            guard top - bottom > 0.005, polygon.count >= 3 else { return }
            let path = UIBezierPath()
            path.move(to: CGPoint(x: polygon[0].x, y: polygon[0].y))
            for point in polygon.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            path.close()
            let shape = SCNShape(path: path, extrusionDepth: top - bottom)
            shape.materials = [materialValue]
            let node = SCNNode(geometry: shape)
            node.eulerAngles.x = .pi / 2
            node.position.y = Float((bottom + top) / 2)
            scene.rootNode.addChildNode(node)
        }
        /// A band along the inner face of a wall, `depth` metres into the room.
        func band(_ a: PlanPoint, _ b: PlanPoint, outward: PlanPoint, depth: Double, from bottom: CGFloat, to top: CGFloat, _ materialValue: SCNMaterial) {
            let inward = outward * -depth
            prism([a, b, b + inward, a + inward], from: bottom, to: top, materialValue)
        }
        /// A slab inside the wall thickness, between `near` and `far` (0 — inner face, 1 — outer face; negative — into the room).
        func slab(_ gap: WallBody.Gap, near: Double, far: Double, from bottom: CGFloat, to top: CGFloat, _ materialValue: SCNMaterial) {
            let a = gap.outward * (gap.thickness * near), b = gap.outward * (gap.thickness * far)
            prism([gap.innerStart + a, gap.innerEnd + a, gap.innerEnd + b, gap.innerStart + b], from: bottom, to: top, materialValue)
        }
        let cornice = material(ceilingColor, roughness: 0.9)
        for piece in body.pieces {
            prism(piece.polygon, from: 0, to: height, wallMaterial)
            band(piece.innerStart, piece.innerEnd, outward: piece.outward, depth: 0.015, from: 0, to: 0.08, skirting)
            if mode == .interior { band(piece.innerStart, piece.innerEnd, outward: piece.outward, depth: 0.03, from: height - 0.06, to: height, cornice) }
        }
        let glass = material(UIColor(red: 0.80, green: 0.90, blue: 1.0, alpha: 1), roughness: 0.05)
        glass.emission.contents = UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 1)
        glass.emission.intensity = 0.8
        let frame = material(UIColor(white: 0.98, alpha: 1), roughness: 0.5)
        let doorMaterial = material(UIColor(red: 0.62, green: 0.48, blue: 0.34, alpha: 1), roughness: 0.55)
        for gap in body.gaps {
            let opening = gap.opening
            let top: CGFloat
            switch opening.kind {
            case .window:
                // Sill height as scanned (French windows start low), 0.85 m when the scan did not say.
                let sill = min(CGFloat(max(0, opening.elevation ?? 0.85)), height - 0.15)
                top = min(opening.height > 0.3 ? sill + CGFloat(opening.height) : 2.2, height - 0.1)
                prism(gap.polygon, from: 0, to: sill, wallMaterial)
                slab(gap, near: 0.45, far: 0.55, from: sill, to: top, glass)
                // Window board in front of the glass; a French window down to the floor has none.
                if sill > 0.1 { slab(gap, near: -0.35, far: 0.45, from: sill - 0.03, to: sill, frame) }
                band(gap.innerStart, gap.innerEnd, outward: gap.outward, depth: 0.015, from: 0, to: 0.08, skirting)
            case .door:
                top = min(opening.height > 1.5 ? CGFloat(opening.height) : 2.05, height - 0.05)
                slab(gap, near: 0.05, far: 0.3, from: 0, to: top, doorMaterial)
            case .opening:
                top = min(opening.height > 1.5 ? CGFloat(opening.height) : 2.1, height - 0.05)
            case .wall:
                continue
            }
            prism(gap.polygon, from: top, to: height, wallMaterial)
            if mode == .interior { band(gap.innerStart, gap.innerEnd, outward: gap.outward, depth: 0.03, from: height - 0.06, to: height, cornice) }
        }

        // Furniture
        if let proposal {
            let separateMirror = proposal.furniture.contains { $0.model == "mirror" }
            for (index, item) in proposal.furniture.enumerated() {
                let baseColor = palette.count > 2 ? palette[2 + index % max(1, palette.count - 2)] : UIColor(FurnitureStyle.color(item.model))
                let node = furniture(kind: item.kind, name: item.name, width: CGFloat(max(0.03, item.width)), depth: CGFloat(max(0.03, item.depth)), color: baseColor, accent: accent, ceiling: wallHeight, withMirror: !separateMirror)
                node.position = SCNVector3(Float(item.x), 0.02, Float(item.y))
                node.eulerAngles.y = -Float(item.rotation * .pi / 180)
                scene.rootNode.addChildNode(node)
            }
        } else {
            for object in plan.objects {
                let node = furniture(kind: "storage", name: object.name, width: CGFloat(max(0.2, object.width)), depth: CGFloat(max(0.2, object.depth)), color: UIColor(white: 0.75, alpha: 1), accent: accent)
                node.position = SCNVector3(Float(object.center.x), 0.02, Float(object.center.y))
                node.eulerAngles.y = -Float(object.rotation)
                scene.rootNode.addChildNode(node)
            }
        }

        // Lights: soft ambient, sun through the windows, warm ceiling lights
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = mode == .interior ? 150 : 300
        ambient.light?.color = UIColor(red: 1, green: 0.97, blue: 0.93, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional; sun.light?.intensity = mode == .interior ? 500 : 650
        sun.light?.castsShadow = true; sun.light?.shadowRadius = 8; sun.light?.shadowSampleCount = 8
        sun.light?.shadowColor = UIColor.black.withAlphaComponent(0.3)
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(sun)
        let centerX = (b.minX + b.maxX) / 2, centerZ = (b.minY + b.maxY) / 2
        if mode == .interior {
            // Same grid of ceiling spotlights as on the ceiling drawing: soft shadows from every fixture.
            // Total light depends on the room size, so a small bathroom is not burnt out.
            let spacing = 1.2
            var spots = 0
            do {
                var x = b.minX + spacing / 2
                while x < b.maxX { var z = b.minY + spacing / 2; while z < b.maxY { if pointInPolygon(PlanPoint(x: x, y: z), outline) { spots += 1 }; z += spacing }; x += spacing }
            }
            let spotIntensity = CGFloat(min(170, max(70, plan.area * 32 / Double(max(1, spots)))))
            var x = b.minX + spacing / 2
            while x < b.maxX {
                var z = b.minY + spacing / 2
                while z < b.maxY {
                    if pointInPolygon(PlanPoint(x: x, y: z), outline) {
                        let lamp = SCNNode(); lamp.light = SCNLight(); lamp.light?.type = .spot; lamp.light?.intensity = spotIntensity
                        lamp.light?.spotInnerAngle = 30; lamp.light?.spotOuterAngle = 95
                        lamp.light?.color = UIColor(red: 1, green: 0.93, blue: 0.82, alpha: 1)
                        lamp.light?.attenuationStartDistance = 0.4; lamp.light?.attenuationEndDistance = 5
                        lamp.light?.castsShadow = true; lamp.light?.shadowRadius = 10; lamp.light?.shadowSampleCount = 6
                        lamp.light?.shadowColor = UIColor.black.withAlphaComponent(0.28)
                        lamp.position = SCNVector3(Float(x), Float(wallHeight - 0.05), Float(z))
                        lamp.eulerAngles.x = -.pi / 2
                        scene.rootNode.addChildNode(lamp)
                        let disc = cylinder(0.045, 0.012, material(.white, roughness: 1), at: SCNVector3(Float(x), Float(wallHeight - 0.004), Float(z)))
                        disc.geometry?.firstMaterial?.emission.contents = UIColor.white
                        scene.rootNode.addChildNode(disc)
                    }
                    z += spacing
                }
                x += spacing
            }
            sun.light?.intensity = plan.windows.isEmpty ? 60 : 450 // no daylight in a room without windows
            ambient.light?.intensity = 140
        }

        // Camera
        let camera = SCNNode()
        camera.name = "camera"
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.05
        camera.camera?.zFar = 200
        camera.camera?.wantsHDR = true
        camera.camera?.bloomIntensity = mode == .interior ? 0 : 0.1 // bloom made small rooms milky white
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = 0
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 1.1 // contact shadows in corners and under furniture
        camera.camera?.screenSpaceAmbientOcclusionRadius = 0.35
        camera.camera?.vignettingIntensity = mode == .interior ? 0.25 : 0
        if mode == .interior, let shot {
            // Exact shot computed from the real plan and furniture.
            camera.camera?.fieldOfView = plan.area < 8 ? 78 : (plan.area < 16 ? 70 : 64)
            camera.position = SCNVector3(Float(shot.eye.x), 1.45, Float(shot.eye.y))
            camera.look(at: SCNVector3(Float(shot.target.x), 1.0, Float(shot.target.y)))
        } else if mode == .interior {
            // Eye level, in the corner from which most of the room is visible.
            camera.camera?.fieldOfView = 72
            let corners = [PlanPoint(x: b.minX, y: b.minY), PlanPoint(x: b.maxX, y: b.minY), PlanPoint(x: b.maxX, y: b.maxY), PlanPoint(x: b.minX, y: b.maxY)]
            let candidates = corners.map { PlanPoint(x: $0.x + (centerX - $0.x) * 0.18, y: $0.y + (centerZ - $0.y) * 0.18) }
                .filter { pointInPolygon($0, outline) }
            let ordered = candidates.sorted { hypot($0.x - centerX, $0.y - centerZ) > hypot($1.x - centerX, $1.y - centerZ) }
            let eye = ordered.isEmpty ? PlanPoint(x: centerX, y: centerZ + 0.5) : ordered[abs(viewpoint) % ordered.count]
            let target = PlanPoint(x: centerX + (centerX - eye.x) * 0.6, y: centerZ + (centerZ - eye.y) * 0.6)
            camera.position = SCNVector3(Float(eye.x), 1.55, Float(eye.y))
            camera.look(at: SCNVector3(Float(target.x), 1.1, Float(target.y)))
        } else if mode == .overhead {
            // Straight top view, like a furnished 3D floor plan.
            camera.camera?.fieldOfView = 40
            let size = Float(max(b.maxX - b.minX, b.maxY - b.minY, 2))
            camera.position = SCNVector3(Float(centerX), size * 1.45 + 2, Float(centerZ) + 0.001)
            camera.look(at: SCNVector3(Float(centerX), 0, Float(centerZ)))
        } else {
            camera.camera?.fieldOfView = 50
            let size = Float(max(b.maxX - b.minX, b.maxY - b.minY, 2))
            camera.position = SCNVector3(Float(centerX) + size * 0.55, size * 1.05, Float(centerZ) + size * 0.95)
            camera.look(at: SCNVector3(Float(centerX), 0, Float(centerZ)))
        }
        scene.rootNode.addChildNode(camera)
        return scene
    }
}

extension Room3DBuilder {
    /// Off-screen render of any view (used as the base for FLUX and for the presentation).
    /// Auto-exposure: the frame is measured and re-exposed until it is neither burnt out nor too dark.
    static func snapshot(plan: FloorPlan, proposal: DesignProposal?, mode: Room3DViewMode, viewpoint: Int = 0, shot: InteriorShot? = nil, size: CGSize = CGSize(width: 1536, height: 1152), autoExposure: Bool = true) -> UIImage? {
        let built = Self.scene(plan: plan, proposal: proposal, mode: mode, viewpoint: viewpoint, shot: shot)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = built
        let cameraNode = built.rootNode.childNode(withName: "camera", recursively: false)
        renderer.pointOfView = cameraNode
        renderer.autoenablesDefaultLighting = false
        if autoExposure, let camera = cameraNode?.camera {
            var offset = Double(camera.exposureOffset)
            let interior = mode == .interior
            for _ in 0..<5 {
                let probe = renderer.snapshot(atTime: 0, with: CGSize(width: 320, height: 240), antialiasingMode: .none)
                guard let stats = RenderQuality.stats(probe, central: !interior) else { break }
                var delta = 0.0
                if stats.clipped > (interior ? 0.03 : 0.04) || stats.mean > (interior ? 0.66 : 0.72) {
                    // Display values ≈ linear^(1/2.2): convert the brightness ratio into exposure stops.
                    delta = -max(0.6, 2.2 * log2(max(stats.mean, 0.5) / 0.46))
                } else if interior && stats.mean < 0.3 {
                    delta = min(2, 2.2 * log2(0.44 / max(0.04, stats.mean)))
                }
                if abs(delta) < 0.1 { break }
                offset = min(3, max(-7, offset + delta))
                camera.exposureOffset = CGFloat(offset)
            }
        }
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    /// Real camera shots of THIS room, chosen by its type: from the entrance, at the main zones and from the far corner.
    /// The camera never stands inside furniture or a wall.
    static func interiorShots(plan: FloorPlan, proposal original: DesignProposal?) -> [InteriorShot] {
        let proposal = original?.placed(in: plan)
        let room = RoomKind.detect(plan: plan, proposal: proposal)
        let b = plan.bounds
        let center = PlanPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
        let items = (proposal?.furniture ?? []).filter { !$0.isMounted }
        let clearance = plan.area < 8 ? 0.2 : 0.35
        func free(_ p: PlanPoint, relaxed: Bool = false) -> Bool {
            let probes = [p, PlanPoint(x: p.x + clearance, y: p.y), PlanPoint(x: p.x - clearance, y: p.y), PlanPoint(x: p.x, y: p.y + clearance), PlanPoint(x: p.x, y: p.y - clearance)]
            guard probes.allSatisfy({ plan.contains($0) }) else { return false }
            return relaxed || !items.contains { $0.covers(p, margin: 0.25) }
        }
        /// Nearest free standing point to the wished one.
        func place(_ wish: PlanPoint) -> PlanPoint {
            if free(wish) { return wish }
            var best: PlanPoint?
            var bestDistance = Double.infinity
            for relaxed in [false, true] {
                var x = b.minX
                while x <= b.maxX {
                    var y = b.minY
                    while y <= b.maxY {
                        let p = PlanPoint(x: x, y: y)
                        let d = p.distance(to: wish)
                        if d < bestDistance, free(p, relaxed: relaxed) { best = p; bestDistance = d }
                        y += 0.1
                    }
                    x += 0.1
                }
                if best != nil { break }
            }
            return best ?? center
        }
        func centroid(_ list: [DesignFurniture]) -> PlanPoint? {
            guard !list.isEmpty else { return nil }
            return PlanPoint(x: list.map(\.x).reduce(0, +) / Double(list.count), y: list.map(\.y).reduce(0, +) / Double(list.count))
        }
        let size = max(b.maxX - b.minX, b.maxY - b.minY)
        /// Camera standing opposite the target, far enough to frame it.
        func facing(_ target: PlanPoint, distance: Double) -> PlanPoint {
            var dx = center.x - target.x, dy = center.y - target.y
            let length = hypot(dx, dy)
            if length < 0.2 { dx = 0; dy = 1 } else { dx /= length; dy /= length }
            return place(PlanPoint(x: target.x + dx * distance, y: target.y + dy * distance))
        }
        var shots: [InteriorShot] = []
        func add(_ title: String, eye: PlanPoint, target: PlanPoint) {
            // Skip a shot that repeats one we already have (same place, same direction).
            let direction = atan2(target.y - eye.y, target.x - eye.x)
            let duplicate = shots.contains { other in
                let otherDirection = atan2(other.target.y - other.eye.y, other.target.x - other.eye.x)
                var delta = abs(direction - otherDirection); if delta > .pi { delta = 2 * .pi - delta }
                return other.eye.distance(to: eye) < 0.5 && delta < 0.5
            }
            if !duplicate && eye.distance(to: target) > 0.4 { shots.append(InteriorShot(title: title, eye: eye, target: target)) }
        }

        if let door = plan.doors.first(where: { $0.kind == .door }) ?? plan.doors.first {
            let doorMid = PlanPoint(x: (door.start.x + door.end.x) / 2, y: (door.start.y + door.end.y) / 2)
            let dx = center.x - doorMid.x, dy = center.y - doorMid.y, length = max(0.001, hypot(dx, dy))
            let eye = place(PlanPoint(x: doorMid.x + dx / length * 0.45, y: doorMid.y + dy / length * 0.45))
            add("Вид от входа", eye: eye, target: PlanPoint(x: center.x + (center.x - eye.x) * 0.6, y: center.y + (center.y - eye.y) * 0.6))
        }
        let all = proposal?.furniture ?? []
        let near = min(2.6, max(1.2, size * 0.45))
        switch room {
        case .bathroom:
            if let wet = centroid(all.filter { $0.model == "shower" || $0.model == "bathtub" }) {
                add(all.contains { $0.model == "bathtub" } ? "Зона ванны" : "Душевая зона", eye: facing(wet, distance: near), target: wet)
            }
            if let sink = centroid(all.filter { $0.model == "sink" }) { add("Зона умывальника", eye: facing(sink, distance: near), target: sink) }
        case .kitchen, .living:
            if let kitchen = centroid(all.filter { $0.model == "kitchen" }) { add("Кухня", eye: facing(kitchen, distance: min(3.2, max(2.0, size * 0.45))), target: kitchen) }
            if let seating = centroid(all.filter { $0.model == "sofa" || $0.model == "tv" }) { add("Гостиная зона", eye: facing(seating, distance: min(3.5, max(2.2, size * 0.5))), target: seating) }
        case .bedroom, .kids:
            if let bed = centroid(all.filter { $0.model == "bed" }) { add("Спальная зона", eye: facing(bed, distance: min(3.5, max(2.2, size * 0.5))), target: bed) }
        case .hall, .office, .garage, .shop, .cafe, .warehouse, .other:
            if let main = centroid(all.filter { ["storage", "desk", "table"].contains($0.model) }) { add(room == .office ? "Рабочая зона" : "Системы хранения", eye: facing(main, distance: min(3, max(1.8, size * 0.45))), target: main) }
        }
        // Far corner view as a general shot.
        let corners = [PlanPoint(x: b.minX, y: b.minY), PlanPoint(x: b.maxX, y: b.minY), PlanPoint(x: b.maxX, y: b.maxY), PlanPoint(x: b.minX, y: b.maxY)]
            .map { place(PlanPoint(x: $0.x + (center.x - $0.x) * 0.12, y: $0.y + (center.y - $0.y) * 0.12)) }
        if let corner = corners.max(by: { a, c in (shots.map { a.distance(to: $0.eye) }.min() ?? 0) < (shots.map { c.distance(to: $0.eye) }.min() ?? 0) }) {
            add("Общий вид", eye: corner, target: PlanPoint(x: center.x + (center.x - corner.x) * 0.5, y: center.y + (center.y - corner.y) * 0.5))
        }
        // A studio set has four views: one more from the corner farthest from the others.
        if shots.count < 4, let corner = corners.max(by: { a, c in (shots.map { a.distance(to: $0.eye) }.min() ?? 0) < (shots.map { c.distance(to: $0.eye) }.min() ?? 0) }) {
            add("Вид из угла", eye: corner, target: PlanPoint(x: center.x + (center.x - corner.x) * 0.5, y: center.y + (center.y - corner.y) * 0.5))
        }
        return shots
    }

    /// Prompt that turns the exact 3D render of the room into a photo WITHOUT changing the layout.
    static func photoPrompt(proposal: DesignProposal?, itemsEnglish: String, plan: FloorPlan? = nil) -> String {
        let furniture = proposal?.furniture ?? []
        let room = RoomKind.detect(plan: plan, proposal: proposal)
        let hasKitchen = furniture.contains { $0.model == "kitchen" }
        var parts = ["Turn THIS exact 3D render of a \(room.english) into a high-end architectural interior visualisation, the quality a top interior design and architecture studio delivers to its client (Corona Renderer / V-Ray, magazine cover level). The reference is a 1:1 model of a laser-scanned real room: its geometry is ground truth and must not change."]
        parts.append(room.rulesEnglish)
        parts.append("GEOMETRY — keep pixel-accurate: the camera position, height, angle and focal length; every wall, corner, edge, wall length, ceiling height and ceiling line; every window and door opening with its exact size and place; the position, size, shape and orientation of every piece of furniture and equipment. Do not add, remove, move, resize, bend or straighten anything; no extra walls, niches, columns, beams, windows, doors or furniture. Vertical lines stay perfectly vertical (two-point perspective), no wide-angle or fisheye distortion, no crop or zoom.")
        parts.append("RENDER QUALITY: physically based materials with real detail — wood grain and plank joints, stone and tile veining with thin grout lines, fabric weave and soft folds, brushed and polished metal, glass with true reflections; physically correct global illumination; soft natural daylight only through the existing windows plus warm 2700–3000 K practical lights (pendants, wall lights, hidden LED lines) where the fittings are; soft contact shadows and ambient occlusion in every corner and under every object; subtle reflections on glossy surfaces; balanced exposure with detail in highlights and shadows, nothing burnt out or crushed; neutral white balance, true-to-life colours; tack-sharp focus across the room.")
        if let plan {
            if plan.windows.isEmpty {
                parts.append("IMPORTANT: this room has NO windows. Do not add any window, glazing, balcony door, curtains or view outside. All walls without openings stay solid walls. Light comes only from ceiling spotlights, wall lights and LED strips.")
            } else {
                parts.append("The room has exactly \(plan.windows.count) window(s), only where they are in the render; do not add more.")
            }
            parts.append("Exactly \(plan.doors.count) door opening(s) as shown; do not add doors. Ceiling height \(String(format: "%.2f", plan.ceilingHeight)) m.")
        }
        if !itemsEnglish.isEmpty { parts.append("Only upgrade realism: replace each simplified object with the real detailed object it represents (\(itemsEnglish)), same size and place, with real materials, textures, seams and soft realistic shadows.") }
        if hasKitchen { parts.append("Kitchen units stay exactly where they are; give them real fronts with handles, a stone countertop, cooktop and sink within the same footprint.") }
        parts.append(room == .bathroom ? "Small details only on existing surfaces (soap dispenser, folded towels, a small plant); nothing else." : "Small decor only on existing surfaces (books, vases, plants, cushions); no new furniture.")
        if let proposal {
            if !proposal.finishesEnglish.isEmpty { parts.append(proposal.finishesEnglish) }
            if !proposal.palette.isEmpty { parts.append("Colour palette: \(proposal.palette.joined(separator: ", ")).") }
            if !proposal.style.isEmpty { parts.append("Style: \(proposal.style).") }
        }
        parts.append("Styled and finished like a professional architectural photo shoot: everything clean, straight and complete, tasteful styling, no clutter. Ultra detailed, no text, no watermark, no people, no CGI look.")
        return parts.joined(separator: " ")
    }
}

final class Room3DController {
    weak var view: SCNView?
    func snapshot() -> UIImage? { view?.snapshot() }
}

struct Room3DSceneView: UIViewRepresentable {
    let scene: SCNScene
    let controller: Room3DController
    var mode: Room3DViewMode = .interior
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = mode == .interior ? .fly : .orbitTurntable
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        controller.view = view
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene {
            view.scene = scene
            view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
            view.defaultCameraController.interactionMode = mode == .interior ? .fly : .orbitTurntable
        }
    }
}

struct Room3DView: View {
    @EnvironmentObject private var store: AppStore
    let plan: FloorPlan
    let proposal: DesignProposal?
    @State private var scene: SCNScene?
    @State private var controller = Room3DController()
    @State private var shareFile: SharedFile?
    @State private var mode: Room3DViewMode = .interior

    var body: some View {
        ZStack(alignment: .bottom) {
            if let scene { Room3DSceneView(scene: scene, controller: controller, mode: mode).ignoresSafeArea(edges: .bottom) }
            else { ProgressView().tint(Theme.orange).frame(maxWidth: .infinity, maxHeight: .infinity) }
            VStack(spacing: 10) {
                Picker("Вид", selection: $mode) { ForEach(Room3DViewMode.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).frame(maxWidth: 260)
                    .padding(6).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                Text(mode == .interior ? "Смотрите по сторонам пальцем, шагайте двумя пальцами" : "Вращайте одним пальцем, двигайте двумя, приближайте щипком").font(.caption).foregroundStyle(Theme.ink.opacity(0.85))
                    .padding(.horizontal, 12).padding(.vertical, 7).background(.ultraThinMaterial, in: Capsule())
                HStack(spacing: 10) {
                    Button { scene = Room3DBuilder.scene(plan: plan, proposal: proposal, mode: mode) } label: { SecondaryActionLabel(title: "Сбросить вид", icon: "arrow.counterclockwise") }
                }
                .buttonStyle(PremiumPressStyle())
            }
            .padding(16)
            .padding(.bottom, 70)
            .padding(.top, 8)
            .frame(maxHeight: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(proposal?.title ?? plan.name).helperScreen(proposal?.title ?? plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareFile) { file in ActivityShareSheet(items: [file.url]) }
        .task { if scene == nil { scene = Room3DBuilder.scene(plan: plan, proposal: proposal, mode: mode); store.track("room_3d_open") } }
        .onChange(of: mode) { _, newMode in scene = Room3DBuilder.scene(plan: plan, proposal: proposal, mode: newMode) }
    }

    private func share() {
        guard let image = controller.snapshot(), let data = BrandGraphics.watermarked(image).jpegData(compressionQuality: 0.9) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("3D-\(plan.name)-\(Int(Date().timeIntervalSince1970)).jpg")
        if (try? data.write(to: url, options: .atomic)) != nil { shareFile = SharedFile(url: url) }
    }
}

// MARK: - Free on-device illustration with Apple Image Playground (iOS 18.1+, Apple Intelligence iPhones)

struct ApplePlaygroundButton: View {
    let prompt: String
    let onImage: (UIImage) -> Void

    var body: some View {
        #if canImport(ImagePlayground)
        if #available(iOS 18.1, *) {
            PlaygroundButtonImpl(prompt: prompt, onImage: onImage)
        }
        #endif
    }
}

#if canImport(ImagePlayground)
@available(iOS 18.1, *)
private struct PlaygroundButtonImpl: View {
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    let prompt: String
    let onImage: (UIImage) -> Void
    @State private var isPresented = false

    var body: some View {
        if supportsImagePlayground {
            Button { isPresented = true } label: { SecondaryActionLabel(title: "Иллюстрация от Apple (бесплатно)", icon: "paintpalette.fill") }
                .buttonStyle(PremiumPressStyle())
                .imagePlaygroundSheet(isPresented: $isPresented, concepts: [.text(String(prompt.prefix(300)))]) { url in
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) { onImage(image) }
                }
        }
    }
}
#endif

/// Finished photorealistic render: view, share, keep in the project photo diary.
struct RenderResultView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let title: String
    @State private var shareFile: SharedFile?
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button { share() } label: { SecondaryActionLabel(title: "Поделиться", icon: "square.and.arrow.up") }.buttonStyle(PremiumPressStyle())
                Button {
                    if (try? store.addProjectPhoto(image, caption: "Визуализация: \(title)")) != nil { saved = true; Haptics.success() }
                } label: { SecondaryActionLabel(title: saved ? "Сохранено в фото‑дневник" : "В фото‑дневник проекта", icon: saved ? "checkmark" : "folder.badge.plus") }
                .buttonStyle(PremiumPressStyle()).disabled(saved)
                InfoNote(text: "Фото создано ИИ по 3D‑макету. Материалы и детали — художественные; размеры и расстановка соответствуют плану.")
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Фотореализм").helperScreen("Фотореализм")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        .sheet(item: $shareFile) { file in ActivityShareSheet(items: [file.url]) }
    }

    private func share() {
        guard let data = BrandGraphics.watermarked(image).jpegData(compressionQuality: 0.92) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Визуализация-\(Brand.name)-\(Int(Date().timeIntervalSince1970)).jpg")
        if (try? data.write(to: url, options: .atomic)) != nil { shareFile = SharedFile(url: url) }
    }
}
