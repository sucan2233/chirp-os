import Foundation

/// E3 source geometry, right-facing on the logical 48-unit canvas. All poses
/// articulate anatomical parts; no existing frame is an input to this pack.
public enum ExpansionDisplayArtGeometry {
    public static let species: [SpeciesID] = [
        .eurasianMagpie, .greyTreepie, .redBilledBlueMagpie, .yellowBilledBlueMagpie,
        .ashyDrongo, .blueWhistlingThrush, .sootyHeadedBulbul, .brownBreastedBulbul,
        .blackBulbul, .collaredFinchbill, .taiwanBarbet, .blueThroatedBarbet
    ]

    public static func frameNames(for species: SpeciesID) -> [String] {
        Self.species.contains(species) ? PoseClip.frameNames + signatureFrameNames(for:species) : []
    }

    /// Frozen append order: preparation, emphasis, recovery, settled pose.
    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        switch species {
        case .eurasianMagpie: return ["eurasianTailReady", "eurasianTailBalance", "eurasianTailReturn", "eurasianTailSettle"]
        case .greyTreepie: return ["treepieTailReady", "treepieTailSweep", "treepieLookBack", "treepieTailSettle"]
        case .redBilledBlueMagpie: return ["redBlueTailReady", "redBlueTailArc", "redBlueHeadReturn", "redBlueTailSettle"]
        case .yellowBilledBlueMagpie: return ["yellowBlueTailReady", "yellowBlueTailPoise", "yellowBlueTailReturn", "yellowBlueTailSettle"]
        case .ashyDrongo: return ["ashyForkReady", "ashyForkOpen", "ashyForkClose", "ashyForkSettle"]
        case .blueWhistlingThrush: return ["whistleTailReady", "whistleTailFan", "whistleTailFold", "whistleTailSettle"]
        case .sootyHeadedBulbul: return ["sootyCallReady", "sootyCallOpen", "sootyCallClose", "sootyCallSettle"]
        case .brownBreastedBulbul: return ["brownCallReady", "brownCallOpen", "brownCallReturn", "brownCallSettle"]
        case .blackBulbul: return ["blackCallReady", "blackCallOpen", "blackCallClose", "blackCallSettle"]
        case .collaredFinchbill: return ["collarBillReady", "collarBillFlex", "collarBillLift", "collarBillSettle"]
        case .taiwanBarbet: return ["taiwanCallReady", "taiwanCallOpen", "taiwanCallReturn", "taiwanCallSettle"]
        case .blueThroatedBarbet: return ["blueThroatReady", "blueThroatOpen", "blueThroatReturn", "blueThroatSettle"]
        default: return []
        }
    }

    public enum BillShape { case pointed, deep, conical, barbet }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, billDepth: Double
        public let tailWidth, wingReach, primaryLength, crest: Double
        public let bill: BillShape
    }

    public static func anatomy(for species: SpeciesID) -> Anatomy? {
        switch species {
        case .eurasianMagpie:
            return Anatomy(width:18, headWidth:8, headHeight:7, billLength:3.2, billDepth:1.1,
                           tailWidth:4.5, wingReach:16, primaryLength:10.2, crest:0, bill:.pointed)
        case .greyTreepie:
            return Anatomy(width:19, headWidth:8, headHeight:7, billLength:3.5, billDepth:1.3,
                           tailWidth:5.1, wingReach:15.2, primaryLength:10.7, crest:0, bill:.deep)
        case .redBilledBlueMagpie:
            return Anatomy(width:14, headWidth:7, headHeight:6, billLength:3.4, billDepth:1.2,
                           tailWidth:4.2, wingReach:17, primaryLength:10, crest:0, bill:.deep)
        case .yellowBilledBlueMagpie:
            return Anatomy(width:14, headWidth:7, headHeight:6, billLength:3.1, billDepth:1.4,
                           tailWidth:4.5, wingReach:16.4, primaryLength:9.7, crest:0, bill:.deep)
        case .ashyDrongo:
            return Anatomy(width:17, headWidth:8, headHeight:7, billLength:3.1, billDepth:1,
                           tailWidth:7.2, wingReach:16, primaryLength:11.2, crest:0.7, bill:.pointed)
        case .blueWhistlingThrush:
            return Anatomy(width:23, headWidth:9, headHeight:8, billLength:3.6, billDepth:1.4,
                           tailWidth:6.5, wingReach:15.3, primaryLength:11.1, crest:0, bill:.deep)
        case .sootyHeadedBulbul:
            return Anatomy(width:19, headWidth:8, headHeight:7, billLength:3, billDepth:0.9,
                           tailWidth:5.8, wingReach:14, primaryLength:10, crest:2, bill:.pointed)
        case .brownBreastedBulbul:
            return Anatomy(width:20, headWidth:8, headHeight:7, billLength:3.1, billDepth:1,
                           tailWidth:6.2, wingReach:14.7, primaryLength:10.4, crest:0, bill:.pointed)
        case .blackBulbul:
            return Anatomy(width:20, headWidth:8, headHeight:7, billLength:3.2, billDepth:1.1,
                           tailWidth:6.1, wingReach:15.1, primaryLength:10.7, crest:4, bill:.pointed)
        case .collaredFinchbill:
            return Anatomy(width:19, headWidth:9, headHeight:8, billLength:4, billDepth:1.8,
                           tailWidth:5.7, wingReach:13.9, primaryLength:10.2, crest:0, bill:.conical)
        case .taiwanBarbet:
            return Anatomy(width:21, headWidth:12, headHeight:10, billLength:6, billDepth:1.8,
                           tailWidth:6.4, wingReach:13.6, primaryLength:10.1, crest:0, bill:.barbet)
        case .blueThroatedBarbet:
            return Anatomy(width:22, headWidth:12, headHeight:10, billLength:5.7, billDepth:1.9,
                           tailWidth:6.8, wingReach:14.1, primaryLength:10.8, crest:0, bill:.barbet)
        default: return nil
        }
    }

    public struct Pose {
        public let body: (y:Double, height:Double, lean:Double, fluff:Double)
        public let head: (x:Double, y:Double, pitch:Double)
        /// Tail's central distal point, independent of the rump and shoulder.
        public let tail: (x:Double, y:Double)
        public let wing, spread, turn, gape, stance, crest: Double

        fileprivate init(_ body:(Double,Double,Double,Double), _ head:(Double,Double,Double),
                         _ tail:(Double,Double), wing:Double = 0, spread:Double = 0,
                         turn:Double = 0, gape:Double = 0, stance:Double = 0, crest:Double = 0) {
            self.body=body; self.head=head; self.tail=tail
            self.wing=wing; self.spread=spread; self.turn=turn
            self.gape=gape; self.stance=stance; self.crest=crest
        }

        public func headWidth(anatomy:Anatomy) -> Double {
            anatomy.headWidth*(1-turn*0.12)
        }

        public func headPoint(_ x:Double, _ y:Double) -> (Double,Double) {
            (head.x+x*cos(head.pitch)-y*sin(head.pitch),
             head.y+x*sin(head.pitch)+y*cos(head.pitch))
        }

        /// Vertex 1 is the upper mandible's terminal contact. Neither the painter
        /// nor the anchor clamps it; gape articulates only the lower mandible.
        public func billVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let root=headWidth(anatomy:a)/2-0.4
            let length=a.billLength*(1-turn*0.1), depth=a.billDepth
            let tip=(root+length,0.45)
            switch a.bill {
            case .pointed:
                return [(root,-depth*0.6),tip,(root+length*0.6,0.95),(root,depth)]
            case .deep:
                return [(root,-depth*0.8),tip,(tip.0-0.5,1.05),(root,depth)]
            case .conical:
                return [(root-0.2,-depth),tip,(root+0.2,depth)]
            case .barbet:
                return [(root,-depth),(tip.0,tip.1),(tip.0-0.8,1.1),
                        (root+length*0.3,depth),(root-0.3,depth*0.8)]
            }
        }

        public func lowerBillVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let root=headWidth(anatomy:a)/2-0.4, length=a.billLength*(1-turn*0.1)
            return [(root,0.8),(root+length-0.45,0.85+gape*2.8),
                    (root+length*0.32,a.billDepth+gape*2.2),
                    (root,a.billDepth+gape*0.8)]
        }
    }

    public static let toePaths: [[(Double,Double)]] = [
        [(25,39),(27,38.5),(29,39)], [(29,39),(31,38.5),(33,39)]
    ]

    public static func beakAnchor(species:SpeciesID, frame:String) -> PoseClip.Anchor? {
        guard let a=anatomy(for:species), let p=pose(species:species,frame:frame) else { return nil }
        let bill=p.billVertices(anatomy:a)[1], tip=p.headPoint(bill.0,bill.1)
        return PoseClip.Anchor(tip.0,tip.1)
    }

    /// Each row authors torso, head, wing and tail separately. Signature rows
    /// remain distinct even on recovery and settling; old idle names are rejected.
    public static func pose(species:SpeciesID, frame:String) -> Pose? {
        switch species {
        case .eurasianMagpie:
            switch frame {
            case "lookNear": return Pose((22.5,11.8,0.7,0),(33.3,20.5,0.29),(2.1,43.8),wing:0.03,spread:0.12)
            case "lookFar": return Pose((21.1,12.7,-0.2,0),(32.4,16.6,-0.19),(2.6,44.5),wing:0.05,turn:0.5)
            case "alertRise": return Pose((20.2,13.3,0.4,0),(32.9,15,-0.15),(3.1,43.2),wing:0.11,spread:0.15)
            case "alertHold": return Pose((19.3,14,0.9,-0.2),(33.4,13.8,-0.06),(3.6,42.1),wing:0.18,spread:0.22)
            case "alertRelax": return Pose((21.8,12.1,-0.4,0.5),(32.1,18.7,0.1),(2.3,43.9),wing:0.02,turn:0.2)
            case "restLower": return Pose((24.1,11.1,-0.6,1),(31.2,23.1,0.19),(2.5,42.5),stance:-0.5)
            case "restTuck": return Pose((24.8,10.7,-1.1,1.5),(26.6,25.7,2.47),(3.2,41.6),turn:0.25,stance:-0.9)
            case "restWake": return Pose((22.4,11.9,0.1,0.6),(31.8,17.9,-0.3),(2.2,43.3),wing:0.12,spread:0.1)
            case "takeoffCrouch": return Pose((25.7,9.6,1.4,0.3),(34.5,24.2,0.17),(2.4,35.1),wing:0.3,spread:0.34,stance:-1.5)
            case "takeoffPush": return Pose((18.7,11.7,2,0),(34.6,15.9,-0.26),(2.1,32.4),wing:0.92,spread:0.48,stance:0.7)
            case "eurasianTailReady": return Pose((22,12.2,0.3,0.1),(32.7,18.5,-0.08),(2.9,41.5),wing:0.06,spread:0.2,turn:0.3)
            case "eurasianTailBalance": return Pose((22.9,11.4,1.1,0),(34.1,21,0.27),(4,32.8),wing:0.16,spread:0.46,stance:-0.6)
            case "eurasianTailReturn": return Pose((21.5,12.8,-0.1,0.2),(31.9,17,-0.22),(3.1,38.3),wing:0.09,spread:0.25,turn:0.65)
            case "eurasianTailSettle": return Pose((22.3,12,-0.2,0.35),(32.6,19.1,0.03),(2.4,43.1),wing:0.04,spread:0.08,turn:0.15)
            default: return nil
            }
        case .greyTreepie:
            switch frame {
            case "lookNear": return Pose((22.7,12.6,0.6,0),(33.4,21.1,0.26),(2.2,42.9),wing:0.02,turn:0.15)
            case "lookFar": return Pose((21.4,13.4,-0.1,0),(32.5,17.4,-0.21),(2.8,43.8),wing:0.04,spread:0.1,turn:0.55)
            case "alertRise": return Pose((20.3,14.1,0.5,0),(33,15.8,-0.18),(3.3,42.7),wing:0.1,spread:0.2)
            case "alertHold": return Pose((19.5,14.8,0.8,-0.2),(33.5,14.4,-0.07),(3.9,41.3),wing:0.16,spread:0.28,turn:0.2)
            case "alertRelax": return Pose((22.1,12.9,-0.3,0.4),(32.2,19.3,0.08),(2.5,43.3),wing:0.03,turn:0.25)
            case "restLower": return Pose((24.3,11.9,-0.6,1.1),(31.3,23.9,0.21),(2.7,41.8),stance:-0.6)
            case "restTuck": return Pose((25,11.3,-1,1.7),(26.9,26.5,2.5),(3.4,40.9),turn:0.35,stance:-1)
            case "restWake": return Pose((22.7,12.8,0,0.7),(32,18.5,-0.28),(2.3,42.8),wing:0.13,spread:0.13)
            case "takeoffCrouch": return Pose((25.9,10.2,1.3,0.4),(34.6,24.9,0.19),(2.6,34.2),wing:0.29,spread:0.3,stance:-1.6)
            case "takeoffPush": return Pose((19,12.4,1.8,0),(34.7,16.6,-0.24),(2.2,31.7),wing:0.9,spread:0.43,stance:0.6)
            case "treepieTailReady": return Pose((22.2,13,0.2,0.2),(32.7,19.2,-0.02),(3.1,41),wing:0.05,spread:0.2,turn:0.25)
            case "treepieTailSweep": return Pose((21.7,13.5,-0.5,0),(31.9,18,-0.16),(4.6,33.7),wing:0.14,spread:0.75,turn:0.6)
            case "treepieLookBack": return Pose((22.4,12.8,-0.3,0.3),(30,19.8,-0.35),(3.5,38.6),wing:0.08,spread:0.32,turn:0.95)
            case "treepieTailSettle": return Pose((22.5,12.7,-0.1,0.5),(32.9,20,0.05),(2.6,42.5),wing:0.03,spread:0.08,turn:0.2)
            default: return nil
            }
        case .redBilledBlueMagpie:
            switch frame {
            case "lookNear": return Pose((22.3,10.2,0.7,0),(33.8,18.6,0.27),(1.8,44.7),wing:0.04,spread:0.15)
            case "lookFar": return Pose((21.2,10.9,-0.2,0),(32.9,15.3,-0.22),(2.1,45.2),wing:0.03,spread:0.08,turn:0.45)
            case "alertRise": return Pose((20.2,11.6,0.4,0),(33.3,13.9,-0.18),(2.5,44.3),wing:0.12,spread:0.22)
            case "alertHold": return Pose((19.4,12.2,0.8,-0.15),(33.7,12.6,-0.08),(2.9,43.5),wing:0.19,spread:0.3,turn:0.15)
            case "alertRelax": return Pose((21.8,10.5,-0.3,0.3),(32.6,17,0.07),(1.9,44.8),wing:0.05,spread:0.12)
            case "restLower": return Pose((24.1,9.7,-0.5,0.8),(31.8,21.4,0.18),(2.2,43.7),stance:-0.5)
            case "restTuck": return Pose((24.9,9.3,-0.8,1.2),(28.5,25,2.43),(2.7,42.9),turn:0.3,stance:-0.9)
            case "restWake": return Pose((22.4,10.3,0.1,0.4),(32.3,16.3,-0.29),(1.7,44.1),wing:0.11,spread:0.19)
            case "takeoffCrouch": return Pose((25.6,8.6,1.4,0.2),(34.9,22.7,0.16),(1.9,36.2),wing:0.32,spread:0.42,stance:-1.5)
            case "takeoffPush": return Pose((18.8,10.1,2,0),(35,14.7,-0.27),(1.6,33),wing:0.94,spread:0.62,stance:0.7)
            case "redBlueTailReady": return Pose((21.9,10.5,0.2,0.1),(33.2,17.2,-0.1),(2.3,42.3),wing:0.06,spread:0.28,turn:0.2)
            case "redBlueTailArc": return Pose((22.7,9.9,1,0),(34.1,19,0.17),(3.5,32.4),wing:0.18,spread:0.82,stance:-0.4)
            case "redBlueHeadReturn": return Pose((21.4,11,-0.2,0.2),(31.8,15.8,-0.3),(2.6,38.6),wing:0.1,spread:0.45,turn:0.8)
            case "redBlueTailSettle": return Pose((22.2,10.4,-0.1,0.25),(33,17.7,0.03),(2,44),wing:0.03,spread:0.14,turn:0.15)
            default: return nil
            }
        case .yellowBilledBlueMagpie:
            switch frame {
            case "lookNear": return Pose((22.5,10.1,0.5,0),(33.6,18.9,0.24),(1.9,44.4),wing:0.03,spread:0.1,turn:0.1)
            case "lookFar": return Pose((21.3,10.7,-0.2,0),(32.7,15.6,-0.18),(2.3,45),wing:0.05,turn:0.6)
            case "alertRise": return Pose((20.4,11.3,0.3,0),(33.1,14.1,-0.15),(2.8,44.1),wing:0.1,spread:0.18)
            case "alertHold": return Pose((19.6,12,0.7,-0.2),(33.5,12.9,-0.05),(3.2,43),wing:0.16,spread:0.27,turn:0.25)
            case "alertRelax": return Pose((22,10.4,-0.4,0.4),(32.5,17.3,0.09),(2.1,44.6),wing:0.02,spread:0.08)
            case "restLower": return Pose((24.2,9.6,-0.6,0.9),(31.5,21.8,0.2),(2.4,43.3),stance:-0.6)
            case "restTuck": return Pose((25,9.1,-1,1.4),(28.1,25.4,2.51),(2.9,42.3),turn:0.4,stance:-1)
            case "restWake": return Pose((22.6,10.2,0,0.5),(32.1,16.7,-0.25),(1.8,43.9),wing:0.12,spread:0.2)
            case "takeoffCrouch": return Pose((25.8,8.4,1.2,0.3),(34.6,23.1,0.18),(2,35.6),wing:0.28,spread:0.36,stance:-1.4)
            case "takeoffPush": return Pose((19,9.9,1.8,0),(34.8,15,-0.23),(1.8,32.6),wing:0.9,spread:0.55,stance:0.6)
            case "yellowBlueTailReady": return Pose((22.1,10.5,0.1,0.15),(32.9,17.5,-0.04),(2.5,42),wing:0.04,spread:0.24,turn:0.35)
            case "yellowBlueTailPoise": return Pose((21.7,11,0.6,0),(32,15.9,-0.32),(3.8,34),wing:0.13,spread:0.68,turn:0.85)
            case "yellowBlueTailReturn": return Pose((22.7,9.9,0.4,0.25),(33.5,18.1,0.12),(2.8,39.1),wing:0.08,spread:0.31,turn:0.4)
            case "yellowBlueTailSettle": return Pose((22.3,10.3,-0.2,0.3),(32.8,18,0.02),(2.2,43.8),wing:0.02,spread:0.12,turn:0.2)
            default: return nil
            }
        case .ashyDrongo:
            switch frame {
            case "lookNear": return Pose((22.6,10.9,0.6,0),(33.4,20.5,0.25),(3.5,40.4),wing:0.03,spread:0.13)
            case "lookFar": return Pose((21.3,11.7,-0.2,0),(32.5,16.9,-0.2),(3.9,40.9),wing:0.04,spread:0.2,turn:0.5)
            case "alertRise": return Pose((20.3,12.3,0.4,0),(32.9,15.3,-0.17),(4.4,40.1),wing:0.1,spread:0.26,crest:0.2)
            case "alertHold": return Pose((19.5,13,0.8,-0.2),(33.4,14,-0.06),(4.9,39.5),wing:0.17,spread:0.34,crest:0.4)
            case "alertRelax": return Pose((22,11.3,-0.3,0.4),(32.2,18.8,0.08),(3.7,40.6),wing:0.02,spread:0.15)
            case "restLower": return Pose((24,10.6,-0.5,0.9),(31.3,23.3,0.18),(3.9,39.4),spread:0.08,stance:-0.5)
            case "restTuck": return Pose((24.7,10.2,-0.9,1.4),(27.1,25.8,2.45),(4.4,38.8),spread:0.05,turn:0.3,stance:-0.9)
            case "restWake": return Pose((22.4,11.2,0.1,0.5),(31.9,18.1,-0.29),(3.4,40.2),wing:0.12,spread:0.22)
            case "takeoffCrouch": return Pose((25.5,9.3,1.4,0.3),(34.4,24.3,0.17),(3.7,33.4),wing:0.3,spread:0.4,stance:-1.4)
            case "takeoffPush": return Pose((18.8,11,1.9,0),(34.5,16.4,-0.25),(3.3,31.6),wing:0.91,spread:0.58,stance:0.6)
            case "ashyForkReady": return Pose((22.1,11.4,0.2,0.1),(32.8,19.1,-0.06),(4.1,39.2),wing:0.06,spread:0.3,turn:0.2)
            case "ashyForkOpen": return Pose((21.5,11.9,0.5,0),(31.9,17.7,-0.23),(4.8,37.2),wing:0.19,spread:1,turn:0.85,crest:0.25)
            case "ashyForkClose": return Pose((21.9,11.6,-0.2,0.3),(32.6,18.6,0.1),(3.9,39.7),wing:0.08,spread:0.38,turn:0.4)
            case "ashyForkSettle": return Pose((22.3,11.2,-0.1,0.4),(32.7,19.5,0.02),(3.8,40.1),wing:0.02,spread:0.17,turn:0.15)
            default: return nil
            }
        case .blueWhistlingThrush:
            switch frame {
            case "lookNear": return Pose((22.4,13.8,0.7,0),(33.2,19.9,0.27),(6.7,40.1),wing:0.03,spread:0.1)
            case "lookFar": return Pose((21.1,14.4,-0.2,0),(32.3,16.2,-0.18),(7.3,40.8),wing:0.04,turn:0.45)
            case "alertRise": return Pose((20.1,15.1,0.4,0),(32.8,14.6,-0.16),(7.8,39.9),wing:0.11,spread:0.18)
            case "alertHold": return Pose((19.2,15.8,0.9,-0.25),(33.3,13.2,-0.07),(8.4,39.2),wing:0.17,spread:0.26)
            case "alertRelax": return Pose((21.8,14,-0.4,0.5),(32,18.3,0.09),(6.9,40.4),wing:0.02,turn:0.2)
            case "restLower": return Pose((24,12.8,-0.6,1.2),(31,22.7,0.2),(7.1,39.2),stance:-0.6)
            case "restTuck": return Pose((24.7,12.1,-1.1,1.8),(26.3,25.5,2.5),(7.8,38.3),turn:0.3,stance:-1)
            case "restWake": return Pose((22.3,13.7,0,0.7),(31.7,17.6,-0.3),(6.5,39.9),wing:0.13,spread:0.14)
            case "takeoffCrouch": return Pose((25.6,10.8,1.5,0.4),(34.4,24,0.18),(6.8,33.8),wing:0.31,spread:0.4,stance:-1.6)
            case "takeoffPush": return Pose((18.6,13.2,2.1,0),(34.5,15.6,-0.26),(6.4,31.5),wing:0.92,spread:0.62,stance:0.7)
            case "whistleTailReady": return Pose((21.9,14.1,0.2,0.2),(32.5,18.4,-0.07),(7.4,38.7),wing:0.05,spread:0.3,turn:0.3)
            case "whistleTailFan": return Pose((21.3,14.7,0.7,0),(31.7,16.8,-0.26),(8.6,34.5),wing:0.18,spread:1,turn:0.8)
            case "whistleTailFold": return Pose((22.6,13.5,0.1,0.4),(32.9,19.1,0.13),(7.6,37.9),wing:0.09,spread:0.4,turn:0.4)
            case "whistleTailSettle": return Pose((22.1,14,-0.2,0.5),(32.4,18.9,0.03),(7,39.7),wing:0.03,spread:0.12,turn:0.15)
            default: return nil
            }
        default: return remainingPose(species:species,frame:frame)
        }
    }

    private static func remainingPose(species:SpeciesID, frame:String) -> Pose? {
        switch species {
        case .sootyHeadedBulbul:
            switch frame {
            case "lookNear": return Pose((22.7,11.8,0.6,0),(33.5,20.6,0.28),(6.5,40.7),wing:0.03,turn:0.15)
            case "lookFar": return Pose((21.5,12.4,-0.2,0),(32.6,17.1,-0.21),(7,41.4),wing:0.04,turn:0.5)
            case "alertRise": return Pose((20.4,13.1,0.4,0),(33,15.5,-0.18),(7.5,40.5),wing:0.1,crest:0.2)
            case "alertHold": return Pose((19.6,13.7,0.8,-0.2),(33.5,14.1,-0.06),(8.1,39.8),wing:0.16,crest:0.4)
            case "alertRelax": return Pose((22.1,12.1,-0.3,0.5),(32.3,18.9,0.08),(6.7,41),wing:0.02,turn:0.2)
            case "restLower": return Pose((24.2,11.1,-0.6,1.1),(31.4,23.3,0.18),(6.9,39.8),stance:-0.5,crest:-0.4)
            case "restTuck": return Pose((24.9,10.6,-1,1.6),(27.2,26,2.48),(7.5,39),turn:0.3,stance:-0.9,crest:-0.6)
            case "restWake": return Pose((22.6,11.7,0.1,0.6),(32.1,18.2,-0.3),(6.3,40.5),wing:0.12,spread:0.15)
            case "takeoffCrouch": return Pose((25.7,9.6,1.3,0.3),(34.6,24.3,0.16),(6.6,34.1),wing:0.28,spread:0.3,stance:-1.4)
            case "takeoffPush": return Pose((19,11.5,1.9,0),(34.7,16.4,-0.25),(6.2,32),wing:0.91,spread:0.5,stance:0.6,crest:0.2)
            case "sootyCallReady": return Pose((21.9,12.4,0.2,0.35),(32.8,17.8,-0.24),(7.1,40.2),wing:0.06,spread:0.1,gape:0.12,crest:0.15)
            case "sootyCallOpen": return Pose((20.9,13.5,0.7,0.65),(33.5,15.3,-0.58),(7.9,39),wing:0.15,spread:0.24,gape:0.85,crest:0.4)
            case "sootyCallClose": return Pose((21.6,12.8,-0.1,0.5),(32.4,17,-0.28),(7.3,39.7),wing:0.09,spread:0.16,turn:0.4,gape:0.18,crest:0.1)
            case "sootyCallSettle": return Pose((22.4,12,-0.2,0.3),(32.9,19.3,0.03),(6.8,40.5),wing:0.02,spread:0.06,turn:0.15)
            default: return nil
            }
        case .brownBreastedBulbul:
            switch frame {
            case "lookNear": return Pose((22.8,11.9,0.5,0),(33.3,20.8,0.25),(6.8,40.6),wing:0.02,spread:0.1)
            case "lookFar": return Pose((21.6,12.6,-0.1,0),(32.4,17.3,-0.18),(7.4,41.2),wing:0.05,turn:0.6)
            case "alertRise": return Pose((20.6,13.2,0.3,0),(32.8,15.7,-0.16),(7.9,40.3),wing:0.09,spread:0.18)
            case "alertHold": return Pose((19.8,13.9,0.7,-0.2),(33.2,14.4,-0.05),(8.5,39.6),wing:0.15,spread:0.25,turn:0.2)
            case "alertRelax": return Pose((22.3,12.2,-0.4,0.4),(32.1,19.1,0.09),(7,40.9),wing:0.03,turn:0.25)
            case "restLower": return Pose((24.3,11.2,-0.5,1.2),(31.1,23.6,0.2),(7.2,39.7),stance:-0.6)
            case "restTuck": return Pose((25,10.7,-0.9,1.8),(26.7,26.3,2.53),(7.9,38.8),turn:0.4,stance:-1)
            case "restWake": return Pose((22.8,11.8,0,0.7),(31.8,18.5,-0.27),(6.6,40.4),wing:0.11,spread:0.13)
            case "takeoffCrouch": return Pose((25.9,9.7,1.2,0.4),(34.3,24.6,0.19),(6.9,33.9),wing:0.27,spread:0.32,stance:-1.5)
            case "takeoffPush": return Pose((19.2,11.6,1.7,0),(34.5,16.7,-0.23),(6.5,31.7),wing:0.89,spread:0.48,stance:0.6)
            case "brownCallReady": return Pose((22,12.5,0.1,0.4),(32.5,18,-0.19),(7.5,40.1),wing:0.04,spread:0.13,turn:0.15,gape:0.08)
            case "brownCallOpen": return Pose((21.1,13.7,0.6,0.75),(33.1,15.7,-0.49),(8.3,38.8),wing:0.13,spread:0.28,gape:0.76)
            case "brownCallReturn": return Pose((21.8,12.9,-0.2,0.55),(32,17.4,-0.22),(7.7,39.5),wing:0.08,spread:0.17,turn:0.55,gape:0.14)
            case "brownCallSettle": return Pose((22.5,12.1,-0.1,0.35),(32.6,19.5,0.04),(7.1,40.3),wing:0.03,spread:0.08,turn:0.2)
            default: return nil
            }
        case .blackBulbul:
            switch frame {
            case "lookNear": return Pose((22.5,12,0.7,0),(33.4,19.8,0.27),(5.7,40.1),wing:0.03,spread:0.12,crest:0.05)
            case "lookFar": return Pose((21.2,12.7,-0.2,0),(32.5,16.2,-0.22),(6.2,40.7),wing:0.04,turn:0.5,crest:0.1)
            case "alertRise": return Pose((20.2,13.4,0.4,0),(32.9,14.7,-0.18),(6.7,39.9),wing:0.11,spread:0.2,crest:0.25)
            case "alertHold": return Pose((19.4,14.1,0.9,-0.2),(33.4,13.3,-0.07),(7.3,39.2),wing:0.17,spread:0.28,crest:0.5)
            case "alertRelax": return Pose((21.9,12.3,-0.3,0.5),(32.2,18.1,0.08),(5.9,40.4),wing:0.02,turn:0.2)
            case "restLower": return Pose((24,11.3,-0.6,1),(31.2,22.6,0.19),(6.1,39.1),stance:-0.5,crest:-0.6)
            case "restTuck": return Pose((24.7,10.8,-1.1,1.6),(26.9,25.4,2.46),(6.7,38.3),turn:0.3,stance:-0.9,crest:-0.8)
            case "restWake": return Pose((22.3,12.1,0.1,0.6),(31.9,17.5,-0.31),(5.5,39.8),wing:0.13,spread:0.16,crest:0.2)
            case "takeoffCrouch": return Pose((25.6,9.8,1.4,0.3),(34.5,23.7,0.17),(5.8,33.5),wing:0.3,spread:0.35,stance:-1.5,crest:-0.3)
            case "takeoffPush": return Pose((18.8,11.8,2,0),(34.6,15.7,-0.26),(5.4,31.4),wing:0.93,spread:0.52,stance:0.7,crest:0.3)
            case "blackCallReady": return Pose((21.7,12.7,0.3,0.25),(32.7,17,-0.28),(6.3,39.7),wing:0.06,spread:0.17,gape:0.12,crest:0.2)
            case "blackCallOpen": return Pose((20.6,13.9,0.8,0.6),(33.4,14.5,-0.62),(7.1,38.2),wing:0.17,spread:0.3,gape:0.95,crest:0.5)
            case "blackCallClose": return Pose((21.3,13.1,-0.1,0.45),(32.3,16.4,-0.32),(6.5,39),wing:0.1,spread:0.2,turn:0.45,gape:0.2,crest:0.15)
            case "blackCallSettle": return Pose((22.2,12.3,-0.2,0.35),(32.8,18.6,0.03),(6,40),wing:0.03,spread:0.1,turn:0.15)
            default: return nil
            }
        case .collaredFinchbill:
            switch frame {
            case "lookNear": return Pose((22.4,12.8,0.5,0),(32.8,19.6,0.24),(6.7,40.3),wing:0.02,turn:0.15)
            case "lookFar": return Pose((21.2,13.5,-0.2,0),(31.9,16,-0.18),(7.2,41),wing:0.04,turn:0.55)
            case "alertRise": return Pose((20.2,14.2,0.3,0),(32.3,14.5,-0.16),(7.7,40.1),wing:0.09,spread:0.16)
            case "alertHold": return Pose((19.4,14.9,0.7,-0.2),(32.8,13.1,-0.05),(8.3,39.4),wing:0.15,spread:0.24)
            case "alertRelax": return Pose((21.9,13,-0.3,0.5),(31.6,17.9,0.08),(6.9,40.6),wing:0.03,turn:0.2)
            case "restLower": return Pose((24,11.8,-0.5,1.1),(30.8,22.2,0.19),(7.1,39.4),stance:-0.6)
            case "restTuck": return Pose((24.7,11.3,-0.9,1.7),(26.3,25.3,2.49),(7.7,38.6),turn:0.3,stance:-1)
            case "restWake": return Pose((22.3,12.7,0,0.6),(31.4,17.3,-0.28),(6.5,40),wing:0.12,spread:0.14)
            case "takeoffCrouch": return Pose((25.5,10.2,1.3,0.4),(33.9,23.4,0.16),(6.8,33.7),wing:0.28,spread:0.31,stance:-1.5)
            case "takeoffPush": return Pose((18.8,12.4,1.8,0),(34,15.4,-0.24),(6.4,31.6),wing:0.9,spread:0.47,stance:0.6)
            case "collarBillReady": return Pose((23,12.1,0.6,0.3),(33.2,22,0.38),(7.4,39.1),wing:0.05,spread:0.12,turn:0.1,stance:-0.3)
            case "collarBillFlex": return Pose((23.5,11.7,1,0.2),(33.7,24,0.55),(8.1,37.8),wing:0.13,spread:0.25,gape:0.72,stance:-0.6)
            case "collarBillLift": return Pose((21.7,13.3,0.1,0.4),(31.8,17.1,-0.2),(7.6,39.5),wing:0.08,spread:0.17,turn:0.55,gape:0.12)
            case "collarBillSettle": return Pose((22.1,13,-0.2,0.45),(32.3,18.4,0.03),(7,40.2),wing:0.02,spread:0.06,turn:0.2)
            default: return nil
            }
        case .taiwanBarbet:
            switch frame {
            case "lookNear": return Pose((22.1,14.8,0.5,0),(30.6,19.2,0.22),(13.4,35.8),wing:0.03,turn:0.1)
            case "lookFar": return Pose((20.9,15.5,-0.2,0),(29.8,15.5,-0.17),(13.9,36.5),wing:0.04,turn:0.5)
            case "alertRise": return Pose((19.9,16.1,0.3,0),(30.2,14,-0.14),(14.4,35.6),wing:0.09,spread:0.15)
            case "alertHold": return Pose((19.1,16.8,0.7,-0.2),(30.6,12.7,-0.05),(14.9,35),wing:0.15,spread:0.23)
            case "alertRelax": return Pose((21.6,15,-0.3,0.5),(29.5,17.5,0.08),(13.6,36.1),wing:0.02,turn:0.2)
            case "restLower": return Pose((23.8,13.5,-0.5,1.2),(28.7,22,0.19),(13.8,34.8),stance:-0.5)
            case "restTuck": return Pose((24.5,12.9,-0.9,1.8),(25.7,26.4,2.39),(14.4,34),turn:0.35,stance:-0.9)
            case "restWake": return Pose((22,14.5,0,0.7),(29.3,16.8,-0.27),(13.2,35.5),wing:0.12,spread:0.12)
            case "takeoffCrouch": return Pose((25.4,11.2,1.3,0.4),(31.7,23.6,0.16),(13.5,31.2),wing:0.27,spread:0.28,stance:-1.5)
            case "takeoffPush": return Pose((18.6,14,1.8,0),(31.9,15,-0.23),(13.1,28.9),wing:0.88,spread:0.44,stance:0.6)
            case "taiwanCallReady": return Pose((21.4,15.2,0.2,0.35),(30,16.8,-0.22),(14,35.3),wing:0.05,spread:0.1,gape:0.08)
            case "taiwanCallOpen": return Pose((20.4,16.3,0.7,0.6),(30.7,14.4,-0.46),(14.8,34.1),wing:0.14,spread:0.23,gape:0.62)
            case "taiwanCallReturn": return Pose((21.1,15.6,-0.1,0.5),(29.6,16.1,-0.2),(14.2,34.8),wing:0.09,spread:0.15,turn:0.4,gape:0.12)
            case "taiwanCallSettle": return Pose((21.9,14.9,-0.2,0.35),(30.1,18,0.03),(13.7,35.7),wing:0.03,spread:0.06,turn:0.15)
            default: return nil
            }
        case .blueThroatedBarbet:
            switch frame {
            case "lookNear": return Pose((22.3,14.9,0.6,0),(30.4,19.5,0.25),(13.7,35.5),wing:0.02,spread:0.08,turn:0.15)
            case "lookFar": return Pose((21.1,15.6,-0.1,0),(29.6,15.8,-0.19),(14.2,36.2),wing:0.05,turn:0.6)
            case "alertRise": return Pose((20.1,16.2,0.4,0),(30,14.3,-0.16),(14.7,35.3),wing:0.1,spread:0.17)
            case "alertHold": return Pose((19.3,16.9,0.8,-0.2),(30.4,13,-0.06),(15.3,34.7),wing:0.16,spread:0.25,turn:0.2)
            case "alertRelax": return Pose((21.8,15.1,-0.4,0.4),(29.3,17.8,0.09),(13.9,35.8),wing:0.03,turn:0.25)
            case "restLower": return Pose((24,13.6,-0.6,1.1),(28.5,22.3,0.21),(14.1,34.5),stance:-0.6)
            case "restTuck": return Pose((24.7,13,-1,1.7),(25.4,26.7,2.44),(14.8,33.7),turn:0.4,stance:-1)
            case "restWake": return Pose((22.2,14.6,0.1,0.6),(29.1,17.1,-0.29),(13.5,35.2),wing:0.13,spread:0.14)
            case "takeoffCrouch": return Pose((25.6,11.3,1.4,0.3),(31.5,23.9,0.18),(13.8,30.9),wing:0.29,spread:0.3,stance:-1.6)
            case "takeoffPush": return Pose((18.8,14.1,2,0),(31.7,15.3,-0.25),(13.4,28.6),wing:0.91,spread:0.46,stance:0.7)
            case "blueThroatReady": return Pose((21.6,15.4,0.3,0.3),(29.8,17.1,-0.26),(14.3,35),wing:0.06,spread:0.13,turn:0.1,gape:0.1)
            case "blueThroatOpen": return Pose((20.6,16.5,0.8,0.65),(30.5,14.7,-0.53),(15.1,33.8),wing:0.16,spread:0.26,gape:0.74)
            case "blueThroatReturn": return Pose((21.3,15.7,-0.2,0.45),(29.4,16.4,-0.25),(14.5,34.5),wing:0.1,spread:0.18,turn:0.55,gape:0.16)
            case "blueThroatSettle": return Pose((22.1,15,-0.1,0.4),(29.9,18.3,0.04),(14,35.4),wing:0.02,spread:0.08,turn:0.2)
            default: return nil
            }
        default: return nil
        }
    }
}
