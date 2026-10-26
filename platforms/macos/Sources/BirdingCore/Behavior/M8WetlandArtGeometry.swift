import Foundation

/// M8d append-only anatomy in right-facing, top-down logical 48 units.
/// These are dry, top-perched presentation poses, not new behavior permissions.
public enum M8WetlandArtGeometry {
    public static let species: [SpeciesID] = [
        .nightHeron, .greyHeron, .chinesePondHeron, .blackWingedStilt,
        .whimbrel, .littleRingedPlover, .commonMoorhen, .eurasianCoot
    ]

    public static func frameNames(for species: SpeciesID) -> [String] {
        guard Self.species.contains(species) else { return [] }
        // Night heron's ten foundation drawings already exist. Returning them
        // here would let the new dispatcher replace historical pixels.
        return (species == .nightHeron ? [] : PoseClip.frameNames)
            + signatureFrameNames(for: species)
    }

    /// Preparation, emphasis, recovery and settling, in playback order.
    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        switch species {
        case .nightHeron: return ["shoulderGather", "shoulderTurn", "shoulderWake", "shoulderSettle"]
        case .greyHeron: return ["distantPoise", "distantReach", "distantDraw", "distantSettle"]
        case .chinesePondHeron: return ["lowPoise", "lowReach", "lowDraw", "lowSettle"]
        case .blackWingedStilt: return ["stiltBalance", "stiltTurn", "stiltInspect", "stiltSettle"]
        case .whimbrel: return ["curvePoise", "curveDip", "curveLift", "curveSettle"]
        case .littleRingedPlover: return ["ploverLower", "ploverTap", "ploverLift", "ploverSettle"]
        case .commonMoorhen: return ["railTailReady", "railTailLift", "railTailFold", "railTailSettle"]
        case .eurasianCoot: return ["breastLower", "breastLift", "breastShake", "breastSettle"]
        default: return []
        }
    }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, tailWidth: Double
        public let curvedBill: Bool
    }

    public static func anatomy(for species: SpeciesID) -> Anatomy? {
        switch species {
        case .nightHeron: return Anatomy(width:16, headWidth:7.5, headHeight:5.5, billLength:8, tailWidth:4, curvedBill:false)
        case .greyHeron: return Anatomy(width:17, headWidth:6.5, headHeight:4.1, billLength:8, tailWidth:4, curvedBill:false)
        case .chinesePondHeron: return Anatomy(width:16, headWidth:6.5, headHeight:4.6, billLength:7.5, tailWidth:4, curvedBill:false)
        case .blackWingedStilt: return Anatomy(width:17, headWidth:6, headHeight:5, billLength:7, tailWidth:4, curvedBill:false)
        case .whimbrel: return Anatomy(width:20, headWidth:7, headHeight:6, billLength:8, tailWidth:4.5, curvedBill:true)
        case .littleRingedPlover: return Anatomy(width:16, headWidth:7, headHeight:6, billLength:2.7, tailWidth:4, curvedBill:false)
        case .commonMoorhen: return Anatomy(width:22, headWidth:7, headHeight:7, billLength:3.3, tailWidth:4.5, curvedBill:false)
        case .eurasianCoot: return Anatomy(width:25, headWidth:7, headHeight:7, billLength:3.5, tailWidth:3.8, curvedBill:false)
        default: return nil
        }
    }

    public struct Pose {
        public let body: (y:Double, height:Double, lean:Double, fluff:Double)
        public let head: (x:Double, y:Double, pitch:Double)
        public let tail: (x:Double, y:Double)
        /// Local wing articulation; even Push keeps the feet planted.
        public let wing: Double
        /// Independent neck bend and knee flexion, not whole-bird transforms.
        public let neck: (x:Double, y:Double)
        public let stance, turn, eye, ruffle: Double

        fileprivate init(_ body:(Double,Double,Double,Double),
                         _ head:(Double,Double,Double), _ tail:(Double,Double),
                         wing:Double = 0, neck:(Double,Double) = (31,23),
                         stance:Double = 0, turn:Double = 0, eye:Double = 1,
                         ruffle:Double = 0) {
            self.body=body; self.head=head; self.tail=tail; self.wing=wing
            self.neck=neck; self.stance=stance; self.turn=turn
            self.eye=eye; self.ruffle=ruffle
        }

        public func headPoint(_ x:Double, _ y:Double) -> (Double,Double) {
            (head.x+x*cos(head.pitch)-y*sin(head.pitch),
             head.y+x*sin(head.pitch)+y*cos(head.pitch))
        }

        public func headWidth(anatomy:Anatomy) -> Double {
            anatomy.headWidth*(1-0.12*abs(turn))
        }

        /// Straight bill: polygon vertex 1 is the physical tip. Whimbrel:
        /// four cubic control points, with the curved endpoint as its tip.
        /// The renderer consumes these exact points before the head transform.
        public func billPath(anatomy:Anatomy) -> [(Double,Double)] {
            let root=headWidth(anatomy:anatomy)/2-0.5
            let length=anatomy.billLength*(1-0.28*abs(turn))
            if anatomy.curvedBill {
                return [(root,-0.3),(root+length*0.60,-0.2),
                        (root+length*1.06,2.2),(root+length,6.2)]
            }
            return [(root,-0.7),(root+length,0.3),
                    (root+length-0.9,1),(root,1.2)]
        }

        public func billTip(anatomy:Anatomy) -> (Double,Double) {
            let path=billPath(anatomy:anatomy)
            let tip=path[anatomy.curvedBill ? 3 : 1]
            return headPoint(tip.0,tip.1)
        }
    }

    public static func beakAnchor(species:SpeciesID, frame:String) -> PoseClip.Anchor? {
        guard let a=anatomy(for:species), let p=pose(species:species,frame:frame) else { return nil }
        let tip=p.billTip(anatomy:a)
        return PoseClip.Anchor(tip.0,tip.1)
    }

    // Each row authors the torso, head, neck and tail independently. There are
    // no aliases to stand/idle, raster inputs, or large-bird passerine scaling.
    public static func pose(species:SpeciesID, frame:String) -> Pose? {
        switch species {
        case .nightHeron:
            switch frame {
            case "shoulderGather": return Pose((21.4,11.7,-0.5,1.5),(33,19.7,0.08),(12.6,32.7),neck:(33,27),stance:-0.3,turn:0.12,eye:0.20,ruffle:0.4)
            case "shoulderTurn": return Pose((21.8,11.4,-0.8,2.0),(31.5,20.9,-0.06),(12.2,32),neck:(32,27.8),stance:-0.5,turn:0.82,eye:0.35,ruffle:0.7)
            case "shoulderWake": return Pose((20.4,12.2,-0.2,0.9),(33.7,17.5,-0.16),(13.2,32.4),wing:0.03,neck:(34,25.8),turn:0.30,eye:1,ruffle:0.2)
            case "shoulderSettle": return Pose((20.9,11.8,0.1,0.4),(33.5,18.7,0.04),(13.6,32.1),neck:(34,26.5),eye:0.7)
            default: return nil
            }
        case .greyHeron:
            switch frame {
            case "lookNear": return Pose((19.7,8.6,0.5,0),(34.2,11.7,0.22),(13.6,27.8),neck:(30.5,20.5),stance:-0.3)
            case "lookFar": return Pose((19,9,-0.1,0),(33.8,7.1,-0.12),(14.2,27.2),neck:(29.3,17.5),stance:0.2)
            case "alertRise": return Pose((18.5,9.4,0.2,0),(34,5.8,-0.10),(14.6,27.5),wing:0.06,neck:(29.5,16.2),stance:0.4)
            case "alertHold": return Pose((18,9.7,0.6,-0.2),(34.4,4.4,-0.05),(15,27.8),wing:0.10,neck:(30.2,14.8),stance:0.6)
            case "alertRelax": return Pose((19.4,8.8,-0.3,0.3),(33.3,9.8,0.07),(13.3,28.2),neck:(29.2,19.6))
            case "restLower": return Pose((21.2,8.7,-0.5,0.6),(32.4,16.4,0.19),(13,29.1),neck:(31.8,24),stance:-1.1,eye:0.25)
            case "restTuck": return Pose((22,8.3,-0.8,1),(27.7,22,2.55),(13.8,29.4),neck:(30.3,26),stance:-1.5,eye:0.1)
            case "restWake": return Pose((19.9,9.1,0,0.5),(33.1,12.2,-0.17),(12.8,28),wing:0.08,neck:(30.5,22.1),stance:-0.4)
            case "takeoffCrouch": return Pose((23.4,7.6,1.1,0.3),(34,19.1,0.13),(12.5,29.7),wing:0.24,neck:(33.5,26.4),stance:-2.3)
            case "takeoffPush": return Pose((16.8,9.1,1.5,0),(34.3,10.1,-0.17),(12,25.7),wing:1,neck:(30.6,19),stance:0.8)
            case "distantPoise": return Pose((19.3,8.8,0.1,0),(33.5,8.6,-0.06),(14,27.9),neck:(29.1,18.4),stance:-0.2)
            case "distantReach": return Pose((18.7,9.2,0.8,0),(35,5.6,-0.11),(14.5,27.1),neck:(31.4,15.3),stance:0.7)
            case "distantDraw": return Pose((19.2,9,0.3,0.2),(33,11.9,0.10),(13.5,28.6),neck:(29.7,21),stance:0.1)
            case "distantSettle": return Pose((19.6,8.7,-0.2,0.3),(33.6,9.5,0.02),(13.9,28.3),neck:(29.4,20),stance:-0.3)
            default: return nil
            }
        case .chinesePondHeron:
            switch frame {
            case "lookNear": return Pose((22.3,9.7,0.6,0),(34,18.1,0.25),(11.8,31),neck:(30.3,24),stance:-0.3)
            case "lookFar": return Pose((21.6,10,-0.2,0),(33.2,14.5,-0.17),(12.5,31.5),neck:(29,21.6))
            case "alertRise": return Pose((20.5,11,0.2,0),(33.5,12.2,-0.18),(13,31.8),wing:0.07,neck:(29.5,20.1),stance:0.3)
            case "alertHold": return Pose((20,11.5,0.7,-0.2),(34,10.8,-0.08),(13.4,32.2),wing:0.12,neck:(30.6,18.7),stance:0.5)
            case "alertRelax": return Pose((22,9.9,-0.4,0.4),(32.8,16.1,0.08),(11.5,31.3),neck:(28.9,23.5))
            case "restLower": return Pose((24,9.3,-0.6,0.9),(31.7,21.8,0.17),(11.9,32),neck:(31.8,28),stance:-0.7,eye:0.2)
            case "restTuck": return Pose((24.6,9,-0.9,1.3),(26.9,25,2.60),(12.7,32.3),neck:(30.3,29),stance:-1,eye:0.1)
            case "restWake": return Pose((22.2,10.1,-0.1,0.5),(32.5,16.8,-0.25),(11.3,31.7),wing:0.08,neck:(30,24),stance:-0.3)
            case "takeoffCrouch": return Pose((25.5,8.4,1.2,0.2),(34,24.1,0.12),(11,30),wing:0.26,neck:(33.4,29),stance:-1.6)
            case "takeoffPush": return Pose((19,10.1,1.7,0),(34.2,16.3,-0.19),(10.5,28),wing:1,neck:(31,22.4),stance:0.6)
            case "lowPoise": return Pose((23.1,9.3,0.8,0.1),(34.3,21.5,0.18),(11.8,29.9),neck:(31.5,26.3),stance:-0.5)
            case "lowReach": return Pose((24.1,8.6,1.4,0),(35.2,25.1,0.30),(11.1,28.8),neck:(33.7,28.3),stance:-1.1)
            case "lowDraw": return Pose((22.8,9.5,0.2,0.4),(32.2,20.4,-0.12),(12.5,30.4),neck:(30.1,25.7),stance:-0.3)
            case "lowSettle": return Pose((22.2,9.8,-0.2,0.3),(33.1,16.9,0.04),(12.1,31.8),neck:(29.2,23.6),stance:0.1)
            default: return nil
            }
        case .blackWingedStilt:
            switch frame {
            case "lookNear": return Pose((19.5,7.8,0.4,0),(34.3,13.5,0.27),(11.7,27.2),neck:(31.4,19.8),stance:-0.4)
            case "lookFar": return Pose((18.9,8.1,-0.2,0),(33.3,10.1,-0.17),(12.4,27.7),neck:(30.7,17.8),stance:0.2)
            case "alertRise": return Pose((18.1,8.6,0.3,0),(33.7,8.4,-0.20),(12.8,28),wing:0.09,neck:(31,16.7),stance:0.5)
            case "alertHold": return Pose((17.7,9,0.6,-0.2),(34.1,7.2,-0.10),(13.2,28.4),wing:0.15,neck:(31.6,15.8),stance:0.7)
            case "alertRelax": return Pose((19.2,8,-0.3,0.3),(32.9,11.8,0.08),(11.6,27.5),neck:(30.2,19.4))
            case "restLower": return Pose((21.5,7.6,-0.5,0.7),(31.8,18.5,0.20),(11.9,28.1),neck:(31.4,24.3),stance:-1.3,eye:0.2)
            case "restTuck": return Pose((22.2,7.3,-0.8,1),(27.1,22.5,2.51),(12.6,28.5),neck:(30.3,26),stance:-1.8,eye:0.1)
            case "restWake": return Pose((19.8,8.2,0,0.5),(32.4,13.2,-0.28),(11.2,27.9),wing:0.09,neck:(31.2,21),stance:-0.5)
            case "takeoffCrouch": return Pose((23.1,6.9,1.1,0.2),(34.4,21.5,0.15),(10.9,27.2),wing:0.28,neck:(33.6,26.2),stance:-2.6)
            case "takeoffPush": return Pose((16.5,8.2,1.6,0),(34.7,11.2,-0.22),(10.5,24.8),wing:1,neck:(31.5,18.9),stance:1)
            case "stiltBalance": return Pose((19.3,7.9,0.7,0),(33.8,11.4,0.04),(12.6,27.4),neck:(31.2,18.8),stance:0.9)
            case "stiltTurn": return Pose((19.6,7.7,0.4,0.2),(32.7,12.5,-0.08),(11.8,27.9),neck:(30.7,20),stance:0.6,turn:0.7)
            case "stiltInspect": return Pose((20.2,7.5,0.9,0),(34.1,20.8,0.85),(11.2,26.9),neck:(32.5,24.5),stance:-0.8)
            case "stiltSettle": return Pose((19.1,8,-0.1,0.2),(33.2,11.9,0.09),(12.1,28.2),neck:(30.6,19.7),stance:-0.2)
            default: return nil
            }
        case .whimbrel:
            switch frame {
            case "lookNear": return Pose((23.4,9.7,0.5,0),(33.5,19.8,0.22),(9.6,31.3),neck:(31,25.5),stance:-0.3)
            case "lookFar": return Pose((22.6,10.2,-0.2,0),(32.7,16.9,-0.18),(10.3,31.9),neck:(30.3,23.8))
            case "alertRise": return Pose((21.6,11,0.2,0),(33,15,-0.22),(10.8,32.4),wing:0.08,neck:(30.5,22.3),stance:0.2)
            case "alertHold": return Pose((21,11.5,0.6,-0.2),(33.4,13.7,-0.12),(11.2,32.7),wing:0.14,neck:(31,21.4),stance:0.4)
            case "alertRelax": return Pose((23,10,-0.4,0.4),(32.2,18.1,0.06),(9.4,31.6),neck:(29.7,24.8))
            case "restLower": return Pose((25.1,9.3,-0.6,0.8),(31.2,23.2,0.13),(9.8,32.5),neck:(30.5,28.5),stance:-0.6,eye:0.2)
            case "restTuck": return Pose((25.7,9,-1,1.3),(27.5,26.3,2.75),(10.6,32.9),neck:(29.3,29.5),stance:-0.9,eye:0.1)
            case "restWake": return Pose((23.2,10.3,0,0.5),(31.9,18.8,-0.24),(9.2,32.1),wing:0.09,neck:(30.1,25.4),stance:-0.2)
            case "takeoffCrouch": return Pose((26.2,8.4,1.3,0.3),(34,24.7,0.12),(8.8,29.9),wing:0.28,neck:(32.5,29.2),stance:-1.5)
            case "takeoffPush": return Pose((19.4,10.2,1.8,0),(34.2,17.7,-0.20),(8.3,28.1),wing:1,neck:(31.6,24),stance:0.6)
            case "curvePoise": return Pose((23.9,9.5,0.8,0),(34,22.1,0.38),(10.1,30.2),neck:(31.8,26.8),stance:-0.5)
            case "curveDip": return Pose((25,8.8,1.5,0.1),(34.4,26.5,0.64),(9.4,28.8),wing:0.03,neck:(33,29.3),stance:-1)
            case "curveLift": return Pose((22.7,10.3,0.2,0.2),(32.9,17.8,-0.30),(10.8,31),neck:(30.2,24.1),stance:0.2)
            case "curveSettle": return Pose((23.1,10,-0.2,0.3),(32.5,19.2,0.02),(9.8,32.2),neck:(30.5,25.6),stance:-0.1)
            default: return nil
            }
        case .littleRingedPlover:
            switch frame {
            case "lookNear": return Pose((23.5,8.8,0.4,0),(33.7,20.8,0.29),(11.6,31.5),stance:-0.2)
            case "lookFar": return Pose((22.7,9.4,-0.2,0),(32.8,17.6,-0.20),(12.3,32.1))
            case "alertRise": return Pose((21.7,10.2,0.3,0),(33.1,15.9,-0.23),(12.8,32.5),wing:0.09,stance:0.2)
            case "alertHold": return Pose((21.1,10.8,0.6,-0.2),(33.5,14.7,-0.12),(13.1,32.9),wing:0.15,stance:0.3)
            case "alertRelax": return Pose((23.1,9.1,-0.3,0.4),(32.4,19,0.07),(11.5,31.8))
            case "restLower": return Pose((25,8.8,-0.5,0.8),(31.6,23.4,0.18),(11.8,32.7),stance:-0.5,eye:0.2)
            case "restTuck": return Pose((25.6,8.5,-0.8,1.2),(27.1,26,2.54),(12.6,33),stance:-0.8,eye:0.1)
            case "restWake": return Pose((23.3,9.6,0,0.5),(32.1,19.6,-0.27),(11.2,32.3),wing:0.09,stance:-0.2)
            case "takeoffCrouch": return Pose((26.3,7.7,1.1,0.2),(34.2,25.1,0.14),(10.8,30.1),wing:0.26,stance:-1.3)
            case "takeoffPush": return Pose((19.7,9.4,1.6,0),(34.5,18.2,-0.24),(10.2,28.5),wing:1,stance:0.5)
            case "ploverLower": return Pose((24.5,8.3,1,0),(34.6,24.8,0.55),(12.2,30.2),stance:-0.5)
            case "ploverTap": return Pose((25.7,7.6,1.6,0),(35.5,31.8,1.03),(11.4,28.5),wing:0.05,stance:-1)
            case "ploverLift": return Pose((22.7,9.5,0.3,0.2),(33.3,18.3,-0.32),(12.8,31.3),stance:0.2)
            case "ploverSettle": return Pose((23.4,9,-0.2,0.3),(32.9,20,0.03),(12,32.4),turn:0.18)
            default: return nil
            }
        case .commonMoorhen:
            switch frame {
            case "lookNear": return Pose((26.3,11.7,0.5,0),(33.6,22.3,0.26),(11.7,30.6),neck:(31,28.5),stance:-0.2)
            case "lookFar": return Pose((25.4,12.3,-0.2,0),(32.8,19.4,-0.18),(12.3,31.2),neck:(30,27))
            case "alertRise": return Pose((24.4,13.1,0.3,0),(33.1,17.7,-0.20),(12.7,31.5),wing:0.08,neck:(30.5,26),stance:0.2)
            case "alertHold": return Pose((23.8,13.6,0.7,-0.2),(33.5,16.3,-0.10),(13.1,31.9),wing:0.14,neck:(31,25),stance:0.4)
            case "alertRelax": return Pose((25.8,12,-0.3,0.4),(32.4,20.5,0.07),(11.5,30.9),neck:(29.8,28))
            case "restLower": return Pose((27.5,10.7,-0.5,0.7),(31.3,25.5,0.18),(11.8,31.7),neck:(30.7,31),stance:-0.5,eye:0.2)
            case "restTuck": return Pose((27.9,10.4,-0.9,1.1),(26.5,28,2.48),(12.5,32),neck:(29,32),stance:-0.8,eye:0.1)
            case "restWake": return Pose((26,11.9,0,0.5),(32,21.2,-0.26),(11.2,31.4),wing:0.08,neck:(30.2,28.6),stance:-0.2)
            case "takeoffCrouch": return Pose((28.5,9.4,1.1,0.2),(34.1,27,0.12),(10.8,28.8),wing:0.25,neck:(32.8,32),stance:-1.2)
            case "takeoffPush": return Pose((21.6,11.8,1.6,0),(34.3,20,-0.22),(10.2,27),wing:1,neck:(31.5,26.5),stance:0.5)
            case "railTailReady": return Pose((26,11.9,0.1,0),(33,20.9,0.04),(11.8,27.3),neck:(30.4,27.9),stance:-0.2)
            case "railTailLift": return Pose((26.7,11.1,0.8,0),(33.6,22.4,0.18),(13.3,21.2),wing:0.06,neck:(31.3,29),stance:-0.6,turn:0.45)
            case "railTailFold": return Pose((25.6,12.2,0.2,0.2),(32.5,19.7,-0.13),(12.5,26.3),neck:(30.1,27.2),stance:0.2,turn:0.2)
            case "railTailSettle": return Pose((26.1,11.8,-0.2,0.3),(32.8,21.5,0.06),(11.6,30.7),neck:(30.4,28.5),stance:-0.1)
            default: return nil
            }
        case .eurasianCoot:
            switch frame {
            case "lookNear": return Pose((26.3,11.8,0.4,0),(33.8,23,0.23),(11.7,32.4),neck:(31.2,29.4),stance:-0.2)
            case "lookFar": return Pose((25.6,12.5,-0.2,0),(33,20.4,-0.16),(12.3,32.9),neck:(30.2,28))
            case "alertRise": return Pose((24.6,13.2,0.2,0),(33.3,18.5,-0.18),(12.8,33.3),wing:0.06,neck:(30.6,26.8),stance:0.2)
            case "alertHold": return Pose((24,13.8,0.6,-0.2),(33.7,17.2,-0.09),(13.2,33.7),wing:0.12,neck:(31.2,26),stance:0.3)
            case "alertRelax": return Pose((26,12.1,-0.3,0.3),(32.6,21.6,0.06),(11.5,32.6),neck:(30,28.8))
            case "restLower": return Pose((27.4,10.7,-0.5,0.7),(31.6,26.1,0.16),(11.8,33.4),neck:(30.5,31.8),stance:-0.5,eye:0.2)
            case "restTuck": return Pose((27.8,10.4,-0.8,1.1),(26.4,28.6,2.52),(12.6,33.8),neck:(29.2,32.8),stance:-0.8,eye:0.1)
            case "restWake": return Pose((26.2,11.8,0,0.5),(32.2,22.3,-0.24),(11.2,33.1),wing:0.08,neck:(30.4,29.4),stance:-0.2)
            case "takeoffCrouch": return Pose((28.4,9.4,1,0.2),(34.2,27.7,0.12),(10.8,30.5),wing:0.24,neck:(33,32.5),stance:-1.2)
            case "takeoffPush": return Pose((22,11.7,1.4,0),(34.5,20.8,-0.20),(10.3,28.7),wing:1,neck:(31.6,27),stance:0.5)
            case "breastLower": return Pose((26.9,11.1,0.1,0.5),(32,26.1,1.93),(12.2,32.1),neck:(32.5,29.8),stance:-0.4,eye:0.65)
            case "breastLift": return Pose((25.5,12.3,0.3,0.2),(33.4,20.4,-0.26),(12.8,32.8),wing:0.04,neck:(30.6,28),stance:0.1)
            case "breastShake": return Pose((26.1,11.7,-0.5,1.4),(32.5,21.9,0.14),(11.4,31.6),wing:0.14,neck:(30.1,29),stance:-0.3,ruffle:1)
            case "breastSettle": return Pose((26.4,11.5,-0.1,0.3),(33,22.7,0.02),(12,33.3),neck:(30.5,29.5),stance:-0.1)
            default: return nil
            }
        default: return nil
        }
    }
}
