import Foundation
import CoreGraphics

/// M8c additions in right-facing, top-down logical 48-unit coordinates.
/// These are presentation poses only; no behavior or habitat is authorized here.
public enum M8SmallArtGeometry {
    public static let species: [SpeciesID] = [
        .yellowBrowedWarbler, .vinousThroatedParrotbill, .yellowRumpedFlycatcher,
        .redFlankedBluetail, .plumbeousWaterRedstart, .longTailedShrike,
        .blackDrongo, .yellowBilledGrosbeak
    ]

    /// All eight lacked the ten-frame base pack at the M8c baseline. The
    /// flycatcher's existing three catch frames are independent and stay intact.
    public static func frameNames(for species: SpeciesID) -> [String] {
        guard Self.species.contains(species) else { return [] }
        return PoseClip.frameNames + signatureFrameNames(for: species)
    }

    /// Preparation, emphasis, recovery, settling; append in exactly this order.
    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        switch species {
        case .yellowBrowedWarbler: return ["canopyReady", "canopyLift", "canopyReturn", "canopySettle"]
        case .vinousThroatedParrotbill: return ["roundGather", "roundTurn", "roundSway", "roundSettle"]
        case .yellowRumpedFlycatcher: return ["wingPoise", "wingFlick", "wingLean", "wingSettle"]
        case .redFlankedBluetail: return ["blueTailReady", "blueTailLift", "blueTailLook", "blueTailSettle"]
        case .plumbeousWaterRedstart: return ["rustFanReady", "rustFanOpen", "rustFanLean", "rustFanSettle"]
        case .longTailedShrike: return ["vigilPoise", "vigilReach", "vigilHold", "vigilSettle"]
        case .blackDrongo: return ["forkPoise", "forkOpen", "forkFold", "forkSettle"]
        case .yellowBilledGrosbeak: return ["billLower", "billFlex", "billLift", "billSettle"]
        default: return []
        }
    }

    public enum BillShape: Equatable { case fine, conical, hooked }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, tailWidth: Double
        /// Local wing reach and folded primary length, independent of body size.
        public let wingReach, primaryLength: Double
        public let bill: BillShape
    }

    /// Dimensions retain the original species' head/body and bill families.
    /// In particular the two long-tailed species do not use a round small-bird
    /// torso, and the grosbeak has its own broad shoulder and heavy bill.
    public static func anatomy(for species: SpeciesID) -> Anatomy? {
        switch species {
        case .yellowBrowedWarbler:
            return Anatomy(width:17, headWidth:7, headHeight:6, billLength:3, tailWidth:3.5,
                           wingReach:14, primaryLength:8.5, bill:.fine)
        case .vinousThroatedParrotbill:
            return Anatomy(width:15, headWidth:9, headHeight:8, billLength:3.8, tailWidth:3.4,
                           wingReach:12.5, primaryLength:8, bill:.conical)
        case .yellowRumpedFlycatcher:
            return Anatomy(width:16, headWidth:CatchArtGeometry.flycatcherHeadWidth,
                           headHeight:CatchArtGeometry.flycatcherHeadHeight, billLength:3, tailWidth:4,
                           wingReach:15, primaryLength:9.5, bill:.fine)
        case .redFlankedBluetail:
            return Anatomy(width:16, headWidth:8, headHeight:7, billLength:3, tailWidth:4,
                           wingReach:13.5, primaryLength:9, bill:.fine)
        case .plumbeousWaterRedstart:
            return Anatomy(width:17, headWidth:9, headHeight:8, billLength:3, tailWidth:4.5,
                           wingReach:14, primaryLength:10, bill:.fine)
        case .longTailedShrike:
            return Anatomy(width:18, headWidth:8.5, headHeight:7, billLength:3.5, tailWidth:3.8,
                           wingReach:17, primaryLength:11, bill:.hooked)
        case .blackDrongo:
            return Anatomy(width:16, headWidth:7, headHeight:6, billLength:3, tailWidth:6,
                           wingReach:17, primaryLength:12, bill:.fine)
        case .yellowBilledGrosbeak:
            return Anatomy(width:20, headWidth:10, headHeight:9, billLength:4, tailWidth:4.5,
                           wingReach:15, primaryLength:9.5, bill:.conical)
        default: return nil
        }
    }

    public struct Pose {
        /// Shoulder height, torso depth, shoulder lean and local feather fullness.
        public let body: (y:Double, height:Double, lean:Double, fluff:Double)
        public let head: (x:Double, y:Double, pitch:Double)
        public let tail: (x:Double, y:Double)
        public let wing, spread, turn, gape, stance, droop: Double

        fileprivate init(_ body:(Double,Double,Double,Double), _ head:(Double,Double,Double),
                         _ tail:(Double,Double), wing:Double = 0, spread:Double = 0,
                         turn:Double = 0, gape:Double = 0, stance:Double = 0, droop:Double = 0) {
            self.body=body; self.head=head; self.tail=tail
            self.wing=wing; self.spread=spread; self.turn=turn
            self.gape=gape; self.stance=stance; self.droop=droop
        }

        /// Turning changes the authored head width and facial marks, while the
        /// anatomical pitch is applied only to local head vectors, never a raster.
        public func headWidth(anatomy: Anatomy) -> Double {
            anatomy.headWidth * (1 - turn * 0.09)
        }

        public func headPoint(_ x:Double, _ y:Double) -> CGPoint {
            CGPoint(x:head.x+x*cos(head.pitch)-y*sin(head.pitch),
                    y:head.y+x*sin(head.pitch)+y*cos(head.pitch))
        }

        /// Vertex 1 is the actual upper bill tip consumed by beakAnchor and the
        /// painter. Gape moves the lower mandible only, keeping this contact exact.
        public func billVertices(anatomy: Anatomy) -> [(Double,Double)] {
            let root=headWidth(anatomy:anatomy)/2-0.45
            let tip=(root+anatomy.billLength*(1-turn*0.08),0.4)
            switch anatomy.bill {
            case .fine:
                return [(root,-0.65),tip,(root+anatomy.billLength-1.1,1.1),(root,1.15)]
            case .conical:
                return [(root-0.3,-1.45),tip,(root+0.1,1.75)]
            case .hooked:
                return [(root,-1),tip,(tip.0-0.15,1.45),
                        (tip.0-1.3,2.3),(tip.0-1,0.95),(root,1.1)]
            }
        }

        public func lowerBillVertices(anatomy: Anatomy) -> [(Double,Double)] {
            let root=headWidth(anatomy:anatomy)/2-0.45
            let length=anatomy.billLength*(1-turn*0.08)
            return [(root,1.0+gape*0.25),(root+length-0.5,1.0+gape*1.8),
                    (root+0.3,1.9+gape*1.2)]
        }
    }

    /// Both toe bands are invariant; their shared terminal point is (29,39).
    /// Knees and hips articulate above these paths during every perched pose.
    public static let toePaths: [[(Double,Double)]] = [
        [(25,39),(27,38.5),(29,39)], [(29,39),(31,38.5),(33,39)]
    ]

    public static func beakAnchor(species: SpeciesID, frame: String) -> PoseClip.Anchor? {
        guard let a=anatomy(for:species), let p=pose(species:species,frame:frame) else { return nil }
        let bill=p.billVertices(anatomy:a)[1]
        let tip=p.headPoint(bill.0,bill.1)
        return PoseClip.Anchor(Double(tip.x),Double(tip.y))
    }

    /// Fourteen separately authored rows per species. Signature poses never
    /// alias the base pack or old idle poses, even at the final settled phase.
    public static func pose(species: SpeciesID, frame: String) -> Pose? {
        switch species {
        case .yellowBrowedWarbler:
            switch frame {
            case "lookNear": return Pose((22.7,10,0.7,0),(33.8,21,0.28),(9,37.8))
            case "lookFar": return Pose((21.8,10.7,-0.1,0),(32.9,17.5,-0.25),(9.7,38.7),turn:0.2)
            case "alertRise": return Pose((20.8,11.5,0.4,0),(33.2,16,-0.22),(10.1,39.5),wing:0.08)
            case "alertHold": return Pose((20,12.2,0.8,-0.2),(33.7,14.8,-0.16),(10.5,40.3),wing:0.15)
            case "alertRelax": return Pose((22.2,10.4,-0.3,0.4),(32.7,18.9,0.08),(8.7,38.2))
            case "restLower": return Pose((24,9.8,-0.6,0.9),(31.8,23.2,0.17),(8.9,37),stance:-0.5)
            case "restTuck": return Pose((24.7,9.5,-1,1.3),(27.6,25.9,2.55),(9.5,36.4),turn:0.3,stance:-0.9)
            case "restWake": return Pose((22.8,10.2,0.1,0.5),(32.4,18,-0.31),(8.4,38.4),wing:0.1)
            case "takeoffCrouch": return Pose((25.6,8.9,1.4,0.2),(34.5,24.2,0.19),(8,33.5),wing:0.28,stance:-1.4)
            case "takeoffPush": return Pose((19.3,10.3,1.8,0),(34.6,16.8,-0.3),(7.5,32),wing:0.88,stance:0.5)
            case "canopyReady": return Pose((21.6,10.6,0.3,0.2),(33,17.1,-0.38),(9.5,38),wing:0.04,turn:0.1)
            case "canopyLift": return Pose((20.4,11.4,0.6,0),(33.6,15.9,-0.64),(10.4,39),wing:0.34,turn:0.2)
            case "canopyReturn": return Pose((21.3,10.8,-0.2,0.3),(32.6,17.4,-0.2),(9.1,38.6),wing:0.15,turn:0.45)
            case "canopySettle": return Pose((22.5,10.3,-0.1,0.3),(33.1,19.6,0.03),(9.2,38.1),wing:0.02,turn:0.1)
            default: return nil
            }
        case .vinousThroatedParrotbill:
            switch frame {
            case "lookNear": return Pose((22.6,12.6,0.4,0.3),(33,21.1,0.24),(3.7,42.7),turn:0.1)
            case "lookFar": return Pose((21.6,13.1,-0.2,0.1),(32.1,17.1,-0.18),(4.1,43.4),turn:0.4)
            case "alertRise": return Pose((20.5,14,0.3,0),(32.7,15.6,-0.16),(4.7,43.9),wing:0.07)
            case "alertHold": return Pose((19.6,14.8,0.6,-0.2),(33.2,14.1,-0.07),(5.2,44.5),wing:0.11,turn:0.2)
            case "alertRelax": return Pose((22.1,12.8,-0.3,0.7),(31.9,19.7,0.07),(3.6,43.1),turn:0.3)
            case "restLower": return Pose((24,11.8,-0.5,1.5),(31,23.7,0.19),(3.8,41.8),stance:-0.6)
            case "restTuck": return Pose((24.6,11.4,-0.9,2),(27.8,26.1,2.42),(4.4,41.1),turn:0.35,stance:-1)
            case "restWake": return Pose((22.9,12.3,0,0.9),(31.8,18.5,-0.27),(3.3,42.8),wing:0.08)
            case "takeoffCrouch": return Pose((25.4,10.8,1.1,0.6),(34,24.5,0.14),(3.5,35.9),wing:0.25,stance:-1.4)
            case "takeoffPush": return Pose((18.9,12.8,1.6,0.1),(34,16.8,-0.22),(3.2,33.8),wing:0.84,stance:0.6)
            case "roundGather": return Pose((23.3,12.3,-0.4,1.7),(31.8,21.2,0.12),(4.1,42.4),turn:0.1,stance:-0.4)
            case "roundTurn": return Pose((23,12.7,-0.6,1.8),(31.1,19.8,-0.15),(4.7,41.4),turn:0.9,stance:-0.4)
            case "roundSway": return Pose((22.7,12.8,0.2,1),(32,19.6,0.08),(6.4,38.3),spread:0.14,turn:0.55)
            case "roundSettle": return Pose((22.4,12.9,-0.1,0.5),(32.5,19.1,0.04),(3.9,42.5),turn:0.2)
            default: return nil
            }
        case .yellowRumpedFlycatcher:
            switch frame {
            case "lookNear": return Pose((22.5,10.9,0.6,0),(33.8,21,0.25),(10,39.6))
            case "lookFar": return Pose((21.3,11.6,-0.2,0),(32.8,17.5,-0.22),(10.7,40.5),turn:0.25)
            case "alertRise": return Pose((20.3,12.4,0.5,0),(33.2,15.9,-0.2),(11.1,41.1),wing:0.1)
            case "alertHold": return Pose((19.4,13.1,0.8,-0.2),(33.7,14.5,-0.09),(11.5,41.7),wing:0.17)
            case "alertRelax": return Pose((21.9,11.3,-0.3,0.5),(32.7,19.2,0.06),(9.8,39.8))
            case "restLower": return Pose((23.8,10.8,-0.6,1),(31.8,23.4,0.18),(9.6,38.8),stance:-0.5)
            case "restTuck": return Pose((24.5,10.4,-1,1.5),(27.3,25.6,2.48),(10.3,38),turn:0.2,stance:-0.9)
            case "restWake": return Pose((22.3,11.2,0,0.6),(32.3,18.2,-0.29),(9.3,40.2),wing:0.12)
            case "takeoffCrouch": return Pose((25.4,9.6,1.5,0.3),(34.7,24.3,0.16),(9,34.3),wing:0.32,stance:-1.5)
            case "takeoffPush": return Pose((18.7,11.8,2,0),(34.8,16.2,-0.28),(8.6,32.5),wing:0.92,stance:0.6)
            case "wingPoise": return Pose((21.8,11.5,0.1,0),(33,18.6,-0.06),(10.3,39.5),wing:0.09,droop:0.5)
            case "wingFlick": return Pose((21.1,11.8,0.2,-0.1),(33.4,17.6,-0.12),(10.9,38.8),wing:0.39,droop:-0.5)
            case "wingLean": return Pose((22.7,10.6,1.3,0),(35,21.8,0.17),(9.1,36.8),wing:0.12,turn:0.2,stance:-0.5)
            case "wingSettle": return Pose((22.1,11.2,-0.1,0.3),(33.1,19.4,0.03),(10.1,39.9),wing:0.02,turn:0.1)
            default: return nil
            }
        case .redFlankedBluetail:
            switch frame {
            case "lookNear": return Pose((22.8,11.8,0.5,0),(33.3,21.7,0.28),(10.1,39.8))
            case "lookFar": return Pose((21.6,12.5,-0.2,0),(32.3,18.1,-0.22),(10.7,40.7),turn:0.2)
            case "alertRise": return Pose((20.5,13.2,0.3,0),(32.8,16.3,-0.19),(11.2,41.4),wing:0.08)
            case "alertHold": return Pose((19.7,13.9,0.6,-0.2),(33.2,15,-0.1),(11.6,41.9),wing:0.13)
            case "alertRelax": return Pose((22.2,12.2,-0.4,0.5),(32,19.8,0.07),(9.7,40.1),turn:0.15)
            case "restLower": return Pose((24,11.4,-0.6,1.1),(31.1,23.7,0.2),(9.8,38.9),stance:-0.5)
            case "restTuck": return Pose((24.7,11,-1,1.7),(27,26,2.5),(10.5,38.1),turn:0.25,stance:-1)
            case "restWake": return Pose((22.7,12,0,0.6),(31.8,18.5,-0.3),(9.2,40.4),wing:0.1)
            case "takeoffCrouch": return Pose((25.5,10.1,1.3,0.3),(34.2,24.8,0.18),(9,34.4),wing:0.28,stance:-1.4)
            case "takeoffPush": return Pose((18.9,12.1,1.8,0),(34.2,16.7,-0.26),(8.6,32.8),wing:0.88,stance:0.6)
            case "blueTailReady": return Pose((22.5,11.9,0.3,0.2),(32.7,20.3,0.06),(11.5,36.8),spread:0.12)
            case "blueTailLift": return Pose((21.9,12.3,0.8,0),(33.4,19.2,-0.06),(12.2,29.1),wing:0.07,spread:0.23,stance:-0.2)
            case "blueTailLook": return Pose((22.1,12,0.1,0.3),(32,19.5,-0.18),(10.9,34.4),spread:0.16,turn:0.75)
            case "blueTailSettle": return Pose((22.6,11.7,-0.1,0.4),(32.8,20.2,0.03),(10.3,39.3),spread:0.04,turn:0.1)
            default: return nil
            }
        case .plumbeousWaterRedstart:
            switch frame {
            case "lookNear": return Pose((22.5,13.6,0.6,0),(33.5,21.3,0.24),(10.2,38.9),spread:0.08)
            case "lookFar": return Pose((21.4,14.1,-0.2,0),(32.5,17.6,-0.18),(10.8,39.8),spread:0.06,turn:0.25)
            case "alertRise": return Pose((20.4,14.8,0.4,0),(32.9,16,-0.16),(11.2,40.5),wing:0.08,spread:0.11)
            case "alertHold": return Pose((19.5,15.4,0.8,-0.2),(33.4,14.7,-0.08),(11.8,41.1),wing:0.13,spread:0.15)
            case "alertRelax": return Pose((22,13.8,-0.3,0.5),(32.1,19.3,0.08),(9.8,39.3),spread:0.05)
            case "restLower": return Pose((24,12.4,-0.5,1.2),(31.2,23.6,0.17),(9.7,38),spread:0.04,stance:-0.6)
            case "restTuck": return Pose((24.5,12,-0.9,1.7),(27.2,26.1,2.45),(10.5,37.2),turn:0.2,stance:-1)
            case "restWake": return Pose((22.7,13.2,0,0.6),(31.9,18.4,-0.27),(9.3,39.6),wing:0.1,spread:0.1)
            case "takeoffCrouch": return Pose((25.6,10.8,1.3,0.4),(34.3,24.8,0.17),(9.1,33.4),wing:0.29,spread:0.26,stance:-1.5)
            case "takeoffPush": return Pose((18.8,12.9,1.8,0),(34.4,16.8,-0.24),(8.7,31.6),wing:0.89,spread:0.36,stance:0.6)
            case "rustFanReady": return Pose((22.6,13.5,0.2,0.2),(32.9,20,-0.02),(10,37.2),spread:0.24)
            case "rustFanOpen": return Pose((21.9,13.8,0.6,0),(33.6,19.1,-0.09),(8.6,34.5),wing:0.09,spread:1)
            case "rustFanLean": return Pose((23.1,12.6,1.2,0.1),(34.9,22.5,0.23),(10.8,35.9),spread:0.12,turn:0.2,stance:-0.4)
            case "rustFanSettle": return Pose((22.4,13.7,-0.1,0.4),(32.8,20.4,0.04),(10.3,38.6),spread:0.07,turn:0.1)
            default: return nil
            }
        case .longTailedShrike:
            switch frame {
            case "lookNear": return Pose((22.2,11.9,0.7,0),(33.6,19.9,0.25),(3.1,43.9),turn:0.15)
            case "lookFar": return Pose((21,12.5,-0.1,0),(32.6,16.1,-0.16),(3.5,44.2),turn:0.4)
            case "alertRise": return Pose((20,13.3,0.5,0),(33,14.5,-0.13),(3.9,44.7),wing:0.06)
            case "alertHold": return Pose((19.1,14,0.9,-0.2),(33.5,13.1,-0.05),(4.3,45.1),wing:0.11,turn:0.2)
            case "alertRelax": return Pose((21.6,12.2,-0.4,0.4),(32.2,18,0.05),(2.9,43.6),turn:0.25)
            case "restLower": return Pose((23.6,11.6,-0.6,1),(31.3,22.5,0.18),(3.2,42.4),stance:-0.5)
            case "restTuck": return Pose((24.2,11.2,-1,1.4),(27.1,25.1,2.5),(3.8,41.5),turn:0.3,stance:-0.9)
            case "restWake": return Pose((22.2,11.9,0,0.6),(31.9,17.3,-0.25),(2.8,43.3),wing:0.08)
            case "takeoffCrouch": return Pose((25,10.4,1.4,0.3),(34.5,23.4,0.15),(3,35.5),wing:0.26,stance:-1.4)
            case "takeoffPush": return Pose((18.4,12.3,1.9,0),(34.5,15.6,-0.22),(2.7,33.6),wing:0.86,stance:0.6)
            case "vigilPoise": return Pose((21.5,12.3,0.1,0),(32.3,17.7,-0.12),(3.5,43.4),turn:0.8)
            case "vigilReach": return Pose((21.1,12.8,1.3,-0.1),(35.4,17.2,0.04),(3,41.3),wing:0.04,turn:0.2,stance:-0.2)
            case "vigilHold": return Pose((21.3,12.5,1.1,0),(35.1,18.5,0.13),(3.7,41.8),turn:0.5,stance:-0.2)
            case "vigilSettle": return Pose((21.9,12,-0.1,0.3),(32.8,18.6,0.01),(3.3,43.7),turn:0.15)
            default: return nil
            }
        case .blackDrongo:
            switch frame {
            case "lookNear": return Pose((22.2,11.8,0.6,0),(33.4,20.2,0.24),(3.2,41.7),spread:0.15)
            case "lookFar": return Pose((21,12.4,-0.1,0),(32.4,16.6,-0.18),(3.6,42.1),spread:0.18,turn:0.25)
            case "alertRise": return Pose((20,13.2,0.4,0),(32.8,15,-0.16),(4,42.5),wing:0.08,spread:0.22)
            case "alertHold": return Pose((19.2,13.8,0.7,-0.2),(33.3,13.6,-0.07),(4.5,42.8),wing:0.14,spread:0.28)
            case "alertRelax": return Pose((21.6,12.1,-0.3,0.4),(32,18.4,0.07),(3.1,41.5),spread:0.17)
            case "restLower": return Pose((23.5,11.5,-0.5,0.8),(31.1,22.9,0.18),(3.3,40.3),spread:0.1,stance:-0.5)
            case "restTuck": return Pose((24.1,11.1,-0.9,1.2),(27,25.4,2.48),(3.9,39.7),spread:0.08,turn:0.2,stance:-0.9)
            case "restWake": return Pose((22.1,11.8,0,0.5),(31.8,17.7,-0.27),(2.9,41.6),wing:0.1,spread:0.2)
            case "takeoffCrouch": return Pose((25,10.2,1.3,0.2),(34.3,23.8,0.16),(3.2,34),wing:0.28,spread:0.3,stance:-1.4)
            case "takeoffPush": return Pose((18.4,12,1.8,0),(34.4,16,-0.25),(2.9,32.2),wing:0.9,spread:0.5,stance:0.6)
            case "forkPoise": return Pose((21.6,12.2,0.2,0),(32.7,18.6,-0.05),(3.7,40.3),wing:0.06,spread:0.3)
            case "forkOpen": return Pose((21,12.7,0.6,-0.1),(32.1,17.5,-0.18),(4.2,38.2),wing:0.2,spread:1,turn:0.7)
            case "forkFold": return Pose((21.4,12.4,-0.2,0.2),(32.8,18.2,0.07),(3.4,40.7),wing:0.03,spread:0.36,turn:0.35,droop:-0.6)
            case "forkSettle": return Pose((21.9,11.9,-0.1,0.3),(32.5,18.9,0.02),(3.5,41.4),spread:0.16,turn:0.1)
            default: return nil
            }
        case .yellowBilledGrosbeak:
            switch frame {
            case "lookNear": return Pose((21.8,13.8,0.4,0),(32.8,18.8,0.23),(11.1,38.6),turn:0.15)
            case "lookFar": return Pose((20.7,14.4,-0.2,0),(31.9,14.9,-0.16),(11.6,39.4),turn:0.35)
            case "alertRise": return Pose((19.7,15.2,0.3,0),(32.3,13.4,-0.14),(12.1,40),wing:0.06)
            case "alertHold": return Pose((18.9,15.8,0.6,-0.2),(32.7,12.2,-0.06),(12.6,40.6),wing:0.1,turn:0.15)
            case "alertRelax": return Pose((21.3,14.1,-0.3,0.5),(31.6,16.9,0.06),(10.8,38.9),turn:0.2)
            case "restLower": return Pose((23.4,12.8,-0.4,1.1),(30.8,21.8,0.17),(10.7,37.6),stance:-0.6)
            case "restTuck": return Pose((24,12.4,-0.8,1.6),(26.4,25,2.45),(11.3,36.9),turn:0.3,stance:-1)
            case "restWake": return Pose((21.8,13.7,0,0.7),(31.3,16.3,-0.26),(10.4,39),wing:0.08)
            case "takeoffCrouch": return Pose((24.9,11.2,1.1,0.4),(33.7,23.4,0.15),(10.1,33.1),wing:0.25,stance:-1.5)
            case "takeoffPush": return Pose((18.1,13.2,1.6,0),(33.8,15,-0.22),(9.7,31.4),wing:0.85,stance:0.6)
            case "billLower": return Pose((22.6,13.2,0.5,0.4),(33,21.4,0.43),(11.3,37.7),turn:0.1,stance:-0.3)
            case "billFlex": return Pose((22.9,13,0.8,0.2),(33.4,23,0.57),(11.8,36.9),turn:0.15,gape:0.65,stance:-0.4)
            case "billLift": return Pose((21.6,13.8,0.1,0.3),(32.2,16.8,-0.19),(11,38.1),turn:0.4,gape:0.15)
            case "billSettle": return Pose((21.9,13.6,-0.1,0.5),(32.4,17.9,0.02),(11.4,38.8),turn:0.15)
            default: return nil
            }
        default: return nil
        }
    }
}
