import Foundation

/// M8f additions in the existing right-facing, top-down 48-unit canvas.
/// These are presentation poses on a dry top perch; they grant no behavior.
public enum M8DistinctArtGeometry {
    public static let species: [SpeciesID] = [
        .barnSwallow, .blackHeadedGull, .hoopoe, .commonKingfisher,
        .eurasianWoodcock, .blackCollaredStarling, .largeBilledCrow, .asianKoel
    ]

    /// Append order: the seven missing foundation packs, then each signature.
    /// The swallow already owns its foundation artwork and must bypass us there.
    public static func frameNames(for species: SpeciesID) -> [String] {
        guard Self.species.contains(species) else { return [] }
        return (species == .barnSwallow ? [] : PoseClip.frameNames)
            + signatureFrameNames(for: species)
    }

    /// Preparation, emphasis, recovery, settled endpoint (exactly four per bird).
    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        switch species {
        case .barnSwallow: return ["wingPoise", "wingLower", "wingAttend", "wingSettle"]
        case .blackHeadedGull: return ["shoulderTurn", "shoulderStretch", "shoulderDraw", "shoulderSettle"]
        case .hoopoe: return ["crestPoise", "crestLower", "crestLift", "crestSettle"]
        case .commonKingfisher: return ["downWatch", "downTurn", "downReach", "downSettle"]
        case .eurasianWoodcock: return ["billBalance", "billSide", "billLower", "billSettle"]
        case .blackCollaredStarling: return ["collarReach", "collarCall", "collarClose", "collarSettle"]
        case .largeBilledCrow: return ["nearTurn", "nearBow", "nearLift", "nearSettle"]
        case .asianKoel: return ["callReach", "callOpen", "callPulse", "callSettle"]
        default: return []
        }
    }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, billDepth, tailWidth: Double
        /// Only the hoopoe has a curved bill. Its endpoint belongs to the curve
        /// itself and is reused by the anchor, rather than approximating a chord.
        public let billDrop: Double

        public var billRoot: Double { headWidth / 2 - 0.5 }
        public var billTip: (Double, Double) { (billRoot + billLength, 0.5 + billDrop) }

        public var billCurve: [(Double, Double)] {
            [(billRoot, 0), (billRoot + billLength * 0.55, 0.3),
             (billRoot + billLength + 0.7, billDrop * 0.38), billTip]
        }
    }

    public static func anatomy(for species: SpeciesID) -> Anatomy? {
        switch species {
        case .barnSwallow:
            return Anatomy(width:18, headWidth:CatchArtGeometry.swallowHeadWidth,
                           headHeight:CatchArtGeometry.swallowHeadHeight,
                           billLength:2.2, billDepth:0.7, tailWidth:5, billDrop:0)
        case .blackHeadedGull:
            return Anatomy(width:24, headWidth:7, headHeight:6, billLength:4, billDepth:0.8, tailWidth:5, billDrop:0)
        case .hoopoe:
            return Anatomy(width:19, headWidth:7, headHeight:6, billLength:8.8, billDepth:0.9, tailWidth:5, billDrop:4.7)
        case .commonKingfisher:
            return Anatomy(width:16, headWidth:11, headHeight:8, billLength:9, billDepth:1, tailWidth:4.5, billDrop:0)
        case .eurasianWoodcock:
            return Anatomy(width:22, headWidth:8, headHeight:7, billLength:10.8, billDepth:0.7, tailWidth:5.5, billDrop:0)
        case .blackCollaredStarling:
            return Anatomy(width:19, headWidth:8, headHeight:8, billLength:4, billDepth:0.9, tailWidth:5, billDrop:0)
        case .largeBilledCrow:
            return Anatomy(width:22, headWidth:10, headHeight:8, billLength:6, billDepth:1.7, tailWidth:7, billDrop:0)
        case .asianKoel:
            return Anatomy(width:18, headWidth:7.5, headHeight:7, billLength:4, billDepth:1, tailWidth:5, billDrop:0)
        default: return nil
        }
    }

    public struct Pose {
        public let body: (y:Double, height:Double, lean:Double, fluff:Double)
        public let head: (x:Double, y:Double, pitch:Double)
        public let tail: (x:Double, y:Double)
        /// Shoulder opening and downward primary flexion are independent.
        public let wing, droop, gape, crest, stance: Double

        fileprivate init(_ body:(Double,Double,Double,Double),
                         _ head:(Double,Double,Double), _ tail:(Double,Double),
                         wing:Double = 0, droop:Double = 0, gape:Double = 0,
                         crest:Double = 0.08, stance:Double = 0) {
            self.body=body; self.head=head; self.tail=tail
            self.wing=wing; self.droop=droop; self.gape=gape
            self.crest=crest; self.stance=stance
        }

        public func headPoint(_ x:Double, _ y:Double) -> (Double,Double) {
            (head.x + x*cos(head.pitch) - y*sin(head.pitch),
             head.y + x*sin(head.pitch) + y*cos(head.pitch))
        }

        /// Upper jaw vertex 1 is the beak anchor, even when the lower jaw opens.
        /// The crow's deep upper jaw has its own convex shoulder contour.
        public func upperBillVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let r=a.billRoot, d=a.billDepth, tip=a.billTip
            if d > 1.5 {
                return [(r+a.billLength*0.45,-d*0.85),tip,(tip.0-0.6,1),
                        (r-0.1,1.4),(r-0.35,-d*0.55),(r+0.8,-d)]
            }
            return [(r,-d), tip, (tip.0-0.7,0.9), (r,1)]
        }

        public func lowerBillVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let r=a.billRoot, tip=a.billTip
            return [(r,0.8), (tip.0-0.6,1+gape*0.58), (r+0.1,1.4+gape)]
        }
    }

    public static func beakAnchor(species:SpeciesID, frame:String) -> PoseClip.Anchor? {
        guard let a=anatomy(for:species), let p=pose(species:species,frame:frame) else { return nil }
        let local=a.billDrop > 0 ? a.billCurve[3] : p.upperBillVertices(anatomy:a)[1]
        let tip=p.headPoint(local.0,local.1)
        return PoseClip.Anchor(tip.0,tip.1)
    }

    /// Each row articulates a new drawing; no finished bird is rotated/scaled.
    /// Body heights leave the toes at y=39, including the two takeoff poses.
    public static func pose(species:SpeciesID, frame:String) -> Pose? {
        switch species {
        case .barnSwallow:
            switch frame {
            case "wingPoise": return Pose((22.6,9.4,0.3,0),(33.1,19.9,-0.10),(2.8,41.2),wing:0.34,droop:0.3)
            case "wingLower": return Pose((23.7,9.1,0.8,0),(33.7,21.2,0.15),(3.3,39.4),wing:0.22,droop:5.5,stance:-0.3)
            case "wingAttend": return Pose((23.3,9.6,-0.3,0.2),(27.8,24.8,2.64),(3.8,40.5),wing:0.11,droop:1.8)
            case "wingSettle": return Pose((22.2,9.8,-0.2,0.35),(32.7,20.6,0.08),(2.9,42.1),wing:0.025,droop:0.5)
            default: return nil
            }
        case .blackHeadedGull:
            switch frame {
            case "lookNear": return Pose((25.8,10.2,0.6,0),(34,21.3,0.24),(9.3,33.4))
            case "lookFar": return Pose((25,10.7,-0.2,0),(33.1,17.6,-0.18),(9.8,33))
            case "alertRise": return Pose((24.2,11.2,0.3,0),(33.8,15.5,-0.18),(10.1,33.5),wing:0.07)
            case "alertHold": return Pose((23.6,11.7,0.6,-0.2),(34,14.4,-0.08),(10.4,34),wing:0.11)
            case "alertRelax": return Pose((25.3,10.4,-0.3,0.4),(32.7,19.4,0.04),(9,33.3))
            case "restLower": return Pose((26.7,9.8,-0.4,0.8),(31.8,24.5,0.16),(8.8,34.6),stance:-0.5)
            case "restTuck": return Pose((27,9.6,-0.7,1.1),(25.7,27,2.67),(9.5,35.1),stance:-0.8)
            case "restWake": return Pose((25.5,10.3,0,0.5),(32.4,19,-0.26),(9.2,33.7),wing:0.06)
            case "takeoffCrouch": return Pose((28.1,8.8,1.1,0.2),(34.6,26,0.13),(8.4,30.6),wing:0.26,stance:-1.1)
            case "takeoffPush": return Pose((22.6,11.4,1.6,0),(34.3,17,-0.22),(8,29.3),wing:1,stance:0.5)
            case "shoulderTurn": return Pose((25.5,10.4,-0.3,0.2),(26.5,25.1,2.54),(9.6,33.6),wing:0.10,droop:0.5)
            case "shoulderStretch": return Pose((24.8,10.7,0.4,0),(34.8,15.8,-0.25),(10.3,33.2),wing:0.12)
            case "shoulderDraw": return Pose((25.9,10,-0.2,0.3),(32.1,22.3,0.19),(9.4,34.1),wing:0.035,droop:0.7)
            case "shoulderSettle": return Pose((25.4,10.5,-0.1,0.45),(33.2,19.8,0.03),(9.7,33.8),droop:0.2)
            default: return nil
            }
        case .hoopoe:
            switch frame {
            case "lookNear": return Pose((22.8,11.6,0.4,0),(31.7,20.2,0.18),(7.4,38.7))
            case "lookFar": return Pose((21.8,12.1,-0.1,0),(31.2,16.4,-0.28),(7.8,39.3))
            case "alertRise": return Pose((20.8,13,0.3,0),(31.6,15.1,-0.24),(8.2,40),wing:0.07,crest:0.14)
            case "alertHold": return Pose((20.2,13.6,0.6,-0.2),(31.9,14.2,-0.17),(8.7,40.5),wing:0.12,crest:0.18)
            case "alertRelax": return Pose((22.4,11.8,-0.3,0.5),(30.9,18.6,-0.06),(7,38.8))
            case "restLower": return Pose((24.1,11.2,-0.5,1),(30.2,23.6,0.12),(7.2,38),stance:-0.5)
            case "restTuck": return Pose((24.7,10.8,-0.8,1.4),(26.4,24.7,2.85),(8,37.5),crest:0.03,stance:-0.8)
            case "restWake": return Pose((22.6,12,0,0.6),(30.6,18,-0.33),(7.1,39.2),wing:0.08)
            case "takeoffCrouch": return Pose((26.1,9.7,1.2,0.2),(32.1,25.1,0.08),(6.7,34.7),wing:0.27,stance:-1.2)
            case "takeoffPush": return Pose((19.3,12.6,1.7,0),(32.1,16,-0.32),(6.1,33.5),wing:1,crest:0.12,stance:0.5)
            // A deliberately small crown change, not a full fan or an alarm claim.
            case "crestPoise": return Pose((22.3,12,0.1,0),(31.2,17.9,-0.12),(7.6,39.1),crest:0.28)
            case "crestLower": return Pose((23.8,10.8,0.8,0),(32,23.8,0.48),(7,35.9),crest:0.36,stance:-0.4)
            case "crestLift": return Pose((21.6,12.5,0.2,0),(31.8,16.6,-0.26),(8.1,38.2),crest:0.21)
            case "crestSettle": return Pose((22.6,11.7,-0.2,0.3),(31,19.1,0.01),(7.5,39.6),crest:0.05)
            default: return nil
            }
        case .commonKingfisher:
            switch frame {
            case "lookNear": return Pose((22.9,13.2,0.3,0),(31.2,20.8,0.25),(14.3,32.6))
            case "lookFar": return Pose((21.8,13.8,-0.2,0),(30.7,16.1,-0.20),(14.6,32.2))
            case "alertRise": return Pose((20.9,14.5,0.2,0),(31.1,14.7,-0.20),(15,32.6),wing:0.06)
            case "alertHold": return Pose((20.1,15.2,0.5,-0.15),(31.4,13.6,-0.08),(15.2,33),wing:0.10)
            case "alertRelax": return Pose((22.4,13.6,-0.3,0.4),(30.4,18.3,0.04),(14,32.7))
            case "restLower": return Pose((24.5,12.3,-0.5,0.8),(29.8,24,0.18),(14.1,33.7),stance:-0.4)
            case "restTuck": return Pose((25.1,11.8,-0.8,1.2),(26.1,26.2,2.94),(14.8,34.1),stance:-0.7)
            case "restWake": return Pose((22.8,13.5,0,0.5),(30.1,18.1,-0.29),(13.9,33.2),wing:0.07)
            case "takeoffCrouch": return Pose((26.1,10.7,1.2,0.2),(31.8,25.4,0.15),(13.8,30.4),wing:0.25,stance:-1.1)
            case "takeoffPush": return Pose((19.5,13.4,1.6,0),(31.8,16.1,-0.23),(13.2,28.8),wing:1,stance:0.5)
            case "downWatch": return Pose((23.3,12.8,0.3,0),(31.5,21.7,0.48),(14.5,32.8))
            case "downTurn": return Pose((23.5,12.7,-0.2,0.1),(29.9,22.2,0.34),(14.9,33.1),droop:0.4)
            case "downReach": return Pose((24.1,12,0.9,0),(32.2,24,0.67),(14.2,31.5),wing:0.035,stance:-0.3)
            case "downSettle": return Pose((22.5,13.5,-0.1,0.25),(30.8,18.8,0.10),(14.7,33.5),droop:0.15)
            default: return nil
            }
        case .eurasianWoodcock:
            switch frame {
            case "lookNear": return Pose((25,12.5,0.3,0),(30.7,24.3,0.22),(12.2,33.5))
            case "lookFar": return Pose((24.2,13,-0.2,0),(30.1,20.5,-0.18),(12.7,33.2))
            case "alertRise": return Pose((23.5,13.7,0.2,0),(30.4,19.2,-0.15),(13,33.6),wing:0.04)
            case "alertHold": return Pose((23,14.2,0.4,-0.15),(30.6,18.3,-0.06),(13.4,34),wing:0.08)
            case "alertRelax": return Pose((24.7,12.7,-0.3,0.5),(29.8,22.8,0.06),(12,33.8))
            case "restLower": return Pose((26,11.4,-0.5,0.9),(29.1,26,0.14),(12.1,34.5),stance:-0.4)
            case "restTuck": return Pose((26.3,11.2,-0.7,1.3),(26,28.2,2.96),(12.9,34.9),stance:-0.7)
            case "restWake": return Pose((24.8,12.7,0,0.6),(29.7,22,-0.23),(11.9,34.1),wing:0.05)
            case "takeoffCrouch": return Pose((27,10.6,0.9,0.2),(31.3,27,0.12),(11.6,31.3),wing:0.24,stance:-1)
            case "takeoffPush": return Pose((21.7,13.5,1.4,0),(31.2,20.2,-0.21),(11.2,29.8),wing:1,stance:0.4)
            // Planted weight shift, not a walking/dancing translation.
            case "billBalance": return Pose((24.6,12.8,-0.65,0.1),(30,22.7,0.09),(12.9,33.9),stance:-0.55)
            case "billSide": return Pose((24.9,12.6,0.25,0),(29,23.6,0.27),(12.4,33.2),droop:0.35,stance:0.35)
            case "billLower": return Pose((26,11.3,0.9,0),(31.1,25.7,0.76),(11.8,31.4),stance:-0.3)
            case "billSettle": return Pose((25.2,12.3,-0.1,0.35),(30.4,23.1,0.13),(12.6,34.2),droop:0.1)
            default: return nil
            }
        case .blackCollaredStarling:
            switch frame {
            case "lookNear": return Pose((22.7,13,0.5,0),(33.1,20.3,0.27),(10.3,38.8))
            case "lookFar": return Pose((21.6,13.7,-0.1,0),(32.2,15.6,-0.19),(10.7,39.4))
            case "alertRise": return Pose((20.6,14.5,0.3,0),(32.7,13.7,-0.20),(11,40),wing:0.08)
            case "alertHold": return Pose((19.8,15.3,0.6,-0.2),(33,12.3,-0.09),(11.5,40.5),wing:0.14)
            case "alertRelax": return Pose((22.2,13.4,-0.3,0.5),(31.9,18.3,0.04),(9.9,38.9))
            case "restLower": return Pose((24.2,12,-0.6,1),(31,23.3,0.18),(10,38.1),stance:-0.5)
            case "restTuck": return Pose((24.8,11.7,-1,1.5),(26.8,25.6,2.64),(10.8,37.7),stance:-0.8)
            case "restWake": return Pose((22.5,13.2,0,0.6),(31.4,17.8,-0.30),(9.8,39.3),wing:0.09)
            case "takeoffCrouch": return Pose((26,10.3,1.4,0.2),(34,24.5,0.14),(9.5,34.8),wing:0.28,stance:-1.3)
            case "takeoffPush": return Pose((18.9,13.6,1.9,0),(34.1,15.5,-0.24),(9,33.1),wing:1,stance:0.5)
            case "collarReach": return Pose((21.7,13.5,0.4,0),(33.6,15.4,-0.13),(10.8,39.2),wing:0.035)
            case "collarCall": return Pose((20.8,14.5,0.7,0.2),(33.8,12.8,-0.36),(11.2,40),wing:0.085,gape:2.1)
            case "collarClose": return Pose((21.5,13.8,0.3,0.1),(33,15.1,-0.17),(10.6,39.6),wing:0.025)
            case "collarSettle": return Pose((22.6,13.1,-0.2,0.35),(32.5,18.8,0.07),(10.4,39.3),droop:0.3)
            default: return nil
            }
        case .largeBilledCrow:
            switch frame {
            case "lookNear": return Pose((22.8,14.1,0.55,0),(33.6,19.8,0.26),(8.4,40.4))
            case "lookFar": return Pose((21.6,14.8,-0.1,0),(32.7,15,-0.17),(8.8,41.2))
            case "alertRise": return Pose((20.6,15.6,0.35,0),(33.2,13.6,-0.18),(9.2,41.7),wing:0.055)
            case "alertHold": return Pose((19.8,16.4,0.65,-0.25),(33.5,12.4,-0.07),(9.8,42.2),wing:0.10)
            case "alertRelax": return Pose((22.2,14.5,-0.4,0.65),(32.3,17.7,0.05),(8,40.7))
            case "restLower": return Pose((24.4,12.5,-0.6,1.2),(31.4,23.5,0.18),(8.1,39.7),stance:-0.5)
            case "restTuck": return Pose((24.9,12,-1,1.7),(26.7,25.8,2.79),(8.9,39.2),stance:-0.8)
            case "restWake": return Pose((22.6,14.2,0,0.75),(31.9,17.1,-0.28),(7.9,41),wing:0.06)
            case "takeoffCrouch": return Pose((26,10.8,1.2,0.3),(34.3,24.7,0.15),(7.6,35.8),wing:0.25,stance:-1.2)
            case "takeoffPush": return Pose((18.7,15.2,1.7,0),(34.4,15.6,-0.22),(7.1,33.9),wing:1,stance:0.45)
            case "nearTurn": return Pose((23,13.9,-0.2,0),(32.4,21.3,0.34),(8.8,40.1),droop:0.35)
            case "nearBow": return Pose((25,11.7,1.25,0.15),(34.6,27,0.70),(7.8,35.1),wing:0.035,stance:-0.65)
            case "nearLift": return Pose((21.8,14.9,0.35,0),(33.4,15.9,-0.20),(8.6,38.9),wing:0.06)
            case "nearSettle": return Pose((22.9,14,-0.2,0.5),(32.9,18.5,0.09),(8.5,41),droop:0.2)
            default: return nil
            }
        case .asianKoel:
            switch frame {
            case "lookNear": return Pose((22.5,12.4,0.5,0),(33,20,0.26),(2.8,43.5))
            case "lookFar": return Pose((21.4,13,-0.1,0),(32.1,15.7,-0.19),(3.2,43.8))
            case "alertRise": return Pose((20.3,13.9,0.3,0),(32.6,14,-0.21),(3.6,44.1),wing:0.065)
            case "alertHold": return Pose((19.6,14.6,0.6,-0.2),(32.9,12.8,-0.10),(4,44.3),wing:0.11)
            case "alertRelax": return Pose((22,12.7,-0.3,0.4),(31.8,18.4,0.05),(2.7,43.1))
            case "restLower": return Pose((24.1,11.4,-0.5,0.85),(30.9,23.2,0.18),(3,42.7),stance:-0.4)
            case "restTuck": return Pose((24.6,11,-0.9,1.3),(26.6,25.3,2.65),(3.7,42.2),stance:-0.7)
            case "restWake": return Pose((22.3,12.6,0,0.5),(31.3,17.7,-0.29),(2.6,43.6),wing:0.075)
            case "takeoffCrouch": return Pose((25.7,10.1,1.2,0.2),(33.7,24.2,0.14),(2.5,37.7),wing:0.27,stance:-1.2)
            case "takeoffPush": return Pose((18.8,12.9,1.7,0),(33.8,15.8,-0.24),(2.3,35.8),wing:1,stance:0.5)
            case "callReach": return Pose((21.5,13,0.3,0),(33.4,15,-0.16),(3.3,43.4),wing:0.025)
            case "callOpen": return Pose((20.6,14,0.6,0.1),(33.7,12.2,-0.37),(3.7,44),wing:0.055,gape:2.4)
            case "callPulse": return Pose((21.1,13.8,0.45,0.55),(33.2,14,-0.25),(3.4,43.7),wing:0.035,droop:0.35,gape:0.95)
            case "callSettle": return Pose((22.4,12.5,-0.2,0.3),(32.4,18.5,0.08),(3.1,43.9),droop:0.2)
            default: return nil
            }
        default: return nil
        }
    }
}
