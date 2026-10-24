import Foundation

/// Generated directly from DetailedBirdArt.bathPose, the rotated bill vertex,
/// and the belly/wing intersections at BathGeometry.birdWaterlineY.
/// Right-facing logical 48x48 coordinates before raster rounding; mirror
/// through PoseClip.Anchor.mirrored(facingRight:) when facing left.
/// Regenerate these constants if any authored bath geometry changes.
enum BathPoseAnchors {
    static func anchor(species:SpeciesID,frame:String)->PoseClip.Anchor? {
        switch species {
        case .treeSparrow:
            switch frame {
            case "bathInspect":return PoseClip.Anchor(39.343532799051,26.212868816067)
            case "bathTouch":return PoseClip.Anchor(40.000000000000,39.000000000000)
            case "bathLower":return PoseClip.Anchor(39.651852485603,30.387289998843)
            case "bath0":return PoseClip.Anchor(38.781234755592,30.924158433801)
            case "bath1":return PoseClip.Anchor(40.002325190475,26.538706659616)
            case "bath2":return PoseClip.Anchor(40.436600064351,32.991150193970)
            case "bathRise":return PoseClip.Anchor(40.491499527023,20.878763080952)
            default:return nil
            }
        case .lightVentedBulbul:
            switch frame {
            case "bathInspect":return PoseClip.Anchor(39.143141183203,23.839985905264)
            case "bathTouch":return PoseClip.Anchor(40.000000000000,39.000000000000)
            case "bathLower":return PoseClip.Anchor(39.210116058439,29.124670897772)
            case "bath0":return PoseClip.Anchor(38.886208665260,28.894245872594)
            case "bath1":return PoseClip.Anchor(39.468342482624,24.649200045700)
            case "bath2":return PoseClip.Anchor(40.069737963049,31.553195083386)
            case "bathRise":return PoseClip.Anchor(39.968342482624,19.149200045700)
            default:return nil
            }
        default:return nil
        }
    }

    /// Feather/bill contacts only; foot masking uses BathGeometry.birdFeetRect.
    /// Inspect/Rise and unsupported pairs intentionally have no water contacts.
    static func waterContacts(species:SpeciesID,frame:String)->[PoseClip.Anchor] {
        switch species {
        case .treeSparrow:
            switch frame {
            case "bathTouch":return [PoseClip.Anchor(40.000000000000,39.000000000000)]
            case "bathLower":return [PoseClip.Anchor(17.339745962156,39.000000000000),PoseClip.Anchor(34.660254037844,39.000000000000)]
            case "bath0":return [PoseClip.Anchor(16.100505063388,39.000000000000),PoseClip.Anchor(35.899494936612,39.000000000000),PoseClip.Anchor(14.000000000000,39.000000000000),PoseClip.Anchor(27.000000000000,39.000000000000),PoseClip.Anchor(39.000000000000,39.000000000000),PoseClip.Anchor(32.666666666667,39.000000000000)]
            case "bath1":return [PoseClip.Anchor(17.339745962156,39.000000000000),PoseClip.Anchor(34.660254037844,39.000000000000)]
            case "bath2":return [PoseClip.Anchor(16.825480175343,39.000000000000),PoseClip.Anchor(36.674519824657,39.000000000000),PoseClip.Anchor(17.000000000000,39.000000000000),PoseClip.Anchor(28.000000000000,39.000000000000),PoseClip.Anchor(38.000000000000,39.000000000000),PoseClip.Anchor(31.333333333333,39.000000000000)]
            default:return []
            }
        case .lightVentedBulbul:
            switch frame {
            case "bathTouch":return [PoseClip.Anchor(40.000000000000,39.000000000000)]
            case "bathLower":return [PoseClip.Anchor(15.230849026836,39.000000000000),PoseClip.Anchor(33.769150973164,39.000000000000)]
            case "bath0":return [PoseClip.Anchor(13.557911993553,39.000000000000),PoseClip.Anchor(35.442088006447,39.000000000000),PoseClip.Anchor(12.000000000000,39.000000000000),PoseClip.Anchor(24.000000000000,39.000000000000),PoseClip.Anchor(41.000000000000,39.000000000000),PoseClip.Anchor(34.400000000000,39.000000000000)]
            case "bath1":return [PoseClip.Anchor(14.741677804509,39.000000000000),PoseClip.Anchor(34.258322195491,39.000000000000)]
            case "bath2":return [PoseClip.Anchor(14.303654253263,39.000000000000),PoseClip.Anchor(36.196345746737,39.000000000000),PoseClip.Anchor(15.000000000000,39.000000000000),PoseClip.Anchor(28.000000000000,39.000000000000),PoseClip.Anchor(40.000000000000,39.000000000000),PoseClip.Anchor(32.500000000000,39.000000000000)]
            default:return []
            }
        default:return []
        }
    }
}
