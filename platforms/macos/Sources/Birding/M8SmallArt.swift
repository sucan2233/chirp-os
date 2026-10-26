import AppKit
import BirdingCore

/// Original M8c paths only. No old frame is an input image, and no whole bird
/// transform is used. BirdArt's dispatcher/cache is owned by the coordinator.
enum M8SmallArt {
    private typealias Geometry = M8SmallArtGeometry
    private typealias Point = (Double,Double)

    private struct Drawing {
        let species: SpeciesID
        let frame: String
        let pose: Geometry.Pose
        let anatomy: Geometry.Anatomy

        var back: String {
            switch species {
            case .yellowBrowedWarbler: return "olive"
            case .vinousThroatedParrotbill: return "tan"
            case .yellowRumpedFlycatcher: return "black"
            case .redFlankedBluetail, .plumbeousWaterRedstart: return "blue"
            case .longTailedShrike: return "orange"
            case .blackDrongo: return "dark"
            default: return "gray"
            }
        }

        var belly: String {
            switch species {
            case .vinousThroatedParrotbill: return "pink"
            case .yellowRumpedFlycatcher: return "yellow"
            case .redFlankedBluetail: return "white"
            case .plumbeousWaterRedstart: return "blue"
            case .blackDrongo: return "dark"
            default: return "cream"
            }
        }

        var feather: String {
            switch species {
            case .yellowBrowedWarbler: return "green"
            case .vinousThroatedParrotbill: return "brown"
            case .redFlankedBluetail: return "navy"
            case .plumbeousWaterRedstart: return "slate"
            case .longTailedShrike: return "dark"
            default: return "black"
            }
        }

        var featherEdge: String {
            switch species {
            case .yellowBrowedWarbler: return "olive"
            case .vinousThroatedParrotbill: return "tan"
            case .yellowRumpedFlycatcher, .blackDrongo: return "dark"
            case .redFlankedBluetail, .plumbeousWaterRedstart: return "blue"
            case .longTailedShrike: return "slate"
            default: return "gray"
            }
        }

        var headColor: String {
            switch species {
            case .yellowBrowedWarbler: return "olive"
            case .vinousThroatedParrotbill: return "orange"
            case .redFlankedBluetail, .plumbeousWaterRedstart: return "blue"
            case .longTailedShrike, .yellowBilledGrosbeak: return "gray"
            default: return "black"
            }
        }

        var billColor: String {
            species == .yellowBilledGrosbeak ? "yellow" :
                (species == .vinousThroatedParrotbill ? "cream" : "dark")
        }

        /// Shoulder lean tapers to zero at the belly. Fullness only alters the
        /// torso contour; feet and head geometry retain their own coordinates.
        func bodyPoint(_ u:Double, _ v:Double) -> Point {
            let width=anatomy.width+pose.body.fluff
            return (34-anatomy.width-pose.body.fluff/2+width*u+pose.body.lean*(1-v),
                    pose.body.y+pose.body.height*v)
        }

        func headPoint(_ x:Double, _ y:Double) -> Point {
            let point=pose.headPoint(x,y)
            return (Double(point.x),Double(point.y))
        }
    }

    static func image(_ frame: String, species: SpeciesID) -> CGImage? {
        guard let a=Geometry.anatomy(for:species),
              let p=Geometry.pose(species:species,frame:frame) else { return nil }
        let density=SpeciesCatalog.standard.profile(species).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let d=Drawing(species:species,frame:frame,pose:p,anatomy:a)
        tail(c,d)
        feet(c,d)
        if p.wing > 0.18 { wing(c,d,far:true) }
        body(c,d)
        neck(c,d)
        wing(c,d,far:false)
        head(c,d)
        if frame == "restTuck" { shoulder(c,d) }
        return c.image
    }

    private static func feet(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose
        for x in [27.0,31.0] {
            let hipY=min(35,p.body.y+p.body.height-1.5)
            c.line([(x-0.8+p.body.lean*0.35,hipY),
                    (x-0.5+p.stance,36),(x,38.5)],"brown",width:1)
        }
        for toes in Geometry.toePaths { c.line(toes,"brown",width:0.8) }
    }

    private static func tail(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy, tx=p.tail.x, ty=p.tail.y
        let root=d.bodyPoint(0.24,0.58)
        if d.species == .blackDrongo {
            // A concave, open fork rather than a fan. All pigment is clipped
            // inside these two lobes, preserving the transparent central notch.
            let half=a.tailWidth*0.43+p.spread*1.9
            let notch=7.8+p.spread*1.4
            let edge:[Point]=[(root.0,root.1),(tx,ty-half),
                              (tx+notch,ty),(tx,ty+half),(root.0+4.5,root.1+3.8)]
            c.poly(edge,"black",outline:true)
            c.within(edge) {
                c.line([(root.0+0.5,root.1+0.4),(tx+1,ty-half+0.8)],"dark",width:0.7)
                c.line([(root.0+3.8,root.1+3.2),(tx+1,ty+half-0.8)],"dark",width:0.7)
            }
            return
        }
        if d.species == .plumbeousWaterRedstart {
            // Broad rust rectrices are authored as a scalloped fan; this is
            // independent of the drongo's permanently notched two-lobe tail.
            let width=a.tailWidth+p.spread*10
            let edge:[Point]=[(root.0,root.1),(tx+2.5,ty-width*0.55),
                              (tx+0.8,ty-width*0.3),(tx,ty),
                              (tx+0.8,ty+width*0.3),(tx+2.5,ty+width*0.55),
                              (root.0+4.5,root.1+3.7)]
            c.poly(edge,"rust",outline:true)
            c.within(edge) {
                for i in 0..<5 {
                    let offset=Double(i-2)*width*0.21
                    c.line([(root.0+2,root.1+1.7),(tx+1.4,ty+offset)],"orange",width:0.65)
                }
                c.line([(root.0+1,root.1),(tx+2.7,ty-width*0.5)],"umber",width:0.65)
            }
            return
        }

        let width=a.tailWidth+p.spread*3
        let edge:[Point]
        switch d.species {
        case .vinousThroatedParrotbill:
            // Long narrow rounded tail balancing a compact, round torso.
            edge=[root,(tx+0.8,ty-1.2),(tx,ty),(tx+1.5,ty+1.1),
                  (tx+width,ty+0.7),(root.0+4,root.1+4)]
        case .longTailedShrike:
            // A long, firm tapered blade, kept distinct from the parrotbill.
            edge=[root,(tx,ty-0.8),(tx+0.2,ty+0.7),
                  (tx+width-0.8,ty+1.2),(root.0+5.1,root.1+3)]
        case .redFlankedBluetail:
            edge=[root,(tx,ty-width*0.2),(tx+0.3,ty+1.1),
                  (tx+width,ty+1),(root.0+4.2,root.1+3.7)]
        case .yellowBilledGrosbeak:
            edge=[root,(tx,ty-1),(tx+0.6,ty+1),(tx+width,ty+1),
                  (root.0+5.5,root.1+3.8)]
        default:
            edge=[root,(tx,ty-0.5),(tx+0.3,ty+0.8),
                  (tx+width,ty+0.6),(root.0+4.3,root.1+3.5)]
        }
        c.poly(edge,d.feather,outline:true)
        c.within(edge) {
            c.line([(root.0+1,root.1+0.8),(tx+0.8,ty)],d.featherEdge,width:0.75)
            c.line([(root.0+3.7,root.1+2.8),(tx+width-0.7,ty+0.4)],d.featherEdge,width:0.6)
        }
    }

    private static func body(_ c:BirdPainter, _ d:Drawing) {
        // Each outline has its own shoulder, keel and rump proportions, rather
        // than an ellipse recolored eight ways. These are local anatomy paths.
        let shape:[Point]
        switch d.species {
        case .yellowBrowedWarbler:
            shape=[(0,0.54),(0.08,0.28),(0.31,0.06),(0.62,0),
                   (0.89,0.2),(1,0.48),(0.9,0.79),(0.65,0.98),
                   (0.34,1),(0.1,0.81)]
        case .vinousThroatedParrotbill:
            shape=[(0,0.49),(0.07,0.21),(0.29,0.03),(0.6,0),
                   (0.86,0.15),(1,0.43),(0.98,0.72),(0.8,0.94),
                   (0.48,1),(0.19,0.88),(0.03,0.69)]
        case .yellowRumpedFlycatcher:
            shape=[(0,0.55),(0.11,0.25),(0.37,0.02),(0.63,0),
                   (0.88,0.19),(1,0.46),(0.92,0.77),(0.7,1),
                   (0.4,0.97),(0.13,0.78)]
        case .redFlankedBluetail:
            shape=[(0,0.52),(0.12,0.24),(0.37,0.02),(0.69,0),
                   (0.91,0.19),(1,0.46),(0.91,0.79),(0.68,1),
                   (0.38,0.99),(0.13,0.79)]
        case .plumbeousWaterRedstart:
            shape=[(0,0.5),(0.08,0.22),(0.32,0.02),(0.66,0),
                   (0.9,0.2),(1,0.51),(0.93,0.83),(0.72,1),
                   (0.39,0.99),(0.12,0.83)]
        case .longTailedShrike:
            shape=[(0,0.57),(0.13,0.29),(0.43,0.03),(0.72,0),
                   (0.94,0.18),(1,0.44),(0.95,0.7),(0.75,0.95),
                   (0.42,1),(0.15,0.81)]
        case .blackDrongo:
            shape=[(0,0.65),(0.15,0.28),(0.47,0),(0.72,0.03),
                   (0.94,0.2),(1,0.48),(0.9,0.8),(0.66,1),
                   (0.38,0.95),(0.11,0.83)]
        default: // Grosbeak: broad, heavy shoulder with a full, deep keel.
            shape=[(0,0.46),(0.08,0.18),(0.34,0),(0.68,0.02),
                   (0.91,0.2),(1,0.49),(0.96,0.78),(0.76,0.97),
                   (0.47,1),(0.18,0.87),(0.03,0.68)]
        }
        let edge=shape.map { d.bodyPoint($0.0,$0.1) }
        c.poly(edge,d.back,outline:true)
        c.within(edge) {
            c.poly([d.bodyPoint(0.6,0.08),d.bodyPoint(0.95,0.15),
                    d.bodyPoint(1.08,0.68),d.bodyPoint(0.7,1.05),
                    d.bodyPoint(0.4,0.98),d.bodyPoint(0.47,0.47)],d.belly)
            if d.species == .redFlankedBluetail {
                // Orange stays on the flank between the blue wing and white
                // breast through the tail lifts and head turns.
                c.poly([d.bodyPoint(0.77,0.24),d.bodyPoint(0.96,0.2),
                        d.bodyPoint(0.94,0.7),d.bodyPoint(0.77,0.84),
                        d.bodyPoint(0.72,0.57)],"orange")
            } else if d.species == .yellowRumpedFlycatcher {
                c.poly([d.bodyPoint(0.02,0.57),d.bodyPoint(0.31,0.5),
                        d.bodyPoint(0.38,0.79),d.bodyPoint(0.08,0.96)],"yellow")
            } else if d.species == .plumbeousWaterRedstart {
                c.line([d.bodyPoint(0.82,0.42),d.bodyPoint(0.73,0.85)],"slate",width:0.8)
            } else if d.species == .vinousThroatedParrotbill {
                c.poly([d.bodyPoint(0.59,0.34),d.bodyPoint(0.94,0.25),
                        d.bodyPoint(1,0.68),d.bodyPoint(0.65,0.83)],"pink")
            } else if d.species == .yellowBilledGrosbeak {
                c.line([d.bodyPoint(0.71,0.5),d.bodyPoint(0.56,0.87)],"silver",width:0.8)
            }
        }
    }

    private static func neck(_ c:BirdPainter, _ d:Drawing) {
        let a=d.anatomy
        let nape=d.headPoint(-a.headWidth*0.31,a.headHeight*0.2)
        let chin=d.headPoint(a.headWidth*0.27,a.headHeight*0.4)
        let edge=[d.bodyPoint(0.49,0.13),nape,chin,d.bodyPoint(0.92,0.61)]
        c.poly(edge,d.belly)
        c.within(edge) {
            c.poly([edge[0],nape,(nape.0+1.5,nape.1+2.4),
                    d.bodyPoint(0.66,0.4)],d.headColor)
            if d.species == .yellowRumpedFlycatcher {
                c.poly([nape,chin,(chin.0-0.6,chin.1+1.4),
                        d.bodyPoint(0.75,0.25)],"black")
            } else if d.species == .longTailedShrike {
                c.line([nape,d.bodyPoint(0.51,0.19)],"orange",width:1.4)
            }
        }
    }

    private static func wing(_ c:BirdPainter, _ d:Drawing, far:Bool) {
        let p=d.pose, a=d.anatomy, open=p.wing
        let root=d.bodyPoint(far ? 0.58:0.4,0.12)
        func w(_ u:Double, _ v:Double) -> Point {
            // A folded primary points down; shoulder/wrist/feathers spread up
            // as opening increases. Reach is species anatomy, never image scale.
            let side=far ? 0.48 : -1.0
            return (root.0+side*u*(5+a.wingReach*open)+v*open*2,
                    root.1+v*(a.primaryLength*(1-open)+5.5*open)+p.droop*v-u*open*15)
        }
        let form:[Point]
        switch d.species {
        case .vinousThroatedParrotbill:
            form=[(-0.6,0.1),(0,-0.05),(0.64,0.25),(1,0.85),
                  (0.8,1.03),(0.4,1.05),(-0.15,0.86),(-0.65,0.49)]
        case .longTailedShrike:
            form=[(-0.65,0.05),(-0.1,-0.08),(0.5,0.2),(1,1),
                  (0.79,1.03),(0.56,0.93),(0.2,0.86),(-0.6,0.48)]
        case .blackDrongo:
            form=[(-0.55,0.02),(0,-0.07),(0.55,0.2),(1,1.03),
                  (0.82,1.1),(0.6,0.98),(0.1,0.75),(-0.6,0.43)]
        case .yellowBilledGrosbeak:
            form=[(-0.7,0.1),(-0.12,-0.06),(0.6,0.19),(1,0.88),
                  (0.76,1.03),(0.3,1.03),(-0.2,0.8),(-0.73,0.49)]
        case .yellowRumpedFlycatcher:
            form=[(-0.62,0.04),(-0.1,-0.1),(0.56,0.17),(1,1.04),
                  (0.81,1.02),(0.5,0.91),(0.05,0.82),(-0.65,0.41)]
        case .plumbeousWaterRedstart:
            form=[(-0.65,0.12),(-0.1,-0.02),(0.56,0.23),(1,0.93),
                  (0.76,1.07),(0.34,1.01),(-0.08,0.84),(-0.64,0.52)]
        case .redFlankedBluetail:
            form=[(-0.6,0.08),(-0.08,-0.06),(0.52,0.2),(1,0.96),
                  (0.78,1.05),(0.32,0.95),(-0.12,0.81),(-0.62,0.46)]
        default:
            form=[(-0.6,0.08),(-0.12,-0.08),(0.47,0.15),(1,0.96),
                  (0.73,1.04),(0.28,0.93),(-0.14,0.77),(-0.64,0.4)]
        }
        let edge=form.map { w($0.0,$0.1) }
        c.poly(edge,far ? d.back:d.feather,outline:true)
        c.within(edge) {
            c.poly([w(-0.5,0.12),w(-0.05,0.02),w(0.5,0.21),
                    w(0.35,0.52),w(-0.3,0.59)],d.back)
            for i in 0..<4 {
                let u = -0.12+Double(i)*0.21
                c.line([w(u,0.31),w(u+0.25,0.98)],d.featherEdge,width:0.65)
            }
            switch d.species {
            case .yellowBrowedWarbler:
                c.line([w(-0.34,0.35),w(0.54,0.43)],"cream",width:1)
                c.line([w(-0.15,0.6),w(0.67,0.67)],"cream",width:0.8)
            case .yellowRumpedFlycatcher:
                c.poly([w(-0.33,0.27),w(0.48,0.33),w(0.63,0.48),w(-0.19,0.48)],"white")
            case .yellowBilledGrosbeak:
                c.line([w(-0.42,0.35),w(0.56,0.45)],"white",width:1.4)
            case .blackDrongo:
                c.line([w(-0.25,0.17),w(0.24,0.25)],"slate",width:0.55)
            case .longTailedShrike:
                c.line([w(-0.3,0.2),w(0.35,0.29)],"orange",width:0.8)
            default: break
            }
        }
    }

    private static func withinHead(_ c:BirdPainter, _ w:Double, _ h:Double, _ paint:()->Void) {
        c.ctx.saveGState()
        c.ctx.addEllipse(in:CGRect(x:-w/2,y:-h/2,width:w,height:h))
        c.ctx.clip()
        c.pigment(paint)
        c.ctx.restoreGState()
    }

    private static func head(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy, w=p.headWidth(anatomy:a), h=a.headHeight
        let x = -w/2, y = -h/2
        c.ctx.saveGState()
        c.ctx.translateBy(x:p.head.x,y:p.head.y)
        c.ctx.rotate(by:CGFloat(p.head.pitch))
        if d.species == .blackDrongo {
            // Keep the established small nape feather, not an enlarged crest.
            c.poly([(x+0.4,y+1.3),(x+0.9,y-0.7),(x+2.9,y-0.1),
                    (x+4.6,y+1.4)],"black")
        }
        c.oval(x,y,w,h,d.headColor,outline:true)
        withinHead(c,w,h) {
            switch d.species {
            case .yellowBrowedWarbler:
                c.line([(x+0.5,y+2),(x+w-0.5,y+1.7)],"cream",width:0.9)
                c.line([(x+1.8,y+3),(x+w,y+2.7)],"brown",width:0.7)
                c.poly([(x+2,y+4),(x+w,y+3.7),(x+w-0.6,y+6),
                        (x+2.6,y+5.7)],"cream")
            case .vinousThroatedParrotbill:
                c.poly([(x+1,y+4),(x+w-1,y+3.5),(x+w-0.7,y+6),
                        (x+3,y+7)],"pink")
                c.line([(x+1.1,y+1.4),(x+3.7,y+0.7)],"tan",width:0.7)
            case .yellowRumpedFlycatcher:
                c.line([(x+0.5,y+1.5),(x+w-1,y+1)],"white",width:0.9)
            case .redFlankedBluetail:
                c.line([(x+1,y+1.5),(x+5,y+1)],"cyan",width:0.7)
                c.poly([(x+3,y+5),(x+w,y+4.5),(x+w-1,y+7),
                        (x+4,y+7)],"white")
            case .plumbeousWaterRedstart:
                c.line([(x+0.8,y+1.7),(x+4.1,y+1)],"slate",width:0.6)
            case .longTailedShrike:
                // The mask remains attached to the turning head, not the neck.
                c.poly([(x,y+2),(x+w,y+2),(x+w,y+3.7),(x+1,y+4)],"black")
                c.poly([(x+2,y+4),(x+w,y+4),(x+w-1,y+6.5),
                        (x+3,y+7)],"cream")
            case .yellowBilledGrosbeak:
                c.poly([(x+w-3,y+2),(x+w,y+2),(x+w,y+5),
                        (x+w-2,y+5)],"black")
            case .blackDrongo:
                c.line([(x+1,y+2),(x+3,y+1)],"slate",width:0.6)
            default: break
            }
        }

        let bill=p.billVertices(anatomy:a)
        if p.gape > 0 {
            let root=bill[0].0
            c.poly([(root,0.8),(bill[1].0-0.5,1+p.gape*1.8),
                    (root,1.8+p.gape*1.2)],"eye")
            c.poly(p.lowerBillVertices(anatomy:a),d.billColor)
        }
        c.poly(bill,d.billColor,outline:a.bill == .conical)
        if a.bill == .conical {
            c.line([(bill[0].0+0.4,0.5),(bill[1].0-0.7,0.5)],
                   d.species == .yellowBilledGrosbeak ? "tan":"buff",width:0.5)
        }

        let ex=w*0.22-p.turn*0.65, ey = -h*0.12
        c.pigment {
            if d.frame == "restTuck" || d.frame == "restLower" {
                c.line([(ex-0.2,ey+0.4),(ex+0.35,ey+0.65),(ex+1,ey+0.35)],"eye",width:0.7)
            } else {
                c.oval(ex,ey,1,1.1,"eye")
                c.oval(ex+0.4,ey,0.45,0.45,"white")
            }
        }
        c.ctx.restoreGState()
    }

    private static func shoulder(_ c:BirdPainter, _ d:Drawing) {
        // A tucked head turns into the scapulars. Feather paths are newly drawn
        // at the shoulder; the bill anchor remains its real geometric endpoint.
        let root=d.bodyPoint(0.47,0.2), x=root.0, y=root.1
        c.poly([(x-2,y+1),(x,y-1),(x+1.8,y),(x+3,y-0.8),
                (x+5,y+2.5),(x+2.4,y+4),(x-1,y+3.7)],d.back)
        c.line([(x-0.5,y+1),(x+1.6,y+2),(x+3.4,y+1.3)],d.featherEdge,width:0.65)
    }
}
