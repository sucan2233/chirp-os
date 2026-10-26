import AppKit
import BirdingCore

/// E5 original paths; existing expansion artwork supplies colors only.
/// Rasterization uses species density, never transformed historical bitmaps.
enum ExpansionLargeArt {
    private typealias Geometry = ExpansionLargeArtGeometry
    private typealias Point = (Double,Double)

    private struct Drawing {
        let id:SpeciesID
        let frame:String
        let pose:Geometry.Pose
        let anatomy:Geometry.Anatomy
        let colors:ExpansionBirdArt.Anatomy

        func b(_ u:Double, _ v:Double) -> Point { pose.bodyPoint(u,v,anatomy:anatomy) }
        func n(_ t:Double, _ across:Double) -> Point { pose.neckPoint(t,across,anatomy:anatomy) }
        func t(_ along:Double, _ across:Double) -> Point { pose.tailPoint(along,across,anatomy:anatomy) }
        var raptor:Bool { id == .uplandBuzzard || id == .himalayanVulture }
        var tailColor:String { id == .greaterCoucal ? "black":colors.wing }
        var featherEdge:String {
            switch id {
            case .orientalTurtleDove: return "tan"
            case .eurasianCollaredDove: return "silver"
            case .uplandBuzzard: return "brown"
            case .himalayanVulture: return "tan"
            case .commonPheasant: return "tan"
            default: return "orange"
            }
        }
    }

    static func image(_ frame:String, species:SpeciesID) -> CGImage? {
        guard let p=Geometry.pose(species:species,frame:frame),
              let a=Geometry.anatomy(for:species),
              let colors=ExpansionBirdArt.profiles[species] else { return nil }
        let density=SpeciesCatalog.standard.profile(species).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let d=Drawing(id:species,frame:frame,pose:p,anatomy:a,colors:colors)
        tail(c,d)
        legs(c,d)
        if p.wing > 0.18 { wing(c,d,far:true) }
        body(c,d)
        neck(c,d)
        wing(c,d,far:false)
        if species == .himalayanVulture { ruff(c,d) }
        head(c,d)
        if frame == "restTuck" { scapularFold(c,d) }
        for path in Geometry.toePaths {
            c.line(path,d.raptor ? "yellow":"brown",width:0.75)
        }
        return c.image
    }

    private static func tail(_ c:BirdPainter, _ d:Drawing) {
        let edge=d.pose.tailVertices(anatomy:d.anatomy)
        c.poly(edge,d.tailColor,outline:true)
        c.within(edge) {
            switch d.id {
            case .orientalTurtleDove:
                for across in [-0.3,0.0,0.3] {
                    c.line([d.t(0.08,across),d.t(0.95,across)],"brown",width:0.65)
                }
                c.poly([d.t(0.85,-0.49),d.t(1,-0.49),d.t(1,0.49),d.t(0.85,0.49)],"buff")
            case .eurasianCollaredDove:
                c.poly([d.t(0.81,-0.5),d.t(1,-0.5),d.t(1,0.5),d.t(0.81,0.5)],"white")
                c.line([d.t(0.05,0),d.t(0.95,0)],"tan",width:0.65)
            case .uplandBuzzard:
                for along in [0.52,0.7,0.87] {
                    c.line([d.t(along,-0.5),d.t(along,0.5)],"umber",width:0.85)
                }
                c.poly([d.t(0.93,-0.5),d.t(1,-0.5),d.t(1,0.5),d.t(0.93,0.5)],"buff")
            case .himalayanVulture:
                c.poly([d.t(0.63,-0.5),d.t(1,-0.5),d.t(1,0.5),d.t(0.63,0.5)],"black")
                for across in [-0.32,0.0,0.32] {
                    c.line([d.t(0.05,across),d.t(0.96,across)],"umber",width:0.65)
                }
            case .commonPheasant:
                c.poly([d.t(0,-0.5),d.t(1,-0.5),d.t(1,0.5),d.t(0,0.5)],"tan")
                c.line([d.t(0,0),d.t(1,0)],"rust",width:0.6)
                // Bars cross the actual tapered rectrices rather than the canvas.
                for index in 0..<8 {
                    let along=0.17+Double(index)*0.1
                    c.line([d.t(along,-0.5),d.t(along,0.5)],"black",width:0.65)
                }
            case .greaterCoucal:
                for across in [-0.3,0.0,0.3] {
                    c.line([d.t(0.05,across),d.t(0.98,across)],"navy",width:0.65)
                }
            default: break
            }
        }
    }

    private static func legs(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, hipY=min(35,p.body.y+p.body.height-1.5)
        for x in [27.0,31.0] {
            let hip=(x-0.5+p.body.lean*0.35,hipY)
            let knee=(x-0.6+p.stance,36.1)
            c.line([hip,knee,(x,38.5)],d.raptor ? "yellow":"brown",width:d.raptor ? 1.1:0.95)
            if d.id == .uplandBuzzard {
                // Feathered shanks stay broad even when the belly rises.
                c.poly([(hip.0-1.5,hip.1-1),(hip.0+1.8,hip.1-1),
                        (knee.0+1.3,36.1),(knee.0+0.3,35.5),(knee.0-1.1,36.1)],"buff",outline:true)
                c.line([(hip.0,hip.1),(knee.0,35.2)],"tan",width:0.65)
            } else if d.id == .himalayanVulture {
                c.poly([(hip.0-1.2,hip.1-0.7),(hip.0+1.6,hip.1-0.7),
                        (knee.0+1.1,35.6),(knee.0-1,35.6)],"buff")
            }
        }
    }

    private static func body(_ c:BirdPainter, _ d:Drawing) {
        let edge=d.pose.bodyVertices(anatomy:d.anatomy)
        c.poly(edge,d.colors.back,outline:true)
        c.within(edge) {
            c.poly([d.b(0.6,0.08),d.b(0.96,0.19),d.b(1.08,0.61),
                    d.b(0.76,1.05),d.b(0.4,1),d.b(0.44,0.48)],d.colors.belly)
            switch d.id {
            case .orientalTurtleDove:
                c.poly([d.b(0.64,0.57),d.b(1,0.52),d.b(0.95,0.92),d.b(0.51,1)],"buff")
                c.line([d.b(0.86,0.21),d.b(0.91,0.53)],"pink",width:1.1)
            case .eurasianCollaredDove:
                c.line([d.b(0.69,0.6),d.b(0.6,0.91)],"silver",width:0.7)
            case .uplandBuzzard:
                for row in 0..<3 {
                    for column in 0..<3 {
                        let u=0.66+Double(column)*0.11, v=0.22+Double(row)*0.23
                        c.line([d.b(u,v),d.b(u-0.025,v+0.15)],"brown",width:0.7)
                    }
                }
            case .himalayanVulture:
                for index in 0..<5 {
                    let u=0.57+Double(index)*0.07
                    c.line([d.b(u,0.24),d.b(u-0.05,0.6)],"tan",width:0.7)
                }
                c.line([d.b(0.87,0.61),d.b(0.77,0.91)],"cream",width:0.85)
            case .commonPheasant:
                for row in 0..<3 {
                    for column in 0..<2 {
                        let u=0.67+Double(column)*0.15, v=0.2+Double(row)*0.24
                        c.line([d.b(u-0.05,v),d.b(u,v+0.1),d.b(u+0.06,v+0.02)],"black",width:0.65)
                    }
                }
            case .greaterCoucal:
                c.line([d.b(0.86,0.24),d.b(0.91,0.51)],"navy",width:0.7)
                c.line([d.b(0.66,0.75),d.b(0.59,0.92)],"dark",width:0.65)
            default: break
            }
        }
    }

    private static func neck(_ c:BirdPainter, _ d:Drawing) {
        let edge=d.pose.neckVertices(anatomy:d.anatomy)
        let color=d.id == .himalayanVulture ? "cream":
            (d.id == .commonPheasant ? "green":d.colors.belly)
        c.poly(edge,color,outline:true)
        c.within(edge) {
            switch d.id {
            case .orientalTurtleDove:
                // A striped nape panel distinct from both a solid collar and
                // the spotted-dove pearl patch; sections follow the bent neck.
                c.poly([d.n(0.47,-0.53),d.n(0.91,-0.53),d.n(0.91,0.09),d.n(0.47,0.09)],"black")
                for across in [-0.42,-0.2,0.01] {
                    c.line([d.n(0.53,across),d.n(0.86,across)],"white",width:0.6)
                }
                c.poly([d.n(0,-0.5),d.n(0.42,-0.5),d.n(0.42,-0.29),d.n(0,-0.29)],"brown")
            case .eurasianCollaredDove:
                c.poly([d.n(0.57,-0.54),d.n(0.66,-0.54),d.n(0.66,0.34),d.n(0.57,0.34)],"black")
                c.line([d.n(0.68,-0.49),d.n(0.68,0.28)],"white",width:0.4)
            case .uplandBuzzard:
                c.poly([d.n(0,-0.5),d.n(0.9,-0.5),d.n(0.9,-0.1),d.n(0,-0.1)],"brown")
                for across in [0.05,0.28] {
                    c.line([d.n(0.26,across),d.n(0.66,across)],"brown",width:0.65)
                }
            case .himalayanVulture:
                // Narrow exposed neck, with no feather streaks bridging it.
                c.line([d.n(0.2,-0.3),d.n(0.8,-0.3)],"tan",width:0.45)
            case .commonPheasant:
                c.poly([d.n(0.6,-0.53),d.n(0.72,-0.53),d.n(0.72,0.53),d.n(0.6,0.53)],"white")
                c.line([d.n(0.79,0.24),d.n(0.95,0.24)],"navy",width:0.65)
            case .greaterCoucal:
                c.line([d.n(0.37,-0.35),d.n(0.88,-0.35)],"navy",width:0.75)
            default: break
            }
        }
    }

    private static func ruff(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy, edge=p.ruffVertices(anatomy:a)
        c.poly(edge,"cream",outline:true)
        c.within(edge) {
            c.poly([p.ruffPoint(-1,0,anatomy:a),p.ruffPoint(-0.6,-0.8,anatomy:a),
                    p.ruffPoint(0.6,-0.8,anatomy:a),p.ruffPoint(1,0,anatomy:a),
                    p.ruffPoint(0.5,0.5,anatomy:a),p.ruffPoint(-0.5,0.5,anatomy:a)],"white")
            for across in [-0.7,-0.35,0.0,0.35,0.7] {
                c.line([p.ruffPoint(across,-0.3,anatomy:a),
                        p.ruffPoint(across+0.08,0.55,anatomy:a)],"silver",width:0.45)
            }
        }
    }

    private static func wing(_ c:BirdPainter, _ d:Drawing, far:Bool) {
        func w(_ u:Double, _ v:Double) -> Point { d.pose.wingPoint(u,v,anatomy:d.anatomy,far:far) }
        let edge=d.pose.wingVertices(anatomy:d.anatomy,far:far)
        let primary=d.id == .himalayanVulture ? "black":d.colors.wing
        c.poly(edge,far ? d.colors.back:primary,outline:true)
        c.within(edge) {
            let coverts=d.id == .greaterCoucal ? "rust":d.colors.back
            c.poly([w(-0.48,0.1),w(-0.03,0),w(0.54,0.15),
                    w(0.5,0.55),w(-0.26,0.66)],coverts)
            for index in 0..<5 {
                let u = -0.08+Double(index)*0.17
                c.line([w(u,0.3),w(u+0.25,1)],d.featherEdge,width:0.65)
            }
            switch d.id {
            case .orientalTurtleDove:
                // Nine scaled coverts on this species' broad rounded wing.
                for row in 0..<3 {
                    for column in 0..<3 {
                        let u = -0.28+Double(column)*0.23+Double(row%2)*0.07
                        let v=0.16+Double(row)*0.19
                        c.poly([w(u-0.1,v),w(u+0.1,v),w(u+0.08,v+0.16),w(u,v+0.21),w(u-0.1,v+0.15)],"umber")
                        c.line([w(u-0.1,v+0.13),w(u,v+0.21),w(u+0.08,v+0.14)],"tan",width:0.65)
                    }
                }
            case .eurasianCollaredDove:
                // Smooth gray coverts, without the turtle dove's scale pattern.
                c.poly([w(-0.4,0.13),w(0.05,0.04),w(0.5,0.22),w(0.39,0.54),w(-0.24,0.59)],"gray")
                c.line([w(-0.21,0.6),w(0.62,0.75)],"silver",width:0.7)
            case .uplandBuzzard:
                c.poly([w(0.28,0.35),w(0.58,0.35),w(0.76,0.55),w(0.5,0.66),w(0.28,0.56)],"umber")
                c.line([w(0.23,0.65),w(0.82,0.78)],"buff",width:0.8)
                c.line([w(0.39,0.82),w(0.83,0.95)],"brown",width:0.8)
            case .himalayanVulture:
                c.poly([w(-0.27,0.35),w(0.5,0.25),w(0.74,0.66),w(0.38,0.9),w(-0.26,0.67)],"umber")
                for index in 0..<6 {
                    let u = -0.3+Double(index)*0.13
                    c.line([w(u,0.12),w(u+0.07,0.53)],"tan",width:0.7)
                }
                c.line([w(-0.3,0.53),w(0.5,0.45)],"buff",width:0.85)
            case .commonPheasant:
                for row in 0..<3 {
                    for column in 0..<3 {
                        let u = -0.26+Double(column)*0.24, v=0.18+Double(row)*0.22
                        c.line([w(u-0.08,v),w(u,v+0.13),w(u+0.12,v+0.03)],"tan",width:0.7)
                    }
                }
            case .greaterCoucal:
                c.poly([w(-0.4,0.1),w(0.1,0.04),w(0.53,0.24),w(0.39,0.66),w(-0.25,0.7)],"rust")
                for u in [-0.2,0.06,0.32] {
                    c.line([w(u,0.28),w(u+0.15,0.65)],"orange",width:0.55)
                }
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
        c.oval(x,y,width,height,d.colors.head,outline:true)
        c.ctx.saveGState()
        c.ctx.addEllipse(in:CGRect(x:x,y:y,width:width,height:height)); c.ctx.clip()
        c.pigment {
            switch d.id {
            case .orientalTurtleDove:
                c.poly([(x+1,0),(width/2-0.3,-0.2),(width/2-0.6,height*0.35),(x+2,height*0.48)],"pink")
                c.line([(x+0.7,y+1.5),(x+3.6,y+0.7)],"silver",width:0.65)
            case .eurasianCollaredDove:
                c.poly([(x+1,0),(width/2-0.4,-0.2),(width/2-0.5,height*0.35),(x+2,height*0.46)],"cream")
                c.line([(x+0.8,y+1.2),(x+3.8,y+0.7)],"buff",width:0.6)
            case .uplandBuzzard:
                c.poly([(x,y),(x+2,y+0.7),(x+3,0.2),(x+1,height*0.31)],"brown")
                c.line([(x+1,y+1.5),(width/2-1,y+1.9)],"umber",width:0.7)
                c.line([(x+2,1),(x+3.5,2.7)],"tan",width:0.65)
            case .himalayanVulture:
                c.line([(x+0.7,y+1.4),(x+2.5,y+0.8)],"tan",width:0.55)
                c.line([(x+1.2,0.6),(x+2.3,2.4)],"buff",width:0.55)
            case .commonPheasant:
                c.poly([(x+0.5,y+2),(width/2,y+2.2),(width/2,1.8),(x+1.3,2.5)],"red")
                c.line([(x+0.8,y+1.2),(x+3.5,y+0.5)],"navy",width:0.7)
            case .greaterCoucal:
                c.line([(x+0.8,y+1.8),(x+4,y+0.7)],"navy",width:0.75)
            default: break
            }
        }
        c.ctx.restoreGState()
        let bill=p.billVertices(anatomy:a)
        if p.gape > 0, let tip=bill.last {
            let root=width/2-0.4
            c.poly([(root,0.7),(tip.0,1.5+p.gape*2.1),(root,1.8+p.gape*1.4)],"eye")
            c.poly(p.lowerBillVertices(anatomy:a),d.colors.bill,outline:true)
        }
        c.poly(bill,d.colors.bill,outline:d.raptor || d.id == .greaterCoucal)
        if d.id == .uplandBuzzard {
            c.pigment { c.oval(width/2-0.6,-1,1.4,1.8,"yellow") }
        }
        let ex=width*0.2+p.turn*0.45, ey = -height*0.12
        c.pigment {
            if d.id == .greaterCoucal { c.oval(ex-0.65,ey-0.65,2.3,2.3,"red") }
            if d.frame == "restLower" || d.frame == "restTuck" {
                c.line([(ex-0.2,ey+0.5),(ex+0.4,ey+0.7),(ex+1,ey+0.4)],"eye",width:0.7)
            } else {
                c.oval(ex,ey,1,1.1,"eye")
                c.oval(ex+0.4,ey,0.4,0.4,"white")
            }
        }
        c.ctx.restoreGState()
    }

    private static func scapularFold(_ c:BirdPainter, _ d:Drawing) {
        let root=d.b(d.anatomy.shoulderU,0.15), x=root.0, y=root.1
        c.poly([(x-1.7,y+1),(x,y-0.6),(x+1.5,y+0.2),(x+2.9,y-0.4),
                (x+4,y+2.5),(x+1.8,y+3.4),(x-1,y+3)],d.colors.back)
        c.line([(x-0.5,y+1),(x+1.2,y+2),(x+2.8,y+1.3)],d.featherEdge,width:0.65)
    }
}
