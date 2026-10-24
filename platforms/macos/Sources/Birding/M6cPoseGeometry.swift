import Foundation
import CoreGraphics
import BirdingCore

/// Editable, right-facing anatomy for M6c only. Coordinates are top-down logical
/// units, independent of native raster density. No old frame is an input here.
enum M6cPoseGeometry {
    struct Anatomy {
        let width,headWidth,headHeight,wingSpan,tailWidth:Double
    }
    struct Pose {
        let body:(y:Double,height:Double,lean:Double,fluff:Double)
        let head:(x:Double,y:Double,pitch:Double)
        let tail:(x:Double,y:Double)
        let wing,turn:Double

        init(_ body:(Double,Double,Double,Double),_ head:(Double,Double,Double),
             _ tail:(Double,Double),_ wing:Double = 0,turn:Double = 0) {
            self.body=body;self.head=head;self.tail=tail;self.wing=wing;self.turn=turn
        }
        func headPoint(_ x:Double,_ y:Double)->CGPoint {
            CGPoint(x:head.x+x*cos(head.pitch)-y*sin(head.pitch),
                    y:head.y+x*sin(head.pitch)+y*cos(head.pitch))
        }
        func billTip(species:SpeciesID,anatomy a:Anatomy)->CGPoint {
            if species == .littleOwl {
                // OwlFace's projected facial midline, then the short hook tip.
                return headPoint(a.headWidth*0.17*turn+0.3,a.headHeight*(-0.02)+4)
            }
            let length=species == .swinhoesWhiteEye ? 2.2:4.0
            return headPoint(a.headWidth/2-0.5+length,0.5)
        }
    }

    static func anatomy(_ id:SpeciesID)->Anatomy? {
        switch id {
        case .lightVentedBulbul:return Anatomy(width:19,headWidth:8,headHeight:7,wingSpan:17,tailWidth:4)
        case .redWhiskeredBulbul:return Anatomy(width:17,headWidth:7.5,headHeight:7,wingSpan:17.5,tailWidth:4)
        case .chineseBlackbird:return Anatomy(width:21,headWidth:8,headHeight:7,wingSpan:19,tailWidth:5)
        case .magpieRobin:return Anatomy(width:17,headWidth:8,headHeight:7,wingSpan:17,tailWidth:4)
        case .swinhoesWhiteEye:return Anatomy(width:15,headWidth:8.5,headHeight:8,wingSpan:14,tailWidth:3.5)
        case .azureWingedMagpie:return Anatomy(width:17,headWidth:7.5,headHeight:7,wingSpan:19,tailWidth:4)
        case .redBilledLeiothrix:return Anatomy(width:17,headWidth:8,headHeight:7,wingSpan:15.5,tailWidth:4)
        case .littleOwl:return Anatomy(width:22,headWidth:19,headHeight:12,wingSpan:19,tailWidth:6)
        default:return nil
        }
    }

    // Body: top Y, height, horizontal lean, added feather width.
    // Head: centre X/Y, clockwise pitch. Tail: terminal X/Y.
    // Every key pose has its own authored row; recovery is not a renamed stand.
    static func pose(species id:SpeciesID,frame:String)->Pose? {
        switch id {
        case .lightVentedBulbul:
            switch frame {
            case "lookNear":return Pose((22.5,12,0.5,0),(33.5,20.5,0.28),(7,40))
            case "lookFar":return Pose((21.5,12.5,0,0),(32.5,16.5,-0.18),(6.5,41))
            case "alertRise":return Pose((20.5,13.5,0.3,0),(33,15,-0.22),(7.5,42),0.10)
            case "alertHold":return Pose((19.5,14.5,0.6,-0.4),(33.5,13.5,-0.12),(8,42.5),0.16)
            case "alertRelax":return Pose((22,12.5,-0.3,0.5),(32,18.5,0.03),(6,40.5))
            case "restLower":return Pose((24,12,-0.7,1.2),(31,22.5,0.18),(6,39.5))
            case "restTuck":return Pose((24.5,12,-1,1.7),(26,25,2.54),(7,39))
            case "restWake":return Pose((22.5,12.5,0,0.8),(31.5,17.5,-0.28),(5.5,41),0.10)
            case "takeoffCrouch":return Pose((25.5,10.5,1.4,0.4),(34,24,0.16),(5.5,36),0.24)
            case "takeoffPush":return Pose((18.5,12.5,2,0),(34.5,16,-0.24),(5,34.5),1)
            case "peekLower":return Pose((23.5,11.5,1.0,0),(34,24,0.35),(6,37.5))
            case "peekLook":return Pose((24.5,10.5,1.7,0),(35.5,28,0.72),(5.5,35))
            case "peekRecover":return Pose((22,12.5,-0.2,0.2),(32,20,-0.10),(6.5,39.5))
            default:return nil
            }
        case .redWhiskeredBulbul:
            switch frame {
            case "lookNear":return Pose((22.5,12.5,0.6,0),(33.2,20.5,0.26),(6,41))
            case "lookFar":return Pose((21.5,13,0,0),(32,16.8,-0.16),(5.5,42))
            case "alertRise":return Pose((20,14,0.4,0),(32.5,14.5,-0.18),(7,42.5),0.12)
            case "alertHold":return Pose((19,15,0.8,-0.5),(33,13,-0.08),(7.5,43),0.18)
            case "alertRelax":return Pose((22,13,-0.4,0.5),(31.5,18.5,0.05),(5,41))
            case "restLower":return Pose((24,12,-0.6,1.0),(30.5,22,0.20),(5,40))
            case "restTuck":return Pose((24.5,12,-1,1.6),(26.5,25,2.38),(6,39.5))
            case "restWake":return Pose((22,13,0,0.7),(31,17.8,-0.26),(4.5,42),0.08)
            case "takeoffCrouch":return Pose((26,10,1.5,0.2),(34,24.5,0.14),(4.5,36.5),0.26)
            case "takeoffPush":return Pose((18.5,12,2.2,0),(34.5,16.5,-0.22),(4,34),1)
            default:return nil
            }
        case .chineseBlackbird:
            switch frame {
            case "lookNear":return Pose((22.5,13,0.8,0),(34,21.5,0.32),(7,40))
            case "lookFar":return Pose((21,14,0.2,0),(33,17,-0.14),(6.5,41))
            case "alertRise":return Pose((19.5,15,0.5,0),(33.5,15,-0.20),(8,42),0.08)
            case "alertHold":return Pose((18.5,16,1,-0.4),(34,13.5,-0.10),(8.5,42.5),0.14)
            case "alertRelax":return Pose((22,13.5,-0.3,0.6),(32.5,19.5,0.04),(6,40))
            case "restLower":return Pose((24,12.5,-0.8,1.3),(31.5,23.5,0.22),(5.5,39.5))
            case "restTuck":return Pose((25,11.5,-1.5,1.8),(25.5,25.5,2.62),(6.5,39))
            case "restWake":return Pose((22,13.5,-0.2,0.8),(32,18,-0.30),(5,41),0.10)
            case "takeoffCrouch":return Pose((26.5,10,1.6,0.3),(35,25,0.12),(5,35.5),0.22)
            case "takeoffPush":return Pose((18,13,2.5,0),(35.5,16,-0.26),(4.5,33),1)
            default:return nil
            }
        case .magpieRobin:
            switch frame {
            case "lookNear":return Pose((22.5,12,0.5,0),(33.5,20.5,0.30),(7,34))
            case "lookFar":return Pose((21.5,12.5,0,0),(32.5,16.5,-0.20),(6,39))
            case "alertRise":return Pose((20,14,0.4,0),(33,15,-0.24),(8,31),0.12)
            case "alertHold":return Pose((19,15,0.8,-0.4),(33.5,13.5,-0.12),(9,28),0.18)
            case "alertRelax":return Pose((22,12.5,-0.3,0.4),(32,19,0.03),(6,37.5))
            case "restLower":return Pose((24,12,-0.6,1),(31,23,0.18),(5.5,41))
            case "restTuck":return Pose((24.5,12,-1,1.5),(26.5,25,2.52),(6.5,40.5))
            case "restWake":return Pose((22.5,12.5,0,0.7),(31.5,17.5,-0.28),(6,34),0.10)
            case "takeoffCrouch":return Pose((26,10,1.5,0.2),(34.5,24.5,0.14),(5,29),0.28)
            case "takeoffPush":return Pose((18.5,12,2.2,0),(35,16,-0.24),(4.5,32),1)
            case "peekLower":return Pose((23.5,11.5,0.9,0),(34,23.5,0.30),(7,29))
            case "peekLook":return Pose((24.5,10.5,1.5,0),(36,27,0.62),(7.5,25))
            case "peekRecover":return Pose((22,12.5,-0.2,0.2),(32,19,-0.15),(6.5,33))
            default:return nil
            }
        case .swinhoesWhiteEye:
            switch frame {
            case "lookNear":return Pose((23,11.5,0.3,0),(33,22,0.24),(12,38))
            case "lookFar":return Pose((22,12,0,0),(32,18.5,-0.22),(11.5,39))
            case "alertRise":return Pose((21,13,0.2,0),(32.5,17,-0.26),(12.5,40),0.10)
            case "alertHold":return Pose((20,14,0.5,-0.3),(33,15.5,-0.14),(13,40.5),0.15)
            case "alertRelax":return Pose((22.5,12,-0.3,0.5),(31.5,20,0.04),(11,38.5))
            case "restLower":return Pose((24.5,11.5,-0.5,1.4),(31,23.5,0.14),(11,38))
            case "restTuck":return Pose((25,11.5,-0.8,2),(27,25.5,2.46),(12,37))
            case "restWake":return Pose((23,12,-0.1,1),(31.5,19,-0.32),(10.5,39),0.08)
            case "takeoffCrouch":return Pose((26.5,10,1.2,0.3),(34,25,0.18),(10,35),0.22)
            case "takeoffPush":return Pose((20,11.5,1.8,0),(34.5,17.5,-0.28),(9.5,33),1)
            default:return nil
            }
        case .azureWingedMagpie:
            switch frame {
            case "lookNear":return Pose((22.5,11,0.6,0),(33.5,21,0.28),(2.5,43))
            case "lookFar":return Pose((21,12,0,0),(32.5,17,-0.16),(2,44))
            case "alertRise":return Pose((20,13,0.4,0),(33,15.5,-0.22),(3,44.5),0.08)
            case "alertHold":return Pose((19,14,0.9,-0.4),(33.5,13.5,-0.10),(3.5,45),0.14)
            case "alertRelax":return Pose((22,11.5,-0.4,0.5),(32,19.5,0.05),(2,42.5))
            case "restLower":return Pose((24,11,-0.7,0.9),(31,23,0.20),(2,43))
            case "restTuck":return Pose((24.5,11,-1.2,1.5),(26,25,2.64),(2.5,42))
            case "restWake":return Pose((22,12,0,0.7),(31.5,18,-0.28),(1.8,43.5),0.08)
            case "takeoffCrouch":return Pose((26,9,1.5,0.2),(34.5,24.5,0.14),(2,35),0.24)
            case "takeoffPush":return Pose((18,11.5,2.3,0),(35,16.5,-0.24),(1.8,32.5),1)
            default:return nil
            }
        case .redBilledLeiothrix:
            switch frame {
            case "lookNear":return Pose((23,11.5,0.4,0),(33,21.5,0.26),(9,39))
            case "lookFar":return Pose((22,12,0,0),(32,17.5,-0.18),(8.5,40))
            case "alertRise":return Pose((21,13,0.3,0),(32.5,16,-0.22),(9.5,41),0.12)
            case "alertHold":return Pose((20,14,0.6,-0.3),(33,14.5,-0.12),(10,41.5),0.18)
            case "alertRelax":return Pose((22.5,12,-0.3,0.5),(31.5,19.5,0.05),(8,39.5))
            case "restLower":return Pose((24.5,11.5,-0.5,1.1),(30.5,23,0.18),(8,39))
            case "restTuck":return Pose((25,11.5,-0.9,1.7),(26,25.5,2.50),(9,38.5))
            case "restWake":return Pose((23,12,0,0.8),(31,18,-0.30),(7.5,40),0.12)
            case "takeoffCrouch":return Pose((26,10.5,1.3,0.3),(34,24.5,0.16),(7,35.5),0.26)
            case "takeoffPush":return Pose((19.5,12,2,0),(34.5,16.5,-0.26),(6.5,33.5),1)
            default:return nil
            }
        case .littleOwl:
            switch frame {
            case "lookNear":return Pose((22,14,0.3,0),(28.5,20,0.16),(17,36),turn:0.15)
            case "lookFar":return Pose((20.5,15,0,0),(28,17,-0.10),(16.5,36.5),turn:0.42)
            case "alertRise":return Pose((19,16.5,0.2,0),(28.5,15.5,-0.08),(17.5,37),0.10,turn:0.22)
            case "alertHold":return Pose((18,17.5,0.5,-0.4),(29,14,-0.04),(18,37),0.16,turn:0.28)
            case "alertRelax":return Pose((21.5,14.5,-0.3,0.7),(27.5,19,0.05),(16,36),turn:0.08)
            case "restLower":return Pose((24,12.5,-0.5,1.5),(27.5,23,0.12),(16,36.5),turn:-0.10)
            case "restTuck":return Pose((24.5,12,-0.8,2),(26,24.5,0.22),(16.5,36),turn:-0.95)
            case "restWake":return Pose((22.5,13.5,0,1),(28,18.5,-0.15),(15.5,36.5),0.08,turn:0.32)
            case "takeoffCrouch":return Pose((26,10.5,1,0.8),(29,24,0.12),(15.5,34),0.24,turn:0.45)
            case "takeoffPush":return Pose((18.5,13,1.5,0),(30,16,-0.14),(15,32),1,turn:0.55)
            default:return nil
            }
        default:return nil
        }
    }
}
