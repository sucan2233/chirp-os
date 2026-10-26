import Foundation
import CoreGraphics

/// Original M8a anatomy in the existing right-facing, top-down 48-unit canvas.
/// This describes new artwork only; it does not grant any behavior permission.
public enum M8PilotArtGeometry {
    public static let species: [SpeciesID] = [
        .greatTit, .orientalMagpie, .greatSpottedWoodpecker,
        .mallard, .littleEgret, .magpieRobin
    ]

    public static func frameNames(for species: SpeciesID) -> [String] {
        guard Self.species.contains(species) else { return [] }
        return (species == .magpieRobin ? [] : PoseClip.frameNames)
            + signatureFrameNames(for: species)
    }

    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        switch species {
        case .greatTit: return ["inspectLean", "inspectDown", "inspectLift", "inspectSettle"]
        case .orientalMagpie: return ["tailPoise", "tailBalance", "tailCounter", "tailSettle"]
        case .greatSpottedWoodpecker: return ["sideBrace", "sideDraw", "sideTap", "sideRecover"]
        case .mallard: return ["wingLook", "wingReach", "wingSmooth", "wingRecover"]
        case .littleEgret: return ["neckPoise", "neckReach", "neckObserve", "neckRecover"]
        case .magpieRobin: return ["tailReady", "tailLift", "tailPulse", "tailRecover"]
        default: return []
        }
    }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, tailWidth: Double

        public var billRoot: Double { headWidth / 2 - 0.5 }
        public var localBillTip: CGPoint { CGPoint(x: billRoot + billLength, y: 0.5) }

        /// The tip in this actual drawing polygon is also the anchor input.
        public func billVertices(flat: Bool) -> [(Double, Double)] {
            let tip = (Double(localBillTip.x), Double(localBillTip.y))
            if flat {
                return [(billRoot,-0.8),(tip.0-0.8,-0.4),tip,(tip.0-0.6,1.7),(billRoot,1.4)]
            }
            return [(billRoot,-0.7),tip,(billRoot,1.2)]
        }
    }

    public static func anatomy(for species: SpeciesID) -> Anatomy? {
        switch species {
        case .greatTit: return Anatomy(width: 17, headWidth: 8.5, headHeight: 8, billLength: 3, tailWidth: 3.5)
        case .orientalMagpie: return Anatomy(width: 18, headWidth: 8, headHeight: 7, billLength: 4, tailWidth: 4)
        case .greatSpottedWoodpecker: return Anatomy(width: 17, headWidth: 8, headHeight: 7, billLength: 7.5, tailWidth: 3.5)
        case .mallard: return Anatomy(width: 26, headWidth: 8, headHeight: 8, billLength: 5, tailWidth: 5)
        case .littleEgret: return Anatomy(width: 16, headWidth: 6.5, headHeight: 4.1, billLength: 8, tailWidth: 4)
        case .magpieRobin: return Anatomy(width: 17, headWidth: 8, headHeight: 7, billLength: 4, tailWidth: 4)
        default: return nil
        }
    }

    public struct Pose {
        /// Body top, height, shoulder shift and additional feather width.
        public let body: (y: Double, height: Double, lean: Double, fluff: Double)
        public let head: (x: Double, y: Double, pitch: Double)
        public let tail: (x: Double, y: Double)
        /// Raised wing amount; droop is separately authored for tail/preen poses.
        public let wing, droop: Double
        /// Egret's middle neck bend; independent of head and shoulder position.
        public let neck: (x: Double, y: Double)
        public let side: Bool

        init(_ body: (Double, Double, Double, Double),
             _ head: (Double, Double, Double), _ tail: (Double, Double),
             wing: Double = 0, droop: Double = 0,
             neck: (Double, Double) = (30, 17), side: Bool = false) {
            self.body = body; self.head = head; self.tail = tail
            self.wing = wing; self.droop = droop; self.neck = neck; self.side = side
        }

        public func headPoint(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: head.x + x * cos(head.pitch) - y * sin(head.pitch),
                    y: head.y + x * sin(head.pitch) + y * cos(head.pitch))
        }

        public func billTip(anatomy: Anatomy) -> CGPoint {
            let tip = anatomy.localBillTip
            return headPoint(Double(tip.x), Double(tip.y))
        }
    }

    /// Kept at the old cling art's two wall grips. The lower grip is also the
    /// renderer's (29,39) reference; no additional rotation or offset is needed.
    public static let sideUpperGrip = CGPoint(x: 29, y: 33)
    public static let sideLowerGrip = CGPoint(x: 29, y: 39)
    public static let sideTapContact = CGPoint(x: 29, y: 13.7)

    public static func beakAnchor(species: SpeciesID, frame: String) -> PoseClip.Anchor? {
        guard let anatomy = anatomy(for: species), let pose = pose(species: species, frame: frame) else { return nil }
        let tip = pose.billTip(anatomy: anatomy)
        return PoseClip.Anchor(Double(tip.x), Double(tip.y))
    }

    /// Every row is a separately authored pose. Core woodpecker poses are top
    /// perched; only its four signature rows use the existing wall grips.
    public static func pose(species: SpeciesID, frame: String) -> Pose? {
        switch species {
        case .greatTit:
            switch frame {
            case "lookNear": return Pose((22.5,13,0.5,0), (33.3,20.5,0.32), (8,40))
            case "lookFar": return Pose((21.5,13,0,0), (32.5,17.2,-0.20), (7.5,41))
            case "alertRise": return Pose((20.5,14,0.3,0), (33,15.5,-0.22), (8.5,41.5), wing: 0.08)
            case "alertHold": return Pose((19.5,15,0.6,-0.3), (33.4,14.2,-0.08), (9,42), wing: 0.15)
            case "alertRelax": return Pose((22,13,-0.3,0.5), (32,18.7,0.06), (7,40.5))
            case "restLower": return Pose((24,12,-0.7,1.0), (31,22.5,0.22), (7,39.5))
            case "restTuck": return Pose((24.5,12,-1,1.5), (26.5,25,2.52), (8,39))
            case "restWake": return Pose((22.7,12.5,0,0.7), (31.5,18,-0.30), (7.5,40.5), wing: 0.10)
            case "takeoffCrouch": return Pose((26,10.5,1.4,0.3), (34,24.8,0.20), (6.5,35.5), wing: 0.26)
            case "takeoffPush": return Pose((18.5,12.5,2,0), (34.5,16.5,-0.25), (6,33), wing: 1)
            case "inspectLean": return Pose((23,12,0.7,0), (34,23.5,0.38), (8,37.5))
            case "inspectDown": return Pose((25,10.8,1.5,0.2), (34.7,28.5,0.94), (7.5,33), droop: 0.8)
            case "inspectLift": return Pose((21.5,13,0.2,0), (33,17.5,-0.32), (8.5,36), wing: 0.07)
            case "inspectSettle": return Pose((22.8,12.5,-0.2,0.5), (32.4,19.7,0.12), (8,39.5), droop: 0.3)
            default: return nil
            }
        case .orientalMagpie:
            switch frame {
            case "lookNear": return Pose((22.5,12,0.8,0), (33.4,21,0.28), (2,43.5))
            case "lookFar": return Pose((21.5,12.5,0,0), (32.5,16.8,-0.18), (2.5,44.5))
            case "alertRise": return Pose((20,14,0.5,0), (33,15,-0.20), (3,45), wing: 0.07)
            case "alertHold": return Pose((19,15,0.8,-0.3), (33.5,13.5,-0.09), (3.5,45.5), wing: 0.13)
            case "alertRelax": return Pose((22,12.5,-0.4,0.5), (32,19,0.04), (2,43))
            case "restLower": return Pose((24,11.8,-0.7,0.9), (31,23,0.20), (2,42.5))
            case "restTuck": return Pose((24.5,11.5,-1.2,1.4), (26,25,2.62), (2.5,41.5))
            case "restWake": return Pose((22.5,12,0,0.6), (31.5,18,-0.28), (2,43.5), wing: 0.08)
            case "takeoffCrouch": return Pose((26,9.5,1.5,0.2), (34,24,0.15), (2,35), wing: 0.25)
            case "takeoffPush": return Pose((18,12,2.3,0), (34.5,16,-0.24), (2,31.5), wing: 1)
            case "tailPoise": return Pose((21.5,13,0.2,0), (32,17,-0.15), (3,40.5), droop: 0.3)
            case "tailBalance": return Pose((23,11.5,1.4,0), (34,21.5,0.30), (3,29.5), droop: 1.4)
            case "tailCounter": return Pose((20.5,13.5,-0.5,0.2), (31.2,17.5,-0.24), (4,36), wing: 0.08, droop: 0.6)
            case "tailSettle": return Pose((22.3,12.3,-0.2,0.3), (32.4,18.8,0.08), (2.5,42), droop: 0.2)
            default: return nil
            }
        case .greatSpottedWoodpecker:
            switch frame {
            case "lookNear": return Pose((21.5,14,0.5,0), (32.5,19.5,0.25), (10,41))
            case "lookFar": return Pose((21,14.5,0,0), (32,15.8,-0.18), (9.5,42))
            case "alertRise": return Pose((19,16,0.3,0), (32.5,13.8,-0.20), (11,42.5), wing: 0.06)
            case "alertHold": return Pose((18,17,0.5,-0.3), (32.8,12.3,-0.10), (11.5,43), wing: 0.12)
            case "alertRelax": return Pose((21.5,14,-0.4,0.4), (31.5,17.8,0.04), (9.5,41))
            case "restLower": return Pose((23.5,12.5,-0.7,0.9), (30.5,22.5,0.16), (9,40.5))
            case "restTuck": return Pose((24,12,-1,1.4), (26,24,2.64), (10,40))
            case "restWake": return Pose((22,13.5,0,0.7), (31,16.8,-0.25), (9,41.5), wing: 0.08)
            case "takeoffCrouch": return Pose((25,11,1.3,0.2), (33.5,23.5,0.18), (8.5,36), wing: 0.24)
            case "takeoffPush": return Pose((18,13,1.8,0), (33.7,15.2,-0.24), (8,33), wing: 1)
            case "sideBrace": return Pose((18.5,17.5,-0.3,0), (16.5,13.2,-0.04), (25,44), droop: 0.2, side: true)
            case "sideDraw": return Pose((19,17,-1,0.3), (14.5,12.7,-0.16), (25.5,44), droop: 0.6, side: true)
            case "sideTap":
                // Solve the unrotated upper-mandible endpoint at the wall x29.
                // Body, folded wing and both grips stay on the outside of it.
                guard let anatomy = anatomy(for: species) else { return nil }
                let tip = anatomy.localBillTip
                return Pose((18,18,0.4,0), (Double(sideTapContact.x-tip.x),Double(sideTapContact.y-tip.y),0),
                            (25.5,44), droop: 0.1, side: true)
            case "sideRecover": return Pose((18.7,17.3,-0.5,0.2), (15.7,13.8,-0.07), (25,43.5), droop: 0.35, side: true)
            default: return nil
            }
        case .mallard:
            switch frame {
            case "lookNear": return Pose((26,11.5,0.4,0), (33,24,0.22), (9.5,32))
            case "lookFar": return Pose((25.5,12,0,0), (32.5,20.5,-0.16), (9,32.5))
            case "alertRise": return Pose((24.8,12.3,0.2,0), (33,18.5,-0.16), (10,33), wing: 0.06)
            case "alertHold": return Pose((24,13,0.5,-0.2), (33.5,17,-0.08), (10.5,33.5), wing: 0.10)
            case "alertRelax": return Pose((26,11.4,-0.3,0.4), (32,22.5,0.04), (9,32))
            case "restLower": return Pose((27,10.5,-0.6,0.7), (31,25.5,0.18), (9,33))
            case "restTuck": return Pose((27.5,10,-0.8,1.0), (24,28,2.66), (10,33.5))
            case "restWake": return Pose((26.5,11,0,0.5), (31.3,21.5,-0.25), (8.5,32.5), wing: 0.08)
            case "takeoffCrouch": return Pose((28,9.5,1,0.1), (34.5,25.5,0.12), (8,32), wing: 0.25)
            case "takeoffPush": return Pose((21,12,1.7,0), (34,17.5,-0.22), (7.5,28), wing: 1)
            case "wingLook": return Pose((25.8,11.5,-0.2,0), (30,21.8,-0.48), (9.5,32.5), droop: 0.3)
            case "wingReach": return Pose((26.5,10.8,-0.6,0.2), (24.5,24,2.40), (10,33), droop: 1.3)
            case "wingSmooth": return Pose((26.8,10.5,-0.3,0.3), (27,25.8,2.72), (9,32), droop: 1.7)
            case "wingRecover": return Pose((26.2,11.2,0.1,0.4), (31.5,22.8,-0.22), (9.5,32.8), droop: 0.5)
            default: return nil
            }
        case .littleEgret:
            switch frame {
            case "lookNear": return Pose((19.5,7.5,0.3,0), (35,12,0.24), (14,27), neck: (31,19))
            case "lookFar": return Pose((19,7.5,0,0), (34,6.5,-0.10), (13.5,27), neck: (30,16))
            case "alertRise": return Pose((18.5,8,0.2,0), (34.2,5.5,-0.08), (14,27.5), wing: 0.06, neck: (31,14.5))
            case "alertHold": return Pose((18,8.5,0.4,-0.2), (34.5,4.2,-0.03), (14.5,28), wing: 0.10, neck: (32,13))
            case "alertRelax": return Pose((19.3,7.7,-0.2,0.3), (33.5,8.5,0.05), (13.5,27), neck: (29.5,17))
            case "restLower": return Pose((21,7.5,-0.5,0.6), (32,17,0.18), (13,28.5), neck: (30,22))
            case "restTuck": return Pose((22,7,-0.7,1), (25.5,22,2.78), (13.5,29), neck: (29,25))
            case "restWake": return Pose((20,7.8,-0.1,0.5), (32.5,10.5,-0.22), (13,28), wing: 0.08, neck: (29.5,18.5))
            case "takeoffCrouch": return Pose((23,7.5,1,0.2), (35.5,18.5,0.10), (12.5,29.5), wing: 0.25, neck: (32,24))
            case "takeoffPush": return Pose((16.5,8.5,1.5,0), (35,10,-0.20), (12,25), wing: 1, neck: (33,18))
            case "neckPoise": return Pose((19.1,7.8,0.1,0), (33.5,8,-0.10), (14,27), neck: (29.5,16.5))
            case "neckReach": return Pose((19.6,7.5,0.7,0), (35.8,13.2,0.22), (13,26.5), neck: (34,20))
            case "neckObserve": return Pose((19.8,7.3,1,0), (35.5,16.5,0.34), (12.5,26), neck: (34.5,22))
            case "neckRecover": return Pose((19.4,7.8,-0.2,0.3), (33.2,10.5,0.02), (13.5,27.5), neck: (30,18.5))
            default: return nil
            }
        case .magpieRobin:
            switch frame {
            case "tailReady": return Pose((21.8,12.5,0.1,0), (32.5,17.8,-0.12), (7,34), droop: 0.6)
            case "tailLift": return Pose((20.5,13.5,0.5,0), (33,16.5,-0.21), (8.5,20.5), droop: 2.2)
            case "tailPulse": return Pose((22.3,12,0.9,0.2), (33.5,20.5,0.16), (7.5,26), droop: 1.4)
            case "tailRecover": return Pose((22,12.5,-0.3,0.4), (32,19.2,0.04), (6.5,37), droop: 0.35)
            default: return nil
            }
        default: return nil
        }
    }
}
