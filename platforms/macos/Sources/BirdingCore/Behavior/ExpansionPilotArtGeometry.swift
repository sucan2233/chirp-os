import Foundation

/// E0's original, articulated poses in right-facing, top-down logical 48 units.
/// The renderer consumes this geometry directly; bill anchors are actual vertices,
/// not a second table of estimates. The presentation origin remains (29, 39).
public enum ExpansionPilotArtGeometry {
    public static let species: [SpeciesID] = [
        .eurasianGreatTit, .whiteWagtail, .indianWhiteEye,
        .crestedMyna, .eurasianNuthatch, .greatEgret
    ]

    public static func frameNames(for species: SpeciesID) -> [String] {
        Self.species.contains(species) ? PoseClip.frameNames + signatureFrameNames(for: species) : []
    }

    public static func signatureFrameNames(for species: SpeciesID) -> [String] {
        switch species {
        case .eurasianGreatTit: return ["inspectLean", "inspectDown", "inspectLift", "inspectSettle"]
        case .whiteWagtail: return ["tailPoise", "tailLift", "tailFall", "tailSettle"]
        case .indianWhiteEye: return ["gleanReady", "gleanReach", "gleanRecoil", "gleanSettle"]
        case .crestedMyna: return ["peckReady", "peckLower", "peckLift", "peckSettle"]
        case .eurasianNuthatch: return ["sideBrace", "sideReach", "sideProbe", "sideRecover"]
        case .greatEgret: return ["neckPoise", "neckReach", "neckObserve", "neckRecover"]
        default: return []
        }
    }

    public struct Anatomy {
        public let width, headWidth, headHeight, billLength, tailWidth: Double
    }

    public static func anatomy(for species: SpeciesID) -> Anatomy? {
        switch species {
        case .eurasianGreatTit: return Anatomy(width:17, headWidth:9, headHeight:8, billLength:3, tailWidth:7)
        case .whiteWagtail: return Anatomy(width:17, headWidth:7, headHeight:6, billLength:3, tailWidth:5)
        case .indianWhiteEye: return Anatomy(width:15, headWidth:8, headHeight:7, billLength:3, tailWidth:7)
        case .crestedMyna: return Anatomy(width:22, headWidth:9, headHeight:8, billLength:3, tailWidth:7)
        case .eurasianNuthatch: return Anatomy(width:19, headWidth:8, headHeight:6, billLength:5, tailWidth:7)
        case .greatEgret: return Anatomy(width:18, headWidth:7, headHeight:4, billLength:8, tailWidth:7)
        default: return nil
        }
    }

    public struct Pose {
        /// Torso top, height, shoulder lean and feather fullness, independent of feet.
        public let body: (y:Double, height:Double, lean:Double, fluff:Double)
        public let head: (x:Double, y:Double, pitch:Double)
        public let tail: (x:Double, y:Double)
        /// Folded wing opening, separate from head and tail articulation.
        public let wing: Double
        /// Egret's lower neck bend; the upper bend follows the head separately.
        public let neck: (x:Double, y:Double)
        /// Horizontal knee flexion. Both dry-perch toe contacts remain planted.
        public let stance: Double
        /// Only the four nuthatch signatures use the established vertical contact.
        public let side: Bool

        fileprivate init(_ body:(Double,Double,Double,Double), _ head:(Double,Double,Double),
                     _ tail:(Double,Double), _ wing:Double = 0,
                     neck:(Double,Double) = (37,22), stance:Double = 0, side:Bool = false) {
            self.body=body; self.head=head; self.tail=tail; self.wing=wing
            self.neck=neck; self.stance=stance; self.side=side
        }

        public func headPoint(_ x:Double, _ y:Double) -> (Double,Double) {
            (head.x+x*cos(head.pitch)-y*sin(head.pitch),
             head.y+x*sin(head.pitch)+y*cos(head.pitch))
        }

        /// Local bill polygon. Vertex 1 is the physical tip used by beakAnchor.
        public func billVertices(anatomy:Anatomy) -> [(Double,Double)] {
            if side { return [(3,0),(10,3),(3,2)] }
            let root=anatomy.headWidth/2-0.5, y=anatomy.headHeight*0.05
            return [(root,y-0.7),(root+anatomy.billLength,y+0.4),(root,y+1.2)]
        }
    }

    public static func beakAnchor(species:SpeciesID, frame:String) -> PoseClip.Anchor? {
        guard let a=anatomy(for:species), let p=pose(species:species,frame:frame) else { return nil }
        let vertex=p.billVertices(anatomy:a)[1], tip=p.headPoint(vertex.0,vertex.1)
        return PoseClip.Anchor(tip.0,tip.1)
    }

    // Each species has fourteen independently authored rows. These are anatomy
    // parameters, never offsets applied to a finished image or aliases of idle.
    public static func pose(species:SpeciesID, frame:String) -> Pose? {
        switch species {
        case .eurasianGreatTit:
            switch frame {
            case "lookNear": return Pose((22.4,12.7,0.6,0),(33,20.2,0.31),(7.6,40.2),0.02)
            case "lookFar": return Pose((21.2,13.4,-0.1,0),(32.2,16.7,-0.24),(8.3,41.6),0.04)
            case "alertRise": return Pose((20.1,14.1,0.4,0),(32.7,15.1,-0.18),(8.8,42.1),0.13)
            case "alertHold": return Pose((19.3,14.9,0.9,-0.3),(33.1,13.8,-0.08),(9.3,42.6),0.19)
            case "alertRelax": return Pose((21.7,13,-0.3,0.5),(32,18.6,0.07),(7.4,40.5),0.05)
            case "restLower": return Pose((23.8,12.2,-0.5,1.1),(31.2,22.6,0.2),(7.7,39.1),0,stance:-0.4)
            case "restTuck": return Pose((24.5,11.8,-1,1.8),(26.5,25,2.48),(8.6,38.7),0,stance:-0.7)
            case "restWake": return Pose((22.2,13.1,0.1,0.7),(31.7,17.7,-0.32),(7.1,41.2),0.12)
            case "takeoffCrouch": return Pose((25.5,10.6,1.4,0.4),(34,24,0.19),(7,35.7),0.28,stance:-1.6)
            case "takeoffPush": return Pose((18.6,12.8,2,0),(34.1,15.8,-0.27),(6.5,33.9),1,stance:0.6)
            case "inspectLean": return Pose((22.6,12.1,1.2,0),(34,21.6,0.38),(8.8,38.8),0.06,stance:-0.3)
            case "inspectDown": return Pose((23.3,11.6,1.9,0),(35.3,25.2,0.7),(9.4,36.6),0.1,stance:-0.7)
            case "inspectLift": return Pose((21.4,13.1,0.5,0.2),(33.7,17.2,-0.33),(8.5,40.1),0.08)
            case "inspectSettle": return Pose((22.1,12.8,-0.2,0.3),(32.3,18.7,0.12),(7.8,40.7),0.03)
            default: return nil
            }
        case .whiteWagtail:
            switch frame {
            case "lookNear": return Pose((22.6,10.1,0.6,0),(34,20.7,0.25),(1.5,41.2),0.03)
            case "lookFar": return Pose((21.5,10.8,-0.2,0),(33.1,17.4,-0.2),(1.8,43),0.02)
            case "alertRise": return Pose((20.2,12,0.5,0),(33.5,15.9,-0.21),(2.8,38.4),0.12)
            case "alertHold": return Pose((19.5,12.8,0.8,-0.2),(34,14.4,-0.1),(3.8,35.7),0.2)
            case "alertRelax": return Pose((22.1,10.5,-0.3,0.3),(33.2,19.4,0.08),(2,40.8),0.04)
            case "restLower": return Pose((24.3,10.1,-0.6,0.8),(32.1,22.5,0.22),(1.7,43.4),0,stance:-0.6)
            case "restTuck": return Pose((25.1,9.8,-1,1.2),(26.5,25.8,2.55),(2.2,42.2),0,stance:-0.9)
            case "restWake": return Pose((22.3,11,0.2,0.5),(32.8,18,-0.3),(2.5,37.4),0.1)
            case "takeoffCrouch": return Pose((25.6,8.8,1.6,0.2),(34.7,24.3,0.14),(2.2,31.2),0.3,stance:-1.8)
            case "takeoffPush": return Pose((18.9,10.8,2.3,0),(35,16.9,-0.25),(1.8,32.8),1,stance:0.8)
            case "tailPoise": return Pose((22.2,10.2,-0.2,0),(33,19.5,0.09),(2,38.2),0.04,stance:-0.2)
            case "tailLift": return Pose((22.8,9.8,0.8,0),(34.2,20.6,0.22),(4.2,27.3),0.09,stance:-0.8)
            case "tailFall": return Pose((21.7,10.7,0.1,0),(33.6,17.8,-0.21),(2.7,34.5),0.06,stance:0.4)
            case "tailSettle": return Pose((22.3,10.3,-0.4,0.2),(32.8,19.1,-0.03),(1.5,42),0.02)
            default: return nil
            }
        case .indianWhiteEye:
            switch frame {
            case "lookNear": return Pose((22.5,11.1,0.4,0),(33.2,21.1,0.27),(11.7,37.8),0.03)
            case "lookFar": return Pose((21.8,11.7,-0.2,0),(32.7,18,-0.23),(12.2,38.8),0.02)
            case "alertRise": return Pose((20.8,12.5,0.3,0),(33.1,16.4,-0.27),(12.7,39.6),0.1)
            case "alertHold": return Pose((20.1,13.1,0.6,-0.2),(33.4,15.1,-0.12),(13.1,40),0.16)
            case "alertRelax": return Pose((22.3,11.4,-0.3,0.4),(32.4,19.9,0.08),(11.5,38.2),0.04)
            case "restLower": return Pose((24.2,10.9,-0.5,1.1),(31.5,22.8,0.17),(11.9,37.1),0,stance:-0.4)
            case "restTuck": return Pose((24.8,10.8,-0.8,1.7),(27,25.1,2.42),(12.8,36.7),0,stance:-0.6)
            case "restWake": return Pose((22.4,11.8,0,0.6),(32.2,18.4,-0.33),(11.3,38.7),0.09)
            case "takeoffCrouch": return Pose((25.8,9.5,1.1,0.2),(34,24.2,0.16),(11.2,34.4),0.24,stance:-1.2)
            case "takeoffPush": return Pose((19.6,11.2,1.7,0),(34.3,17,-0.29),(10.8,32.9),1,stance:0.5)
            case "gleanReady": return Pose((22,11.6,0.4,0),(33.4,18.2,-0.32),(12.2,38.2),0.05)
            case "gleanReach": return Pose((20.6,12.6,1.2,0),(35,14.6,-0.57),(13.7,39.7),0.14,stance:0.4)
            case "gleanRecoil": return Pose((21.3,12,-0.4,0.5),(31.6,17.2,-0.16),(11.8,39.1),0.11,stance:-0.3)
            case "gleanSettle": return Pose((22.2,11.3,-0.1,0.2),(32.8,19.3,-0.07),(11.6,38.4),0.02)
            default: return nil
            }
        case .crestedMyna:
            switch frame {
            case "lookNear": return Pose((22.6,13.5,0.8,0),(33.2,20.5,0.3),(8.8,38.2),0.03)
            case "lookFar": return Pose((21.1,14.3,-0.1,0),(32.2,16.1,-0.15),(9.3,39.4),0.02)
            case "alertRise": return Pose((19.8,15.5,0.5,0),(32.7,14.5,-0.19),(9.9,40.3),0.11)
            case "alertHold": return Pose((18.9,16.2,1,-0.3),(33.1,13.1,-0.07),(10.5,40.8),0.18)
            case "alertRelax": return Pose((21.8,14,-0.4,0.5),(32,18.2,0.06),(8.7,38.6),0.05)
            case "restLower": return Pose((24.1,12.5,-0.7,1.1),(31,22.3,0.21),(8.6,37.5),0,stance:-0.6)
            case "restTuck": return Pose((24.9,11.8,-1.3,1.7),(25.4,25.1,2.57),(9.6,37),0,stance:-1)
            case "restWake": return Pose((22,14,-0.1,0.7),(31.5,17,-0.29),(8.2,39.3),0.12)
            case "takeoffCrouch": return Pose((26.2,10.4,1.7,0.3),(34.2,24.5,0.17),(8,34.7),0.27,stance:-1.8)
            case "takeoffPush": return Pose((18.1,13.7,2.4,0),(34.7,15.7,-0.25),(7.5,32.6),1,stance:0.8)
            case "peckReady": return Pose((22.9,12.7,1.1,0),(33.8,22.1,0.41),(9.4,36.6),0.05,stance:-0.5)
            case "peckLower": return Pose((24.5,11.3,2,0),(35,29,0.86),(10.6,33.5),0.13,stance:-1.4)
            case "peckLift": return Pose((21.5,14,0.5,0.2),(33.4,17.5,-0.23),(9.7,38),0.09,stance:0.2)
            case "peckSettle": return Pose((22.2,13.8,-0.2,0.3),(32.2,18.6,0.1),(8.9,38.8),0.03)
            default: return nil
            }
        case .eurasianNuthatch:
            switch frame {
            // Base pack is top-only. No side attachment is inferred from species.
            case "lookNear": return Pose((22.3,10.9,0.7,0),(34,21.2,0.25),(11.8,34.7),0.03)
            case "lookFar": return Pose((21.1,11.8,-0.2,0),(32.8,18,-0.17),(12.4,35.9),0.02)
            case "alertRise": return Pose((20.2,12.6,0.4,0),(33.4,16.4,-0.22),(12.9,36.7),0.12)
            case "alertHold": return Pose((19.3,13.4,0.8,-0.3),(33.9,15,-0.09),(13.4,37.2),0.18)
            case "alertRelax": return Pose((21.8,11.5,-0.3,0.4),(32.6,20,0.07),(11.7,35.2),0.04)
            case "restLower": return Pose((24.1,10.6,-0.6,1),(31.5,23.3,0.19),(11.6,34.4),0,stance:-0.5)
            case "restTuck": return Pose((24.7,10.4,-1,1.5),(26.7,25.2,2.6),(12.5,33.8),0,stance:-0.8)
            case "restWake": return Pose((22,11.8,0,0.6),(32.2,18.5,-0.3),(11.1,35.8),0.1)
            case "takeoffCrouch": return Pose((25.7,9.2,1.4,0.2),(34.8,24.4,0.16),(11,31.5),0.28,stance:-1.6)
            case "takeoffPush": return Pose((18.8,11.4,2.1,0),(35,17,-0.27),(10.5,30.1),1,stance:0.7)
            // Side body uses the existing x=29 contact line and head-first stance.
            case "sideBrace": return Pose((19.4,14.8,-0.2,0),(23.6,33.8,-0.08),(17.2,12.6),0.03,side:true)
            case "sideReach": return Pose((19.8,15.1,0.5,0),(25.6,34.1,-0.12),(16.4,13.4),0.09,side:true)
            case "sideProbe": return Pose((20.2,15.2,1,0),(27,34.7,0.08),(16,14.2),0.14,side:true)
            case "sideRecover": return Pose((19.1,14.6,-0.4,0.3),(24.1,33.1,-0.2),(17.8,12.1),0.06,side:true)
            default: return nil
            }
        case .greatEgret:
            switch frame {
            // Long neck and leg flexion have their own rows, never passerine scaling.
            case "lookNear": return Pose((19.6,8.8,0.5,0),(34.5,10.4,0.23),(12.6,27.4),0.02,neck:(38,23),stance:-0.4)
            case "lookFar": return Pose((18.6,9.2,-0.2,0),(33.3,5.8,-0.13),(13.3,27),0.03,neck:(36.5,19.5),stance:0.2)
            case "alertRise": return Pose((18,9.6,0.3,0),(33.7,4.6,-0.1),(13.8,27.4),0.1,neck:(35.8,17.8),stance:0.4)
            case "alertHold": return Pose((17.5,10,0.6,-0.2),(34,3.5,-0.04),(14.2,27.8),0.16,neck:(35,16.5),stance:0.6)
            case "alertRelax": return Pose((19.1,9,-0.3,0.3),(32.8,7.5,0.09),(12.8,27.5),0.04,neck:(37.8,22.2))
            case "restLower": return Pose((21,8.9,-0.5,0.7),(31.4,14,0.27),(12.3,28.9),0,neck:(37,25),stance:-1.2)
            case "restTuck": return Pose((21.8,8.5,-0.8,1),(27.7,20.3,2.38),(12.8,29.2),0,neck:(34.5,27),stance:-1.7)
            case "restWake": return Pose((19.7,9.1,-0.1,0.4),(32.1,10,-0.19),(12,27.8),0.09,neck:(38.2,24),stance:-0.5)
            case "takeoffCrouch": return Pose((23.1,7.9,1.4,0.3),(34.6,16,0.16),(11.5,28.4),0.31,neck:(39,27.5),stance:-2.7)
            case "takeoffPush": return Pose((16.4,9.2,1.9,0),(34.8,8,-0.2),(11.8,24.7),1,neck:(36.5,20),stance:1.1)
            case "neckPoise": return Pose((19.3,8.9,0.1,0),(32.7,9.3,0.06),(13.1,27.7),0.03,neck:(38.6,23.7),stance:-0.3)
            case "neckReach": return Pose((18.8,9.1,0.8,0),(35.3,6.2,-0.18),(13.7,27.1),0.07,neck:(36.2,19.4),stance:0.2)
            case "neckObserve": return Pose((18.5,9.4,1,0),(35.1,8.1,0.12),(13.9,27.5),0.06,neck:(37.3,20.5),stance:0.3)
            case "neckRecover": return Pose((19.5,8.8,-0.2,0.2),(32.4,10.7,-0.03),(12.7,28.1),0.02,neck:(39,24.8),stance:-0.4)
            default: return nil
            }
        default: return nil
        }
    }
}
