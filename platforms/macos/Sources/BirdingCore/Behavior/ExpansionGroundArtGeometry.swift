import Foundation

/// E2 original anatomy in a right-facing, top-down 48-unit canvas.
/// Drawing and bill contacts consume the same paths. No behavior is granted here.
public enum ExpansionGroundArtGeometry {
    public static let species: [SpeciesID] = [
        .silkyStarling, .whiteCheekedStarling, .carrionCrow, .daurianJackdaw,
        .redBilledChough, .plainLaughingthrush, .henricsLaughingthrush,
        .whiteBrowedLaughingthrush, .groundTit, .rufousBreastedAccentor,
        .hornedLark, .redThroatedThrush
    ]

    public static func frameNames(for species: SpeciesID) -> [String] {
        Self.species.contains(species) ? PoseClip.frameNames + signatureFrameNames(for:species) : []
    }

    /// Frozen order: preparation, emphasis, recovery, settling.
    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        switch species {
        case .silkyStarling: return ["silkBowReady","silkBowDown","silkBowRecover","silkBowSettle"]
        case .whiteCheekedStarling: return ["cheekDipReady","cheekDipDown","cheekDipRecover","cheekDipSettle"]
        case .carrionCrow: return ["crowInclineReady","crowInclineDown","crowInclineRecover","crowInclineSettle"]
        case .daurianJackdaw: return ["jackdawLeanReady","jackdawLeanDown","jackdawLeanRecover","jackdawLeanSettle"]
        case .redBilledChough: return ["choughProbeReady","choughProbeDown","choughProbeRecover","choughProbeSettle"]
        case .plainLaughingthrush: return ["plainDipReady","plainDipDown","plainDipRecover","plainDipSettle"]
        case .henricsLaughingthrush: return ["henricLookReady","henricLookDown","henricLookRecover","henricLookSettle"]
        case .whiteBrowedLaughingthrush: return ["whiteBrowLeanReady","whiteBrowLeanDown","whiteBrowLeanRecover","whiteBrowLeanSettle"]
        case .groundTit: return ["groundProbeReady","groundProbeDown","groundProbeRecover","groundProbeSettle"]
        case .rufousBreastedAccentor: return ["accentorDipReady","accentorDipDown","accentorDipRecover","accentorDipSettle"]
        case .hornedLark: return ["hornLookReady","hornLookDown","hornLookRecover","hornLookSettle"]
        case .redThroatedThrush: return ["redThroatLeanReady","redThroatLeanDown","redThroatLeanRecover","redThroatLeanSettle"]
        default: return []
        }
    }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, billDepth, billCurve: Double
        public let tailWidth, wingReach, primaryLength, kneeHeight: Double
        /// Individual shoulder, breast, keel and rump contours, normalized locally.
        public let bodyContour: [(Double,Double)]
    }

    public static func anatomy(for species: SpeciesID) -> Anatomy? {
        switch species {
        case .silkyStarling:
            return Anatomy(width:21,headWidth:8,headHeight:7,billLength:3.3,billDepth:1.6,billCurve:0.25,
                tailWidth:6.6,wingReach:15.2,primaryLength:10,kneeHeight:36,
                bodyContour:[(0,0.57),(0.12,0.27),(0.38,0.04),(0.67,0),(0.91,0.19),(1,0.48),(0.91,0.81),(0.63,1),(0.3,0.94),(0.08,0.77)])
        case .whiteCheekedStarling:
            return Anatomy(width:21,headWidth:8,headHeight:7,billLength:3.1,billDepth:1.8,billCurve:0.2,
                tailWidth:6.8,wingReach:14.7,primaryLength:10.4,kneeHeight:35.9,
                bodyContour:[(0,0.52),(0.09,0.22),(0.34,0.01),(0.63,0),(0.88,0.15),(1,0.46),(0.95,0.75),(0.72,0.98),(0.39,1),(0.12,0.82)])
        case .carrionCrow:
            return Anatomy(width:23,headWidth:9,headHeight:8,billLength:5,billDepth:2.1,billCurve:0.55,
                tailWidth:7.1,wingReach:16.5,primaryLength:12.2,kneeHeight:35.6,
                bodyContour:[(0,0.62),(0.14,0.29),(0.44,0.02),(0.72,0),(0.93,0.2),(1,0.5),(0.91,0.8),(0.65,1),(0.33,0.96),(0.09,0.82)])
        case .daurianJackdaw:
            return Anatomy(width:22,headWidth:9,headHeight:8,billLength:4.6,billDepth:1.9,billCurve:0.35,
                tailWidth:7.3,wingReach:15.8,primaryLength:11.4,kneeHeight:35.8,
                bodyContour:[(0,0.55),(0.1,0.24),(0.32,0.03),(0.61,0),(0.87,0.16),(1,0.44),(0.96,0.74),(0.75,0.97),(0.43,1),(0.14,0.84)])
        case .redBilledChough:
            return Anatomy(width:21,headWidth:8,headHeight:7,billLength:6,billDepth:1.05,billCurve:3.8,
                tailWidth:6.2,wingReach:16.7,primaryLength:11.8,kneeHeight:35.5,
                bodyContour:[(0,0.66),(0.16,0.31),(0.45,0.04),(0.74,0),(0.94,0.18),(1,0.43),(0.94,0.72),(0.71,0.95),(0.38,1),(0.11,0.85)])
        case .plainLaughingthrush:
            return Anatomy(width:22,headWidth:8,headHeight:7,billLength:5.8,billDepth:0.95,billCurve:3.5,
                tailWidth:5.7,wingReach:14.3,primaryLength:10.5,kneeHeight:36.1,
                bodyContour:[(0,0.59),(0.12,0.28),(0.39,0.05),(0.68,0),(0.91,0.18),(1,0.49),(0.91,0.82),(0.65,1),(0.32,0.97),(0.08,0.8)])
        case .henricsLaughingthrush:
            return Anatomy(width:21,headWidth:8,headHeight:8,billLength:3.3,billDepth:1.65,billCurve:0.6,
                tailWidth:5.9,wingReach:14.8,primaryLength:10.8,kneeHeight:36.2,
                bodyContour:[(0,0.54),(0.09,0.25),(0.34,0.02),(0.64,0),(0.89,0.17),(1,0.45),(0.95,0.76),(0.73,0.98),(0.41,1),(0.13,0.83)])
        case .whiteBrowedLaughingthrush:
            return Anatomy(width:22,headWidth:9,headHeight:8,billLength:3.4,billDepth:1.65,billCurve:0.4,
                tailWidth:6,wingReach:14.5,primaryLength:11,kneeHeight:36,
                bodyContour:[(0,0.61),(0.13,0.31),(0.4,0.06),(0.7,0),(0.93,0.21),(1,0.51),(0.92,0.83),(0.66,1),(0.34,0.98),(0.09,0.81)])
        case .groundTit:
            return Anatomy(width:19,headWidth:8,headHeight:7,billLength:6,billDepth:0.9,billCurve:3.3,
                tailWidth:5.1,wingReach:13.9,primaryLength:8.3,kneeHeight:34.7,
                bodyContour:[(0,0.63),(0.17,0.32),(0.46,0.05),(0.75,0),(0.95,0.17),(1,0.44),(0.91,0.72),(0.67,0.95),(0.35,1),(0.1,0.84)])
        case .rufousBreastedAccentor:
            return Anatomy(width:18,headWidth:8,headHeight:7,billLength:2.8,billDepth:1.2,billCurve:0.25,
                tailWidth:5.5,wingReach:12.7,primaryLength:8.7,kneeHeight:35.5,
                bodyContour:[(0,0.51),(0.08,0.23),(0.33,0.02),(0.64,0),(0.9,0.2),(1,0.5),(0.93,0.79),(0.69,1),(0.36,0.99),(0.1,0.81)])
        case .hornedLark:
            return Anatomy(width:18,headWidth:7,headHeight:6,billLength:2.9,billDepth:1.4,billCurve:0.3,
                tailWidth:5.4,wingReach:13.2,primaryLength:8.2,kneeHeight:35.1,
                bodyContour:[(0,0.6),(0.14,0.29),(0.43,0.04),(0.72,0),(0.94,0.2),(1,0.47),(0.91,0.77),(0.67,0.98),(0.35,1),(0.09,0.83)])
        case .redThroatedThrush:
            return Anatomy(width:22,headWidth:8,headHeight:7,billLength:3.2,billDepth:1.35,billCurve:0.25,
                tailWidth:6.4,wingReach:15,primaryLength:10.7,kneeHeight:35.7,
                bodyContour:[(0,0.57),(0.11,0.26),(0.38,0.03),(0.68,0),(0.91,0.19),(1,0.5),(0.94,0.8),(0.71,0.99),(0.38,1),(0.11,0.82)])
        default: return nil
        }
    }

    public struct Pose {
        public let body: (y:Double,height:Double,lean:Double,fluff:Double)
        public let head: (x:Double,y:Double,pitch:Double)
        public let tail: (x:Double,y:Double)
        public let wing, turn, stance, fan: Double

        fileprivate init(_ body:(Double,Double,Double,Double), _ head:(Double,Double,Double),
                         _ tail:(Double,Double), _ wing:Double, turn:Double = 0,
                         stance:Double = 0, fan:Double = 0) {
            self.body=body; self.head=head; self.tail=tail; self.wing=wing
            self.turn=turn; self.stance=stance; self.fan=fan
        }

        public func bodyPoint(_ u:Double, _ v:Double, anatomy a:Anatomy) -> (Double,Double) {
            (34-a.width-body.fluff/2+(a.width+body.fluff)*u+body.lean*(1-v),
             body.y+body.height*v)
        }

        public func headWidth(anatomy a:Anatomy) -> Double { a.headWidth*(1-turn*0.12) }

        public func headPoint(_ x:Double, _ y:Double) -> (Double,Double) {
            (head.x+x*cos(head.pitch)-y*sin(head.pitch),
             head.y+x*sin(head.pitch)+y*cos(head.pitch))
        }

        /// Upper and lower curved edges share vertex 3, the physical bill tip.
        /// The curvature remains anatomical under a head turn or downward pitch.
        public func billVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let root=headWidth(anatomy:a)/2-0.45
            let length=a.billLength*(1-turn*0.06), drop=a.billCurve
            return [(root,-a.billDepth/2),
                    (root+length*0.4,-a.billDepth*0.4+drop*0.12),
                    (root+length*0.78,drop*0.46),
                    (root+length,drop+0.3),
                    (root+length*0.73,drop*0.52+a.billDepth*0.65),
                    (root+length*0.36,drop*0.14+a.billDepth*0.65),
                    (root,a.billDepth*0.65)]
        }
    }

    public static let toePaths: [[(Double,Double)]] = [
        [(25,39),(27,38.5),(29,39)], [(29,39),(31,38.5),(33,39)]
    ]

    public static func beakAnchor(species:SpeciesID, frame:String) -> PoseClip.Anchor? {
        guard let a=anatomy(for:species), let p=pose(species:species,frame:frame) else { return nil }
        let tip=p.billVertices(anatomy:a)[3], world=p.headPoint(tip.0,tip.1)
        return PoseClip.Anchor(world.0,world.1)
    }

    /// Fourteen independently authored joint configurations for each species.
    /// No row transforms a finished bird, aliases historical art, or moves toes.
    public static func pose(species:SpeciesID, frame:String) -> Pose? {
        switch species {
        case .silkyStarling:
            switch frame {
            case "lookNear": return Pose((22.7,12.1,0.7,0),(33.4,21.2,0.33),(10.2,37.9),0.04,turn:0.12)
            case "lookFar": return Pose((21.4,12.9,-0.2,0),(32.4,17.3,-0.22),(10.8,39),0.02,turn:0.48)
            case "alertRise": return Pose((20.3,13.7,0.4,0),(32.9,15.7,-0.17),(11.3,39.8),0.1)
            case "alertHold": return Pose((19.4,14.5,0.8,-0.2),(33.3,14.2,-0.08),(11.8,40.5),0.17,turn:0.17)
            case "alertRelax": return Pose((22.2,12.5,-0.3,0.4),(32.2,19.2,0.09),(9.8,38.4),0.05,turn:0.24)
            case "restLower": return Pose((24.2,11.4,-0.5,1),(31.4,23.4,0.23),(10,37.1),0.01,stance:-0.5)
            case "restTuck": return Pose((24.8,11.1,-1,1.5),(26.8,26,2.48),(10.7,36.5),0,turn:0.3,stance:-0.9)
            case "restWake": return Pose((22.6,12.3,0.1,0.6),(31.9,18.3,-0.31),(9.6,39.1),0.12)
            case "takeoffCrouch": return Pose((25.7,9.9,1.4,0.3),(34.5,24.8,0.19),(9.1,33.7),0.3,stance:-1.5,fan:0.2)
            case "takeoffPush": return Pose((18.8,12.2,1.9,0),(34.2,16.6,-0.27),(8.7,32),0.91,stance:0.6,fan:0.35)
            case "silkBowReady": return Pose((23,11.9,1.1,0),(33.7,22.3,0.38),(10.7,36.8),0.07,turn:0.18,stance:-0.3)
            case "silkBowDown": return Pose((24.4,10.5,2.2,0),(35,27.3,0.71),(11.8,33.7),0.15,turn:0.3,stance:-1.1,fan:0.17)
            case "silkBowRecover": return Pose((21.8,12.8,0.3,0.2),(32.8,18.1,-0.26),(10.4,38.3),0.09,turn:0.65,stance:0.1)
            case "silkBowSettle": return Pose((22.4,12.2,-0.1,0.3),(32.7,19.8,0.04),(10.1,38.7),0.03,turn:0.19)
            default: return nil
            }
        case .whiteCheekedStarling:
            switch frame {
            case "lookNear": return Pose((22.5,13,0.8,0),(33.1,20.5,0.29),(10.3,37.8),0.05,turn:0.2)
            case "lookFar": return Pose((21.2,13.8,-0.1,0),(32,16.7,-0.2),(10.9,38.7),0.03,turn:0.6)
            case "alertRise": return Pose((20.1,14.5,0.5,0),(32.5,15.1,-0.18),(11.4,39.4),0.11)
            case "alertHold": return Pose((19.2,15.2,0.9,-0.2),(33,13.7,-0.06),(11.9,40.1),0.18,turn:0.22)
            case "alertRelax": return Pose((22,13.4,-0.4,0.5),(31.8,18.7,0.07),(9.9,38.1),0.04,turn:0.35)
            case "restLower": return Pose((24,12,-0.7,1.1),(31,22.9,0.18),(10.2,36.8),0.02,stance:-0.6)
            case "restTuck": return Pose((24.7,11.6,-1.1,1.7),(26.4,25.6,2.57),(10.8,36.2),0,turn:0.25,stance:-1)
            case "restWake": return Pose((22.3,13.1,0,0.7),(31.5,17.8,-0.28),(9.5,38.8),0.13)
            case "takeoffCrouch": return Pose((25.9,10.1,1.6,0.4),(34.3,24.1,0.16),(9.2,33.4),0.31,stance:-1.6,fan:0.17)
            case "takeoffPush": return Pose((18.4,13,2.2,0),(34.3,16,-0.25),(8.8,31.9),0.9,stance:0.7,fan:0.31)
            case "cheekDipReady": return Pose((23.2,12.3,1.2,0.1),(33.8,22.6,0.44),(10.8,36.1),0.06,turn:0.12,stance:-0.4)
            case "cheekDipDown": return Pose((24.8,10.8,2,0),(34.9,28.9,0.92),(12,33),0.14,turn:0.2,stance:-1.3,fan:0.12)
            case "cheekDipRecover": return Pose((21.6,13.6,0.2,0.3),(32.2,17.3,-0.18),(10.5,38),0.1,turn:0.85,stance:0.2)
            case "cheekDipSettle": return Pose((22.2,13.2,-0.2,0.4),(32.5,19.3,0.02),(10.1,38.4),0.025,turn:0.25)
            default: return nil
            }
        case .carrionCrow:
            switch frame {
            case "lookNear": return Pose((22.1,14,0.9,0),(32.9,18.9,0.3),(6.2,39.9),0.04,turn:0.23)
            case "lookFar": return Pose((20.8,14.9,-0.2,0),(31.6,14.6,-0.18),(6.8,40.7),0.02,turn:0.55)
            case "alertRise": return Pose((19.6,15.6,0.5,0),(32.2,13,-0.16),(7.4,41.5),0.09)
            case "alertHold": return Pose((18.6,16.4,1,-0.3),(32.7,11.5,-0.07),(8,42.2),0.16,turn:0.16)
            case "alertRelax": return Pose((21.5,14.5,-0.4,0.4),(31.4,16.8,0.06),(5.9,40.1),0.05,turn:0.3)
            case "restLower": return Pose((23.8,12.6,-0.8,1.1),(30.5,22.1,0.2),(6.1,38.7),0.01,stance:-0.7)
            case "restTuck": return Pose((24.4,12.1,-1.3,1.6),(25.9,25.1,2.5),(6.9,38),0,turn:0.32,stance:-1.2)
            case "restWake": return Pose((22,14,0,0.6),(31.1,16,-0.29),(5.6,40.5),0.12)
            case "takeoffCrouch": return Pose((25.6,10.7,1.8,0.3),(34,23.4,0.17),(5.3,34.1),0.32,stance:-1.9,fan:0.23)
            case "takeoffPush": return Pose((18,14,2.3,0),(33.9,14.6,-0.24),(4.9,32.4),0.89,stance:0.9,fan:0.44)
            case "crowInclineReady": return Pose((22.6,13.6,1.1,0),(33.3,20.4,0.34),(6.8,38.2),0.06,turn:0.42,stance:-0.4)
            case "crowInclineDown": return Pose((24.3,11.6,2.5,0),(34.5,26.6,0.66),(8.3,34.6),0.15,turn:0.24,stance:-1.2,fan:0.18)
            case "crowInclineRecover": return Pose((21.1,14.7,0.1,0.2),(31.9,16.1,-0.13),(6.6,39.6),0.1,turn:0.82,stance:0.1)
            case "crowInclineSettle": return Pose((21.8,14.2,-0.2,0.3),(32.1,17.5,0.03),(6.3,40.3),0.03,turn:0.22)
            default: return nil
            }
        case .daurianJackdaw:
            switch frame {
            case "lookNear": return Pose((22.3,14,0.6,0),(32.8,19.6,0.28),(7.2,39.7),0.04,turn:0.35)
            case "lookFar": return Pose((21,14.8,-0.2,0),(31.7,15.3,-0.19),(7.9,40.5),0.025,turn:0.65)
            case "alertRise": return Pose((19.9,15.5,0.4,0),(32.3,13.7,-0.17),(8.4,41.2),0.1)
            case "alertHold": return Pose((19,16.2,0.9,-0.2),(32.8,12.3,-0.06),(9,41.9),0.17,turn:0.25)
            case "alertRelax": return Pose((21.8,14.3,-0.3,0.5),(31.5,17.6,0.07),(6.9,40),0.05,turn:0.4)
            case "restLower": return Pose((24,12.3,-0.6,1.2),(30.7,22.6,0.19),(7.1,38.5),0.02,stance:-0.6)
            case "restTuck": return Pose((24.6,11.8,-1.2,1.8),(26.1,25.5,2.55),(7.8,37.8),0,turn:0.38,stance:-1)
            case "restWake": return Pose((22.2,13.7,0.1,0.7),(31.2,16.7,-0.3),(6.6,40.4),0.13)
            case "takeoffCrouch": return Pose((25.8,10.4,1.5,0.4),(34.1,24.2,0.18),(6.2,34),0.29,stance:-1.7,fan:0.2)
            case "takeoffPush": return Pose((18.3,13.4,2,0),(34,15.2,-0.26),(5.8,32.6),0.88,stance:0.8,fan:0.4)
            case "jackdawLeanReady": return Pose((22.6,13.6,0.8,0.1),(32.5,20.1,0.2),(7.8,38.4),0.07,turn:0.82,stance:-0.2)
            case "jackdawLeanDown": return Pose((24,11.9,2.1,0),(34.3,25.8,0.58),(9.2,35.1),0.14,turn:0.42,stance:-1.1,fan:0.13)
            case "jackdawLeanRecover": return Pose((21.3,14.4,-0.1,0.6),(31.1,18.3,-0.12),(7.5,39.5),0.09,turn:0.6,stance:0.1)
            case "jackdawLeanSettle": return Pose((22,14.1,-0.2,0.4),(32.1,18.5,0.04),(7.3,40.1),0.03,turn:0.2)
            default: return nil
            }
        case .redBilledChough:
            switch frame {
            case "lookNear": return Pose((22.2,13.1,0.8,0),(32.6,20.2,0.27),(5.3,39.8),0.05,turn:0.15)
            case "lookFar": return Pose((20.9,14,-0.1,0),(31.4,16.2,-0.24),(5.9,40.5),0.03,turn:0.45)
            case "alertRise": return Pose((19.8,14.8,0.5,0),(32,14.5,-0.21),(6.5,41.2),0.11)
            case "alertHold": return Pose((18.9,15.6,0.9,-0.2),(32.5,13.1,-0.12),(7.1,41.9),0.18,turn:0.2)
            case "alertRelax": return Pose((21.7,13.5,-0.3,0.3),(31.2,18.3,0.04),(5,40.1),0.04,turn:0.3)
            case "restLower": return Pose((23.8,11.9,-0.6,0.9),(30.4,23.1,0.2),(5.2,38.6),0.01,stance:-0.6)
            case "restTuck": return Pose((24.5,11.4,-1,1.4),(26.5,25.4,2.47),(5.9,37.9),0,turn:0.25,stance:-1)
            case "restWake": return Pose((22,13.1,0.1,0.5),(30.9,17.3,-0.32),(4.7,40.4),0.12)
            case "takeoffCrouch": return Pose((25.5,10.2,1.6,0.2),(33.5,24.3,0.15),(4.3,33.7),0.31,stance:-1.7,fan:0.18)
            case "takeoffPush": return Pose((18.4,12.9,2.1,0),(33.6,16,-0.29),(3.9,32.2),0.87,stance:0.8,fan:0.33)
            case "choughProbeReady": return Pose((22.9,12.5,1,0),(33.2,22.2,0.34),(5.8,37.5),0.08,turn:0.12,stance:-0.4)
            case "choughProbeDown": return Pose((24.4,10.8,2.3,0),(34,28.1,0.76),(7.2,33.6),0.16,turn:0.22,stance:-1.3,fan:0.16)
            case "choughProbeRecover": return Pose((21.2,13.8,0.3,0.2),(31.8,18,-0.27),(5.6,39.2),0.1,turn:0.52,stance:0.2)
            case "choughProbeSettle": return Pose((21.9,13.3,-0.2,0.3),(31.9,19.1,-0.03),(5.2,40.2),0.025,turn:0.18)
            default: return nil
            }
        case .plainLaughingthrush:
            switch frame {
            case "lookNear": return Pose((22.6,14,0.7,0),(32.6,21.4,0.25),(5.2,41.8),0.04,turn:0.25)
            case "lookFar": return Pose((21.3,14.7,-0.2,0),(31.5,17.4,-0.23),(5.8,42.5),0.02,turn:0.55)
            case "alertRise": return Pose((20.2,15.4,0.4,0),(32,15.8,-0.2),(6.4,43.1),0.09)
            case "alertHold": return Pose((19.3,16.1,0.8,-0.2),(32.5,14.3,-0.1),(7,43.7),0.16,turn:0.17)
            case "alertRelax": return Pose((22,14.3,-0.3,0.5),(31.3,19.4,0.06),(4.9,42),0.05,turn:0.3)
            case "restLower": return Pose((24.1,12.4,-0.6,1.2),(30.5,23.8,0.18),(5.1,40.5),0.01,stance:-0.6)
            case "restTuck": return Pose((24.7,11.9,-1.1,1.8),(26.2,26.1,2.52),(5.8,39.8),0,turn:0.3,stance:-1)
            case "restWake": return Pose((22.3,13.9,0,0.7),(31,18.3,-0.31),(4.6,42.4),0.11)
            case "takeoffCrouch": return Pose((25.8,10.7,1.5,0.3),(33.6,25.2,0.16),(4.2,35.5),0.28,stance:-1.6,fan:0.2)
            case "takeoffPush": return Pose((18.8,13.4,2,0),(33.4,17.1,-0.28),(3.8,33.6),0.9,stance:0.7,fan:0.32)
            case "plainDipReady": return Pose((23,13.2,0.8,0.1),(32.4,22.1,0.3),(5.7,40.1),0.06,turn:0.72,stance:-0.3)
            case "plainDipDown": return Pose((24.5,11.7,2.1,0),(34,28.2,0.69),(7.1,36.2),0.13,turn:0.18,stance:-1.1,fan:0.14)
            case "plainDipRecover": return Pose((21.6,14.5,0.2,0.4),(31.7,18.4,-0.21),(5.5,41.4),0.09,turn:0.48,stance:0.1)
            case "plainDipSettle": return Pose((22.4,14.1,-0.2,0.3),(31.9,20.1,0.02),(5.1,42.2),0.03,turn:0.22)
            default: return nil
            }
        case .henricsLaughingthrush:
            switch frame {
            case "lookNear": return Pose((22.4,14.1,0.6,0),(32.9,21.1,0.3),(5.3,41.9),0.05,turn:0.2)
            case "lookFar": return Pose((21.1,14.9,-0.2,0),(31.8,17,-0.2),(6,42.6),0.03,turn:0.6)
            case "alertRise": return Pose((20,15.6,0.4,0),(32.4,15.4,-0.18),(6.5,43.3),0.1)
            case "alertHold": return Pose((19.1,16.3,0.9,-0.3),(32.9,13.9,-0.07),(7.1,43.9),0.17,turn:0.25)
            case "alertRelax": return Pose((21.8,14.5,-0.4,0.5),(31.6,19.1,0.08),(5,42.1),0.04,turn:0.35)
            case "restLower": return Pose((24,12.5,-0.7,1.2),(30.8,23.5,0.22),(5.2,40.6),0.02,stance:-0.6)
            case "restTuck": return Pose((24.6,12,-1.2,1.8),(26,26.2,2.58),(5.9,39.9),0,turn:0.35,stance:-1.1)
            case "restWake": return Pose((22.1,14,0,0.7),(31.3,18,-0.29),(4.7,42.5),0.12)
            case "takeoffCrouch": return Pose((25.7,10.8,1.4,0.3),(34.2,25,0.18),(4.3,35.6),0.3,stance:-1.6,fan:0.21)
            case "takeoffPush": return Pose((18.6,13.6,2,0),(34,16.8,-0.25),(3.9,33.8),0.9,stance:0.7,fan:0.36)
            case "henricLookReady": return Pose((22.9,13.4,1,0.1),(33.4,22.5,0.37),(5.9,40.2),0.07,turn:0.22,stance:-0.4)
            case "henricLookDown": return Pose((24.4,11.9,2.2,0),(34.7,29.2,0.88),(7.4,36.3),0.15,turn:0.32,stance:-1.2,fan:0.18)
            case "henricLookRecover": return Pose((21.4,14.8,-0.2,0.4),(30.7,18.7,-0.15),(5.7,41.5),0.1,turn:0.93,stance:0.1)
            case "henricLookSettle": return Pose((22.2,14.3,-0.1,0.4),(32.2,19.8,0.03),(5.2,42.3),0.025,turn:0.28)
            default: return nil
            }
        case .whiteBrowedLaughingthrush:
            switch frame {
            case "lookNear": return Pose((22.2,14.2,0.7,0),(32.7,20.5,0.27),(5.3,41.8),0.045,turn:0.28)
            case "lookFar": return Pose((20.9,15,-0.2,0),(31.6,16.5,-0.21),(5.9,42.5),0.025,turn:0.56)
            case "alertRise": return Pose((19.8,15.7,0.5,0),(32.2,14.9,-0.17),(6.5,43.2),0.11)
            case "alertHold": return Pose((18.9,16.4,1,-0.2),(32.7,13.4,-0.06),(7.1,43.8),0.18,turn:0.2)
            case "alertRelax": return Pose((21.6,14.6,-0.3,0.6),(31.4,18.7,0.07),(5,42),0.05,turn:0.4)
            case "restLower": return Pose((23.8,12.7,-0.7,1.3),(30.6,23.1,0.2),(5.2,40.5),0.01,stance:-0.7)
            case "restTuck": return Pose((24.5,12.1,-1.1,1.9),(26.1,25.8,2.54),(5.9,39.7),0,turn:0.32,stance:-1.1)
            case "restWake": return Pose((21.9,14.1,0.1,0.8),(31.1,17.5,-0.3),(4.7,42.4),0.13)
            case "takeoffCrouch": return Pose((25.6,10.9,1.6,0.4),(34,24.6,0.17),(4.3,35.3),0.31,stance:-1.7,fan:0.22)
            case "takeoffPush": return Pose((18.4,13.8,2.1,0),(33.9,16.3,-0.26),(3.9,33.5),0.89,stance:0.8,fan:0.35)
            case "whiteBrowLeanReady": return Pose((22.7,13.7,1,0.1),(33.3,21.9,0.33),(5.8,40),0.07,turn:0.4,stance:-0.3)
            case "whiteBrowLeanDown": return Pose((24.1,12.1,2.4,0),(35.1,27.3,0.55),(7.3,36.5),0.14,turn:0.18,stance:-1.2,fan:0.15)
            case "whiteBrowLeanRecover": return Pose((21.3,14.9,0.1,0.5),(31.7,17.8,-0.22),(5.6,41.3),0.1,turn:0.72,stance:0.1)
            case "whiteBrowLeanSettle": return Pose((22,14.4,-0.2,0.4),(32,19.3,0.01),(5.2,42.2),0.03,turn:0.24)
            default: return nil
            }
        case .groundTit:
            switch frame {
            case "lookNear": return Pose((22.5,11.6,0.8,0),(32.7,22.4,0.23),(7.2,37.8),0.05,turn:0.16)
            case "lookFar": return Pose((21.2,12.3,-0.1,0),(31.6,18.7,-0.26),(7.8,38.6),0.03,turn:0.46)
            case "alertRise": return Pose((20.1,13,0.5,0),(32.2,17,-0.22),(8.3,39.3),0.1)
            case "alertHold": return Pose((19.2,13.7,0.9,-0.2),(32.7,15.6,-0.12),(8.9,40),0.16,turn:0.18)
            case "alertRelax": return Pose((21.9,11.9,-0.3,0.3),(31.4,20.4,0.04),(6.9,38.1),0.04,turn:0.3)
            case "restLower": return Pose((24,10.5,-0.5,0.9),(30.6,24.3,0.19),(7.1,36.7),0.01,stance:-0.8)
            case "restTuck": return Pose((24.6,10.2,-1,1.4),(26.4,26.2,2.49),(7.8,36),0,turn:0.26,stance:-1.2)
            case "restWake": return Pose((22.2,11.8,0,0.5),(31.1,19.4,-0.32),(6.6,38.5),0.11)
            case "takeoffCrouch": return Pose((25.5,8.8,1.4,0.2),(33.6,25.8,0.15),(6.2,32.2),0.27,stance:-1.9,fan:0.16)
            case "takeoffPush": return Pose((18.8,11.5,2,0),(33.7,17.8,-0.29),(5.8,30.7),0.9,stance:0.9,fan:0.3)
            case "groundProbeReady": return Pose((22.9,11.2,1.2,0),(33.3,23.6,0.29),(7.8,36.1),0.07,turn:0.14,stance:-0.5)
            case "groundProbeDown": return Pose((24.2,9.8,2.4,0),(34.4,28.6,0.64),(9.2,32.9),0.14,turn:0.24,stance:-1.5,fan:0.15)
            case "groundProbeRecover": return Pose((21.5,12.2,-0.2,0.4),(30.9,20.6,-0.19),(7.6,37.3),0.09,turn:0.58,stance:-0.1)
            case "groundProbeSettle": return Pose((22.2,11.8,-0.1,0.3),(32,21.4,-0.02),(7.1,38.3),0.025,turn:0.2)
            default: return nil
            }
        case .rufousBreastedAccentor:
            switch frame {
            case "lookNear": return Pose((22.6,12,0.5,0),(33.3,21.7,0.28),(9.2,38.8),0.04,turn:0.18)
            case "lookFar": return Pose((21.3,12.7,-0.2,0),(32.2,17.9,-0.22),(9.8,39.6),0.02,turn:0.5)
            case "alertRise": return Pose((20.2,13.4,0.3,0),(32.8,16.3,-0.2),(10.4,40.3),0.09)
            case "alertHold": return Pose((19.3,14.1,0.7,-0.2),(33.2,14.9,-0.09),(11,41),0.15,turn:0.2)
            case "alertRelax": return Pose((22,12.3,-0.3,0.5),(32,19.8,0.08),(8.9,39.1),0.05,turn:0.32)
            case "restLower": return Pose((24,11.1,-0.6,1.1),(31.2,23.8,0.21),(9.1,37.6),0.01,stance:-0.6)
            case "restTuck": return Pose((24.6,10.8,-1,1.6),(27,26.2,2.53),(9.8,36.9),0,turn:0.28,stance:-1)
            case "restWake": return Pose((22.3,12.1,0,0.6),(31.7,18.8,-0.3),(8.6,39.5),0.1)
            case "takeoffCrouch": return Pose((25.6,9.5,1.2,0.3),(34.4,25,0.18),(8.2,33.7),0.28,stance:-1.5,fan:0.17)
            case "takeoffPush": return Pose((18.9,11.9,1.8,0),(34.3,17.4,-0.26),(7.8,32.1),0.92,stance:0.6,fan:0.3)
            case "accentorDipReady": return Pose((23,11.6,0.9,0.1),(33.8,23,0.39),(9.8,37.1),0.06,turn:0.16,stance:-0.3)
            case "accentorDipDown": return Pose((24.4,10.2,1.9,0),(35,29.1,0.89),(11.1,33.7),0.12,turn:0.24,stance:-1.1,fan:0.14)
            case "accentorDipRecover": return Pose((21.7,12.6,0.1,0.4),(31.9,19,-0.17),(9.5,38.2),0.08,turn:0.78,stance:0.1)
            case "accentorDipSettle": return Pose((22.3,12.2,-0.1,0.3),(32.6,20.5,0.03),(9.1,39.3),0.025,turn:0.22)
            default: return nil
            }
        case .hornedLark:
            switch frame {
            case "lookNear": return Pose((22.4,10.9,0.7,0),(33.7,22.4,0.27),(8.2,38.8),0.045,turn:0.2)
            case "lookFar": return Pose((21.1,11.6,-0.1,0),(32.6,18.8,-0.23),(8.8,39.6),0.025,turn:0.55)
            case "alertRise": return Pose((20,12.3,0.5,0),(33.2,17.1,-0.19),(9.4,40.3),0.1)
            case "alertHold": return Pose((19.1,13,0.8,-0.2),(33.6,15.7,-0.08),(10,41),0.16,turn:0.18)
            case "alertRelax": return Pose((21.8,11.2,-0.3,0.4),(32.4,20.6,0.07),(7.9,39.1),0.04,turn:0.35)
            case "restLower": return Pose((23.9,10.1,-0.5,0.9),(31.6,24.2,0.19),(8.1,37.6),0.01,stance:-0.6)
            case "restTuck": return Pose((24.5,9.8,-1,1.4),(27.4,26.3,2.51),(8.8,36.9),0,turn:0.3,stance:-1)
            case "restWake": return Pose((22.1,11.1,0,0.5),(32.1,19.5,-0.31),(7.6,39.5),0.11)
            case "takeoffCrouch": return Pose((25.4,8.5,1.3,0.2),(34.7,25.7,0.17),(7.2,33.1),0.27,stance:-1.6,fan:0.2)
            case "takeoffPush": return Pose((18.7,10.7,1.9,0),(34.6,18,-0.27),(6.8,31.6),0.91,stance:0.7,fan:0.32)
            case "hornLookReady": return Pose((22.8,10.5,1,0.1),(34.2,23.6,0.36),(8.8,37),0.06,turn:0.25,stance:-0.4)
            case "hornLookDown": return Pose((24.1,9.3,2,0),(35.4,28.5,0.72),(10.2,33.5),0.13,turn:0.35,stance:-1.2,fan:0.15)
            case "hornLookRecover": return Pose((21.5,11.5,-0.1,0.3),(32.2,19.8,-0.18),(8.5,38.1),0.09,turn:0.85,stance:0.1)
            case "hornLookSettle": return Pose((22.1,11.1,-0.2,0.3),(33,21.2,0.02),(8.1,39.3),0.03,turn:0.24)
            default: return nil
            }
        case .redThroatedThrush:
            switch frame {
            case "lookNear": return Pose((22.3,13,0.8,0),(33.2,21,0.29),(7.2,39.8),0.05,turn:0.2)
            case "lookFar": return Pose((21,13.8,-0.2,0),(32.1,17,-0.21),(7.8,40.6),0.03,turn:0.53)
            case "alertRise": return Pose((19.9,14.5,0.5,0),(32.7,15.4,-0.18),(8.4,41.3),0.11)
            case "alertHold": return Pose((19,15.2,0.9,-0.2),(33.2,14,-0.07),(9,42),0.18,turn:0.18)
            case "alertRelax": return Pose((21.7,13.4,-0.4,0.5),(31.9,19.2,0.08),(6.9,40.1),0.05,turn:0.34)
            case "restLower": return Pose((23.9,11.9,-0.7,1.1),(31.1,23.3,0.2),(7.1,38.6),0.01,stance:-0.6)
            case "restTuck": return Pose((24.5,11.5,-1.2,1.7),(26.7,26,2.56),(7.8,37.9),0,turn:0.3,stance:-1)
            case "restWake": return Pose((22,13.1,0.1,0.7),(31.6,18.1,-0.3),(6.6,40.5),0.12)
            case "takeoffCrouch": return Pose((25.7,10.2,1.6,0.3),(34.4,24.9,0.17),(6.2,34.2),0.3,stance:-1.7,fan:0.2)
            case "takeoffPush": return Pose((18.5,12.9,2.1,0),(34.3,16.6,-0.26),(5.8,32.6),0.89,stance:0.8,fan:0.34)
            case "redThroatLeanReady": return Pose((22.8,12.5,1.2,0.1),(33.9,22.5,0.36),(7.8,38),0.07,turn:0.3,stance:-0.4)
            case "redThroatLeanDown": return Pose((24.2,11.1,2.5,0),(35.4,27.8,0.61),(9.3,34.4),0.15,turn:0.2,stance:-1.2,fan:0.17)
            case "redThroatLeanRecover": return Pose((21.3,13.7,0.2,0.4),(32.3,17.9,-0.23),(7.6,39.2),0.1,turn:0.68,stance:0.1)
            case "redThroatLeanSettle": return Pose((22,13.2,-0.1,0.4),(32.6,19.8,0.03),(7.1,40.3),0.03,turn:0.23)
            default: return nil
            }
        default: return nil
        }
    }
}
