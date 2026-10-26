import AppKit
import BirdingCore

/// E4 original paths only, at each species' native catalog density. These are
/// stylized idle/presentation drawings, without water, props or contact targets.
enum ExpansionWetlandArt {
    private typealias Geometry = ExpansionWetlandArtGeometry
    private typealias Point = (Double,Double)

    private struct Drawing {
        let species: SpeciesID
        let frame: String
        let pose: Geometry.Pose
        let anatomy: Geometry.Anatomy
        let colors: ExpansionBirdArt.Anatomy

        func b(_ u:Double, _ v:Double) -> Point { pose.bodyPoint(u,v,anatomy:anatomy) }

        var legColor: String {
            switch species {
            case .easternSpotBilledDuck: return "orange"
            case .ruddyShelduck, .easternCattleEgret: return "dark"
            case .blackTailedGull: return "yellow"
            default: return "brown"
            }
        }

        var featherEdge: String {
            switch species {
            case .easternSpotBilledDuck: return "tan"
            case .ruddyShelduck: return "silver"
            case .easternCattleEgret, .blackTailedGull: return "silver"
            case .greatCrestedGrebe: return "brown"
            default: return "umber"
            }
        }
    }

    static func image(_ frame:String, species:SpeciesID) -> CGImage? {
        guard let a=Geometry.anatomy(for:species),
              let p=Geometry.pose(species:species,frame:frame),
              let colors=ExpansionBirdArt.profiles[species] else { return nil }
        let density=SpeciesCatalog.standard.profile(species).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let d=Drawing(species:species,frame:frame,pose:p,anatomy:a,colors:colors)
        support(c,d)
        tail(c,d)
        if p.wing > 0.16 { wing(c,d,far:true) }
        torso(c,d)
        neck(c,d)
        wing(c,d,far:false)
        head(c,d)
        return c.image
    }

    private static func support(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy, paths=Geometry.toePaths(for:d.species)
        for (index,path) in paths.enumerated() {
            let ankle=path[1], hip:Point, hock:Point, width:Double
            let bias=index == 0 ? p.balance : -p.balance
            switch a.support {
            case .rearGrebe:
                // The low, short shanks attach behind the shoulder. These are
                // independently authored rear supports, not shortened duck legs.
                hip=d.b(index == 0 ? 0.48:0.64,0.82)
                hock=(ankle.0-1.8+p.stance+bias,37.2)
                width=0.85
            case .egret:
                hip=d.b(index == 0 ? 0.62:0.8,0.83)
                hock=(ankle.0-0.7+p.stance+bias,hip.1+(38.5-hip.1)*0.5)
                width=0.75
            case .gull:
                hip=d.b(index == 0 ? 0.67:0.82,0.83)
                hock=(ankle.0-0.6+p.stance+bias,36.4)
                width=0.9
            case .webbed:
                hip=d.b(index == 0 ? 0.65:0.8,0.83)
                hock=(ankle.0-0.8+p.stance+bias,37.1)
                width=1
            }
            c.line([hip,hock,ankle],d.legColor,width:width)
            switch a.support {
            case .webbed:
                c.poly([(ankle.0-0.5,37.6),path[0],path[2],
                        (ankle.0+0.5,37.6)],d.legColor)
                c.line([ankle,path[0]],"outline",width:0.45)
            case .gull:
                c.poly([(ankle.0-0.3,38),path[0],path[2],
                        (ankle.0+0.5,38)],d.legColor)
            case .rearGrebe:
                // Short separated toe strokes on dry support; no paddling,
                // waterline, duck web or detached/lifted foot is introduced.
                c.line([ankle,(ankle.0-1.3,38)],d.legColor,width:0.6)
            case .egret:
                c.line([ankle,(ankle.0-1.7,38)],d.legColor,width:0.6)
            }
            c.line(path,d.legColor,width:0.7)
        }
    }

    private static func tail(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy, tx=p.tail.x, ty=p.tail.y
        let edge:[Point]
        let fill:String
        switch d.species {
        case .easternSpotBilledDuck:
            edge=[d.b(0.24,0.39),(tx-1,ty-1.1),(tx+a.tailWidth,ty-0.5),d.b(0.3,0.79)]
            fill="umber"
        case .ruddyShelduck:
            edge=[d.b(0.24,0.4),(tx-0.8,ty-1.3),(tx+0.5,ty+0.5),
                  (tx+a.tailWidth,ty+0.1),d.b(0.32,0.81)]
            fill="black"
        case .easternCattleEgret:
            edge=[d.b(0.28,0.4),(tx-0.5,ty-0.8),(tx+a.tailWidth,ty+0.5),d.b(0.4,0.86)]
            fill="white"
        case .blackTailedGull:
            edge=[d.b(0.28,0.39),(tx-0.6,ty-0.8),(tx+0.4,ty+1),
                  (tx+a.tailWidth,ty+0.7),d.b(0.36,0.84)]
            fill="white"
        case .greatCrestedGrebe:
            // An inconspicuous feather tuft, not a projecting passerine tail.
            edge=[d.b(0.14,0.35),(tx-0.7,ty-1.2),(tx,ty+0.5),
                  (tx+1,ty+1.1),(tx+a.tailWidth,ty+0.4),d.b(0.22,0.83)]
            fill="brown"
        default:
            // The little grebe's rounded, downy rump has its own movable lobes.
            let puff=p.ruffle*0.7
            edge=[d.b(0.14,0.28),(tx-0.9-puff,ty-1.6),
                  (tx-1.2-puff,ty-0.2),(tx-0.1,ty+0.8+puff),
                  (tx+1.5,ty+1.3),(tx+a.tailWidth,ty+0.4),d.b(0.25,0.84)]
            fill="umber"
        }
        c.poly(edge,fill,outline:true)
        c.within(edge) {
            c.line([d.b(0.2,0.48),(tx+0.5,ty-0.2)],d.featherEdge,width:0.65)
            if d.species == .blackTailedGull {
                // A broad black subterminal band and narrow white end follow
                // the moving tail's end rather than fixed canvas coordinates.
                c.poly([(tx-0.4,ty-0.65),(tx+a.tailWidth-0.5,ty+0.05),
                        (tx+a.tailWidth-0.2,ty+0.9),(tx+0.2,ty+1.05)],"black")
                c.line([(tx+0.5,ty+0.8),(tx+a.tailWidth-0.4,ty+0.55)],"white",width:0.65)
            } else if d.species == .littleGrebe {
                c.line([(tx+0.3,ty-0.2),(tx+1.5,ty+0.7)],"buff",width:0.65)
            }
        }
    }

    private static func torso(_ c:BirdPainter, _ d:Drawing) {
        let edge=d.anatomy.bodyContour.map { d.b($0.0,$0.1) }
        c.poly(edge,d.colors.back,outline:true)
        c.within(edge) {
            c.poly([d.b(0.58,0.1),d.b(0.93,0.13),d.b(1.06,0.66),
                    d.b(0.73,1.04),d.b(0.32,0.99),d.b(0.44,0.49)],d.colors.belly)
            switch d.species {
            case .easternSpotBilledDuck:
                for i in 0..<7 {
                    let u=0.55+Double(i%4)*0.095, v=0.43+Double(i/4)*0.22
                    c.line([d.b(u,v),d.b(u+0.025,v+0.13)],"brown",width:0.65)
                }
                c.line([d.b(0.2,0.8),d.b(0.48,0.92)],"tan",width:0.75)
            case .ruddyShelduck:
                c.line([d.b(0.73,0.23),d.b(0.86,0.59)],"buff",width:0.7)
                c.poly([d.b(0.1,0.15),d.b(0.29,0.06),d.b(0.38,0.3),d.b(0.17,0.47)],"rust")
            case .easternCattleEgret:
                c.poly([d.b(0.37,0.08),d.b(0.71,0.04),d.b(0.8,0.25),
                        d.b(0.61,0.43),d.b(0.4,0.33)],"buff")
                c.line([d.b(0.78,0.49),d.b(0.7,0.86)],"silver",width:0.6)
            case .blackTailedGull:
                c.poly([d.b(0.14,0.21),d.b(0.48,0.02),d.b(0.7,0.14),
                        d.b(0.64,0.39),d.b(0.23,0.62)],"slate")
                c.line([d.b(0.85,0.42),d.b(0.79,0.8)],"silver",width:0.65)
            case .greatCrestedGrebe:
                c.line([d.b(0.6,0.65),d.b(0.83,0.67),d.b(0.91,0.49)],"silver",width:0.65)
                c.line([d.b(0.24,0.8),d.b(0.47,0.9)],"tan",width:0.65)
            case .littleGrebe:
                c.poly([d.b(0.6,0.12),d.b(0.93,0.16),d.b(0.99,0.41),d.b(0.78,0.5)],"rust")
                c.line([d.b(0.12,0.63),d.b(0.21,0.84),d.b(0.4,0.9)],"tan",width:0.7)
            default: break
            }
        }
        if d.pose.ruffle > 0 {
            // Three local scapular tips are newly drawn anatomy, not particles
            // or whole-body inflation. Their position follows the shoulder.
            for i in 0..<3 {
                let root=d.b(0.22+Double(i)*0.14,0.14)
                c.poly([(root.0-1,root.1+0.6),(root.0,root.1-d.pose.ruffle),
                        (root.0+1.3,root.1+0.8)],d.colors.back)
            }
        }
    }

    private static func neck(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy, path=p.neckPath(anatomy:a)
        let fill:String
        switch d.species {
        case .easternCattleEgret: fill="buff"
        case .ruddyShelduck: fill="orange"
        default: fill=d.colors.belly
        }
        c.curve(path,"outline",width:a.neckWidth+Double(c.unit)*2)
        c.curve(path,fill,width:a.neckWidth)
        c.pigment {
            switch d.species {
            case .ruddyShelduck:
                let upper=(0...12).map { p.neckPoint(0.42+Double($0)*0.58/12,anatomy:a) }
                c.line(upper,"buff",width:a.neckWidth-0.5)
                c.line(p.neckCrossSection(0.73,anatomy:a),"black",width:0.8)
            case .easternSpotBilledDuck:
                let stripe=(0...12).map { i -> Point in
                    let cut=p.neckCrossSection(Double(i)/12,anatomy:a)
                    return ((cut[0].0+cut[1].0)/2,(cut[0].1+cut[1].1)/2)
                }
                c.line(stripe,"tan",width:0.9)
            case .easternCattleEgret:
                let front=(0...12).map { i -> Point in
                    let cut=p.neckCrossSection(Double(i)/12,anatomy:a)
                    return ((cut[1].0+cut[2].0)/2,(cut[1].1+cut[2].1)/2)
                }
                c.line(front,"cream",width:0.8)
            case .greatCrestedGrebe:
                let rear=(0...14).map { i -> Point in
                    let cut=p.neckCrossSection(Double(i)/14,anatomy:a)
                    return (cut[0].0*0.7+cut[1].0*0.3,cut[0].1*0.7+cut[1].1*0.3)
                }
                c.line(rear,"brown",width:0.7)
            case .littleGrebe:
                let throat=(0...12).map { p.neckPoint(0.3+Double($0)*0.7/12,anatomy:a) }
                c.line(throat,"rust",width:a.neckWidth*0.65)
            case .blackTailedGull:
                let front=(0...12).map { i -> Point in
                    let cut=p.neckCrossSection(Double(i)/12,anatomy:a)
                    return (cut[2].0*0.65+cut[1].0*0.35,cut[2].1*0.65+cut[1].1*0.35)
                }
                c.line(front,"silver",width:0.55)
            default: break
            }
        }
    }

    private static func wing(_ c:BirdPainter, _ d:Drawing, far:Bool) {
        let p=d.pose, a=d.anatomy, open=p.wing
        let root=d.b(far ? 0.62:0.44,0.13)
        func w(_ u:Double, _ v:Double) -> Point {
            let side=far ? 0.49 : -1.0
            return (root.0+side*u*(4+a.wingReach*open)+v*open*1.6,
                    root.1+v*(a.primaryLength*(1-open)+5.4*open)-u*open*17)
        }
        let edge=a.wingContour.map { w($0.0,$0.1) }
        c.poly(edge,far ? d.colors.back:d.colors.wing,outline:true)
        c.within(edge) {
            let coverts=d.species == .ruddyShelduck ? "white":d.colors.back
            c.poly([w(-0.54,0.12),w(-0.09,0.02),w(0.47,0.18),
                    w(0.39,0.53),w(-0.35,0.61)],coverts)
            if d.species == .ruddyShelduck || d.species == .blackTailedGull {
                c.poly([w(0.45,0.45),w(0.81,0.56),w(1,0.99),
                        w(0.59,1.04),w(0.3,0.86)],"black")
            }
            for i in 0..<4 {
                let u = -0.12+Double(i)*0.21
                c.line([w(u,0.32),w(u+0.27,0.98)],d.featherEdge,width:0.65)
            }
            switch d.species {
            case .easternSpotBilledDuck:
                c.poly([w(-0.18,0.51),w(0.48,0.56),w(0.62,0.74),w(-0.05,0.7)],"navy")
                c.line([w(-0.2,0.49),w(0.49,0.55)],"white",width:0.7)
                c.line([w(-0.05,0.72),w(0.61,0.76)],"white",width:0.75)
                for i in 0..<3 {
                    let u = -0.3+Double(i)*0.24
                    c.line([w(u,0.18),w(u+0.13,0.4)],"tan",width:0.65)
                }
            case .ruddyShelduck:
                c.poly([w(0.01,0.5),w(0.5,0.55),w(0.62,0.73),w(0.11,0.72)],"green")
                c.line([w(-0.33,0.15),w(0.28,0.25)],"cream",width:0.65)
            case .easternCattleEgret:
                c.poly([w(-0.4,0.12),w(0.24,0.13),w(0.37,0.35),w(-0.26,0.42)],"buff")
                c.line([w(-0.1,0.42),w(0.62,0.94)],"silver",width:0.65)
            case .blackTailedGull:
                c.line([w(-0.18,0.72),w(0.66,0.88)],"white",width:0.9)
                c.oval(w(0.81,0.97).0-0.6,w(0.81,0.97).1-0.4,1.1,0.85,"white")
            case .greatCrestedGrebe:
                c.line([w(-0.23,0.51),w(0.58,0.63)],"cream",width:0.7)
            case .littleGrebe:
                c.line([w(-0.31,0.35),w(0.41,0.46)],"tan",width:0.65)
                c.line([w(0.09,0.53),w(0.76,0.93)],"umber",width:0.75)
            default: break
            }
        }
    }

    private static func head(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy, w=p.headWidth(anatomy:a), h=a.headHeight
        let x = -w/2, y = -h/2
        c.ctx.saveGState()
        c.ctx.translateBy(x:p.head.x,y:p.head.y)
        c.ctx.rotate(by:CGFloat(p.head.pitch))
        if d.species == .greatCrestedGrebe {
            // Double crest and flared rusty cheek collar share the head joint.
            // The ornament remains compact even in alert and tucked poses.
            c.poly([(x+0.5,y+1.8),(x-1.5,y-3),(x+1.3,y-0.5),
                    (x+3.3,y-2.7),(x+4.5,y+1.2)],"black",outline:true)
            let ruff:[Point]=[(x-1.2,0.2),(x+1.3,-0.3),(w/2-0.2,0.5),
                              (w*0.21,h*0.78),(x+0.5,h*0.9),(x-1.7,h*0.58)]
            c.poly(ruff,"rust",outline:true)
            c.within(ruff) {
                c.line([(x-0.9,1.2),(x-0.9,h*0.55),(x+1.1,h*0.77)],"black",width:1.1)
            }
        }

        let edge=a.headContour.map { ($0.0*w,$0.1*h) }
        c.poly(edge,d.colors.head,outline:true)
        c.within(edge) {
            switch d.species {
            case .easternSpotBilledDuck:
                c.poly([(x,-h*0.22),(w/2,-h*0.16),(w/2,h*0.07),(x+1,h*0.13)],"umber")
                c.line([(x+0.7,y+1.6),(w/2-0.6,y+1.3)],"cream",width:0.9)
                c.poly([(x+1,h*0.16),(w*0.43,h*0.09),(w*0.33,h*0.38),(x+2,h*0.48)],"buff")
            case .ruddyShelduck:
                c.line([(x+0.9,y+1.7),(w*0.31,y+1)],"cream",width:0.7)
                c.poly([(x+1,h*0.13),(w*0.43,h*0.08),(w*0.3,h*0.4),(x+2,h*0.46)],"buff")
            case .easternCattleEgret:
                c.line([(x+0.7,y+1.5),(x+3.5,y+0.8)],"orange",width:0.7)
                c.poly([(x+1,h*0.13),(w*0.42,h*0.07),(w*0.3,h*0.4),(x+2,h*0.46)],"cream")
                c.line([(w*0.17,-0.4),(w*0.47,-0.2)],"yellow",width:0.7)
            case .blackTailedGull:
                c.line([(x+0.9,y+1.4),(x+4,y+0.9)],"silver",width:0.6)
            case .greatCrestedGrebe:
                c.poly([(x+0.5,-0.1),(w*0.46,-h*0.02),(w*0.33,h*0.38),(x+1.5,h*0.49)],"white")
                c.line([(x+0.6,y+0.9),(w*0.29,y+0.8)],"umber",width:0.7)
            case .littleGrebe:
                c.poly([(x+0.9,h*0.11),(w*0.45,h*0.03),(w*0.34,h*0.38),(x+1.8,h*0.48)],"rust")
                c.oval(w/2-1.9,h*0.05,2,1.4,"yellow")
            default: break
            }
        }

        let bill=p.billVertices(anatomy:a), root=bill[0].0, length=bill[2].0-root
        c.poly(bill,d.colors.bill)
        c.within(bill) {
            // Colored tip bands are head-local and clipped to the actual bill.
            // No stripe, tip or highlight creates an unreported extra endpoint.
            if d.species == .easternSpotBilledDuck {
                c.poly([(root+length*0.67,-2),(root+length+0.2,-2),
                        (root+length+0.2,3),(root+length*0.67,3)],"yellow")
            } else if d.species == .blackTailedGull {
                c.poly([(root+length*0.58,-2),(root+length*0.82,-2),
                        (root+length*0.82,3),(root+length*0.58,3)],"black")
                c.poly([(root+length*0.82,-2),(root+length+0.2,-2),
                        (root+length+0.2,3),(root+length*0.82,3)],"red")
            }
            if a.bill == .spatulate {
                c.oval(root+length*0.23,-0.05,0.8,0.45,"eye")
                c.line([(root+0.4,0.7),(root+length*0.6,0.8)],"outline",width:0.45)
            }
        }

        let ex=w*0.21-p.turn*0.6, ey = -h*0.12
        c.within(edge) {
            if d.species == .greatCrestedGrebe {
                c.oval(ex-0.6,ey-0.6,2.1,2.1,"red")
            } else if d.species == .blackTailedGull {
                c.oval(ex-0.55,ey-0.55,2,2,"yellow")
            }
            if d.frame == "restTuck" {
                c.line([(ex-0.25,ey+0.3),(ex+0.35,ey+0.65),(ex+1,ey+0.3)],"eye",width:0.7)
            } else {
                c.oval(ex,ey,1,1.05,"eye")
                c.oval(ex+0.4,ey,0.4,0.4,"white")
            }
        }
        c.ctx.restoreGState()
    }
}
