import AppKit
import BirdingCore

/// E1 source paths only: draw every articulated part at catalog pixel density.
/// Historical ExpansionBirdArt contributes its palette, never a finished image.
enum ExpansionSmallArt {
    private typealias Geometry = ExpansionSmallArtGeometry
    private typealias Point = (Double,Double)

    private struct Drawing {
        let species:SpeciesID
        let frame:String
        let pose:Geometry.Pose
        let anatomy:Geometry.Anatomy
        let colors:ExpansionBirdArt.Anatomy

        func b(_ u:Double, _ v:Double) -> Point { pose.bodyPoint(u,v,anatomy:anatomy) }
        func h(_ x:Double, _ y:Double) -> Point { pose.headPoint(x,y) }
        func t(_ u:Double, _ v:Double) -> Point { pose.tailPoint(u,v,anatomy:anatomy) }

        var tailColor:String {
            switch species {
            case .daurianRedstart, .blueFrontedRedstart, .blackRedstart: return "rust"
            default: return colors.wing
            }
        }

        var featherEdge:String {
            switch species {
            case .marshTit, .blackThroatedBushtit, .whiskeredYuhina: return "tan"
            case .greenBackedTit: return "slate"
            case .silverThroatedBushtit: return "silver"
            case .daurianRedstart: return "dark"
            case .blueFrontedRedstart: return "blue"
            case .blackRedstart: return "slate"
            case .commonTailorbird, .ornateSunbird: return "olive"
            case .greyCappedGreenfinch: return "brown"
            default: return "buff"
            }
        }
    }

    static func image(_ frame:String, species:SpeciesID) -> CGImage? {
        guard let p=Geometry.pose(species:species,frame:frame),
              let a=Geometry.anatomy(for:species),
              let colors=ExpansionBirdArt.profiles[species] else { return nil }
        let density=SpeciesCatalog.standard.profile(species).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let d=Drawing(species:species,frame:frame,pose:p,anatomy:a,colors:colors)
        tail(c,d)
        legs(c,d)
        if p.wing > 0.18 { wing(c,d,far:true) }
        torso(c,d)
        neck(c,d)
        wing(c,d,far:false)
        // The tit's slim abdominal stripe is torso pigment, never a wing bar.
        if species == .greenBackedTit {
            c.within(p.bodyVertices(anatomy:a)) {
                c.line([d.b(0.91,0.29),d.b(0.84,0.63),d.b(0.72,0.95)],"black",width:1.05)
            }
        }
        head(c,d)
        if frame == "restTuck" { tuckedScapulars(c,d) }
        return c.image
    }

    private static func legs(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose
        for x in [27.0,31.0] {
            c.line([(x-0.7+p.body.lean*0.3,min(35,p.body.y+p.body.height-1.4)),
                    (x-0.6+p.stance,36.2),(x,38.5)],"brown",width:0.9)
        }
        for path in Geometry.toePaths { c.line(path,"brown",width:0.75) }
    }

    private static func tail(_ c:BirdPainter, _ d:Drawing) {
        let edge=d.pose.tailVertices(species:d.species,anatomy:d.anatomy)
        c.poly(edge,d.tailColor,outline:true)
        c.within(edge) {
            if d.species != .silverThroatedBushtit {
                for across in [-0.27,0.0,0.27] {
                    c.line([d.t(0.06,across),d.t(0.94,across)],
                           d.tailColor == "rust" ? "orange":d.featherEdge,width:0.6)
                }
            }
            switch d.species {
            case .daurianRedstart:
                c.poly([d.t(0,-0.12),d.t(1,-0.12),d.t(1,0.12),d.t(0,0.12)],"black")
            case .blueFrontedRedstart:
                // Central rectrices and transverse distal bar form the same
                // inverted T at rest, when lifted, and during the recovery.
                c.poly([d.t(0,-0.13),d.t(1,-0.13),d.t(1,0.13),d.t(0,0.13)],"black")
                c.poly([d.t(0.86,-0.5),d.t(1,-0.5),d.t(1,0.5),d.t(0.86,0.5)],"black")
            case .blackRedstart:
                c.poly([d.t(0,-0.08),d.t(1,-0.08),d.t(1,0.08),d.t(0,0.08)],"black")
            case .silverThroatedBushtit:
                // Continuous narrow outer vanes; a dark core remains visible.
                for band in [(-0.47,-0.34),(0.34,0.47)] {
                    c.poly([d.t(0.1,band.0),d.t(0.99,band.0),
                            d.t(0.99,band.1),d.t(0.1,band.1)],"white")
                }
                // At 48px density pale feather shafts would erase the dark
                // rectrix core; keep one continuous center through the motion.
                c.line([d.t(0.05,0),d.t(0.99,0)],"black",width:1.1)
            case .greyCappedGreenfinch:
                for band in [(-0.46,-0.23),(0.23,0.46)] {
                    c.poly([d.t(0.08,band.0),d.t(0.87,band.0),
                            d.t(0.87,band.1),d.t(0.08,band.1)],"yellow")
                }
            case .twite:
                c.line([d.t(0.16,-0.4),d.t(0.97,-0.4)],"buff",width:0.6)
                c.line([d.t(0.16,0.4),d.t(0.97,0.4)],"buff",width:0.6)
            case .blackThroatedBushtit:
                c.line([d.t(0.1,0),d.t(0.98,0)],"umber",width:0.8)
            case .commonTailorbird:
                c.line([d.t(0.05,0),d.t(0.97,0)],"olive",width:0.9)
            default: break
            }
        }
    }

    private static func torso(_ c:BirdPainter, _ d:Drawing) {
        let edge=d.pose.bodyVertices(anatomy:d.anatomy)
        c.poly(edge,d.colors.back,outline:true)
        c.within(edge) {
            c.poly([d.b(0.57,0.1),d.b(0.92,0.15),d.b(1.08,0.59),
                    d.b(0.83,1.05),d.b(0.4,1),d.b(0.45,0.48)],d.colors.belly)
            switch d.species {
            case .marshTit:
                // Warm flanks, plain cream abdomen: no great-tit belly line.
                c.line([d.b(0.59,0.64),d.b(0.48,0.91)],"buff",width:1)
            case .blackThroatedBushtit:
                c.poly([d.b(0.65,0.22),d.b(1,0.26),d.b(0.97,0.46),d.b(0.65,0.4)],"rust")
            case .silverThroatedBushtit:
                c.poly([d.b(0.42,0.61),d.b(0.81,0.58),d.b(0.84,0.9),d.b(0.45,1)],"pink")
            case .whiskeredYuhina:
                c.line([d.b(0.63,0.15),d.b(0.91,0.28)],"buff",width:1.6)
            case .daurianRedstart:
                c.poly([d.b(0.01,0.57),d.b(0.3,0.52),d.b(0.38,0.8),d.b(0.12,0.95)],"rust")
            case .blackRedstart:
                // The existing rufiventris bird retains its extensive rust belly.
                c.line([d.b(0.84,0.57),d.b(0.73,0.88)],"orange",width:0.8)
            case .commonTailorbird:
                c.line([d.b(0.61,0.54),d.b(0.51,0.9)],"buff",width:0.65)
            case .greyCappedGreenfinch:
                c.poly([d.b(0.19,0.76),d.b(0.48,0.75),d.b(0.52,1),d.b(0.25,0.99)],"yellow")
            case .twite:
                c.poly([d.b(0.01,0.51),d.b(0.3,0.48),d.b(0.36,0.71),d.b(0.04,0.8)],"pink")
                // Streak lengths follow the keel instead of a fixed canvas grid.
                for row in 0..<2 {
                    for column in 0..<3 {
                        let u=0.67+Double(column)*0.1, v=0.29+Double(row)*0.28
                        c.line([d.b(u,v),d.b(u-0.035,v+0.18)],"umber",width:0.65)
                    }
                }
            case .ornateSunbird:
                c.line([d.b(0.73,0.55),d.b(0.65,0.89)],"yellow",width:1.2)
            default: break
            }
        }
    }

    private static func neck(_ c:BirdPainter, _ d:Drawing) {
        let a=d.anatomy
        let nape=d.h(-a.headWidth*0.32,a.headHeight*0.2)
        let chin=d.h(a.headWidth*0.29,a.headHeight*0.39)
        let edge=[d.b(0.47,0.1),nape,chin,d.b(0.94,0.58)]
        c.poly(edge,d.colors.belly)
        c.within(edge) {
            c.poly([edge[0],nape,d.h(-a.headWidth*0.1,a.headHeight*0.47),d.b(0.65,0.35)],d.colors.back)
            let bib:[Point]=[d.h(-0.2,a.headHeight*0.23),chin,d.b(0.9,0.34),d.b(0.73,0.27)]
            switch d.species {
            case .greenBackedTit, .blackThroatedBushtit, .daurianRedstart, .blackRedstart:
                c.poly(bib,"black")
            case .silverThroatedBushtit: c.poly(bib,"silver")
            case .blueFrontedRedstart, .ornateSunbird:
                c.poly(bib,"navy")
                if d.species == .ornateSunbird {
                    c.line([d.h(1.7,a.headHeight*0.36),d.b(0.86,0.31)],"blue",width:0.8)
                }
            case .whiskeredYuhina:
                c.poly([nape,d.h(-a.headWidth*0.18,a.headHeight*0.5),
                        d.b(0.67,0.34),d.b(0.53,0.24)],"buff")
            default: break
            }
        }
    }

    private static func wing(_ c:BirdPainter, _ d:Drawing, far:Bool) {
        func w(_ u:Double, _ v:Double) -> Point { d.pose.wingPoint(u,v,anatomy:d.anatomy,far:far) }
        let edge=d.pose.wingVertices(anatomy:d.anatomy,far:far)
        c.poly(edge,far ? d.colors.back:d.colors.wing,outline:true)
        c.within(edge) {
            c.poly([w(-0.48,0.11),w(-0.04,0.01),w(0.5,0.2),w(0.35,0.53),w(-0.3,0.6)],d.colors.back)
            for n in 0..<4 {
                let u = -0.1+Double(n)*0.21
                c.line([w(u,0.3),w(u+0.26,0.98)],d.featherEdge,width:0.65)
            }
            switch d.species {
            case .greenBackedTit:
                c.line([w(-0.37,0.28),w(0.46,0.35)],"white",width:0.85)
                c.line([w(-0.22,0.54),w(0.63,0.62)],"white",width:1.05)
            case .daurianRedstart:
                c.poly([w(-0.31,0.28),w(0.43,0.32),w(0.57,0.51),w(-0.18,0.5)],"white")
            case .greyCappedGreenfinch:
                c.poly([w(0.29,0.32),w(0.52,0.35),w(0.88,0.93),w(0.62,0.99)],"yellow")
            case .twite:
                c.line([w(-0.36,0.32),w(0.49,0.4)],"buff",width:0.9)
                c.line([w(-0.1,0.54),w(0.64,0.65)],"tan",width:0.65)
                for u in [-0.3,0.0,0.3] {
                    c.line([w(u,0.12),w(u+0.15,0.36)],"umber",width:0.65)
                }
            case .silverThroatedBushtit:
                c.line([w(-0.2,0.59),w(0.67,0.76)],"white",width:0.75)
            case .blueFrontedRedstart:
                c.line([w(-0.25,0.19),w(0.36,0.3)],"blue",width:0.65)
            case .marshTit:
                c.line([w(-0.27,0.35),w(0.55,0.48)],"tan",width:0.6)
            case .blackRedstart:
                c.line([w(-0.28,0.29),w(0.46,0.4)],"dark",width:0.7)
            default: break
            }
        }
    }

    private static func head(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy, width=p.headWidth(anatomy:a), height=a.headHeight
        let x = -width/2, y = -height/2
        c.ctx.saveGState()
        c.ctx.translateBy(x:p.head.x,y:p.head.y)
        c.ctx.rotate(by:CGFloat(p.head.pitch))
        if d.species == .whiskeredYuhina {
            // Three rooted crown feathers move as head anatomy, not an antenna.
            c.poly([(x+0.2,y+2),(x+0.7,y-3.9),(x+2.4,y-2.2),
                    (x+3.4,y-3.1),(x+4.4,y-0.8),(x+6,y+1.5)],"brown",outline:true)
        }
        c.oval(x,y,width,height,d.colors.head,outline:true)
        c.ctx.saveGState()
        c.ctx.addEllipse(in:CGRect(x:x,y:y,width:width,height:height))
        c.ctx.clip()
        c.pigment {
            func cheek(_ color:String) {
                c.poly([(x+0.9,-0.1),(width/2-0.5,-0.35),
                        (width/2-0.7,height*0.34),(x+2,height*0.49)],color)
            }
            switch d.species {
            case .marshTit:
                cheek("cream")
                // A small chin patch distinct from the green-backed tit's bib.
                c.poly([(width*0.13,height*0.29),(width/2,height*0.23),
                        (width*0.3,height*0.5),(width*0.12,height*0.44)],"black")
            case .greenBackedTit: cheek("white")
            case .blackThroatedBushtit:
                cheek("white")
                c.poly([(x,y+2.1),(width/2,y+2.4),(width/2,0.3),(x+0.7,0.5)],"black")
                c.line([(x+1,y+0.8),(x+5,y+0.5)],"rust",width:1.1)
            case .silverThroatedBushtit:
                cheek("silver")
                c.line([(x+0.4,y+2),(x+2,y+0.6),(x+4.8,y+0.8)],"black",width:1.25)
                c.poly([(x+3,height*0.22),(width/2,height*0.12),
                        (width/2,height*0.48),(x+3.6,height*0.5)],"silver")
            case .whiskeredYuhina:
                cheek("cream")
                c.line([(width/2-2.4,0),(x+3,height*0.48)],"black",width:0.9)
                c.line([(x+0.6,y+1.4),(x+4,y+0.7)],"tan",width:0.65)
            case .daurianRedstart:
                cheek("black")
                c.line([(x+1,y+1.1),(x+5,y+0.7)],"silver",width:0.85)
            case .blueFrontedRedstart:
                c.poly([(x+0.7,y+1.4),(width/2-0.5,y+0.9),
                        (width/2-0.3,y+2),(x+1.5,y+2.2)],"cyan")
                cheek("navy")
            case .blackRedstart:
                cheek("black")
                c.line([(x+1,y+1.4),(x+4.6,y+0.7)],"slate",width:0.65)
            case .commonTailorbird:
                cheek("cream")
                c.line([(x+1,y+1),(x+4.9,y+0.8)],"orange",width:0.9)
            case .greyCappedGreenfinch:
                cheek("tan")
                c.line([(x+0.8,y+1.4),(x+4.2,y+0.6)],"silver",width:0.65)
            case .twite:
                cheek("buff")
                for n in 0..<3 {
                    let u=x+1+Double(n)*1.7
                    c.line([(u,y+0.5),(u+0.5,y+2.3)],"umber",width:0.6)
                }
            case .ornateSunbird:
                c.poly([(x,y),(width/2,y),(width/2,y+2.7),(x+1,y+2.6)],"olive")
                c.line([(width/2-2,height*0.2),(width/2-1,height*0.47)],"blue",width:0.7)
            default: break
            }
        }
        c.ctx.restoreGState()

        let bill=p.billVertices(anatomy:a)
        if p.gape > 0 {
            let r=width/2-0.35
            c.poly([(r,0.5),(bill[1].0-0.3,0.85+p.gape*1.9),(r,1.7+p.gape*1.4)],"eye")
            c.poly(p.lowerBillVertices(anatomy:a),d.colors.bill,outline:true)
        }
        c.poly(bill,d.colors.bill,outline:a.bill == .conical)
        if a.bill == .conical {
            c.line([(width/2,0.45),(bill[1].0-0.7,0.45)],
                   d.species == .twite ? "tan":"buff",width:0.5)
        }
        let ex=width*0.2-p.turn*0.65, ey = -height*0.12
        c.pigment {
            if d.species == .whiskeredYuhina {
                c.oval(ex-0.7,ey-0.7,2.4,2.4,"white")
            }
            if d.frame == "restTuck" || d.frame == "restLower" {
                c.line([(ex-0.15,ey+0.45),(ex+0.4,ey+0.65),(ex+1,ey+0.35)],"eye",width:0.65)
            } else {
                c.oval(ex,ey,1,1.1,"eye")
                c.oval(ex+0.4,ey,0.4,0.4,"white")
            }
        }
        c.ctx.restoreGState()
    }

    private static func tuckedScapulars(_ c:BirdPainter, _ d:Drawing) {
        // A local feather fold partly overlaps the tucked nape, leaving the
        // geometric bill tip unobscured for downstream anchor consumers.
        let root=d.b(0.41,0.16), x=root.0, y=root.1
        c.poly([(x-1.6,y+1),(x,y-0.7),(x+1.6,y+0.2),(x+3,y-0.4),
                (x+4.1,y+2.5),(x+1.7,y+3.4),(x-1,y+3)],d.colors.back)
        c.line([(x-0.4,y+1),(x+1.1,y+2),(x+2.6,y+1.3)],d.featherEdge,width:0.6)
    }
}
