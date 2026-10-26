import Foundation

/// E5 original anatomy in top-down, right-facing 48-unit coordinates.
/// Presentation only: no habitat, food, contact or behavioral admission data.
public enum ExpansionLargeArtGeometry {
    public static let species: [SpeciesID] = [
        .orientalTurtleDove, .eurasianCollaredDove, .uplandBuzzard,
        .himalayanVulture, .commonPheasant, .greaterCoucal
    ]

    public static func frameNames(for species:SpeciesID) -> [String] {
        Self.species.contains(species) ? PoseClip.frameNames+signatureFrameNames(for:species) : []
    }

    /// Frozen append order: preparation, emphasis, recovery, settled pause.
    public static func signatureFrameNames(for species:SpeciesID) -> [String] {
        switch species {
        case .orientalTurtleDove: return ["turtleShoulderReady", "turtleShoulderTurn", "turtleShoulderLift", "turtleShoulderSettle"]
        case .eurasianCollaredDove: return ["collaredTurnReady", "collaredTurnEase", "collaredTurnReturn", "collaredTurnSettle"]
        case .uplandBuzzard: return ["uplandWatchReady", "uplandWatchLoosen", "uplandWatchFold", "uplandWatchSettle"]
        case .himalayanVulture: return ["vultureGazeReady", "vultureGazeDraw", "vultureGazeRecover", "vultureGazeSettle"]
        case .commonPheasant: return ["pheasantPeerReady", "pheasantPeerLower", "pheasantPeerLift", "pheasantPeerSettle"]
        case .greaterCoucal: return ["coucalLiftReady", "coucalLiftGape", "coucalLiftClose", "coucalLiftSettle"]
        default: return []
        }
    }

    public enum BillShape: Equatable { case short, hooked, arched }
    public enum TailShape: Equatable { case rounded, square, tapered, graduated }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, neckWidth, tailWidth:Double
        public let shoulderU, wingChord, primaryLength, wingReach:Double
        public let bill:BillShape
        public let tail:TailShape
        public let torso, wing:[(Double,Double)]
    }

    public static func anatomy(for species:SpeciesID) -> Anatomy? {
        switch species {
        case .orientalTurtleDove:
            return Anatomy(width:25, headWidth:7, headHeight:6, billLength:3.1, neckWidth:5.8, tailWidth:5.8,
                shoulderU:0.55, wingChord:7.5, primaryLength:12.4, wingReach:16.5, bill:.short, tail:.rounded,
                torso:[(0,0.52),(0.06,0.26),(0.28,0.05),(0.58,0),(0.84,0.12),(1,0.38),(0.98,0.69),(0.81,0.94),(0.49,1),(0.19,0.88),(0.03,0.7)],
                wing:[(-0.62,0.1),(-0.1,-0.05),(0.52,0.12),(0.93,0.59),(1,0.92),(0.79,1.08),(0.42,1.06),(-0.16,0.86),(-0.65,0.49)])
        case .eurasianCollaredDove:
            return Anatomy(width:24, headWidth:7, headHeight:6, billLength:2.8, neckWidth:5, tailWidth:6.2,
                shoulderU:0.54, wingChord:7.1, primaryLength:12.1, wingReach:16.8, bill:.short, tail:.rounded,
                torso:[(0,0.58),(0.08,0.3),(0.33,0.05),(0.65,0),(0.89,0.17),(1,0.46),(0.93,0.78),(0.69,1),(0.36,0.97),(0.11,0.81)],
                wing:[(-0.59,0.06),(-0.02,-0.07),(0.56,0.18),(1,0.98),(0.79,1.05),(0.34,0.97),(-0.21,0.81),(-0.64,0.4)])
        case .uplandBuzzard:
            return Anatomy(width:23, headWidth:9, headHeight:8, billLength:3.5, neckWidth:6.5, tailWidth:7,
                shoulderU:0.59, wingChord:8.6, primaryLength:13, wingReach:17.3, bill:.hooked, tail:.square,
                torso:[(0,0.5),(0.05,0.22),(0.29,0.01),(0.62,0),(0.88,0.17),(1,0.44),(0.98,0.72),(0.79,0.96),(0.47,1),(0.17,0.88),(0.02,0.69)],
                wing:[(-0.51,0.13),(-0.02,-0.07),(0.57,0.04),(1,0.59),(0.9,0.77),(0.98,0.86),(0.8,0.88),(0.83,1.03),(0.65,0.97),(0.56,1.08),(0.26,0.98),(-0.25,0.68),(-0.56,0.32)])
        case .himalayanVulture:
            return Anatomy(width:25, headWidth:6, headHeight:7, billLength:3.8, neckWidth:2.8, tailWidth:7.4,
                shoulderU:0.6, wingChord:9.1, primaryLength:14.5, wingReach:19, bill:.hooked, tail:.square,
                torso:[(0,0.48),(0.04,0.2),(0.27,0),(0.61,0.01),(0.87,0.14),(1,0.4),(0.99,0.73),(0.8,0.96),(0.48,1),(0.15,0.88),(0.02,0.68)],
                wing:[(-0.57,0.16),(-0.08,-0.08),(0.58,0.02),(1.02,0.5),(0.9,0.65),(1.01,0.73),(0.85,0.8),(0.94,0.91),(0.74,0.9),(0.78,1.06),(0.58,0.98),(0.49,1.1),(0.15,0.98),(-0.3,0.68),(-0.61,0.35)])
        case .commonPheasant:
            return Anatomy(width:16, headWidth:7, headHeight:7, billLength:2.8, neckWidth:4.4, tailWidth:3.8,
                shoulderU:0.43, wingChord:5.8, primaryLength:9.5, wingReach:14.8, bill:.short, tail:.tapered,
                torso:[(0,0.66),(0.13,0.32),(0.4,0.04),(0.72,0),(0.96,0.19),(1,0.49),(0.89,0.78),(0.62,0.96),(0.3,1),(0.08,0.85)],
                wing:[(-0.57,0.08),(-0.04,-0.05),(0.48,0.15),(1,0.86),(0.81,1.03),(0.35,1.06),(-0.2,0.86),(-0.63,0.44)])
        case .greaterCoucal:
            return Anatomy(width:23, headWidth:9, headHeight:8, billLength:3.7, neckWidth:6.2, tailWidth:5.2,
                shoulderU:0.58, wingChord:7.6, primaryLength:12.6, wingReach:16, bill:.arched, tail:.graduated,
                torso:[(0,0.62),(0.12,0.3),(0.38,0.02),(0.69,0),(0.91,0.19),(1,0.48),(0.94,0.79),(0.7,1),(0.37,0.96),(0.1,0.83)],
                wing:[(-0.61,0.09),(-0.07,-0.06),(0.51,0.13),(0.94,0.68),(1,0.99),(0.76,1.08),(0.34,1.01),(-0.22,0.85),(-0.67,0.46)])
        default: return nil
        }
    }

    public struct Pose {
        public let body:(y:Double,height:Double,lean:Double,fluff:Double)
        public let head:(x:Double,y:Double,pitch:Double)
        public let tail:(x:Double,y:Double)
        /// Independent lower-neck bend; the upper bend follows the skull.
        public let neck:(x:Double,y:Double)
        public let wing, shoulder, turn, gape, stance:Double

        fileprivate init(_ body:(Double,Double,Double,Double), _ head:(Double,Double,Double),
                         _ tail:(Double,Double), neck:(Double,Double), wing:Double,
                         shoulder:Double = 0, turn:Double = 0, gape:Double = 0, stance:Double = 0) {
            self.body=body; self.head=head; self.tail=tail; self.neck=neck
            self.wing=wing; self.shoulder=shoulder; self.turn=turn; self.gape=gape; self.stance=stance
        }

        public func bodyPoint(_ u:Double, _ v:Double, anatomy a:Anatomy) -> (Double,Double) {
            (34-a.width-body.fluff/2+(a.width+body.fluff)*u+body.lean*(1-v), body.y+body.height*v)
        }
        public func bodyVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            a.torso.map { bodyPoint($0.0,$0.1,anatomy:a) }
        }
        public func headWidth(anatomy a:Anatomy) -> Double { a.headWidth*(1-abs(turn)*0.1) }
        public func headPoint(_ x:Double, _ y:Double) -> (Double,Double) {
            (head.x+x*cos(head.pitch)-y*sin(head.pitch), head.y+x*sin(head.pitch)+y*cos(head.pitch))
        }

        /// Last vertex is the actual distal tip, including the raptor hook.
        /// Gape articulates only the lower mandible, preserving this endpoint.
        public func billVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let r=headWidth(anatomy:a)/2-0.4, length=a.billLength*(1-abs(turn)*0.05)
            switch a.bill {
            case .short: return [(r,-0.65),(r,1.2),(r+length,0.45)]
            case .hooked:
                return [(r+length-1.1,1.1),(r,1.2),(r,-1.2),
                        (r+length-1.1,-0.9),(r+length,0.2),
                        (r+length-0.1,1.75),(r+length-1.4,3)]
            case .arched:
                return [(r,1.2),(r,-1.1),(r+length*0.5,-1.1),
                        (r+length,0.25),(r+length-0.2,1.6)]
            }
        }
        public func lowerBillVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let r=headWidth(anatomy:a)/2-0.4, length=a.billLength*(1-abs(turn)*0.05)
            return [(r,1),(r+0.2,1.8+gape*1.4),(r+length-0.4,1.5+gape*2.1)]
        }

        public func wingPoint(_ u:Double, _ v:Double, anatomy a:Anatomy, far:Bool = false) -> (Double,Double) {
            let root=bodyPoint(far ? 0.74:a.shoulderU,0.12,anatomy:a)
            let side=far ? 0.62 : -1.0
            return (root.0+side*u*(a.wingChord+wing*a.wingReach)+v*wing*1.4,
                    root.1+v*(a.primaryLength*(1-wing)+7.3*wing)+shoulder*v-u*wing*18)
        }
        public func wingVertices(anatomy a:Anatomy, far:Bool = false) -> [(Double,Double)] {
            a.wing.map { wingPoint($0.0,$0.1,anatomy:a,far:far) }
        }

        public func tailPoint(_ along:Double, _ across:Double, anatomy a:Anatomy) -> (Double,Double) {
            let root=bodyPoint(0.22,0.59,anatomy:a)
            let dx=tail.x-root.0, dy=tail.y-root.1, length=max(1,hypot(dx,dy))
            let distal=a.tail == .tapered ? a.tailWidth*(1-along*0.76) : a.tailWidth
            let width=4*(1-along)+distal*along
            return (root.0+dx*along-dy/length*across*width,
                    root.1+dy*along+dx/length*across*width)
        }
        public func tailVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let form:[(Double,Double)]
            switch a.tail {
            case .rounded: form=[(0,-0.5),(0.9,-0.5),(1,-0.26),(1,0.26),(0.9,0.5),(0,0.5)]
            case .square: form=[(0,-0.5),(1,-0.46),(1,0.46),(0,0.5)]
            case .tapered: form=[(0,-0.5),(0.6,-0.5),(1,0),(0.6,0.5),(0,0.5)]
            case .graduated:
                form=[(0,-0.5),(0.83,-0.5),(0.94,-0.32),(1,-0.12),
                      (1,0.12),(0.94,0.32),(0.83,0.5),(0,0.5)]
            }
            return form.map { tailPoint($0.0,$0.1,anatomy:a) }
        }

        /// Cubic neck center and its true tangent also define feather/neck-ring
        /// sections. A collar cannot drift when the lower neck bends or retracts.
        public func neckCenter(_ t:Double, anatomy a:Anatomy) -> (Double,Double) {
            let p0=bodyPoint(0.77,0.2,anatomy:a), p1=neck
            let p2=headPoint(-a.headWidth*0.43,a.headHeight*0.67)
            let p3=headPoint(0,a.headHeight*0.22), u=1-t
            return (u*u*u*p0.0+3*u*u*t*p1.x+3*u*t*t*p2.0+t*t*t*p3.0,
                    u*u*u*p0.1+3*u*u*t*p1.y+3*u*t*t*p2.1+t*t*t*p3.1)
        }
        public func neckTangent(_ t:Double, anatomy a:Anatomy) -> (Double,Double) {
            let p0=bodyPoint(0.77,0.2,anatomy:a), p1=neck
            let p2=headPoint(-a.headWidth*0.43,a.headHeight*0.67)
            let p3=headPoint(0,a.headHeight*0.22), u=1-t
            let dx=3*u*u*(p1.x-p0.0)+6*u*t*(p2.0-p1.x)+3*t*t*(p3.0-p2.0)
            let dy=3*u*u*(p1.y-p0.1)+6*u*t*(p2.1-p1.y)+3*t*t*(p3.1-p2.1)
            let length=max(0.001,hypot(dx,dy))
            return (dx/length,dy/length)
        }
        public func neckPoint(_ t:Double, _ across:Double, anatomy a:Anatomy) -> (Double,Double) {
            let center=neckCenter(t,anatomy:a), tangent=neckTangent(t,anatomy:a)
            let width=a.neckWidth*(1-t)+a.headWidth*0.32*t
            return (center.0-tangent.1*across*width,center.1+tangent.0*across*width)
        }
        public func neckVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let left=(0...12).map { neckPoint(Double($0)/12,-0.5,anatomy:a) }
            let right=(0...12).reversed().map { neckPoint(Double($0)/12,0.5,anatomy:a) }
            return left+right
        }
        public func ruffPoint(_ across:Double, _ along:Double, anatomy a:Anatomy) -> (Double,Double) {
            let center=neckCenter(0.12,anatomy:a), tangent=neckTangent(0.12,anatomy:a)
            return (center.0-tangent.1*across*5.6+tangent.0*along*2,
                    center.1+tangent.0*across*5.6+tangent.1*along*2)
        }
        public func ruffVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            (0..<24).map { i in
                let angle=Double(i)*Double.pi/12, feather=i%2 == 0 ? 1.0:0.85
                return ruffPoint(cos(angle)*feather,sin(angle)*feather,anatomy:a)
            }
        }
    }

    public static let toePaths:[[(Double,Double)]] = [
        [(25,39),(27,38.5),(29,39)], [(29,39),(31,38.5),(33,39)]
    ]

    public static func beakAnchor(species:SpeciesID, frame:String) -> PoseClip.Anchor? {
        guard let a=anatomy(for:species), let p=pose(species:species,frame:frame),
              let vertex=p.billVertices(anatomy:a).last else { return nil }
        let tip=p.headPoint(vertex.0,vertex.1)
        return PoseClip.Anchor(tip.0,tip.1)
    }

    /// Every species owns fourteen authored joint configurations; no bitmap
    /// input, whole-bird transform, historical pose alias or species substitution.
    public static func pose(species:SpeciesID, frame:String) -> Pose? {
        switch species {
        case .orientalTurtleDove:
            switch frame {
            case "lookNear": return Pose((22.6,13.7,0.4,0.1),(33.4,19.5,0.22),(5.9,40.5),neck:(32.7,25.8),wing:0.03,turn:0.2)
            case "lookFar": return Pose((21.7,14.3,-0.2,0),(32.5,16.1,-0.18),(6.6,41.2),neck:(31.4,22.4),wing:0.05,turn:0.55)
            case "alertRise": return Pose((20.9,15,0.3,0),(33,14.7,-0.15),(7.3,41.9),neck:(32,21.2),wing:0.12)
            case "alertHold": return Pose((20.2,15.6,0.6,-0.2),(33.4,13.5,-0.06),(8,42.5),neck:(32.6,20),wing:0.19,turn:0.15)
            case "alertRelax": return Pose((22.2,14,-0.3,0.5),(32.3,18.2,0.07),(5.8,40.9),neck:(31.3,25),wing:0.06,shoulder:0.3)
            case "restLower": return Pose((24,12.5,-0.5,1.1),(31.5,22.8,0.15),(6.2,39.7),neck:(30.5,27.4),wing:0.01,shoulder:0.4,stance:-0.6)
            case "restTuck": return Pose((24.6,12,-0.9,1.7),(26.9,25.9,2.35),(7,38.9),neck:(28.4,27.8),wing:0.02,shoulder:0.5,turn:0.35,stance:-1)
            case "restWake": return Pose((22.8,13.6,0,0.7),(32,17.7,-0.27),(5.5,40.7),neck:(31.4,24),wing:0.14)
            case "takeoffCrouch": return Pose((25.3,11.4,1.2,0.3),(34.3,24.2,0.15),(5.2,34.8),neck:(33.1,28.1),wing:0.29,stance:-1.4)
            case "takeoffPush": return Pose((19.5,13.5,1.6,0),(34.4,16,-0.23),(5,32.9),neck:(33.8,21.8),wing:0.71,stance:0.6)
            case "turtleShoulderReady": return Pose((22.8,13.4,-0.4,0.4),(31.2,20.8,0.46),(6.5,40.2),neck:(29.7,26.7),wing:0.1,shoulder:0.6,turn:0.3)
            case "turtleShoulderTurn": return Pose((23.4,12.8,-0.8,0.9),(27.4,25.2,2.2),(7.2,39.1),neck:(28.7,28.4),wing:0.23,shoulder:1.1,turn:0.6,stance:-0.3)
            case "turtleShoulderLift": return Pose((21.7,14.1,0.1,0.3),(32.2,16.7,-0.29),(6.8,40.6),neck:(31.4,23),wing:0.12,shoulder:-0.35,turn:0.25)
            case "turtleShoulderSettle": return Pose((22.5,13.8,-0.2,0.5),(32.8,18.6,0.03),(6.1,41),neck:(31.7,24.8),wing:0.04,shoulder:0.2,turn:0.1)
            default: return nil
            }
        case .eurasianCollaredDove:
            switch frame {
            case "lookNear": return Pose((22.4,12.9,0.5,0),(33.6,19.4,0.24),(5.9,41.3),neck:(32.6,25.2),wing:0.04,turn:0.15)
            case "lookFar": return Pose((21.4,13.6,-0.2,0),(32.8,16,-0.19),(6.6,42),neck:(31.7,22),wing:0.05,turn:0.5)
            case "alertRise": return Pose((20.5,14.3,0.3,0),(33.2,14.5,-0.17),(7.3,42.6),neck:(32.2,20.8),wing:0.12)
            case "alertHold": return Pose((19.8,14.9,0.7,-0.2),(33.7,13.3,-0.07),(8,43.1),neck:(32.8,19.6),wing:0.2,turn:0.15)
            case "alertRelax": return Pose((22,13.2,-0.3,0.4),(32.6,18.1,0.08),(5.7,41.7),neck:(31.5,24.3),wing:0.06,shoulder:0.25)
            case "restLower": return Pose((23.9,11.9,-0.5,1),(31.8,22.6,0.16),(6.2,40.5),neck:(30.9,26.8),wing:0.01,shoulder:0.35,stance:-0.6)
            case "restTuck": return Pose((24.5,11.5,-0.9,1.5),(27.2,25.7,2.32),(6.9,39.6),neck:(28.7,27.4),wing:0.02,shoulder:0.4,turn:0.35,stance:-0.9)
            case "restWake": return Pose((22.6,12.8,0,0.6),(32.3,17.6,-0.26),(5.4,41.4),neck:(31.7,23.4),wing:0.13)
            case "takeoffCrouch": return Pose((25.1,10.8,1.3,0.3),(34.5,23.9,0.16),(5.1,34.6),neck:(33.4,27.5),wing:0.3,stance:-1.4)
            case "takeoffPush": return Pose((19.2,12.7,1.7,0),(34.6,15.7,-0.24),(4.9,32.6),neck:(34,21.4),wing:0.72,stance:0.6)
            case "collaredTurnReady": return Pose((21.9,13.3,-0.1,0.2),(32.2,18.9,-0.08),(6.4,41.6),neck:(31,24.8),wing:0.09,shoulder:0.2,turn:-0.55)
            case "collaredTurnEase": return Pose((22.6,12.7,-0.5,0.8),(31.5,20.2,0.17),(7.2,40.6),neck:(30,26.2),wing:0.2,shoulder:1,turn:0.75,stance:-0.2)
            case "collaredTurnReturn": return Pose((21.5,13.8,0.2,0.3),(33,17.2,-0.15),(6.8,41.2),neck:(32,23.1),wing:0.11,shoulder:-0.3,turn:0.35)
            case "collaredTurnSettle": return Pose((22.2,13.1,-0.2,0.4),(33.1,18.7,0.03),(6.2,41.9),neck:(32,24.4),wing:0.04,shoulder:0.15,turn:0.1)
            default: return nil
            }
        case .uplandBuzzard:
            switch frame {
            case "lookNear": return Pose((21.7,15.5,0.4,0.1),(32.6,17.9,0.2),(8.6,39.5),neck:(30.4,23.9),wing:0.03,turn:0.2)
            case "lookFar": return Pose((20.9,16.1,-0.2,0),(31.8,14.7,-0.16),(9.3,40.1),neck:(29.9,21.8),wing:0.05,turn:-0.5)
            case "alertRise": return Pose((20.1,16.8,0.2,0),(32.2,13.3,-0.13),(9.9,40.8),neck:(30.5,20.3),wing:0.1)
            case "alertHold": return Pose((19.5,17.4,0.5,-0.2),(32.7,12.2,-0.05),(10.6,41.4),neck:(31,19.1),wing:0.16,turn:0.15)
            case "alertRelax": return Pose((21.4,15.9,-0.3,0.6),(31.7,16.8,0.07),(8.4,39.8),neck:(29.8,23.3),wing:0.06,shoulder:0.35)
            case "restLower": return Pose((23.1,14.4,-0.5,1.2),(30.9,21.1,0.15),(8.9,38.7),neck:(29.2,26),wing:0.01,shoulder:0.4,stance:-0.5)
            case "restTuck": return Pose((23.8,13.8,-0.9,1.8),(26.3,25.3,2.18),(9.6,37.9),neck:(27.8,28),wing:0.02,shoulder:0.5,turn:0.3,stance:-0.9)
            case "restWake": return Pose((21.9,15.4,-0.1,0.7),(31.4,16.3,-0.23),(8.1,39.6),neck:(29.7,22.8),wing:0.12)
            case "takeoffCrouch": return Pose((24.3,13.1,1,0.4),(33.5,22.4,0.15),(7.8,34.5),neck:(31.8,27),wing:0.27,stance:-1.2)
            case "takeoffPush": return Pose((19.1,15.1,1.4,0),(33.7,14.9,-0.2),(7.5,32.8),neck:(32,21.2),wing:0.64,stance:0.5)
            case "uplandWatchReady": return Pose((21.3,16,-0.2,0.3),(31.2,16,-0.08),(9.1,39.9),neck:(29.2,22.7),wing:0.08,shoulder:0.2,turn:-0.6)
            case "uplandWatchLoosen": return Pose((21.9,15.4,-0.5,1.3),(32,17.3,0.1),(8.5,39.1),neck:(29.6,24),wing:0.23,shoulder:1.2,turn:0.55)
            case "uplandWatchFold": return Pose((20.9,16.5,0.1,0.4),(32.5,15,-0.16),(9.5,39.6),neck:(30.7,21.5),wing:0.12,shoulder:-0.5,turn:0.25)
            case "uplandWatchSettle": return Pose((21.6,15.7,-0.2,0.5),(31.9,16.9,0.03),(8.9,40.1),neck:(30,23.1),wing:0.04,shoulder:0.2,turn:0.1)
            default: return nil
            }
        case .himalayanVulture:
            switch frame {
            case "lookNear": return Pose((21,16.3,0.3,0.2),(33.8,16.6,0.16),(12.5,36.7),neck:(34.6,24.3),wing:0.03,turn:0.15)
            case "lookFar": return Pose((20.3,16.9,-0.2,0.1),(33,13.4,-0.14),(13.1,37.3),neck:(33.5,21.6),wing:0.05,turn:-0.45)
            case "alertRise": return Pose((19.6,17.5,0.2,0),(33.4,12,-0.11),(13.7,37.9),neck:(33.8,20.1),wing:0.1)
            case "alertHold": return Pose((19,18.1,0.5,-0.2),(33.8,10.9,-0.04),(14.3,38.5),neck:(34.2,18.8),wing:0.16,turn:0.15)
            case "alertRelax": return Pose((20.8,16.6,-0.3,0.7),(32.9,15.5,0.06),(12.3,37),neck:(33.3,23.4),wing:0.06,shoulder:0.4)
            case "restLower": return Pose((22.5,15.1,-0.5,1.3),(32.1,20.2,0.14),(12.8,36),neck:(32.8,27),wing:0.01,shoulder:0.5,stance:-0.5)
            case "restTuck": return Pose((23.2,14.6,-0.8,1.9),(27.5,25.1,2.12),(13.5,35.4),neck:(30.2,28.3),wing:0.02,shoulder:0.6,turn:0.3,stance:-0.9)
            case "restWake": return Pose((21.2,16.2,-0.1,0.8),(32.6,15,-0.21),(12,36.8),neck:(33.4,22.7),wing:0.12)
            case "takeoffCrouch": return Pose((23.7,14,0.9,0.5),(34.5,21.7,0.13),(11.7,32.5),neck:(35,27.8),wing:0.25,stance:-1.1)
            case "takeoffPush": return Pose((18.7,15.9,1.3,0.1),(34.6,14,-0.18),(11.4,30.8),neck:(34.6,21.4),wing:0.62,stance:0.4)
            case "vultureGazeReady": return Pose((20.6,16.7,-0.2,0.4),(32.7,14.6,-0.07),(13,37.1),neck:(33.3,22.3),wing:0.08,shoulder:0.2,turn:-0.55)
            case "vultureGazeDraw": return Pose((21.5,15.8,-0.6,1.1),(31.2,19.1,0.14),(12.6,36.2),neck:(31.5,26.5),wing:0.21,shoulder:1.1,turn:0.6,stance:-0.2)
            case "vultureGazeRecover": return Pose((20.1,17.2,0.1,0.4),(33.3,14.1,-0.15),(13.4,36.7),neck:(33.8,21.8),wing:0.11,shoulder:-0.4,turn:0.3)
            case "vultureGazeSettle": return Pose((20.9,16.5,-0.2,0.6),(33.1,15.8,0.02),(12.8,37.4),neck:(33.7,23.6),wing:0.04,shoulder:0.2,turn:0.1)
            default: return nil
            }
        case .commonPheasant:
            switch frame {
            case "lookNear": return Pose((22.8,11.8,0.5,0),(33.7,17.6,0.26),(2.2,44.5),neck:(32.3,24),wing:0.03,turn:0.2)
            case "lookFar": return Pose((21.7,12.5,-0.2,0),(32.9,14.3,-0.2),(2.7,44.8),neck:(31.7,21.4),wing:0.05,turn:0.5)
            case "alertRise": return Pose((20.8,13.2,0.3,0),(33.3,12.9,-0.17),(3.2,45),neck:(32.3,20),wing:0.11)
            case "alertHold": return Pose((20.1,13.8,0.7,-0.2),(33.8,11.7,-0.06),(3.8,45.2),neck:(32.9,18.7),wing:0.18,turn:0.15)
            case "alertRelax": return Pose((22.4,12.1,-0.3,0.5),(32.7,16.3,0.09),(2.1,44.2),neck:(31.5,23.2),wing:0.06,shoulder:0.2)
            case "restLower": return Pose((24.2,11,-0.5,1),(32,21,0.18),(2.5,42.9),neck:(31,26.2),wing:0.01,stance:-0.7)
            case "restTuck": return Pose((24.9,10.6,-0.9,1.5),(27.5,25.3,2.38),(3.2,42),neck:(29.5,27.2),wing:0.02,turn:0.35,stance:-1.1)
            case "restWake": return Pose((23,11.7,0,0.6),(32.4,15.8,-0.29),(2,43.7),neck:(31.6,22.4),wing:0.13)
            case "takeoffCrouch": return Pose((25.5,9.8,1.2,0.3),(34.6,22.6,0.17),(2.2,35.1),neck:(33.3,27.1),wing:0.29,stance:-1.6)
            case "takeoffPush": return Pose((19.5,11.4,1.8,0),(34.7,14.7,-0.24),(2.4,32.8),neck:(33.8,20.7),wing:0.76,stance:0.6)
            case "pheasantPeerReady": return Pose((22.6,12,0.3,0.2),(33,18.6,0.28),(2.8,43.1),neck:(31.6,24.7),wing:0.09,turn:0.65,stance:-0.2)
            case "pheasantPeerLower": return Pose((23.7,11.2,1.3,0.1),(34.9,24.1,0.6),(4.4,39.4),neck:(33.8,28),wing:0.2,turn:0.3,stance:-0.8)
            case "pheasantPeerLift": return Pose((21.8,12.7,0.1,0.4),(32.8,15.2,-0.27),(3.5,41.6),neck:(31.5,22),wing:0.12,turn:0.4)
            case "pheasantPeerSettle": return Pose((22.7,11.9,-0.2,0.4),(33.1,17,0.04),(2.5,44),neck:(31.9,23.6),wing:0.04,turn:0.15)
            default: return nil
            }
        case .greaterCoucal:
            switch frame {
            case "lookNear": return Pose((22,14.6,0.6,0),(32.9,18.8,0.24),(3.3,42.7),neck:(30.8,24.7),wing:0.04,turn:0.2)
            case "lookFar": return Pose((21,15.3,-0.2,0),(32.1,15.4,-0.2),(3.9,43.2),neck:(30.1,22),wing:0.05,turn:0.5)
            case "alertRise": return Pose((20.1,16,0.3,0),(32.5,14,-0.16),(4.5,43.6),neck:(30.7,20.7),wing:0.12)
            case "alertHold": return Pose((19.4,16.7,0.7,-0.2),(33,12.8,-0.06),(5.1,44),neck:(31.3,19.4),wing:0.19,turn:0.15)
            case "alertRelax": return Pose((21.6,14.9,-0.3,0.5),(31.9,17.5,0.08),(3.2,42.5),neck:(29.9,24),wing:0.06,shoulder:0.25)
            case "restLower": return Pose((23.5,13.6,-0.5,1.1),(31.1,22,0.17),(3.6,41.3),neck:(29.5,26.7),wing:0.01,stance:-0.6)
            case "restTuck": return Pose((24.2,13.1,-0.9,1.6),(26.6,25.6,2.3),(4.3,40.4),neck:(28.3,28),wing:0.02,turn:0.35,stance:-1)
            case "restWake": return Pose((22.2,14.5,0,0.6),(31.6,17,-0.28),(3,42.1),neck:(30,23.2),wing:0.13)
            case "takeoffCrouch": return Pose((24.8,12.3,1.3,0.3),(33.8,23.5,0.16),(3.1,34.6),neck:(32.1,27.6),wing:0.3,stance:-1.5)
            case "takeoffPush": return Pose((19,14.2,1.8,0),(34,15.9,-0.23),(3.2,32.4),neck:(32.6,21.7),wing:0.7,stance:0.6)
            case "coucalLiftReady": return Pose((21.8,14.8,0.2,0.2),(32.6,17.6,-0.17),(3.8,42.3),neck:(30.7,23.5),wing:0.09,turn:0.25)
            case "coucalLiftGape": return Pose((20.6,15.7,0.6,0),(33.4,14,-0.4),(4.6,41),neck:(31.8,20.8),wing:0.23,turn:0.1,gape:0.75)
            case "coucalLiftClose": return Pose((21.2,15.2,-0.2,0.5),(32,16.3,-0.12),(4.1,41.8),neck:(30.4,22.7),wing:0.14,turn:0.5,gape:0.2)
            case "coucalLiftSettle": return Pose((21.9,14.7,-0.1,0.4),(32.4,18.1,0.03),(3.6,42.6),neck:(30.5,24.2),wing:0.05,turn:0.15)
            default: return nil
            }
        default: return nil
        }
    }
}
