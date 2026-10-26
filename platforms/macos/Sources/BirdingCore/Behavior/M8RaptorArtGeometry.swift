import Foundation

/// M8e additions in the existing top-down, right-facing 48-unit canvas.
/// These are presentation poses on a dry top perch, not behavior permissions.
public enum M8RaptorArtGeometry {
    public static let species: [SpeciesID] = [
        .commonKestrel, .peregrineFalcon, .blackKite, .commonBuzzard,
        .littleOwl, .collaredScopsOwl, .asianBarredOwlet, .piedKingfisher
    ]

    /// Actual append order. The little owl's accepted M6c foundation is retained.
    public static func frameNames(for species: SpeciesID) -> [String] {
        guard Self.species.contains(species) else { return [] }
        return (species == .littleOwl ? [] : PoseClip.frameNames)
            + signatureFrameNames(for: species)
    }

    /// Preparation, emphasis, recovery, settlement; timing belongs to the caller.
    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        switch species {
        case .commonKestrel:
            return ["kestrelScanReady", "kestrelScanFocus", "kestrelScanReturn", "kestrelScanSettle"]
        case .peregrineFalcon:
            return ["peregrineWatchReady", "peregrineWatchLow", "peregrineWatchLift", "peregrineWatchSettle"]
        case .blackKite:
            return ["kitePreenReady", "kitePreenReach", "kitePreenFold", "kitePreenSettle"]
        case .commonBuzzard:
            return ["buzzardShoulderReady", "buzzardShoulderLoosen", "buzzardShoulderDraw", "buzzardShoulderSettle"]
        case .littleOwl:
            return ["littleOwlBowReady", "littleOwlBowDip", "littleOwlBowLift", "littleOwlBowSettle"]
        case .collaredScopsOwl:
            return ["scopsTiltReady", "scopsTiltBlink", "scopsTiltOpen", "scopsTiltSettle"]
        case .asianBarredOwlet:
            return ["owletScanReady", "owletScanTurn", "owletScanNod", "owletScanSettle"]
        case .piedKingfisher:
            return ["piedLookReady", "piedLookReach", "piedLookDraw", "piedLookSettle"]
        default: return []
        }
    }

    public enum Form { case falcon, kite, buzzard, littleOwl, scops, owlet, kingfisher }

    public struct Anatomy {
        public let form: Form
        public let width, headWidth, headHeight, billLength, tailWidth: Double
        public var owl: Bool {
            switch form {
            case .littleOwl, .scops, .owlet: return true
            default: return false
            }
        }
    }

    /// Dimensions retain DetailedBirdArt's species silhouettes and owl face sizes.
    public static func anatomy(for species: SpeciesID) -> Anatomy? {
        switch species {
        case .commonKestrel:
            return Anatomy(form: .falcon, width: 17, headWidth: 8, headHeight: 7, billLength: 3, tailWidth: 4)
        case .peregrineFalcon:
            return Anatomy(form: .falcon, width: 20, headWidth: 9, headHeight: 8, billLength: 3, tailWidth: 5)
        case .blackKite:
            return Anatomy(form: .kite, width: 19, headWidth: 7.5, headHeight: 7, billLength: 3, tailWidth: 6.4)
        case .commonBuzzard:
            return Anatomy(form: .buzzard, width: 22, headWidth: 8, headHeight: 7, billLength: 3, tailWidth: 6)
        case .littleOwl:
            return Anatomy(form: .littleOwl, width: 22, headWidth: 19, headHeight: 12, billLength: 3, tailWidth: 6)
        case .collaredScopsOwl:
            return Anatomy(form: .scops, width: 18, headWidth: 17, headHeight: 13, billLength: 3, tailWidth: 6)
        case .asianBarredOwlet:
            return Anatomy(form: .owlet, width: 20, headWidth: 18, headHeight: 14, billLength: 3, tailWidth: 7)
        case .piedKingfisher:
            return Anatomy(form: .kingfisher, width: 17, headWidth: 11, headHeight: 8, billLength: 7.7, tailWidth: 4)
        default: return nil
        }
    }

    public struct Pose {
        public let body: (y: Double, height: Double, lean: Double, fluff: Double)
        public let head: (x: Double, y: Double, pitch: Double)
        public let tail: (x: Double, y: Double)
        /// Local wing opening, shoulder relaxation and head perspective.
        public let wing, shoulder, turn: Double
        public let eyesClosed: Bool

        fileprivate init(_ body: (Double, Double, Double, Double),
                         _ head: (Double, Double, Double), _ tail: (Double, Double),
                         wing: Double = 0, shoulder: Double = 0,
                         turn: Double = 0, eyesClosed: Bool = false) {
            self.body = body; self.head = head; self.tail = tail
            self.wing = wing; self.shoulder = shoulder; self.turn = turn
            self.eyesClosed = eyesClosed
        }

        public func headPoint(_ x: Double, _ y: Double) -> (Double, Double) {
            (head.x + x * cos(head.pitch) - y * sin(head.pitch),
             head.y + x * sin(head.pitch) + y * cos(head.pitch))
        }

        public func headWidth(anatomy: Anatomy) -> Double {
            anatomy.owl ? anatomy.headWidth : anatomy.headWidth * (1 - abs(turn) * 0.10)
        }

        /// Owl facial discs and bill move together during a modest perspective turn.
        public func faceMid(anatomy: Anatomy) -> Double { anatomy.headWidth * 0.17 * turn }

        /// The final vertex is the physical bill tip, consumed by both APIs.
        public func billVertices(anatomy a: Anatomy) -> [(Double, Double)] {
            if a.owl {
                let mid = faceMid(anatomy: a), eyeY = a.headHeight * -0.02
                return [(mid - 1, eyeY + 1), (mid + 1, eyeY + 1), (mid + 0.3, eyeY + 4)]
            }
            let root = headWidth(anatomy: a) / 2 - 0.5
            if a.form == .kingfisher {
                return [(root, -0.7), (root, 1), (root + a.billLength, 0.4)]
            }
            // A hooked tip, not the forward elbow, is the contact anchor.
            return [(root + 1.8, 1), (root, 1), (root, -1),
                    (root + a.billLength, 0), (root + a.billLength, 2),
                    (root + 1.5, 3)]
        }
    }

    public static func beakAnchor(species: SpeciesID, frame: String) -> PoseClip.Anchor? {
        guard let a = anatomy(for: species), let p = pose(species: species, frame: frame),
              let vertex = p.billVertices(anatomy: a).last else { return nil }
        let tip = p.headPoint(vertex.0, vertex.1)
        return PoseClip.Anchor(tip.0, tip.1)
    }

    /// Each row authors the articulated source drawing. No row aliases an old frame.
    /// Even push preparation keeps both toes on the top perch; flight is external.
    public static func pose(species: SpeciesID, frame: String) -> Pose? {
        switch species {
        case .commonKestrel:
            switch frame {
            case "lookNear": return Pose((22.5,13.4,0.6,0),(33,19.3,0.24),(7.2,42.1),turn:0.15)
            case "lookFar": return Pose((21.8,14,-0.2,0),(32.2,15.4,-0.15),(7.8,43.1),turn:-0.38)
            case "alertRise": return Pose((20.9,14.8,0.3,0),(32.7,14.3,-0.17),(8.3,43.7),wing:0.07)
            case "alertHold": return Pose((20.2,15.4,0.7,-0.2),(33.1,13.2,-0.06),(8.8,44),wing:0.12,turn:0.12)
            case "alertRelax": return Pose((22.2,13.7,-0.3,0.4),(32.3,17.4,0.07),(7.4,42.6),shoulder:0.15)
            case "restLower": return Pose((23.9,12.4,-0.5,0.8),(31.5,21,0.16),(7.5,41.3),eyesClosed:true)
            case "restTuck": return Pose((24.3,12,-0.8,1.1),(27.4,25.1,2.22),(8.2,40.7),shoulder:0.2,eyesClosed:true)
            case "restWake": return Pose((22.6,13.4,-0.1,0.4),(31.9,17,-0.24),(7.1,42),wing:0.06)
            case "takeoffCrouch": return Pose((25,11.4,1.1,0.2),(33.8,23.4,0.19),(6.8,36.6),wing:0.23)
            case "takeoffPush": return Pose((19.8,13.3,1.5,0),(34,15.8,-0.21),(6.6,35.1),wing:0.74)
            case "kestrelScanReady": return Pose((22.1,13.7,-0.1,0),(31.8,16.3,-0.08),(7.6,42.9),turn:-0.62)
            case "kestrelScanFocus": return Pose((22.9,12.9,1.2,0),(34.1,19.6,0.17),(7.1,39.6),wing:0.04,turn:0.46)
            case "kestrelScanReturn": return Pose((21.7,14.1,0.3,0.1),(32.7,16.5,-0.19),(8,41.5),turn:0.22)
            case "kestrelScanSettle": return Pose((22.3,13.6,-0.2,0.3),(32.4,17.9,0.03),(7.7,42.4),shoulder:0.12,turn:-0.08)
            default: return nil
            }
        case .peregrineFalcon:
            switch frame {
            case "lookNear": return Pose((22.7,14.1,0.5,0),(33.1,19.8,0.18),(10.2,39.8),turn:0.18)
            case "lookFar": return Pose((21.9,14.8,-0.2,0),(32.3,16.2,-0.12),(10.7,40.4),turn:-0.3)
            case "alertRise": return Pose((20.8,15.8,0.4,-0.1),(32.8,14.9,-0.14),(11,41),wing:0.05)
            case "alertHold": return Pose((20.3,16.2,0.8,-0.3),(33.3,14.1,-0.04),(11.4,41.4),wing:0.09,turn:0.12)
            case "alertRelax": return Pose((22.4,14.4,-0.3,0.2),(32.2,18.3,0.05),(10.1,40.1),shoulder:0.1)
            case "restLower": return Pose((24,12.8,-0.4,0.6),(31.7,22.1,0.12),(10.5,39.3),eyesClosed:true)
            case "restTuck": return Pose((24.5,12.2,-0.8,0.9),(27.1,25.5,2.12),(11,38.8),shoulder:0.15,eyesClosed:true)
            case "restWake": return Pose((22.6,14.2,-0.1,0.3),(32,17.4,-0.18),(9.8,40.3),wing:0.05)
            case "takeoffCrouch": return Pose((25.1,11.6,1.2,0),(34,23.6,0.14),(9.3,35.9),wing:0.22)
            case "takeoffPush": return Pose((19.7,14.1,1.7,0),(34.1,16,-0.18),(9,34.8),wing:0.70)
            case "peregrineWatchReady": return Pose((22.8,13.8,0.6,-0.1),(33.4,20.6,0.10),(10.4,39.1),turn:-0.12)
            case "peregrineWatchLow": return Pose((24,12.3,1.4,-0.2),(34.6,23,0.20),(10,36.7),wing:0.06,turn:0.24)
            case "peregrineWatchLift": return Pose((21.9,14.5,0.4,-0.1),(33.1,16.5,-0.15),(10.9,38.5),wing:0.025,shoulder:-0.25)
            case "peregrineWatchSettle": return Pose((22.5,14.2,-0.2,0.1),(32.6,18.1,0.02),(10.3,40),shoulder:-0.12,turn:0.07)
            default: return nil
            }
        case .blackKite:
            switch frame {
            case "lookNear": return Pose((22.6,13.3,0.5,0),(32.9,20.1,0.22),(3.1,41.4),turn:0.15)
            case "lookFar": return Pose((21.8,14,-0.3,0),(32.1,16.4,-0.16),(3.4,42.2),turn:-0.35)
            case "alertRise": return Pose((20.8,14.9,0.2,0),(32.6,15.1,-0.18),(3.9,42.6),wing:0.06)
            case "alertHold": return Pose((20.1,15.5,0.6,-0.2),(33,14.2,-0.07),(4.4,42.8),wing:0.11,turn:0.1)
            case "alertRelax": return Pose((22.2,13.7,-0.4,0.4),(32,18.6,0.05),(3.3,41.9),shoulder:0.18)
            case "restLower": return Pose((23.8,12.4,-0.6,0.8),(31.2,22.1,0.18),(3.2,40.9),eyesClosed:true)
            case "restTuck": return Pose((24.4,11.8,-1,1.1),(26.4,25.2,2.25),(3.7,40.4),shoulder:0.2,eyesClosed:true)
            case "restWake": return Pose((22.5,13.4,-0.2,0.5),(31.8,17.7,-0.22),(3,41.6),wing:0.07)
            case "takeoffCrouch": return Pose((25.2,11,1.2,0.2),(33.9,23.7,0.17),(2.8,35.1),wing:0.24)
            case "takeoffPush": return Pose((19.8,13.1,1.6,0),(34,16.4,-0.22),(2.9,33.5),wing:0.66)
            case "kitePreenReady": return Pose((22.7,13.1,-0.5,0.2),(30.6,19.8,0.48),(3.6,41.8),wing:0.08,shoulder:0.5,turn:-0.2)
            case "kitePreenReach": return Pose((23.2,12.7,-0.9,0.3),(27.2,24.7,2.28),(3.9,40.6),wing:0.15,shoulder:0.8,eyesClosed:true)
            case "kitePreenFold": return Pose((22.4,13.6,-0.2,0.1),(31.4,17.3,-0.24),(3.2,41.1),wing:0.035,shoulder:-0.35)
            case "kitePreenSettle": return Pose((22.1,13.9,0.1,0.3),(32.3,18.4,0.04),(3.5,42),shoulder:0.12,turn:0.08)
            default: return nil
            }
        case .commonBuzzard:
            switch frame {
            case "lookNear": return Pose((22.2,14.9,0.4,0.2),(32.7,19.7,0.16),(10.2,39.1),turn:0.14)
            case "lookFar": return Pose((21.5,15.5,-0.3,0.1),(31.9,16.4,-0.10),(10.8,39.9),turn:-0.38)
            case "alertRise": return Pose((20.7,16.2,0.2,0),(32.5,15.1,-0.13),(11.2,40.3),wing:0.045)
            case "alertHold": return Pose((20.1,16.8,0.5,-0.2),(32.9,14.3,-0.05),(11.7,40.7),wing:0.085,turn:0.12)
            case "alertRelax": return Pose((22,15.1,-0.4,0.6),(31.8,18.4,0.04),(10.3,39.5),shoulder:0.3)
            case "restLower": return Pose((23.5,13.6,-0.6,1.2),(31,21.8,0.16),(10.4,38.7),shoulder:0.35,eyesClosed:true)
            case "restTuck": return Pose((24.1,13,-1,1.6),(26.3,25.2,2.16),(11,38.3),shoulder:0.45,eyesClosed:true)
            case "restWake": return Pose((22.2,14.8,-0.2,0.7),(31.7,17.7,-0.18),(10,39.4),wing:0.055)
            case "takeoffCrouch": return Pose((24.7,12.3,1,0.4),(33.5,23.3,0.14),(9.4,35.5),wing:0.23)
            case "takeoffPush": return Pose((19.9,14.7,1.4,0.1),(33.7,16.4,-0.17),(9.1,34.1),wing:0.63)
            case "buzzardShoulderReady": return Pose((21.9,15.2,-0.4,0.3),(31.2,17.5,-0.04),(10.6,39.6),shoulder:0.15,turn:-0.56)
            case "buzzardShoulderLoosen": return Pose((22.6,14.6,-0.6,1.3),(32.1,18.6,0.09),(10.1,38.9),wing:0.11,shoulder:1.2,turn:0.38)
            case "buzzardShoulderDraw": return Pose((21.4,15.7,0.1,0.2),(32.6,16.3,-0.12),(11.1,39.3),wing:0.03,shoulder:-0.5,turn:0.19)
            case "buzzardShoulderSettle": return Pose((22.1,15,-0.2,0.5),(32,18.1,0.02),(10.7,39.8),shoulder:0.18,turn:-0.07)
            default: return nil
            }
        case .littleOwl:
            switch frame {
            case "littleOwlBowReady": return Pose((21.5,14.5,0.4,0.1),(28.3,20.9,-0.10),(17.2,37.8),shoulder:0.1,turn:-0.24)
            case "littleOwlBowDip": return Pose((23.3,12.8,1,0.4),(29.4,24.4,0.21),(16.8,37.1),wing:0.035,shoulder:0.45,turn:0.4)
            case "littleOwlBowLift": return Pose((20.7,15.1,0.1,0.2),(28.5,18.7,-0.08),(17.7,38.1),shoulder:-0.15,turn:0.12)
            case "littleOwlBowSettle": return Pose((21.3,14.8,-0.2,0.3),(27.9,20.4,0.02),(17.4,37.5),shoulder:0.15,turn:-0.08)
            default: return nil
            }
        case .collaredScopsOwl:
            switch frame {
            case "lookNear": return Pose((18.1,18.1,0.3,0),(28.6,18.5,0.08),(19,38.5),turn:0.32)
            case "lookFar": return Pose((17.6,18.5,-0.2,0),(27.7,16.3,-0.06),(19.5,38.9),turn:-0.5)
            case "alertRise": return Pose((16.9,19,0.2,-0.1),(28.1,15,-0.04),(19.8,39.1),wing:0.04,turn:0.18)
            case "alertHold": return Pose((16.4,19.5,0.4,-0.2),(28.4,14.1,0.02),(20.2,39.4),wing:0.07,turn:0.34)
            case "alertRelax": return Pose((17.8,18.4,-0.3,0.4),(27.8,17.3,0.03),(19.2,38.7),shoulder:0.18,turn:-0.14)
            case "restLower": return Pose((19.6,16.7,-0.4,0.8),(27.6,21.1,0.07),(19.3,38.3),eyesClosed:true)
            case "restTuck": return Pose((20.8,15.6,-0.6,1.1),(27.2,24.6,0.12),(19.8,38),shoulder:0.3,turn:-0.32,eyesClosed:true)
            case "restWake": return Pose((18.4,17.8,-0.1,0.4),(28,18,-0.09),(18.9,38.7),wing:0.045,turn:0.22)
            case "takeoffCrouch": return Pose((21.5,15.1,0.7,0.3),(28.9,23.4,0.08),(18.5,36.7),wing:0.21,turn:0.28)
            case "takeoffPush": return Pose((16.7,17.4,1,0),(28.9,15.7,-0.06),(18.3,34.9),wing:0.60,turn:0.34)
            case "scopsTiltReady": return Pose((17.9,18.2,0.1,0.1),(28.4,17.5,-0.15),(19.4,38.6),turn:0.3)
            case "scopsTiltBlink": return Pose((18.6,17.7,-0.2,0.4),(27.9,18.4,-0.19),(19.1,38.3),shoulder:0.28,turn:-0.2,eyesClosed:true)
            case "scopsTiltOpen": return Pose((17.6,18.6,0.2,0.2),(28.2,16.8,-0.07),(19.7,38.8),shoulder:0.08,turn:0.17)
            case "scopsTiltSettle": return Pose((18,18.1,-0.1,0.3),(28,17.9,0.025),(19.5,38.4),shoulder:0.14,turn:-0.06)
            default: return nil
            }
        case .asianBarredOwlet:
            switch frame {
            case "lookNear": return Pose((20.5,15.5,0.4,0),(28.7,21.1,0.07),(16.2,38.7),turn:0.36)
            case "lookFar": return Pose((19.9,16,-0.2,0),(27.6,18.4,-0.055),(16.7,39.2),turn:-0.52)
            case "alertRise": return Pose((19.2,16.7,0.2,-0.1),(28,17.1,-0.04),(17.1,39.5),wing:0.04,turn:0.2)
            case "alertHold": return Pose((18.7,17.2,0.4,-0.2),(28.5,16.2,0.015),(17.6,39.8),wing:0.075,turn:0.37)
            case "alertRelax": return Pose((20.2,15.8,-0.3,0.4),(27.8,20,0.03),(16.4,39),shoulder:0.2,turn:-0.16)
            case "restLower": return Pose((21.9,14.3,-0.4,0.9),(27.5,23.2,0.06),(16.5,38.3),eyesClosed:true)
            case "restTuck": return Pose((22.7,13.6,-0.7,1.2),(27.1,26,0.11),(17,38),shoulder:0.35,turn:-0.35,eyesClosed:true)
            case "restWake": return Pose((20.8,15.2,-0.1,0.5),(28.1,20.1,-0.08),(16,38.8),wing:0.05,turn:0.23)
            case "takeoffCrouch": return Pose((23.2,13.4,0.7,0.3),(29,25,0.07),(15.7,36.5),wing:0.22,turn:0.3)
            case "takeoffPush": return Pose((18.8,15.6,1.1,0),(29.1,18,-0.05),(15.4,34.7),wing:0.61,turn:0.35)
            case "owletScanReady": return Pose((20.1,15.9,-0.2,0.1),(27.3,19.1,-0.04),(16.6,39.1),turn:-0.63)
            case "owletScanTurn": return Pose((19.8,16.1,0.3,0.1),(28.8,18.6,0.035),(17.1,39.4),shoulder:0.15,turn:0.65)
            case "owletScanNod": return Pose((21,15.1,0.5,0.3),(28.5,22.2,0.16),(16.5,38.6),shoulder:0.25,turn:0.32)
            case "owletScanSettle": return Pose((20.4,15.6,-0.1,0.25),(28,20.2,0.01),(16.8,38.9),shoulder:0.1,turn:-0.09)
            default: return nil
            }
        case .piedKingfisher:
            switch frame {
            // The long bill is authored inside the canvas, not shortened by clipping.
            case "lookNear": return Pose((22.6,11.5,0.5,0),(32.3,19.9,0.25),(13.1,33.6),turn:0.13)
            case "lookFar": return Pose((21.8,12.2,-0.2,0),(31.5,16.4,-0.16),(13.6,34.3),turn:-0.32)
            case "alertRise": return Pose((20.9,13,0.3,0),(31.9,15.1,-0.17),(14,34.8),wing:0.065)
            case "alertHold": return Pose((20.3,13.6,0.6,-0.2),(32.3,14.3,-0.06),(14.4,35.2),wing:0.11,turn:0.12)
            case "alertRelax": return Pose((22.2,11.9,-0.3,0.3),(31.7,18.5,0.06),(13.3,33.9),shoulder:0.13)
            case "restLower": return Pose((23.9,10.5,-0.5,0.7),(30.8,21.9,0.18),(13.4,33.1),eyesClosed:true)
            case "restTuck": return Pose((24.5,10,-0.8,1),(28.5,24.2,2.25),(13.9,32.7),shoulder:0.2,eyesClosed:true)
            case "restWake": return Pose((22.5,11.6,-0.1,0.4),(31.1,17.6,-0.23),(12.9,33.7),wing:0.065)
            case "takeoffCrouch": return Pose((25.1,9.5,1,0.2),(33.2,23.4,0.17),(12.5,30.8),wing:0.23)
            case "takeoffPush": return Pose((19.9,11.5,1.4,0),(33.1,16.4,-0.20),(12.2,29.6),wing:0.70)
            case "piedLookReady": return Pose((22.3,11.8,0.6,0),(32.6,19.3,0.22),(13.4,33.4),turn:-0.12)
            case "piedLookReach": return Pose((23.2,10.8,1.5,-0.1),(33.8,22.8,0.42),(12.8,31.7),wing:0.045,turn:0.23)
            case "piedLookDraw": return Pose((22.1,12,-0.6,0.3),(29.8,18.6,-0.12),(13.8,33),shoulder:0.16,turn:-0.55)
            case "piedLookSettle": return Pose((22.4,11.7,-0.1,0.2),(31.8,18.9,0.045),(13.5,33.8),shoulder:0.08,turn:0.07)
            default: return nil
            }
        default: return nil
        }
    }
}
