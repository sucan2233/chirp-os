import Foundation

/// E1 original part geometry, facing right on the established 48-unit canvas.
/// These presentation assets confer no behavior, food or habitat permissions.
public enum ExpansionSmallArtGeometry {
    public static let species: [SpeciesID] = [
        .marshTit, .greenBackedTit, .blackThroatedBushtit, .silverThroatedBushtit,
        .whiskeredYuhina, .daurianRedstart, .blueFrontedRedstart, .blackRedstart,
        .commonTailorbird, .greyCappedGreenfinch, .twite, .ornateSunbird
    ]

    public static func frameNames(for species: SpeciesID) -> [String] {
        Self.species.contains(species) ? PoseClip.frameNames + signatureFrameNames(for: species) : []
    }

    /// Frozen order: preparation, emphasis, recovery, settled pause.
    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        switch species {
        case .marshTit: return ["marshReady", "marshDip", "marshReturn", "marshSettle"]
        case .greenBackedTit: return ["greenInspectReady", "greenInspectReach", "greenInspectLift", "greenInspectSettle"]
        case .blackThroatedBushtit: return ["chestnutReady", "chestnutReach", "chestnutRecoil", "chestnutSettle"]
        case .silverThroatedBushtit: return ["silverReady", "silverPeer", "silverReturn", "silverSettle"]
        case .whiskeredYuhina: return ["whiskerReady", "whiskerLift", "whiskerReturn", "whiskerSettle"]
        case .daurianRedstart: return ["daurianReady", "daurianTailLift", "daurianTailFall", "daurianSettle"]
        case .blueFrontedRedstart: return ["blueFrontReady", "blueFrontTailLift", "blueFrontReturn", "blueFrontSettle"]
        case .blackRedstart: return ["rufousReady", "rufousTailLift", "rufousReturn", "rufousSettle"]
        case .commonTailorbird: return ["tailorReady", "tailorTailFan", "tailorTailFold", "tailorSettle"]
        case .greyCappedGreenfinch: return ["greenfinchReady", "greenfinchBillFlex", "greenfinchLift", "greenfinchSettle"]
        case .twite: return ["twiteReady", "twiteBillFlex", "twiteReturn", "twiteSettle"]
        case .ornateSunbird: return ["sunbirdReady", "sunbirdReach", "sunbirdRecoil", "sunbirdSettle"]
        default: return []
        }
    }

    public enum BillShape: Equatable { case fine, conical, curved }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, tailWidth: Double
        public let wingReach, primaryLength, wingChord: Double
        public let bill: BillShape
        /// Local contours describe each species' keel and folded primary shape.
        public let torso, wing: [(Double, Double)]
    }

    public static func anatomy(for species: SpeciesID) -> Anatomy? {
        switch species {
        case .marshTit:
            return Anatomy(width:16, headWidth:9, headHeight:8, billLength:2.7, tailWidth:4.2,
                wingReach:12.5, primaryLength:10, wingChord:5.1, bill:.fine,
                torso:[(0,0.51),(0.08,0.24),(0.32,0.02),(0.61,0),(0.86,0.17),(1,0.44),(0.95,0.74),(0.74,0.97),(0.42,1),(0.15,0.86)],
                wing:[(-0.54,0.08),(0.02,-0.04),(0.55,0.22),(1,0.87),(0.79,1.03),(0.38,1.02),(-0.26,0.83),(-0.62,0.44)])
        case .greenBackedTit:
            return Anatomy(width:16, headWidth:9, headHeight:8, billLength:3, tailWidth:4.5,
                wingReach:13.4, primaryLength:10.5, wingChord:5.4, bill:.fine,
                torso:[(0,0.56),(0.11,0.25),(0.37,0.01),(0.66,0),(0.9,0.21),(1,0.5),(0.92,0.82),(0.68,1),(0.35,0.97),(0.12,0.8)],
                wing:[(-0.62,0.04),(-0.08,-0.06),(0.51,0.17),(1,0.97),(0.75,1.06),(0.28,0.95),(-0.18,0.79),(-0.65,0.41)])
        case .blackThroatedBushtit:
            return Anatomy(width:14, headWidth:9, headHeight:8, billLength:2.1, tailWidth:3.1,
                wingReach:11, primaryLength:8.3, wingChord:4.4, bill:.fine,
                torso:[(0,0.47),(0.06,0.22),(0.29,0.02),(0.58,0),(0.86,0.14),(1,0.42),(0.98,0.71),(0.79,0.95),(0.46,1),(0.15,0.85),(0.02,0.67)],
                wing:[(-0.62,0.12),(-0.09,-0.02),(0.47,0.2),(1,0.82),(0.85,1.02),(0.39,1.08),(-0.21,0.9),(-0.66,0.53)])
        case .silverThroatedBushtit:
            return Anatomy(width:14, headWidth:9, headHeight:8, billLength:2.3, tailWidth:3.3,
                wingReach:11.8, primaryLength:9, wingChord:4.6, bill:.fine,
                torso:[(0,0.53),(0.05,0.26),(0.26,0.05),(0.55,0),(0.82,0.09),(0.99,0.35),(1,0.67),(0.83,0.92),(0.52,1),(0.22,0.92),(0.04,0.75)],
                wing:[(-0.56,0.05),(0.04,-0.05),(0.62,0.25),(1,0.94),(0.76,1.09),(0.33,1.04),(-0.18,0.87),(-0.62,0.4)])
        case .whiskeredYuhina:
            return Anatomy(width:16, headWidth:8, headHeight:8, billLength:2.9, tailWidth:4.1,
                wingReach:12.8, primaryLength:9.4, wingChord:5, bill:.fine,
                torso:[(0,0.58),(0.12,0.29),(0.39,0.02),(0.68,0),(0.9,0.19),(1,0.47),(0.93,0.78),(0.71,0.98),(0.38,1),(0.11,0.79)],
                wing:[(-0.65,0.09),(-0.06,-0.09),(0.58,0.15),(1,0.94),(0.8,1.02),(0.5,0.94),(0.04,0.87),(-0.66,0.47)])
        case .daurianRedstart:
            return Anatomy(width:16, headWidth:8, headHeight:7, billLength:2.8, tailWidth:4.4,
                wingReach:13.1, primaryLength:10, wingChord:5.2, bill:.fine,
                torso:[(0,0.57),(0.13,0.25),(0.38,0.02),(0.65,0),(0.89,0.18),(1,0.45),(0.94,0.75),(0.73,0.98),(0.43,1),(0.15,0.83)],
                wing:[(-0.6,0.06),(-0.02,-0.08),(0.53,0.19),(1,1),(0.78,1.04),(0.41,0.98),(-0.13,0.8),(-0.64,0.39)])
        case .blueFrontedRedstart:
            return Anatomy(width:17, headWidth:8, headHeight:7, billLength:3.1, tailWidth:5,
                wingReach:14, primaryLength:10.7, wingChord:5.3, bill:.fine,
                torso:[(0,0.6),(0.1,0.31),(0.39,0.03),(0.69,0),(0.93,0.2),(1,0.49),(0.91,0.8),(0.67,1),(0.34,0.96),(0.1,0.8)],
                wing:[(-0.61,0.03),(-0.08,-0.1),(0.5,0.15),(1,1.04),(0.8,1.07),(0.49,0.91),(-0.03,0.82),(-0.65,0.4)])
        case .blackRedstart:
            return Anatomy(width:18, headWidth:8, headHeight:7, billLength:3, tailWidth:4.7,
                wingReach:13.7, primaryLength:11, wingChord:5.6, bill:.fine,
                torso:[(0,0.54),(0.07,0.25),(0.33,0.02),(0.64,0),(0.89,0.16),(1,0.43),(0.96,0.75),(0.77,0.96),(0.45,1),(0.16,0.86),(0.03,0.7)],
                wing:[(-0.67,0.1),(-0.13,-0.04),(0.5,0.21),(1,0.96),(0.8,1.08),(0.36,1.03),(-0.19,0.85),(-0.7,0.5)])
        case .commonTailorbird:
            return Anatomy(width:15, headWidth:7, headHeight:6, billLength:3.4, tailWidth:3.3,
                wingReach:11.9, primaryLength:8.7, wingChord:4.7, bill:.fine,
                torso:[(0,0.61),(0.14,0.3),(0.43,0.02),(0.7,0),(0.93,0.24),(1,0.53),(0.89,0.82),(0.61,1),(0.3,0.94),(0.09,0.79)],
                wing:[(-0.53,0.04),(0.03,-0.07),(0.53,0.12),(1,0.98),(0.72,1.04),(0.31,0.92),(-0.2,0.79),(-0.59,0.37)])
        case .greyCappedGreenfinch:
            return Anatomy(width:18, headWidth:9, headHeight:8, billLength:3.9, tailWidth:5.3,
                wingReach:13.3, primaryLength:10.1, wingChord:5.7, bill:.conical,
                torso:[(0,0.48),(0.07,0.2),(0.32,0),(0.66,0.01),(0.91,0.2),(1,0.49),(0.95,0.78),(0.76,0.98),(0.44,1),(0.16,0.88),(0.03,0.69)],
                wing:[(-0.72,0.08),(-0.14,-0.06),(0.56,0.17),(1,0.88),(0.79,1.07),(0.31,1.06),(-0.25,0.83),(-0.75,0.46)])
        case .twite:
            return Anatomy(width:17, headWidth:8, headHeight:7, billLength:3.2, tailWidth:4.4,
                wingReach:12.6, primaryLength:9.8, wingChord:5, bill:.conical,
                torso:[(0,0.55),(0.09,0.26),(0.34,0.03),(0.64,0),(0.9,0.19),(1,0.48),(0.94,0.79),(0.7,1),(0.38,0.98),(0.12,0.81)],
                wing:[(-0.62,0.06),(-0.07,-0.05),(0.52,0.2),(1,0.99),(0.77,1.06),(0.31,0.97),(-0.18,0.83),(-0.66,0.43)])
        case .ornateSunbird:
            return Anatomy(width:14, headWidth:7, headHeight:6, billLength:6, tailWidth:3.6,
                wingReach:11.7, primaryLength:8.2, wingChord:4.3, bill:.curved,
                torso:[(0,0.58),(0.14,0.28),(0.43,0.01),(0.7,0),(0.93,0.22),(1,0.51),(0.9,0.81),(0.64,1),(0.3,0.94),(0.08,0.77)],
                wing:[(-0.55,0.04),(0.02,-0.09),(0.51,0.17),(1,0.92),(0.75,1.03),(0.34,0.94),(-0.14,0.8),(-0.59,0.4)])
        default: return nil
        }
    }

    public struct Pose {
        public let body: (y:Double, height:Double, lean:Double, fluff:Double)
        public let head: (x:Double, y:Double, pitch:Double)
        public let tail: (x:Double, y:Double)
        public let wing, spread, turn, gape, stance: Double

        fileprivate init(_ body:(Double,Double,Double,Double), _ head:(Double,Double,Double),
                         _ tail:(Double,Double), wing:Double, spread:Double = 0,
                         turn:Double = 0, gape:Double = 0, stance:Double = 0) {
            self.body=body; self.head=head; self.tail=tail
            self.wing=wing; self.spread=spread; self.turn=turn; self.gape=gape; self.stance=stance
        }

        public func bodyPoint(_ u:Double, _ v:Double, anatomy a:Anatomy) -> (Double,Double) {
            (34-a.width-body.fluff/2+(a.width+body.fluff)*u+body.lean*(1-v), body.y+body.height*v)
        }

        public func bodyVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            a.torso.map { bodyPoint($0.0,$0.1,anatomy:a) }
        }

        public func headWidth(anatomy a:Anatomy) -> Double { a.headWidth*(1-turn*0.1) }

        public func headPoint(_ x:Double, _ y:Double) -> (Double,Double) {
            (head.x+x*cos(head.pitch)-y*sin(head.pitch), head.y+x*sin(head.pitch)+y*cos(head.pitch))
        }

        /// Curved bills are a filled ribbon. Vertex 1 is its distal tip,
        /// including the downward curve; it is never a straight-bill estimate.
        public func billVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let r=headWidth(anatomy:a)/2-0.35, length=a.billLength*(1-turn*0.06)
            switch a.bill {
            case .fine: return [(r,-0.55),(r+length,0.55),(r+0.3,1.15)]
            case .conical: return [(r-0.2,-1.3),(r+length,0.45),(r,1.85)]
            case .curved:
                return [(r+length-0.55,2.1),(r+length,3.9),
                        (r+length-0.9,2.65),(r+length*0.6,1.1),
                        (r,0.75),(r,-0.35),(r+length*0.4,-0.2),
                        (r+length*0.78,0.85)]
            }
        }

        public func lowerBillVertices(anatomy a:Anatomy) -> [(Double,Double)] {
            let r=headWidth(anatomy:a)/2-0.35
            let length=a.billLength*(1-turn*0.06)
            return [(r,0.9),(r+length-0.35,0.85+gape*1.9),(r+0.15,1.7+gape*1.4)]
        }

        /// Shoulder, wrist and primaries articulate separately from the torso.
        public func wingPoint(_ u:Double, _ v:Double, anatomy a:Anatomy, far:Bool = false) -> (Double,Double) {
            let root=bodyPoint(far ? 0.61:0.41,0.13,anatomy:a)
            let side=far ? 0.48 : -1.0
            return (root.0+side*u*(a.wingChord+a.wingReach*wing)+v*wing*2,
                    root.1+v*(a.primaryLength*(1-wing)+5.2*wing)-u*wing*14)
        }

        public func wingVertices(anatomy a:Anatomy, far:Bool = false) -> [(Double,Double)] {
            a.wing.map { wingPoint($0.0,$0.1,anatomy:a,far:far) }
        }

        /// Tail pigment uses the same longitudinal/cross-feather coordinates as
        /// its contour. Edges and inverted-T bars stay attached during tail lifts.
        public func tailPoint(_ along:Double, _ across:Double, anatomy a:Anatomy) -> (Double,Double) {
            let root=bodyPoint(0.24,0.59,anatomy:a)
            let dx=tail.x-root.0, dy=tail.y-root.1, length=max(1,hypot(dx,dy))
            let width=3.5*(1-along)+(a.tailWidth+spread*3.8)*along
            return (root.0+dx*along-dy/length*across*width,
                    root.1+dy*along+dx/length*across*width)
        }

        public func tailVertices(species:SpeciesID, anatomy a:Anatomy) -> [(Double,Double)] {
            let form:[(Double,Double)]
            switch species {
            case .greyCappedGreenfinch, .twite:
                form=[(0,-0.5),(1,-0.5),(0.83,0),(1,0.5),(0,0.5)]
            case .blackThroatedBushtit:
                form=[(0,-0.5),(0.95,-0.5),(1,-0.18),(1,0.18),(0.95,0.5),(0,0.5)]
            case .silverThroatedBushtit:
                form=[(0,-0.5),(1,-0.47),(0.99,0.47),(0,0.5)]
            case .commonTailorbird:
                form=[(0,-0.5),(0.88,-0.5),(1,-0.15),(1,0.15),(0.88,0.5),(0,0.5)]
            default:
                form=[(0,-0.5),(0.97,-0.5),(1,-0.22),(1,0.32),(0.96,0.5),(0,0.5)]
            }
            return form.map { tailPoint($0.0,$0.1,anatomy:a) }
        }
    }

    public static let toePaths: [[(Double,Double)]] = [
        [(25,39),(27,38.5),(29,39)], [(29,39),(31,38.5),(33,39)]
    ]

    public static func beakAnchor(species:SpeciesID, frame:String) -> PoseClip.Anchor? {
        guard let a=anatomy(for:species), let p=pose(species:species,frame:frame) else { return nil }
        let vertex=p.billVertices(anatomy:a)[1], tip=p.headPoint(vertex.0,vertex.1)
        return PoseClip.Anchor(tip.0,tip.1)
    }

    /// Fourteen authored joint configurations per bird. No row transforms an
    /// existing raster, aliases an idle, or derives another bird's finished pose.
    public static func pose(species:SpeciesID, frame:String) -> Pose? {
        switch species {
        case .marshTit:
            switch frame {
            case "lookNear": return Pose((22.8,12.6,0.4,0.1),(32.8,21.2,0.33),(10.3,39.4),wing:0.03,turn:0.15)
            case "lookFar": return Pose((21.4,13.2,-0.2,0),(31.9,17.4,-0.27),(10.9,40.2),wing:0.05,turn:0.6)
            case "alertRise": return Pose((20.6,13.7,0.3,0),(32.3,15.8,-0.21),(11.6,40.9),wing:0.12)
            case "alertHold": return Pose((19.7,14.6,0.6,-0.2),(32.8,14.5,-0.1),(12.2,41.8),wing:0.19,turn:0.2)
            case "alertRelax": return Pose((22.1,12.9,-0.4,0.5),(31.7,19.7,0.09),(10.2,40),wing:0.06,turn:0.25)
            case "restLower": return Pose((24.3,11.6,-0.5,1.2),(31,24.2,0.22),(10.5,38.2),wing:0.01,stance:-0.6)
            case "restTuck": return Pose((25,11.1,-0.9,1.9),(27.2,26.1,2.39),(11.2,37.4),wing:0.02,turn:0.4,stance:-1)
            case "restWake": return Pose((22.9,12.4,0.1,0.8),(31.5,18.7,-0.34),(9.8,39.1),wing:0.15)
            case "takeoffCrouch": return Pose((25.8,10.5,1.2,0.4),(33.6,25,0.2),(9.5,34.4),wing:0.3,stance:-1.4)
            case "takeoffPush": return Pose((19,12.1,1.8,0),(33.9,16.9,-0.26),(9.1,32.3),wing:0.86,stance:0.5)
            case "marshReady": return Pose((22.6,12.7,0.2,0.4),(31.9,20.6,0.19),(11,39.1),wing:0.08,turn:0.65)
            case "marshDip": return Pose((23.7,11.8,1.5,0.2),(34.2,25.4,0.68),(11.8,36.2),wing:0.16,turn:0.2,stance:-0.8)
            case "marshReturn": return Pose((22,12.8,-0.7,1),(30.8,20.1,-0.2),(10.7,38.5),wing:0.11,turn:0.4,stance:-0.3)
            case "marshSettle": return Pose((23.1,12.1,-0.2,0.7),(32.2,20.8,0.03),(10.4,39.6),wing:0.04,turn:0.15)
            default: return nil
            }
        case .greenBackedTit:
            switch frame {
            case "lookNear": return Pose((22.4,12.9,0.7,0),(33.1,20.5,0.29),(8.4,40.6),wing:0.04,turn:0.1)
            case "lookFar": return Pose((21.1,13.5,-0.1,0),(32.2,16.8,-0.22),(9.1,41.4),wing:0.03,turn:0.5)
            case "alertRise": return Pose((20,14.3,0.4,-0.1),(32.7,15.3,-0.2),(9.8,42),wing:0.14)
            case "alertHold": return Pose((19.2,15,0.8,-0.2),(33.3,13.9,-0.08),(10.4,42.7),wing:0.22,turn:0.2)
            case "alertRelax": return Pose((21.8,13.2,-0.3,0.4),(32,18.8,0.11),(8.2,40.9),wing:0.07)
            case "restLower": return Pose((23.9,12,-0.6,1.1),(31.3,23.3,0.18),(8.7,39.8),wing:0.01,stance:-0.5)
            case "restTuck": return Pose((24.7,11.5,-1,1.7),(26.9,25.7,2.46),(9.5,38.8),wing:0.02,turn:0.35,stance:-0.9)
            case "restWake": return Pose((22.5,12.7,0.1,0.6),(31.9,18,-0.29),(7.9,41.2),wing:0.13)
            case "takeoffCrouch": return Pose((25.3,10.9,1.4,0.3),(34,24.3,0.17),(7.6,34.9),wing:0.33,stance:-1.5)
            case "takeoffPush": return Pose((18.6,12.6,2,0),(34.2,16.3,-0.25),(7.2,32.8),wing:0.9,stance:0.7)
            case "greenInspectReady": return Pose((22.3,12.6,0.6,0.2),(33.3,21.7,0.36),(9,39.5),wing:0.1,turn:0.3,stance:-0.2)
            case "greenInspectReach": return Pose((23.1,11.9,1.8,0),(35,23.1,0.42),(9.8,37.4),wing:0.18,turn:0.15,stance:-0.5)
            case "greenInspectLift": return Pose((20.8,13.8,0.5,0.2),(33.4,16.2,-0.44),(9.2,40.5),wing:0.12,turn:0.45)
            case "greenInspectSettle": return Pose((22,13.1,-0.2,0.3),(32.5,19.5,0.04),(8.5,41.2),wing:0.05,turn:0.2)
            default: return nil
            }
        case .blackThroatedBushtit:
            switch frame {
            case "lookNear": return Pose((22.9,11.7,0.4,0.2),(32.6,21.4,0.3),(5.3,41.9),wing:0.04,turn:0.2)
            case "lookFar": return Pose((21.8,12.4,-0.2,0.1),(31.8,17.7,-0.26),(5.9,42.5),wing:0.06,turn:0.5)
            case "alertRise": return Pose((20.8,13.1,0.3,0),(32.2,16,-0.23),(6.5,43),wing:0.13)
            case "alertHold": return Pose((20,13.9,0.6,-0.2),(32.7,14.7,-0.12),(7.1,43.5),wing:0.2,turn:0.2)
            case "alertRelax": return Pose((22.4,12,-0.3,0.6),(31.6,19.8,0.08),(5.1,42.2),wing:0.07,turn:0.3)
            case "restLower": return Pose((24.4,11.2,-0.5,1.2),(30.9,24,0.2),(5.5,41),wing:0.01,stance:-0.5)
            case "restTuck": return Pose((25,10.8,-0.9,1.8),(27.7,26.3,2.36),(6.3,40.3),wing:0.02,turn:0.4,stance:-0.9)
            case "restWake": return Pose((23,11.9,0,0.7),(31.5,18.8,-0.32),(4.9,42.7),wing:0.14)
            case "takeoffCrouch": return Pose((25.7,9.8,1.1,0.4),(33.5,25,0.18),(4.6,35.8),wing:0.29,stance:-1.3)
            case "takeoffPush": return Pose((19.4,11.5,1.6,0),(33.7,17,-0.28),(4.2,33.2),wing:0.84,stance:0.5)
            case "chestnutReady": return Pose((22.1,12.1,0.3,0.2),(32.3,18.5,-0.33),(5.8,42),wing:0.09,turn:0.25)
            case "chestnutReach": return Pose((20.4,13.3,0.9,0),(33.8,15,-0.65),(7,43.2),wing:0.26,turn:0.1,stance:0.3)
            case "chestnutRecoil": return Pose((21.5,12.5,-0.4,0.8),(31.1,18.3,-0.13),(6.3,39.2),wing:0.16,turn:0.65,stance:-0.2)
            case "chestnutSettle": return Pose((22.6,11.9,-0.1,0.4),(32,20.2,0.03),(5.6,41.6),wing:0.05,turn:0.2)
            default: return nil
            }
        case .silverThroatedBushtit:
            switch frame {
            case "lookNear": return Pose((23.1,11.5,0.5,0.3),(32.7,21.7,0.27),(3.2,43.6),wing:0.03,turn:0.25)
            case "lookFar": return Pose((22,12.2,-0.2,0.1),(31.9,17.9,-0.22),(3.8,44),wing:0.05,turn:0.6)
            case "alertRise": return Pose((21.1,13,0.2,0),(32.4,16.3,-0.19),(4.4,44.4),wing:0.11)
            case "alertHold": return Pose((20.3,13.7,0.6,-0.2),(32.8,14.9,-0.07),(5,44.8),wing:0.18,turn:0.2)
            case "alertRelax": return Pose((22.7,11.8,-0.4,0.7),(31.7,20.1,0.08),(3.1,43.7),wing:0.06,turn:0.3)
            case "restLower": return Pose((24.6,10.9,-0.6,1.4),(31,24.3,0.18),(3.4,42.4),wing:0.01,stance:-0.6)
            case "restTuck": return Pose((25.3,10.5,-1,2),(27.8,26.5,2.4),(4.1,41.7),wing:0.02,turn:0.35,stance:-1)
            case "restWake": return Pose((23.2,11.7,0,0.8),(31.6,19,-0.28),(3,43.2),wing:0.12)
            case "takeoffCrouch": return Pose((25.9,9.6,1.2,0.5),(33.7,25.2,0.16),(3.2,35.2),wing:0.28,stance:-1.4)
            case "takeoffPush": return Pose((19.6,11.2,1.7,0.1),(33.8,17.3,-0.23),(3.1,32.9),wing:0.83,stance:0.5)
            case "silverReady": return Pose((22.6,12,0.2,0.6),(31.8,20.7,0.12),(3.7,43.4),wing:0.08,turn:0.65)
            case "silverPeer": return Pose((21.4,12.9,0.8,0.2),(34,17,-0.4),(4.8,42.2),wing:0.23,turn:0.8,stance:0.2)
            case "silverReturn": return Pose((22.1,12.3,-0.5,0.8),(31.2,19.4,-0.08),(4.1,39.5),wing:0.15,turn:0.4)
            case "silverSettle": return Pose((22.9,11.8,-0.2,0.5),(32.2,20.5,0.04),(3.5,43.1),wing:0.04,turn:0.2)
            default: return nil
            }
        case .whiskeredYuhina:
            switch frame {
            case "lookNear": return Pose((22.5,12.1,0.6,0),(33.1,20.8,0.29),(9.3,39.1),wing:0.04,turn:0.2)
            case "lookFar": return Pose((21.4,12.8,-0.1,0),(32.3,17,-0.24),(10,40),wing:0.05,turn:0.5)
            case "alertRise": return Pose((20.3,13.5,0.4,0),(32.8,15.5,-0.2),(10.6,40.7),wing:0.12)
            case "alertHold": return Pose((19.5,14.2,0.7,-0.2),(33.2,14.2,-0.1),(11.3,41.4),wing:0.2,turn:0.15)
            case "alertRelax": return Pose((22,12.4,-0.3,0.5),(32.1,19.1,0.09),(9.1,39.5),wing:0.06)
            case "restLower": return Pose((24,11.5,-0.5,1.1),(31.4,23.6,0.2),(9.5,38.3),wing:0.01,stance:-0.5)
            case "restTuck": return Pose((24.8,11,-0.9,1.6),(27.4,25.8,2.45),(10.3,37.6),wing:0.02,turn:0.35,stance:-0.9)
            case "restWake": return Pose((22.6,12,0,0.6),(32,18.3,-0.31),(8.8,39.8),wing:0.13)
            case "takeoffCrouch": return Pose((25.5,10.1,1.3,0.3),(34.1,24.5,0.18),(8.5,34.1),wing:0.31,stance:-1.4)
            case "takeoffPush": return Pose((18.9,11.9,1.9,0),(34.3,16.6,-0.26),(8.1,32.2),wing:0.87,stance:0.6)
            case "whiskerReady": return Pose((21.9,12.5,0.3,0.2),(32.7,18.5,-0.28),(9.9,39.2),wing:0.09,turn:0.3)
            case "whiskerLift": return Pose((20.2,13.6,0.9,0),(34,14.6,-0.59),(11,40.5),wing:0.27,turn:0.15,stance:0.3)
            case "whiskerReturn": return Pose((21.3,12.9,-0.6,0.8),(31.3,18.2,-0.13),(9.4,39.9),wing:0.16,turn:0.7,stance:-0.2)
            case "whiskerSettle": return Pose((22.3,12.3,-0.1,0.4),(32.5,19.8,0.03),(9.6,39.4),wing:0.05,turn:0.2)
            default: return nil
            }
        case .daurianRedstart:
            switch frame {
            case "lookNear": return Pose((22.7,11.8,0.6,0),(33.3,21.1,0.26),(7.5,41.6),wing:0.03)
            case "lookFar": return Pose((21.5,12.5,-0.2,0),(32.4,17.5,-0.23),(8.2,42.3),wing:0.05,turn:0.45)
            case "alertRise": return Pose((20.4,13.2,0.4,0),(32.9,15.8,-0.19),(8.9,42.9),wing:0.12)
            case "alertHold": return Pose((19.6,13.9,0.8,-0.2),(33.4,14.5,-0.08),(9.5,43.5),wing:0.2,turn:0.15)
            case "alertRelax": return Pose((22.2,12.1,-0.3,0.5),(32.2,19.6,0.08),(7.3,41.9),wing:0.06)
            case "restLower": return Pose((24.1,11.1,-0.6,1.1),(31.5,23.8,0.2),(7.8,40.8),wing:0.01,stance:-0.5)
            case "restTuck": return Pose((24.8,10.7,-1,1.6),(27.1,26,2.48),(8.6,39.8),wing:0.02,turn:0.3,stance:-0.9)
            case "restWake": return Pose((22.8,11.7,0,0.6),(32.1,18.6,-0.3),(7,41.5),wing:0.13)
            case "takeoffCrouch": return Pose((25.4,9.9,1.4,0.3),(34.3,24.7,0.17),(6.7,34.5),wing:0.31,stance:-1.5)
            case "takeoffPush": return Pose((18.8,11.6,1.9,0),(34.5,16.6,-0.25),(6.4,32.5),wing:0.89,stance:0.6)
            case "daurianReady": return Pose((22.4,12,0.2,0.2),(32.7,20.3,0.07),(8.2,38.1),wing:0.08,spread:0.15)
            case "daurianTailLift": return Pose((22,12.4,0.8,0),(33.5,19.3,-0.09),(9.5,29.6),wing:0.19,spread:0.4,stance:-0.3)
            case "daurianTailFall": return Pose((21.6,12.6,-0.2,0.4),(32,18.7,-0.23),(8.6,35.9),wing:0.12,spread:0.22,turn:0.6)
            case "daurianSettle": return Pose((22.6,11.9,-0.1,0.3),(32.8,20.4,0.03),(7.7,41.2),wing:0.04,spread:0.04,turn:0.15)
            default: return nil
            }
        case .blueFrontedRedstart:
            switch frame {
            case "lookNear": return Pose((22.4,12.2,0.7,0),(33.4,20.8,0.28),(6.5,41.5),wing:0.04,turn:0.15)
            case "lookFar": return Pose((21.3,12.9,-0.1,0),(32.5,17.2,-0.21),(7.2,42.2),wing:0.06,turn:0.4)
            case "alertRise": return Pose((20.2,13.6,0.5,-0.1),(33,15.5,-0.17),(7.9,42.8),wing:0.14)
            case "alertHold": return Pose((19.4,14.3,0.9,-0.2),(33.5,14.2,-0.07),(8.6,43.4),wing:0.22,turn:0.2)
            case "alertRelax": return Pose((21.9,12.5,-0.4,0.5),(32.3,19.3,0.1),(6.3,41.8),wing:0.07)
            case "restLower": return Pose((23.8,11.5,-0.6,1),(31.6,23.5,0.19),(6.8,40.6),wing:0.01,stance:-0.6)
            case "restTuck": return Pose((24.6,11.1,-1,1.6),(26.8,25.8,2.51),(7.6,39.7),wing:0.02,turn:0.3,stance:-1)
            case "restWake": return Pose((22.5,12.1,0,0.6),(32.2,18.3,-0.29),(6,41.3),wing:0.15)
            case "takeoffCrouch": return Pose((25.2,10.3,1.5,0.3),(34.4,24.4,0.16),(5.7,34),wing:0.34,stance:-1.5)
            case "takeoffPush": return Pose((18.6,12,2,0),(34.6,16.3,-0.24),(5.4,31.9),wing:0.91,stance:0.7)
            case "blueFrontReady": return Pose((22.2,12.4,0.3,0.2),(32.9,20,0.05),(7.4,37.8),wing:0.1,spread:0.18,turn:0.2)
            case "blueFrontTailLift": return Pose((21.6,13,0.9,0),(33.8,18.7,-0.11),(8.9,27.8),wing:0.24,spread:0.55,turn:0.7,stance:-0.2)
            case "blueFrontReturn": return Pose((22,12.6,-0.3,0.5),(31.9,19,-0.19),(7.8,34.1),wing:0.14,spread:0.3,turn:0.45)
            case "blueFrontSettle": return Pose((22.5,12,-0.1,0.4),(33,20.2,0.02),(6.7,41.1),wing:0.05,spread:0.06,turn:0.15)
            default: return nil
            }
        case .blackRedstart:
            switch frame {
            case "lookNear": return Pose((22.1,13,0.6,0),(33.1,20.2,0.27),(6.5,41.4),wing:0.04)
            case "lookFar": return Pose((20.9,13.7,-0.2,0),(32.2,16.5,-0.22),(7.2,42.1),wing:0.05,turn:0.4)
            case "alertRise": return Pose((19.8,14.4,0.4,0),(32.7,14.9,-0.18),(7.9,42.7),wing:0.13)
            case "alertHold": return Pose((19,15.1,0.8,-0.2),(33.2,13.6,-0.08),(8.5,43.3),wing:0.21,turn:0.2)
            case "alertRelax": return Pose((21.6,13.3,-0.4,0.5),(32,18.6,0.08),(6.3,41.7),wing:0.06)
            case "restLower": return Pose((23.6,12.3,-0.6,1.1),(31.3,22.9,0.2),(6.8,40.5),wing:0.01,stance:-0.6)
            case "restTuck": return Pose((24.4,11.8,-1,1.7),(26.5,25.6,2.47),(7.6,39.6),wing:0.02,turn:0.35,stance:-1)
            case "restWake": return Pose((22.2,12.9,0,0.6),(31.9,17.7,-0.3),(6,41.2),wing:0.14)
            case "takeoffCrouch": return Pose((25,11,1.4,0.4),(34.1,23.9,0.18),(5.7,33.9),wing:0.32,stance:-1.6)
            case "takeoffPush": return Pose((18.2,12.7,1.9,0),(34.3,15.7,-0.26),(5.4,31.8),wing:0.9,stance:0.7)
            case "rufousReady": return Pose((21.9,13.2,0.2,0.2),(32.5,19.3,0.06),(7.2,37.6),wing:0.09,spread:0.12)
            case "rufousTailLift": return Pose((22.3,12.6,1,0.1),(33.6,20.6,0.2),(8.7,28.9),wing:0.2,spread:0.31,stance:-0.4)
            case "rufousReturn": return Pose((22.7,12.1,1.3,0.3),(34.3,22.6,0.37),(7.7,35.3),wing:0.15,spread:0.17,turn:0.3,stance:-0.6)
            case "rufousSettle": return Pose((22,13.1,-0.2,0.4),(32.6,19.5,0.03),(6.7,41),wing:0.05,spread:0.03,turn:0.15)
            default: return nil
            }
        case .commonTailorbird:
            switch frame {
            case "lookNear": return Pose((23,10.8,0.6,0),(33.7,21.4,0.25),(5.6,42.1),wing:0.04,turn:0.1)
            case "lookFar": return Pose((21.9,11.5,-0.2,0),(32.9,18,-0.24),(6.2,42.8),wing:0.05,turn:0.5)
            case "alertRise": return Pose((20.9,12.2,0.3,0),(33.3,16.5,-0.23),(6.8,43.3),wing:0.12)
            case "alertHold": return Pose((20.1,12.9,0.7,-0.2),(33.8,15.2,-0.11),(7.4,43.8),wing:0.19,turn:0.15)
            case "alertRelax": return Pose((22.5,11.1,-0.3,0.4),(32.7,20,0.09),(5.4,42.4),wing:0.06)
            case "restLower": return Pose((24.4,10.2,-0.5,1),(32,24,0.19),(5.8,41.3),wing:0.01,stance:-0.5)
            case "restTuck": return Pose((25.1,9.9,-0.9,1.5),(27.8,26.2,2.5),(6.5,40.4),wing:0.02,turn:0.3,stance:-0.9)
            case "restWake": return Pose((23.1,10.7,0,0.6),(32.5,19.1,-0.32),(5.1,42),wing:0.13)
            case "takeoffCrouch": return Pose((25.8,9,1.2,0.3),(34.6,25,0.16),(4.8,33.6),wing:0.29,stance:-1.3)
            case "takeoffPush": return Pose((19.6,10.5,1.8,0),(34.7,17.6,-0.28),(4.5,31.7),wing:0.85,stance:0.5)
            case "tailorReady": return Pose((22.7,11,0.2,0.2),(33,20.4,0.06),(6.8,35.9),wing:0.09,spread:0.17)
            case "tailorTailFan": return Pose((23.4,10.4,0.9,0),(33.9,21.2,0.2),(8,22.8),wing:0.23,spread:0.8,turn:0.6,stance:-0.4)
            case "tailorTailFold": return Pose((22.2,11.6,-0.3,0.5),(32.3,18.8,-0.18),(6.9,30.7),wing:0.15,spread:0.37,turn:0.35)
            case "tailorSettle": return Pose((22.9,10.9,-0.1,0.3),(33.2,20.8,0.03),(5.9,41.7),wing:0.05,spread:0.05,turn:0.15)
            default: return nil
            }
        case .greyCappedGreenfinch:
            switch frame {
            case "lookNear": return Pose((22,13,0.5,0.1),(32.7,20.7,0.28),(9.4,39.2),wing:0.03,turn:0.15)
            case "lookFar": return Pose((20.8,13.8,-0.2,0),(31.9,16.8,-0.2),(10.1,40),wing:0.05,turn:0.45)
            case "alertRise": return Pose((19.7,14.6,0.3,0),(32.3,15.1,-0.17),(10.8,40.6),wing:0.11)
            case "alertHold": return Pose((18.9,15.3,0.7,-0.2),(32.8,13.8,-0.07),(11.4,41.3),wing:0.18,turn:0.2)
            case "alertRelax": return Pose((21.5,13.4,-0.4,0.6),(31.7,18.9,0.09),(9.2,39.6),wing:0.06)
            case "restLower": return Pose((23.5,12.3,-0.6,1.2),(31,23.2,0.2),(9.7,38.4),wing:0.01,stance:-0.6)
            case "restTuck": return Pose((24.2,11.9,-1,1.8),(26.3,25.8,2.42),(10.5,37.7),wing:0.02,turn:0.35,stance:-1)
            case "restWake": return Pose((22.1,13,0,0.7),(31.5,18,-0.3),(8.9,39.4),wing:0.12)
            case "takeoffCrouch": return Pose((24.9,11,1.2,0.4),(33.7,24.4,0.17),(8.6,33.9),wing:0.3,stance:-1.5)
            case "takeoffPush": return Pose((18.1,12.8,1.8,0),(33.8,16,-0.24),(8.2,32),wing:0.87,stance:0.6)
            case "greenfinchReady": return Pose((22.6,12.6,0.6,0.4),(32.9,22.2,0.42),(10.1,38.6),wing:0.09,turn:0.2,stance:-0.3)
            case "greenfinchBillFlex": return Pose((23.2,12,1,0.2),(33.5,24.2,0.58),(10.9,36.7),wing:0.17,gape:0.85,stance:-0.6)
            case "greenfinchLift": return Pose((21,13.6,0.1,0.4),(31.8,17.4,-0.26),(9.8,39.1),wing:0.13,turn:0.6,gape:0.2)
            case "greenfinchSettle": return Pose((21.8,13.2,-0.2,0.5),(32.3,19.7,0.03),(9.6,39.8),wing:0.04,turn:0.15)
            default: return nil
            }
        case .twite:
            switch frame {
            case "lookNear": return Pose((22.6,11.9,0.6,0),(33.2,21.2,0.3),(7.6,40.7),wing:0.04,turn:0.2)
            case "lookFar": return Pose((21.4,12.6,-0.2,0),(32.4,17.5,-0.23),(8.3,41.4),wing:0.05,turn:0.5)
            case "alertRise": return Pose((20.3,13.4,0.4,0),(32.8,15.9,-0.19),(9,42),wing:0.12)
            case "alertHold": return Pose((19.5,14.1,0.7,-0.2),(33.3,14.6,-0.08),(9.7,42.7),wing:0.19,turn:0.15)
            case "alertRelax": return Pose((22.1,12.2,-0.4,0.5),(32.2,19.6,0.09),(7.4,41),wing:0.06)
            case "restLower": return Pose((24.1,11.2,-0.5,1.1),(31.5,23.8,0.2),(7.9,39.8),wing:0.01,stance:-0.6)
            case "restTuck": return Pose((24.8,10.8,-0.9,1.6),(27,26,2.43),(8.7,39),wing:0.02,turn:0.35,stance:-1)
            case "restWake": return Pose((22.7,11.8,0,0.7),(32,18.7,-0.31),(7.1,40.8),wing:0.13)
            case "takeoffCrouch": return Pose((25.5,10,1.3,0.3),(34.2,24.9,0.18),(6.8,34),wing:0.31,stance:-1.4)
            case "takeoffPush": return Pose((18.9,11.7,1.8,0),(34.4,16.7,-0.25),(6.4,32.1),wing:0.88,stance:0.6)
            case "twiteReady": return Pose((23.1,11.6,0.5,0.3),(33.3,22.9,0.4),(8.2,39.5),wing:0.09,turn:0.25,stance:-0.2)
            case "twiteBillFlex": return Pose((23.8,11.1,0.9,0.2),(33.9,24.7,0.55),(9,37.6),wing:0.18,turn:0.15,gape:0.7,stance:-0.5)
            case "twiteReturn": return Pose((21.6,12.7,-0.3,0.5),(31.9,18.5,-0.17),(8,40.2),wing:0.12,turn:0.8,gape:0.15)
            case "twiteSettle": return Pose((22.4,12.1,-0.1,0.4),(32.7,20.3,0.04),(7.8,41.1),wing:0.05,turn:0.2)
            default: return nil
            }
        case .ornateSunbird:
            switch frame {
            case "lookNear": return Pose((23,10.7,0.5,0),(32.4,21.5,0.2),(11.4,37.9),wing:0.04,turn:0.15)
            case "lookFar": return Pose((21.9,11.4,-0.2,0),(31.6,18,-0.29),(12,38.7),wing:0.05,turn:0.45)
            case "alertRise": return Pose((20.9,12.1,0.3,0),(32,16.4,-0.25),(12.6,39.3),wing:0.12)
            case "alertHold": return Pose((20.1,12.8,0.6,-0.2),(32.5,15.1,-0.14),(13.2,39.9),wing:0.19,turn:0.2)
            case "alertRelax": return Pose((22.5,11,-0.3,0.5),(31.4,19.9,0.06),(11.2,38.2),wing:0.06)
            case "restLower": return Pose((24.4,10.1,-0.5,1),(30.7,24,0.17),(11.6,37.1),wing:0.01,stance:-0.5)
            case "restTuck": return Pose((25.1,9.8,-0.9,1.5),(27.6,26.3,2.35),(12.3,36.4),wing:0.02,turn:0.3,stance:-0.9)
            case "restWake": return Pose((23.1,10.6,0,0.6),(31.3,19,-0.36),(10.9,38),wing:0.13)
            case "takeoffCrouch": return Pose((25.8,8.9,1.2,0.3),(33.3,25,0.14),(10.6,33),wing:0.29,stance:-1.3)
            case "takeoffPush": return Pose((19.6,10.4,1.7,0),(33.5,17.4,-0.32),(10.2,31.1),wing:0.85,stance:0.5)
            case "sunbirdReady": return Pose((22.4,11.1,0.3,0.2),(32,19.5,-0.32),(12,37.7),wing:0.09,turn:0.2)
            case "sunbirdReach": return Pose((20.5,12.3,1,0),(33.5,15.3,-0.72),(13.5,39),wing:0.28,turn:0.1,stance:0.3)
            case "sunbirdRecoil": return Pose((21.6,11.6,-0.5,0.7),(30.8,18.7,-0.24),(11.5,38.4),wing:0.17,turn:0.6,stance:-0.2)
            case "sunbirdSettle": return Pose((22.8,10.9,-0.1,0.4),(31.9,20.7,-0.06),(11.7,38.1),wing:0.05,turn:0.15)
            default: return nil
            }
        default: return nil
        }
    }
}
