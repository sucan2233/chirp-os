import Foundation

/// Generated from M6cPoseGeometry.pose and the renderer's actual bill vertices.
/// Right-facing, top-down 48-unit coordinates, before raster rounding.
/// Passerines rotate (headWidth/2 - 0.5 + billLength, 0.5) around the head;
/// littleOwl rotates (headWidth*0.17*turn + 0.3, 4 - headHeight*0.02).
/// Mirroring belongs to PoseClip.Anchor; unsupported pairs return nil.
enum M6cPoseAnchors {
    static func anchor(species:SpeciesID,frame:String)->PoseClip.Anchor? {
        switch species {
        case .lightVentedBulbul:
            switch frame {
            case "lookNear":return PoseClip.Anchor(40.569737963049,23.053195083386)
            case "lookFar":return PoseClip.Anchor(39.968342482624,15.649200045700)
            case "alertRise":return PoseClip.Anchor(40.428345681520,13.851226551559)
            case "alertHold":return PoseClip.Anchor(41.005920872548,13.098562763260)
            case "alertRelax":return PoseClip.Anchor(39.481627503016,19.224741268393)
            case "restLower":return PoseClip.Anchor(38.289312909198,24.334643647088)
            case "restTuck":return PoseClip.Anchor(19.533757219696,28.832454084027)
            case "restWake":return PoseClip.Anchor(38.846093611613,15.907860354925)
            case "takeoffCrouch":return PoseClip.Anchor(41.324545522010,25.688500191295)
            case "takeoffPush":return PoseClip.Anchor(41.903886124604,14.702899289223)
            case "peekLower":return PoseClip.Anchor(40.873846442628,27.041419912340)
            case "peekLook":return PoseClip.Anchor(40.808850632571,33.321287904356)
            case "peekRecover":return PoseClip.Anchor(39.512447947909,19.748751457788)
            default:return nil
            }
        case .redWhiskeredBulbul:
            switch frame {
            case "lookNear":return PoseClip.Anchor(40.077787065529,22.847028990285)
            case "lookFar":return PoseClip.Anchor(39.237056907780,16.138556643735)
            case "alertRise":return PoseClip.Anchor(39.722381559427,13.693957439057)
            case "alertHold":return PoseClip.Anchor(40.266769717679,12.919019321875)
            case "alertRelax":return PoseClip.Anchor(38.715949803228,19.361724107410)
            case "restLower":return PoseClip.Anchor(37.506148023951,23.930385937185)
            case "restTuck":return PoseClip.Anchor(20.907862887628,29.641174691437)
            case "restWake":return PoseClip.Anchor(38.134867617421,16.419360987849)
            case "takeoffCrouch":return PoseClip.Anchor(41.109294415220,26.006795579277)
            case "takeoffPush":return PoseClip.Anchor(41.684371319187,15.405783957329)
            default:return nil
            }
        case .chineseBlackbird:
            switch frame {
            case "lookNear":return PoseClip.Anchor(40.961982355310,24.333866913662)
            case "lookFar":return PoseClip.Anchor(40.496391528917,16.448534638275)
            case "alertRise":return PoseClip.Anchor(40.949833999207,14.000013307958)
            case "alertHold":return PoseClip.Anchor(41.512447947909,13.248751457788)
            case "alertRelax":return PoseClip.Anchor(39.974006132864,20.299520059730)
            case "restLower":return PoseClip.Anchor(38.710116058439,25.624670897772)
            case "restTuck":return PoseClip.Anchor(18.748168767951,28.803448957366)
            case "restWake":return PoseClip.Anchor(39.312783771773,16.261266694603)
            case "takeoffCrouch":return PoseClip.Anchor(42.386208665260,26.394245872594)
            case "takeoffPush":return PoseClip.Anchor(42.876465111955,14.555090849876)
            default:return nil
            }
        case .magpieRobin:
            switch frame {
            case "lookNear":return PoseClip.Anchor(40.517263565111,23.194069794523)
            case "lookFar":return PoseClip.Anchor(39.949833999207,15.500013307958)
            case "alertRise":return PoseClip.Anchor(40.403886124604,13.702899289223)
            case "alertHold":return PoseClip.Anchor(41.005920872548,13.098562763260)
            case "alertRelax":return PoseClip.Anchor(39.481627503016,19.724741268393)
            case "restLower":return PoseClip.Anchor(38.289312909198,24.834643647088)
            case "restTuck":return PoseClip.Anchor(20.111694396989,28.961003852881)
            case "restWake":return PoseClip.Anchor(38.846093611613,15.907860354925)
            case "takeoffCrouch":return PoseClip.Anchor(41.856848414273,26.041681357938)
            case "takeoffPush":return PoseClip.Anchor(42.403886124604,14.702899289223)
            case "peekLower":return PoseClip.Anchor(41.017263565111,26.194069794523)
            case "peekLook":return PoseClip.Anchor(41.813570844700,31.764702932361)
            case "peekRecover":return PoseClip.Anchor(39.490502150757,18.373599545416)
            default:return nil
            }
        case .swinhoesWhiteEye:
            switch frame {
            case "lookNear":return PoseClip.Anchor(38.660609637156,23.899999614667)
            case "lookFar":return PoseClip.Anchor(37.915704635058,17.689482467334)
            case "alertRise":return PoseClip.Anchor(38.378560645846,15.953565705309)
            case "alertHold":return PoseClip.Anchor(38.961556734787,15.164826465973)
            case "alertRelax":return PoseClip.Anchor(37.425245967540,20.737536591741)
            case "restLower":return PoseClip.Anchor(36.822013620143,24.825389530240)
            case "restTuck":return PoseClip.Anchor(22.064391497979,28.860397106709)
            case "restWake":return PoseClip.Anchor(37.305234017899,17.602946673375)
            case "takeoffCrouch":return PoseClip.Anchor(39.764355185376,26.557147808278)
            case "takeoffPush":return PoseClip.Anchor(40.356457682231,16.336211610199)
            default:return nil
            }
        case .azureWingedMagpie:
            switch frame {
            case "lookNear":return PoseClip.Anchor(40.329474103471,23.484106171245)
            case "lookFar":return PoseClip.Anchor(39.737056907780,16.338556643735)
            case "alertRise":return PoseClip.Anchor(40.184371319187,14.405783957329)
            case "alertHold":return PoseClip.Anchor(40.763696906589,13.273709811950)
            case "alertRelax":return PoseClip.Anchor(39.215949803228,20.361724107410)
            case "restLower":return PoseClip.Anchor(38.006148023951,24.930385937185)
            case "restTuck":return PoseClip.Anchor(19.402658987147,28.047555013471)
            case "restWake":return PoseClip.Anchor(38.605829752035,16.476949267066)
            case "takeoffCrouch":return PoseClip.Anchor(41.609294415220,26.006795579277)
            case "takeoffPush":return PoseClip.Anchor(42.161051630891,15.262324945829)
            default:return nil
            }
        case .redBilledLeiothrix:
            switch frame {
            case "lookNear":return PoseClip.Anchor(40.119384560063,23.911299128258)
            case "lookFar":return PoseClip.Anchor(39.468342482624,16.649200045700)
            case "alertRise":return PoseClip.Anchor(39.928345681520,14.851226551559)
            case "alertHold":return PoseClip.Anchor(40.505920872548,14.098562763260)
            case "alertRelax":return PoseClip.Anchor(38.965637368327,20.374218899728)
            case "restLower":return PoseClip.Anchor(37.789312909198,24.834643647088)
            case "restTuck":return PoseClip.Anchor(19.692186811346,29.587969273006)
            case "restWake":return PoseClip.Anchor(38.312783771773,16.261266694603)
            case "takeoffCrouch":return PoseClip.Anchor(41.324545522010,26.188500191295)
            case "takeoffPush":return PoseClip.Anchor(41.876465111955,15.055090849876)
            default:return nil
            }
        case .littleOwl:
            switch frame {
            case "lookNear":return PoseClip.Anchor(28.675443346939,23.836959718581)
            case "lookFar":return PoseClip.Anchor(30.023697546792,20.575831623428)
            case "alertRise":return PoseClip.Anchor(29.807847053714,19.167212625973)
            case "alertHold":return PoseClip.Anchor(30.353796505004,17.708829246951)
            case "alertRelax":return PoseClip.Anchor(27.869780468947,22.783209347206)
            case "restLower":return PoseClip.Anchor(27.027047501969,26.730207090043)
            case "restTuck":return PoseClip.Anchor(22.477684528744,27.565205697984)
            case "restWake":return PoseClip.Anchor(29.880512487636,22.018488559573)
            case "takeoffCrouch":return PoseClip.Anchor(30.290772043563,27.942875826292)
            case "takeoffPush":return PoseClip.Anchor(32.580865627198,19.433450868201)
            default:return nil
            }
        default:return nil
        }
    }
}
