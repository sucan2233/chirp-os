import Foundation

/// E4 presentation anatomy, right-facing and top-down in a logical 48-unit canvas.
/// These stylized dry-support poses are not verified natural-history behavior.
public enum ExpansionWetlandArtGeometry {
    public static let species: [SpeciesID] = [
        .easternSpotBilledDuck, .ruddyShelduck, .easternCattleEgret,
        .blackTailedGull, .greatCrestedGrebe, .littleGrebe
    ]

    public static func frameNames(for species:SpeciesID) -> [String] {
        Self.species.contains(species) ? PoseClip.frameNames + signatureFrameNames(for:species) : []
    }

    /// Preparation, emphasis, recovery, settling. No old idle names are aliases.
    public static func signatureFrameNames(for species:SpeciesID) -> [String] {
        switch species {
        case .easternSpotBilledDuck:
            return ["spotShoulderReady","spotShoulderTurn","spotShoulderRecover","spotShoulderSettle"]
        case .ruddyShelduck:
            return ["shelduckShoulderReady","shelduckShoulderTurn","shelduckShoulderRecover","shelduckShoulderSettle"]
        case .easternCattleEgret:
            return ["cattleNeckReady","cattleNeckReach","cattleNeckRecover","cattleNeckSettle"]
        case .blackTailedGull:
            return ["gullShoulderReady","gullShoulderTurn","gullShoulderRecover","gullShoulderSettle"]
        case .greatCrestedGrebe:
            return ["crestedNeckReady","crestedNeckTurn","crestedNeckRecover","crestedNeckSettle"]
        case .littleGrebe:
            return ["littleNeckReady","littleNeckTurn","littleNeckRecover","littleNeckSettle"]
        default: return []
        }
    }

    public enum Support: Equatable { case webbed, egret, gull, rearGrebe }
    public enum Bill: Equatable { case spatulate, spear, gull, fine }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, billDepth: Double
        public let neckWidth, tailWidth, wingReach, primaryLength: Double
        public let support: Support
        public let bill: Bill
        public let bodyContour, headContour, wingContour: [(Double,Double)]
    }

    public static func anatomy(for species:SpeciesID) -> Anatomy? {
        switch species {
        case .easternSpotBilledDuck:
            return Anatomy(width:27,headWidth:9,headHeight:7,billLength:5.5,billDepth:2.1,
                neckWidth:5,tailWidth:6.8,wingReach:15.2,primaryLength:9.1,support:.webbed,bill:.spatulate,
                bodyContour:[(0,0.53),(0.07,0.25),(0.29,0.04),(0.61,0),(0.86,0.16),(1,0.43),(0.96,0.73),(0.76,0.95),(0.45,1),(0.16,0.85)],
                headContour:[(-0.5,-0.1),(-0.37,-0.4),(-0.04,-0.5),(0.3,-0.39),(0.49,-0.1),(0.47,0.22),(0.18,0.48),(-0.2,0.48),(-0.46,0.24)],
                wingContour:[(-0.69,0.07),(-0.12,-0.08),(0.52,0.17),(1,0.87),(0.81,1.02),(0.4,1.05),(-0.15,0.87),(-0.71,0.48)])
        case .ruddyShelduck:
            return Anatomy(width:27,headWidth:8,headHeight:7,billLength:5.2,billDepth:2,
                neckWidth:4.8,tailWidth:7.1,wingReach:15.8,primaryLength:10.1,support:.webbed,bill:.spatulate,
                bodyContour:[(0,0.57),(0.11,0.26),(0.37,0.03),(0.68,0),(0.91,0.18),(1,0.46),(0.93,0.79),(0.67,1),(0.33,0.98),(0.08,0.8)],
                headContour:[(-0.5,-0.08),(-0.35,-0.4),(0,-0.5),(0.34,-0.35),(0.5,-0.04),(0.43,0.28),(0.1,0.5),(-0.28,0.44),(-0.48,0.19)],
                wingContour:[(-0.7,0.1),(-0.1,-0.07),(0.56,0.18),(1,0.91),(0.82,1.06),(0.45,1.02),(-0.13,0.84),(-0.71,0.5)])
        case .easternCattleEgret:
            return Anatomy(width:20,headWidth:8,headHeight:6,billLength:7.6,billDepth:1.65,
                neckWidth:3.8,tailWidth:5,wingReach:17.3,primaryLength:8.6,support:.egret,bill:.spear,
                bodyContour:[(0,0.62),(0.14,0.29),(0.43,0.03),(0.72,0),(0.94,0.2),(1,0.49),(0.9,0.81),(0.64,1),(0.3,0.96),(0.08,0.81)],
                headContour:[(-0.5,-0.06),(-0.34,-0.39),(0.04,-0.5),(0.36,-0.31),(0.5,-0.01),(0.37,0.3),(0.01,0.48),(-0.33,0.37)],
                wingContour:[(-0.61,0.05),(-0.06,-0.09),(0.54,0.16),(1,0.93),(0.86,1.05),(0.71,0.95),(0.55,1.07),(0.05,0.84),(-0.64,0.43)])
        case .blackTailedGull:
            return Anatomy(width:25,headWidth:8,headHeight:6,billLength:5.5,billDepth:1.65,
                neckWidth:4.1,tailWidth:7,wingReach:16.3,primaryLength:10.2,support:.gull,bill:.gull,
                bodyContour:[(0,0.6),(0.13,0.3),(0.41,0.04),(0.72,0),(0.94,0.19),(1,0.43),(0.94,0.72),(0.72,0.96),(0.4,1),(0.1,0.84)],
                headContour:[(-0.5,-0.07),(-0.33,-0.4),(0.04,-0.5),(0.38,-0.3),(0.5,0.01),(0.4,0.31),(0.02,0.5),(-0.35,0.35)],
                wingContour:[(-0.66,0.03),(-0.05,-0.1),(0.56,0.14),(1,1.02),(0.83,1.08),(0.6,0.93),(0.07,0.79),(-0.65,0.41)])
        case .greatCrestedGrebe:
            return Anatomy(width:25,headWidth:7,headHeight:5,billLength:5,billDepth:1.2,
                neckWidth:3.1,tailWidth:3.5,wingReach:13.6,primaryLength:7.3,support:.rearGrebe,bill:.fine,
                bodyContour:[(0,0.52),(0.09,0.23),(0.34,0.02),(0.68,0),(0.92,0.18),(1,0.46),(0.94,0.76),(0.7,0.97),(0.36,1),(0.1,0.84)],
                headContour:[(-0.5,-0.07),(-0.34,-0.4),(0.02,-0.5),(0.36,-0.32),(0.5,-0.01),(0.4,0.29),(0.03,0.5),(-0.35,0.36)],
                wingContour:[(-0.66,0.1),(-0.12,-0.04),(0.5,0.2),(1,0.88),(0.76,1.05),(0.32,1.02),(-0.18,0.8),(-0.68,0.49)])
        case .littleGrebe:
            return Anatomy(width:24,headWidth:8,headHeight:7,billLength:4.6,billDepth:1.25,
                neckWidth:4.3,tailWidth:4.2,wingReach:12.9,primaryLength:8,support:.rearGrebe,bill:.fine,
                bodyContour:[(0,0.48),(0.07,0.18),(0.32,0),(0.66,0.02),(0.91,0.2),(1,0.48),(0.93,0.8),(0.68,1),(0.35,0.98),(0.09,0.81)],
                headContour:[(-0.5,-0.09),(-0.37,-0.38),(-0.07,-0.5),(0.29,-0.42),(0.49,-0.12),(0.46,0.23),(0.14,0.5),(-0.24,0.46),(-0.48,0.21)],
                wingContour:[(-0.68,0.12),(-0.12,-0.04),(0.52,0.22),(1,0.84),(0.77,1.04),(0.34,1.07),(-0.17,0.86),(-0.7,0.53)])
        default: return nil
        }
    }

    public struct Pose {
        public let body: (y:Double,height:Double,lean:Double,fluff:Double)
        public let head: (x:Double,y:Double,pitch:Double)
        public let neck: (x:Double,y:Double)
        public let tail: (x:Double,y:Double)
        public let wing, turn, stance, balance, ruffle: Double

        fileprivate init(_ body:(Double,Double,Double,Double), _ head:(Double,Double,Double),
                         _ neck:(Double,Double), _ tail:(Double,Double), _ wing:Double,
                         turn:Double = 0, stance:Double = 0, balance:Double = 0, ruffle:Double = 0) {
            self.body=body; self.head=head; self.neck=neck; self.tail=tail; self.wing=wing
            self.turn=turn; self.stance=stance; self.balance=balance; self.ruffle=ruffle
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

        /// Vertex 2 is the actual tip for every bill. Tip patches clip to this
        /// polygon, so colored bands cannot extend beyond the reported anchor.
        public func billVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let root=headWidth(anatomy:a)/2-0.45
            let length=a.billLength*(1-turn*0.1), depth=a.billDepth
            switch a.bill {
            case .spatulate:
                return [(root,-depth/2),(root+length*0.86,-depth*0.38),
                        (root+length,0.35),(root+length*0.76,depth*0.72),(root,depth*0.65)]
            case .gull:
                return [(root,-depth*0.55),(root+length*0.72,-depth*0.24),
                        (root+length,0.35),(root+length*0.75,depth*0.82),(root,depth*0.65)]
            case .spear, .fine:
                return [(root,-depth/2),(root+length*0.65,-depth*0.22),
                        (root+length,0.3),(root+length*0.65,depth*0.53),(root,depth*0.65)]
            }
        }

        /// A cubic spine joins the torso to the head with a separately authored
        /// lower bend and a head-local upper bend; there is no whole-bird tilt.
        public func neckPath(anatomy a:Anatomy) -> [(Double,Double)] {
            [bodyPoint(0.81,0.36,anatomy:a),(neck.x,neck.y),
             headPoint(-a.headWidth*0.65,a.headHeight*0.58),
             headPoint(-a.headWidth*0.15,a.headHeight*0.18)]
        }

        public func neckPoint(_ t:Double, anatomy a:Anatomy) -> (Double,Double) {
            let path=neckPath(anatomy:a), u=1-t
            return (u*u*u*path[0].0+3*u*u*t*path[1].0+3*u*t*t*path[2].0+t*t*t*path[3].0,
                    u*u*u*path[0].1+3*u*u*t*path[1].1+3*u*t*t*path[2].1+t*t*t*path[3].1)
        }

        /// The shelduck collar follows a normal to the actual neck spine.
        public func neckCrossSection(_ t:Double, anatomy a:Anatomy) -> [(Double,Double)] {
            let path=neckPath(anatomy:a), center=neckPoint(t,anatomy:a), u=1-t
            let dx=3*u*u*(path[1].0-path[0].0)+6*u*t*(path[2].0-path[1].0)+3*t*t*(path[3].0-path[2].0)
            let dy=3*u*u*(path[1].1-path[0].1)+6*u*t*(path[2].1-path[1].1)+3*t*t*(path[3].1-path[2].1)
            let length=max(0.001,hypot(dx,dy)), half=a.neckWidth*0.5
            let nx = -dy/length, ny=dx/length
            return [(center.0-nx*half,center.1-ny*half),center,
                    (center.0+nx*half,center.1+ny*half)]
        }
    }

    /// Rear grebe toes sit behind the other dry-support bands. Their terminal
    /// toe still reaches (29,39), preserving the common presentation reference.
    public static func toePaths(for species:SpeciesID) -> [[(Double,Double)]] {
        guard let a=anatomy(for:species) else { return [] }
        switch a.support {
        case .rearGrebe: return [[(21,39),(23,38.5),(25,39)],[(25,39),(27,38.5),(29,39)]]
        default: return [[(25,39),(27,38.5),(29,39)],[(29,39),(31,38.5),(33,39)]]
        }
    }

    public static func beakAnchor(species:SpeciesID, frame:String) -> PoseClip.Anchor? {
        guard let a=anatomy(for:species), let p=pose(species:species,frame:frame) else { return nil }
        let tip=p.billVertices(anatomy:a)[2], world=p.headPoint(tip.0,tip.1)
        return PoseClip.Anchor(world.0,world.1)
    }

    /// Each species has fourteen separately authored rows, including the final
    /// settled signature. Water, targets and contact clips are outside this set.
    public static func pose(species:SpeciesID, frame:String) -> Pose? {
        switch species {
        case .easternSpotBilledDuck:
            switch frame {
            case "lookNear": return Pose((24.1,12.1,0.7,0),(32.6,21.1,0.25),(34.3,28.2),(8.9,32.9),0.04,turn:0.16,stance:-0.2)
            case "lookFar": return Pose((23.2,12.8,-0.2,0),(31.7,17.7,-0.18),(32.8,25.5),(9.6,33.7),0.025,turn:0.55)
            case "alertRise": return Pose((22.3,13.4,0.4,0),(32.1,16,-0.16),(33.2,24),(10.1,34.3),0.1,stance:0.2)
            case "alertHold": return Pose((21.5,14,0.8,-0.2),(32.6,14.5,-0.07),(33.5,22.6),(10.7,35),0.17,turn:0.2,stance:0.4)
            case "alertRelax": return Pose((23.7,12.4,-0.3,0.5),(31.5,19.4,0.06),(33.2,27),(8.6,33.2),0.05,turn:0.3)
            case "restLower": return Pose((25.8,10.8,-0.6,1.1),(30.7,24.8,0.17),(32.5,30.1),(8.8,34.2),0.01,stance:-0.8)
            case "restTuck": return Pose((26.5,10.3,-1,1.6),(24.6,28,2.69),(29.6,32),(9.4,34.7),0,turn:0.28,stance:-1.2)
            case "restWake": return Pose((24.3,11.9,0,0.7),(31.1,20.3,-0.27),(33.7,28.4),(8.3,33.5),0.12,stance:-0.3)
            case "takeoffCrouch": return Pose((27.1,9.3,1.4,0.3),(33.6,25.4,0.16),(35.2,31.5),(7.9,29.8),0.3,stance:-1.7)
            case "takeoffPush": return Pose((20.5,12,1.9,0),(33.6,17,-0.24),(33.7,25.1),(7.5,28.4),0.9,stance:0.8)
            case "spotShoulderReady": return Pose((24.8,11.6,-0.3,0.6),(30.5,23,0.5),(32.3,29.1),(9.4,32.3),0.08,turn:0.52,stance:-0.3)
            case "spotShoulderTurn": return Pose((25.4,11.2,-0.9,1.2),(25.8,25.6,2.33),(29.7,30.8),(10.4,31.4),0.2,turn:0.82,stance:-0.6,ruffle:0.55)
            case "spotShoulderRecover": return Pose((23.8,12.3,0.2,0.5),(30.2,21.3,-0.18),(32.1,27.9),(9.2,33.6),0.11,turn:0.35,stance:-0.1)
            case "spotShoulderSettle": return Pose((24.2,12,-0.1,0.3),(32,20,0.03),(33.7,27.8),(8.7,33.4),0.03,turn:0.18)
            default: return nil
            }
        case .ruddyShelduck:
            switch frame {
            case "lookNear": return Pose((22.2,14,0.6,0),(32.8,18.3,0.24),(34.5,26.9),(8.2,33.8),0.05,turn:0.18,stance:-0.1)
            case "lookFar": return Pose((21.2,14.8,-0.2,0),(31.8,14.9,-0.19),(32.6,23.9),(8.9,34.5),0.03,turn:0.58)
            case "alertRise": return Pose((20.3,15.4,0.4,0),(32.3,13.2,-0.17),(33.1,22.3),(9.5,35.2),0.11,stance:0.3)
            case "alertHold": return Pose((19.5,16.1,0.9,-0.2),(32.8,11.8,-0.07),(33.5,20.9),(10.1,35.8),0.18,turn:0.22,stance:0.5)
            case "alertRelax": return Pose((21.8,14.3,-0.3,0.5),(31.6,16.7,0.07),(33.3,25.4),(7.9,34.1),0.04,turn:0.32)
            case "restLower": return Pose((24.3,12.4,-0.7,1.2),(30.7,22.7,0.18),(32.7,29.6),(8.1,35),0.01,stance:-0.8)
            case "restTuck": return Pose((25,12,-1.2,1.8),(24.2,27,2.73),(29.4,31.4),(8.7,35.5),0,turn:0.32,stance:-1.3)
            case "restWake": return Pose((22.5,13.7,0.1,0.7),(31.2,17.8,-0.28),(33.8,27.3),(7.6,34.4),0.13,stance:-0.3)
            case "takeoffCrouch": return Pose((26.1,10.6,1.6,0.4),(33.9,24,0.17),(35.5,31),(7.2,30.4),0.31,stance:-1.8)
            case "takeoffPush": return Pose((19,13.2,2.1,0),(33.8,15.4,-0.25),(34.1,24),(6.8,28.9),0.89,stance:0.9)
            case "shelduckShoulderReady": return Pose((22.9,13.2,-0.4,0.6),(30.6,20.4,0.46),(32.1,28),(8.8,33.1),0.09,turn:0.48,stance:-0.3)
            case "shelduckShoulderTurn": return Pose((23.7,12.8,-1,1.3),(25.6,24,2.4),(29.4,30),(9.8,32),0.22,turn:0.78,stance:-0.7,ruffle:0.6)
            case "shelduckShoulderRecover": return Pose((21.9,14.1,0.2,0.5),(30.3,18.6,-0.16),(32.3,26.8),(8.5,34.6),0.12,turn:0.4,stance:-0.1)
            case "shelduckShoulderSettle": return Pose((22.3,13.9,-0.1,0.3),(32.1,17.3,0.02),(33.9,26.3),(8,34.3),0.03,turn:0.2)
            default: return nil
            }
        case .easternCattleEgret:
            switch frame {
            case "lookNear": return Pose((21.8,11.4,0.6,0),(32.6,17.4,0.24),(34.7,26.5),(13.1,30.8),0.04,stance:-0.3)
            case "lookFar": return Pose((20.9,12,-0.2,0),(31.7,13.4,-0.17),(32.6,22.9),(13.7,31.3),0.025,turn:0.4,stance:0.1)
            case "alertRise": return Pose((20,12.6,0.4,0),(32.2,11.7,-0.14),(32.9,21.2),(14.3,31.8),0.1,stance:0.4)
            case "alertHold": return Pose((19.2,13.3,0.8,-0.2),(32.7,10.1,-0.06),(33.1,19.7),(14.9,32.3),0.17,turn:0.2,stance:0.6)
            case "alertRelax": return Pose((21.4,11.7,-0.3,0.4),(31.5,15.4,0.07),(33.7,24.9),(12.8,31.1),0.05,turn:0.25,stance:-0.1)
            case "restLower": return Pose((23.8,10.7,-0.6,0.9),(30.7,21.6,0.19),(33.2,28.4),(13,32),0.01,stance:-1.1)
            case "restTuck": return Pose((24.5,10.2,-1,1.4),(26.2,25.2,2.58),(31,29.6),(13.6,32.5),0,turn:0.28,stance:-1.6)
            case "restWake": return Pose((22.1,11.5,0,0.6),(31.1,16.4,-0.26),(34.2,26.1),(12.5,31.5),0.12,stance:-0.5)
            case "takeoffCrouch": return Pose((25.4,9.3,1.3,0.3),(33.5,23,0.15),(35.6,30),(12.1,28.7),0.3,stance:-2.1)
            case "takeoffPush": return Pose((18.7,11.5,1.8,0),(33.6,14.4,-0.23),(33.6,23.4),(11.7,27.3),0.9,stance:0.9)
            case "cattleNeckReady": return Pose((21.6,11.5,0.4,0.2),(32.7,15.5,0.08),(34.5,24.5),(13.6,30.6),0.07,turn:0.22,stance:0.3,balance:0.45)
            case "cattleNeckReach": return Pose((22.5,10.8,1.3,0),(34.8,18.5,0.31),(36.5,26.9),(14.4,29.7),0.15,turn:0.14,stance:-0.4,balance:0.8)
            case "cattleNeckRecover": return Pose((20.8,12,0.1,0.5),(31.9,13.8,-0.2),(33.2,23.2),(13.9,31.4),0.1,turn:0.58,stance:0.2,balance:0.2)
            case "cattleNeckSettle": return Pose((21.5,11.6,-0.1,0.3),(32.1,16.2,0.02),(34.1,25.5),(13.2,31.2),0.03,turn:0.18,stance:-0.1)
            default: return nil
            }
        case .blackTailedGull:
            switch frame {
            case "lookNear": return Pose((24,10.7,0.7,0),(32.7,20.5,0.25),(34.7,27.4),(7.2,33.8),0.05,turn:0.18,stance:-0.2)
            case "lookFar": return Pose((23.1,11.3,-0.2,0),(31.7,17,-0.18),(32.8,24.9),(7.9,34.5),0.03,turn:0.5)
            case "alertRise": return Pose((22.2,12,0.4,0),(32.2,15.3,-0.16),(33.1,23.3),(8.5,35.1),0.11,stance:0.3)
            case "alertHold": return Pose((21.4,12.7,0.8,-0.2),(32.7,13.9,-0.07),(33.5,21.8),(9.1,35.7),0.18,turn:0.2,stance:0.5)
            case "alertRelax": return Pose((23.6,11,-0.3,0.4),(31.5,18.7,0.07),(33.5,26.2),(6.9,34.1),0.04,turn:0.3)
            case "restLower": return Pose((25.6,10,-0.6,1),(30.6,24,0.18),(32.8,29.9),(7.1,35),0.01,stance:-0.8)
            case "restTuck": return Pose((26.3,9.7,-1,1.5),(25,27.2,2.66),(30,31.2),(7.7,35.5),0,turn:0.3,stance:-1.2)
            case "restWake": return Pose((24.2,10.9,0,0.6),(31.1,19.6,-0.27),(34.1,27.7),(6.6,34.4),0.13,stance:-0.3)
            case "takeoffCrouch": return Pose((27,8.8,1.4,0.3),(33.7,24.8,0.16),(35.4,30.6),(6.2,30.1),0.31,stance:-1.7)
            case "takeoffPush": return Pose((20.3,10.8,1.9,0),(33.7,16.5,-0.24),(33.7,24.9),(5.8,28.6),0.89,stance:0.8)
            case "gullShoulderReady": return Pose((24.7,10.4,-0.3,0.5),(30.9,22.2,0.45),(32.8,28.8),(7.8,33.1),0.09,turn:0.5,stance:-0.3)
            case "gullShoulderTurn": return Pose((25.3,10.1,-0.8,1.1),(26.3,24.6,2.36),(30.4,30.3),(8.9,32.1),0.21,turn:0.8,stance:-0.6,ruffle:0.5)
            case "gullShoulderRecover": return Pose((23.7,11.2,0.2,0.5),(30.5,20.6,-0.17),(32.7,27.4),(7.6,34.5),0.12,turn:0.37,stance:-0.1)
            case "gullShoulderSettle": return Pose((24.1,10.8,-0.1,0.3),(32.1,19.4,0.03),(34.1,26.9),(7,34.3),0.03,turn:0.18)
            default: return nil
            }
        case .greatCrestedGrebe:
            switch frame {
            case "lookNear": return Pose((26.2,9.9,0.6,0),(32.8,15.8,0.23),(34.7,26.9),(11.3,33.7),0.04,turn:0.2,stance:-0.2)
            case "lookFar": return Pose((25.4,10.4,-0.2,0),(31.8,12.3,-0.17),(32.8,23.8),(11.9,34.2),0.025,turn:0.52)
            case "alertRise": return Pose((24.6,11,0.4,0),(32.3,10.7,-0.14),(33.1,22.1),(12.4,34.7),0.09,stance:0.1)
            case "alertHold": return Pose((23.9,11.5,0.8,-0.2),(32.8,9.3,-0.05),(33.5,20.6),(13,35.2),0.15,turn:0.18,stance:0.2)
            case "alertRelax": return Pose((25.8,10.2,-0.3,0.4),(31.6,14.1,0.06),(33.3,25.4),(11,34),0.04,turn:0.28)
            case "restLower": return Pose((27.1,9.4,-0.6,0.9),(30.8,23.3,0.16),(33,30.8),(11.2,34.8),0.01,stance:-0.6)
            case "restTuck": return Pose((27.6,9.1,-1,1.4),(25.8,28.4,2.64),(30.5,32.4),(11.8,35.3),0,turn:0.3,stance:-0.9)
            case "restWake": return Pose((26.3,9.9,0,0.6),(31.2,16.6,-0.25),(34,27.5),(10.7,34.3),0.11,stance:-0.2)
            case "takeoffCrouch": return Pose((28,8.5,1.2,0.3),(33.7,24,0.15),(35.2,31.7),(10.3,32.8),0.28,stance:-1.2)
            case "takeoffPush": return Pose((21.7,10.4,1.8,0),(33.6,15.2,-0.22),(33.9,25.4),(9.9,30.9),0.87,stance:0.5)
            case "crestedNeckReady": return Pose((26,10,-0.2,0.3),(32.2,16.3,0.12),(33.5,27),(11.8,33.3),0.07,turn:0.4,stance:-0.1)
            case "crestedNeckTurn": return Pose((26.6,9.6,-0.7,0.8),(29.7,19.3,-0.08),(31.3,28.9),(12.8,32.7),0.17,turn:0.92,stance:-0.4,ruffle:0.45)
            case "crestedNeckRecover": return Pose((25.5,10.4,0.1,0.4),(31.7,14.5,-0.2),(32.8,25.8),(12.1,34.4),0.1,turn:0.58,stance:0.1)
            case "crestedNeckSettle": return Pose((26.1,10,-0.1,0.25),(32.3,15.1,0.02),(34.1,26.3),(11.2,34.1),0.03,turn:0.22)
            default: return nil
            }
        case .littleGrebe:
            switch frame {
            case "lookNear": return Pose((24.5,11.9,0.5,0),(32.4,23.1,0.24),(33.8,29.7),(11.8,34.8),0.04,turn:0.18,stance:-0.2)
            case "lookFar": return Pose((23.7,12.5,-0.2,0),(31.5,19.9,-0.18),(32.1,27.7),(12.4,35.3),0.025,turn:0.55)
            case "alertRise": return Pose((22.9,13.1,0.3,0),(32,18.3,-0.15),(32.6,26.1),(12.9,35.8),0.09,stance:0.1)
            case "alertHold": return Pose((22.2,13.6,0.7,-0.2),(32.5,16.9,-0.06),(33,24.6),(13.5,36.3),0.15,turn:0.2,stance:0.2)
            case "alertRelax": return Pose((24.1,12.2,-0.3,0.5),(31.3,21.6,0.07),(32.7,28.9),(11.5,35.1),0.04,turn:0.3)
            case "restLower": return Pose((25.5,11.2,-0.6,1),(30.5,26,0.17),(32.2,32),(11.7,35.9),0.01,stance:-0.6)
            case "restTuck": return Pose((26,10.9,-1,1.5),(25.5,29.1,2.7),(29.6,33.4),(12.3,36.4),0,turn:0.32,stance:-0.9)
            case "restWake": return Pose((24.6,11.9,0,0.7),(30.9,22.5,-0.26),(33.3,30.1),(11.2,35.4),0.11,stance:-0.2)
            case "takeoffCrouch": return Pose((26.8,9.9,1.1,0.3),(33.3,27,0.15),(34.6,33.1),(10.8,33.9),0.27,stance:-1.1)
            case "takeoffPush": return Pose((20.7,11.7,1.7,0),(33.2,20.8,-0.23),(33.2,28),(10.4,32),0.88,stance:0.5)
            case "littleNeckReady": return Pose((24.6,11.7,-0.2,0.5),(31.8,23.6,0.14),(32.6,30),(12.3,34.4),0.07,turn:0.4,stance:-0.1,ruffle:0.2)
            case "littleNeckTurn": return Pose((25.2,11.2,-0.6,1.1),(29.6,24.8,-0.1),(30.7,31.2),(13.4,33.8),0.18,turn:0.95,stance:-0.4,ruffle:0.8)
            case "littleNeckRecover": return Pose((24,12.3,0.1,0.6),(31.2,21.8,-0.19),(32.2,29.1),(12.6,35.6),0.1,turn:0.6,stance:0.1,ruffle:0.3)
            case "littleNeckSettle": return Pose((24.5,12,-0.1,0.3),(31.9,22.2,0.02),(33.1,29.5),(11.7,35.2),0.03,turn:0.23)
            default: return nil
            }
        default: return nil
        }
    }
}
