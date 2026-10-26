import Foundation
import CoreGraphics

/// M8b's appended, dry-perch artwork in top-down logical 48-unit coordinates.
/// These are presentation poses; they grant no feeding, social or sound ability.
public enum M8CommonArtGeometry {
    public static let species: [SpeciesID] = [
        .treeSparrow, .lightVentedBulbul, .redWhiskeredBulbul, .chineseBlackbird,
        .spottedDove, .swinhoesWhiteEye, .redBilledLeiothrix, .azureWingedMagpie
    ]

    public static func frameNames(for species: SpeciesID) -> [String] {
        // All eight M8b species already own the ten PoseClip foundation frames.
        // The order here is the actual append order, never a replacement pack.
        signatureFrameNames(for: species)
    }

    /// Preparation, emphasis, recovery, settled pose, in playback order.
    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        switch species {
        case .treeSparrow: return ["fluffReady", "fluffPeck", "fluffLook", "fluffSettle"]
        case .lightVentedBulbul: return ["shoulderReady", "shoulderReach", "shoulderSmooth", "shoulderSettle"]
        case .redWhiskeredBulbul: return ["callPoise", "callOpen", "callClose", "callSettle"]
        case .chineseBlackbird: return ["perchReady", "perchTap", "perchLift", "perchSettle"]
        case .spottedDove: return ["preenPoise", "preenShoulder", "preenSmooth", "preenSettle"]
        case .swinhoesWhiteEye: return ["gleanReady", "gleanReach", "gleanRecoil", "gleanSettle"]
        case .redBilledLeiothrix: return ["dipReady", "dipLow", "dipTurn", "dipSettle"]
        case .azureWingedMagpie: return ["balanceReady", "balanceReach", "balanceTurn", "balanceSettle"]
        default: return []
        }
    }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, tailWidth: Double

        /// Independently authored normalized torso contours. The dove's broad
        /// low flank and magpie's narrow keel do not use the small-bird outline.
        public let bodyOutline: [(Double, Double)]
    }

    public static func anatomy(for species: SpeciesID) -> Anatomy? {
        switch species {
        case .treeSparrow:
            return Anatomy(width: 17, headWidth: 9, headHeight: 8, billLength: 3, tailWidth: 4,
                bodyOutline: [(0.08,0.20),(0.30,0.02),(0.64,0),(0.88,0.15),(1,0.44),
                              (0.91,0.79),(0.68,0.98),(0.33,1),(0.05,0.77),(0,0.46)])
        case .lightVentedBulbul:
            return Anatomy(width: 19, headWidth: 8, headHeight: 7, billLength: 4, tailWidth: 4,
                bodyOutline: [(0.08,0.22),(0.32,0.04),(0.66,0),(0.88,0.16),(1,0.40),
                              (0.93,0.71),(0.74,0.96),(0.43,1),(0.13,0.81),(0,0.52)])
        case .redWhiskeredBulbul:
            return Anatomy(width: 17, headWidth: 7.5, headHeight: 7, billLength: 4, tailWidth: 4,
                bodyOutline: [(0.12,0.24),(0.35,0.02),(0.65,0),(0.90,0.19),(1,0.49),
                              (0.84,0.83),(0.67,1),(0.36,0.95),(0.08,0.71),(0,0.44)])
        case .chineseBlackbird:
            return Anatomy(width: 21, headWidth: 8, headHeight: 7, billLength: 4, tailWidth: 5,
                bodyOutline: [(0,0.41),(0.13,0.16),(0.40,0),(0.71,0.05),(0.94,0.26),
                              (1,0.58),(0.85,0.88),(0.60,1),(0.27,0.92),(0.05,0.71)])
        case .spottedDove:
            return Anatomy(width: 23, headWidth: 7, headHeight: 6, billLength: 3.5, tailWidth: 5,
                bodyOutline: [(0,0.44),(0.13,0.15),(0.39,0),(0.66,0.05),(0.88,0.26),
                              (1,0.52),(0.93,0.82),(0.68,1),(0.33,0.98),(0.08,0.79)])
        case .swinhoesWhiteEye:
            return Anatomy(width: 15, headWidth: 8.5, headHeight: 8, billLength: 2.2, tailWidth: 3.5,
                bodyOutline: [(0.07,0.19),(0.32,0),(0.67,0.03),(0.91,0.22),(1,0.53),
                              (0.84,0.84),(0.56,1),(0.25,0.92),(0,0.63)])
        case .redBilledLeiothrix:
            return Anatomy(width: 17, headWidth: 8, headHeight: 7, billLength: 4, tailWidth: 4,
                bodyOutline: [(0.03,0.28),(0.27,0.02),(0.58,0),(0.85,0.17),(1,0.46),
                              (0.91,0.77),(0.64,1),(0.32,0.96),(0.08,0.76),(0,0.53)])
        case .azureWingedMagpie:
            return Anatomy(width: 17, headWidth: 7.5, headHeight: 7, billLength: 4, tailWidth: 4,
                bodyOutline: [(0,0.40),(0.22,0.12),(0.57,0),(0.82,0.07),(1,0.30),
                              (0.96,0.59),(0.78,0.87),(0.50,1),(0.22,0.84),(0.03,0.62)])
        default: return nil
        }
    }

    public struct Pose {
        public let body: (y: Double, height: Double, lean: Double, fluff: Double)
        public let head: (x: Double, y: Double, pitch: Double)
        public let tail: (x: Double, y: Double)
        /// Local shoulder rise and primary sweep; never a whole-bird transform.
        public let shoulder, sweep: Double
        public let lookingBack: Bool
        /// Separation of the two authored mandibles; no sound event is emitted.
        public let gape: Double

        fileprivate init(_ body: (Double, Double, Double, Double),
                         _ head: (Double, Double, Double), _ tail: (Double, Double),
                         shoulder: Double = 0, sweep: Double = 0,
                         lookingBack: Bool = false, gape: Double = 0) {
            self.body = body; self.head = head; self.tail = tail
            self.shoulder = shoulder; self.sweep = sweep
            self.lookingBack = lookingBack; self.gape = gape
        }

        /// Reflect only the newly drawn head anatomy for a backward glance.
        /// Its crown remains above the eye instead of rotating upside down.
        public func headPoint(_ x: Double, _ y: Double) -> CGPoint {
            let xx = lookingBack ? -x : x
            return CGPoint(x: head.x + xx*cos(head.pitch) - y*sin(head.pitch),
                           y: head.y + xx*sin(head.pitch) + y*cos(head.pitch))
        }

        /// Vertex 1 is the upper mandible tip in both closed and open drawings.
        public func billVertices(anatomy: Anatomy) -> [(Double, Double)] {
            let root = anatomy.headWidth/2 - 0.5, tip = root + anatomy.billLength
            if gape > 0 {
                return [(root,-0.7),(tip,0.5-gape*0.25),(root,0.3)]
            }
            return [(root,-0.7),(tip,0.5),(tip-0.8,1.15),(root,1.3)]
        }

        public func lowerBillVertices(anatomy: Anatomy) -> [(Double, Double)] {
            guard gape > 0 else { return [] }
            let root = anatomy.headWidth/2 - 0.5
            return [(root,0.7),(root+anatomy.billLength-0.4,0.8+gape),(root,1.5)]
        }

        public func bodyPoint(_ u: Double, _ v: Double, anatomy: Anatomy) -> CGPoint {
            let width = anatomy.width + body.fluff
            return CGPoint(x: 34-anatomy.width-body.fluff/2 + u*width + body.lean*(1-v),
                           y: body.y + v*body.height)
        }
    }

    public static func beakAnchor(species: SpeciesID, frame: String) -> PoseClip.Anchor? {
        guard let a = anatomy(for: species), let p = pose(species: species, frame: frame) else { return nil }
        let vertex = p.billVertices(anatomy: a)[1]
        let tip = p.headPoint(vertex.0, vertex.1)
        return PoseClip.Anchor(Double(tip.x), Double(tip.y))
    }

    public static func pose(species: SpeciesID, frame: String) -> Pose? {
        switch species {
        case .treeSparrow:
            switch frame {
            case "fluffReady": return Pose((21.8,13.6,-0.3,2.2),(31.8,19.5,0.16),(11.6,39.3),shoulder:0.6,sweep:0.6)
            case "fluffPeck": return Pose((25.4,10.8,1.6,0.6),(34.3,29.5,0.92),(11,34.2),sweep:-0.5)
            case "fluffLook": return Pose((21.6,13.1,0.2,0.3),(33.1,17.6,-0.28),(12.2,38.4),shoulder:0.2)
            case "fluffSettle": return Pose((22.7,12.8,-0.2,0.7),(31.4,19.7,-0.08),(11.8,39.6),lookingBack:true)
            default: return nil
            }
        case .lightVentedBulbul:
            switch frame {
            case "shoulderReady": return Pose((21.9,12.7,0.3,0.2),(33.4,18.9,0.29),(6.6,40.8),shoulder:0.3)
            case "shoulderReach": return Pose((22.7,12.1,-0.7,0.6),(28.8,21.5,-0.58),(6.2,39.4),shoulder:1.2,sweep:0.8,lookingBack:true)
            case "shoulderSmooth": return Pose((23.2,11.9,-0.9,0.3),(27.6,23,-0.30),(6.8,39.8),shoulder:0.5,sweep:-0.6,lookingBack:true)
            case "shoulderSettle": return Pose((22.1,12.6,-0.1,0.4),(32.1,18.1,-0.09),(6.4,41.3),shoulder:0.1)
            default: return nil
            }
        case .redWhiskeredBulbul:
            switch frame {
            case "callPoise": return Pose((21.3,13.4,0.2,0.1),(32.3,16.7,-0.24),(5.8,41.8),shoulder:0.2)
            case "callOpen": return Pose((20.4,14.3,0.5,0.9),(33,14.7,-0.45),(6.7,42.6),shoulder:0.5,sweep:0.5,gape:1.7)
            case "callClose": return Pose((21.4,13.2,0.1,0.5),(32.4,16.1,-0.20),(6.1,42.1),shoulder:0.1,sweep:-0.3)
            case "callSettle": return Pose((22.3,12.6,-0.3,0.2),(31.7,18.6,0.06),(5.6,41.2),sweep:0.2)
            default: return nil
            }
        case .chineseBlackbird:
            switch frame {
            case "perchReady": return Pose((23.1,12.2,1.1,0),(34.4,22.6,0.39),(6.8,38.3),sweep:0.2)
            case "perchTap": return Pose((25.7,10.5,1.8,-0.1),(34.8,29.3,1.02),(5.7,33.5),shoulder:0.2,sweep:-0.8)
            case "perchLift": return Pose((20.6,14.1,0.4,0.1),(33.6,16.4,-0.27),(7.2,39.7),shoulder:0.4)
            case "perchSettle": return Pose((21.8,13.4,-0.2,0.3),(32.7,18.5,0.07),(6.5,41.4),sweep:0.3)
            default: return nil
            }
        case .spottedDove:
            switch frame {
            case "preenPoise": return Pose((22.2,12.8,-0.2,0.3),(31.1,18.4,-0.18),(5.8,41.8),shoulder:0.3,lookingBack:true)
            case "preenShoulder": return Pose((23,12.2,-0.5,0.7),(27.7,23.1,-0.64),(5.5,40.7),shoulder:1.4,sweep:0.6,lookingBack:true)
            case "preenSmooth": return Pose((23.4,11.9,-0.7,0.4),(26.5,24.2,-0.32),(6.1,41.1),shoulder:0.6,sweep:-0.9,lookingBack:true)
            case "preenSettle": return Pose((21.9,13,-0.1,0.2),(32,17.5,-0.16),(5.7,42.3),shoulder:0.1)
            default: return nil
            }
        case .swinhoesWhiteEye:
            switch frame {
            case "gleanReady": return Pose((23,11.7,0.4,0.4),(32.4,21,0.32),(11.7,38.4),shoulder:0.2)
            case "gleanReach": return Pose((23.7,11.1,1.2,0),(35,21.2,0.18),(11,35.6),sweep:-0.4)
            case "gleanRecoil": return Pose((22.1,12.5,-0.5,1),(31,18.5,-0.38),(12.1,39.1),shoulder:0.5,sweep:0.5)
            case "gleanSettle": return Pose((23.1,11.9,-0.1,0.6),(31.8,20.6,0.04),(11.4,38.9),sweep:0.1)
            default: return nil
            }
        case .redBilledLeiothrix:
            switch frame {
            case "dipReady": return Pose((22.7,12.1,0.5,0.2),(33.1,21.9,0.41),(9.3,39),shoulder:0.3)
            case "dipLow": return Pose((25.2,10.4,0.8,1.3),(33.5,26.5,0.65),(9.9,36.8),shoulder:0.5,sweep:0.7)
            case "dipTurn": return Pose((23.8,11.6,-0.6,0.8),(28.5,21.3,-0.16),(8.8,39.3),sweep:-0.4,lookingBack:true)
            case "dipSettle": return Pose((22.6,12.4,-0.2,0.4),(31.9,19.2,0.08),(9.1,40.4),shoulder:0.1)
            default: return nil
            }
        case .azureWingedMagpie:
            switch frame {
            case "balanceReady": return Pose((22.3,11.6,0.8,0),(33.5,20.2,0.24),(2.6,41.4),shoulder:0.2,sweep:0.3)
            case "balanceReach": return Pose((23.3,10.7,1.6,-0.1),(35,23,0.36),(3.8,33.8),shoulder:0.4,sweep:-1)
            case "balanceTurn": return Pose((22.6,11.4,-0.5,0.2),(29.1,19.5,-0.12),(2.7,38.7),shoulder:0.2,sweep:0.6,lookingBack:true)
            case "balanceSettle": return Pose((22.1,11.8,-0.1,0.3),(32,18.5,0.05),(2.3,43.8),sweep:0.1)
            default: return nil
            }
        default: return nil
        }
    }
}
