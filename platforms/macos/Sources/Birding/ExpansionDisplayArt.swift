import AppKit
import BirdingCore

/// E3's additional source drawings. Historical ExpansionBirdArt frames are never
/// used as pixels; only their species palettes supply the established colours.
enum ExpansionDisplayArt {
    private typealias Geometry = ExpansionDisplayArtGeometry
    private typealias Point = (Double,Double)

    private struct Drawing {
        let species: SpeciesID
        let frame: String
        let pose: Geometry.Pose
        let anatomy: Geometry.Anatomy
        let colors: ExpansionBirdArt.Anatomy

        func bodyPoint(_ u:Double, _ v:Double) -> Point {
            let b=pose.body, width=anatomy.width+b.fluff
            return (34-anatomy.width-b.fluff/2+width*u+b.lean*(1-v),
                    b.y+b.height*v)
        }

        func headPoint(_ x:Double, _ y:Double) -> Point { pose.headPoint(x,y) }

        var tailColor: String { species == .greyTreepie ? "gray" : colors.wing }
        var legs: String {
            switch species {
            case .redBilledBlueMagpie, .yellowBilledBlueMagpie, .blackBulbul: return "red"
            default: return "brown"
            }
        }
    }

    static func image(_ frame:String, species:SpeciesID) -> CGImage? {
        guard let anatomy=Geometry.anatomy(for:species),
              let pose=Geometry.pose(species:species,frame:frame),
              let colors=ExpansionBirdArt.profiles[species] else { return nil }
        let density=SpeciesCatalog.standard.profile(species).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let d=Drawing(species:species,frame:frame,pose:pose,anatomy:anatomy,colors:colors)
        tail(c,d)
        feet(c,d)
        if pose.wing > 0.18 { wing(c,d,far:true) }
        body(c,d)
        neck(c,d)
        wing(c,d,far:false)
        flankMarks(c,d)
        head(c,d)
        return c.image
    }

    private static func feet(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose
        for x in [27.0,31.0] {
            let hipY=min(35.6,p.body.y+p.body.height-1.6)
            c.line([(x-0.7+p.body.lean*0.3,hipY),
                    (x-0.6+p.stance,36.7),(x,38.5)],d.legs,width:0.9)
        }
        for toes in Geometry.toePaths { c.line(toes,d.legs,width:0.75) }
    }

    /// A feather is a fresh tapered polygon between moving anatomical endpoints.
    /// Its terminal bands use that same axis, staying attached at every tail angle.
    private static func feather(_ c:BirdPainter, root:Point, tip:Point, width:Double,
                                color:String, shaft:String, band:String? = nil,
                                cap:String? = nil) {
        let dx=tip.0-root.0, dy=tip.1-root.1, length=max(0.1,hypot(dx,dy))
        let nx = -dy/length, ny=dx/length
        func f(_ t:Double, _ across:Double) -> Point {
            (root.0+dx*t+nx*across,root.1+dy*t+ny*across)
        }
        let edge=[f(0,-width*0.38),f(0.45,-width*0.58),f(0.96,-width*0.45),
                  f(1,0),f(0.96,width*0.45),f(0.42,width*0.58),f(0,width*0.38)]
        c.poly(edge,color,outline:true)
        c.within(edge) {
            c.line([f(0.08,0),f(0.93,0)],shaft,width:0.5)
            if let band {
                c.poly([f(0.79,-width),f(1,-width),f(1,width),f(0.79,width)],band)
            }
            if let cap {
                c.poly([f(0.94,-width),f(1.02,-width),f(1.02,width),f(0.94,width)],cap)
            }
        }
    }

    private static func tail(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy, tx=p.tail.x, ty=p.tail.y
        let root=d.bodyPoint(0.25,0.62)
        switch d.species {
        case .ashyDrongo, .blackBulbul:
            let drongo=d.species == .ashyDrongo
            let half=a.tailWidth/2+p.spread*(drongo ? 1.7:0.8)
            let notch=drongo ? 8.5+p.spread*1.5 : 2.1+p.spread
            // A concave silhouette leaves the central fork genuinely empty.
            // All feather detail is clipped, so it cannot bridge the notch.
            let edge=[root,(tx+0.9,ty-half*0.85),(tx,ty-half),
                      (tx+notch,ty),(tx,ty+half),(tx+1.2,ty+half*0.8),
                      (root.0+4.2,root.1+3.4)]
            c.poly(edge,d.tailColor,outline:true)
            c.within(edge) {
                c.line([(root.0+0.3,root.1+0.2),(tx+1,ty-half+0.5)],drongo ? "gray":"slate",width:0.65)
                c.line([(root.0+3.5,root.1+2.8),(tx+1,ty+half-0.6)],drongo ? "gray":"slate",width:0.6)
            }
        case .redBilledBlueMagpie, .yellowBilledBlueMagpie:
            let red=d.species == .redBilledBlueMagpie
            // Outer rectrices are shorter; the two species have separately
            // authored step lengths and lateral spread, not recoloured rasters.
            for index in [-2,2,-1,1,0] {
                let i=Double(index), step=abs(i)
                let end=(tx+step*(red ? 2.4:2.1)+i*p.spread*0.25,
                         ty-step*(red ? 3.2:2.9)+i*p.spread*0.65)
                let start=d.bodyPoint(0.22+i*0.045,0.61+i*0.012)
                feather(c,root:start,tip:end,width:1.65+p.spread*0.3,
                        color:"blue",shaft:red ? "cyan":"navy",band:"black",cap:"white")
            }
        case .eurasianMagpie:
            for i in (0..<3).reversed() {
                let n=Double(i)
                feather(c,root:(root.0+n*1.1,root.1+n*0.7),
                        tip:(tx+n*(1.6+p.spread),ty-n*0.7),
                        width:1.9+p.spread*0.4,color:"navy",shaft:i == 1 ? "green":"blue")
            }
        case .greyTreepie:
            for i in (0..<4).reversed() {
                let n=Double(i)
                feather(c,root:(root.0+n*0.95,root.1+n*0.65),
                        tip:(tx+n*(1.35+p.spread*0.6),ty-n*(1+p.spread*0.5)),
                        width:1.8+p.spread*0.4,color:"gray",shaft:"slate",band:"black")
            }
        case .blueWhistlingThrush:
            for index in [-2,2,-1,1,0] {
                let i=Double(index)
                feather(c,root:(root.0+i*0.4,root.1+i*0.35),
                        tip:(tx+abs(i)*0.85,ty+i*(0.8+p.spread*2)),
                        width:2,color:"blue",shaft:"navy")
            }
        case .sootyHeadedBulbul:
            for index in [3,2,1,0] {
                let i=Double(index)
                feather(c,root:(root.0+i*0.9,root.1+i*0.4),
                        tip:(tx+i*1.1,ty+i*(0.35+p.spread*0.6)),
                        width:1.95,color:"umber",shaft:"brown",cap:"white")
            }
        case .brownBreastedBulbul:
            for index in [3,2,1,0] {
                let i=Double(index)
                feather(c,root:(root.0+i,root.1+i*0.5),
                        tip:(tx+i*1.3,ty-i*(0.3+p.spread*0.7)),
                        width:2.2,color:"umber",shaft:"tan")
            }
        case .collaredFinchbill:
            for index in [2,1,0] {
                let i=Double(index)
                feather(c,root:(root.0+i*1.2,root.1+i*0.6),
                        tip:(tx+i*(1.8+p.spread),ty-i*0.4),
                        width:2.3,color:"green",shaft:"olive",band:"black")
            }
        case .taiwanBarbet:
            for index in [2,1,0] {
                let i=Double(index)
                feather(c,root:(root.0+i*1.2,root.1+i*0.4),
                        tip:(tx+i*1.7,ty+i*(0.4+p.spread)),
                        width:2.4,color:"green",shaft:"olive")
            }
        case .blueThroatedBarbet:
            for index in [3,2,1,0] {
                let i=Double(index)
                feather(c,root:(root.0+i,root.1+i*0.4),
                        tip:(tx+i*1.5,ty-i*(0.25+p.spread*0.8)),
                        width:2.3,color:"green",shaft:"dark")
            }
        default: break
        }
    }

    private static func bodyEdge(_ d:Drawing) -> [Point] {
        // Individual shoulder, rump and keel contours preserve the source
        // proportions, including the blue magpies' small body / very long tail.
        let form:[Point]
        switch d.species {
        case .eurasianMagpie:
            form=[(0,0.59),(0.13,0.28),(0.43,0.01),(0.72,0),
                  (0.94,0.22),(1,0.5),(0.9,0.8),(0.67,1),(0.36,0.98),(0.1,0.81)]
        case .greyTreepie:
            form=[(0,0.61),(0.1,0.3),(0.39,0.04),(0.7,0),
                  (0.93,0.18),(1,0.47),(0.94,0.75),(0.73,0.98),(0.4,1),(0.12,0.84)]
        case .redBilledBlueMagpie:
            form=[(0,0.66),(0.16,0.26),(0.46,0),(0.75,0.03),
                  (0.96,0.25),(1,0.52),(0.85,0.84),(0.6,1),(0.3,0.93),(0.07,0.79)]
        case .yellowBilledBlueMagpie:
            form=[(0,0.62),(0.12,0.29),(0.42,0.02),(0.71,0),
                  (0.95,0.2),(1,0.48),(0.91,0.8),(0.66,1),(0.34,0.96),(0.08,0.82)]
        case .ashyDrongo:
            form=[(0,0.65),(0.16,0.27),(0.48,0),(0.74,0.04),
                  (0.95,0.23),(1,0.52),(0.88,0.82),(0.63,1),(0.35,0.93),(0.1,0.83)]
        case .blueWhistlingThrush:
            form=[(0,0.52),(0.07,0.23),(0.32,0.02),(0.66,0),
                  (0.91,0.18),(1,0.47),(0.95,0.79),(0.75,0.98),
                  (0.44,1),(0.17,0.88),(0.03,0.7)]
        case .sootyHeadedBulbul:
            form=[(0,0.57),(0.1,0.27),(0.37,0.02),(0.67,0),
                  (0.92,0.21),(1,0.51),(0.9,0.82),(0.66,1),(0.35,0.97),(0.1,0.81)]
        case .brownBreastedBulbul:
            form=[(0,0.55),(0.08,0.25),(0.34,0),(0.66,0.02),
                  (0.91,0.19),(1,0.48),(0.94,0.78),(0.73,1),(0.4,0.98),(0.12,0.83)]
        case .blackBulbul:
            form=[(0,0.64),(0.14,0.28),(0.45,0),(0.71,0.02),
                  (0.94,0.2),(1,0.5),(0.9,0.8),(0.66,1),(0.34,0.96),(0.08,0.83)]
        case .collaredFinchbill:
            form=[(0,0.49),(0.07,0.2),(0.33,0),(0.66,0.01),
                  (0.9,0.19),(1,0.48),(0.96,0.76),(0.77,0.96),
                  (0.46,1),(0.18,0.88),(0.03,0.69)]
        case .taiwanBarbet:
            form=[(0,0.47),(0.06,0.19),(0.3,0),(0.64,0.01),
                  (0.9,0.18),(1,0.46),(0.97,0.76),(0.8,0.97),
                  (0.49,1),(0.2,0.9),(0.04,0.71)]
        default: // Blue-throated barbet: wider shoulder, longer primary cover.
            form=[(0,0.5),(0.08,0.21),(0.35,0),(0.68,0.03),
                  (0.92,0.22),(1,0.51),(0.94,0.81),(0.73,1),
                  (0.42,0.99),(0.15,0.86),(0.02,0.68)]
        }
        return form.map { d.bodyPoint($0.0,$0.1) }
    }

    private static func body(_ c:BirdPainter, _ d:Drawing) {
        let edge=bodyEdge(d)
        c.poly(edge,d.colors.back,outline:true)
        c.within(edge) {
            c.poly([d.bodyPoint(0.61,0.08),d.bodyPoint(0.94,0.16),
                    d.bodyPoint(1.07,0.65),d.bodyPoint(0.74,1.05),
                    d.bodyPoint(0.4,0.98),d.bodyPoint(0.48,0.43)],d.colors.belly)
            switch d.species {
            case .eurasianMagpie:
                c.poly([d.bodyPoint(0.48,0.06),d.bodyPoint(0.88,0.04),
                        d.bodyPoint(1,0.4),d.bodyPoint(0.72,0.56),d.bodyPoint(0.52,0.35)],"black")
            case .ashyDrongo:
                c.line([d.bodyPoint(0.82,0.33),d.bodyPoint(0.7,0.81)],"gray",width:0.55)
            default: break
            }
        }
    }

    private static func flankMarks(_ c:BirdPainter, _ d:Drawing) {
        // Exposed vent and breast plumage lies in front of the folded wing's
        // lower edge. Clip to the actual torso, never to the whole bird alpha.
        c.within(bodyEdge(d)) {
            switch d.species {
            case .sootyHeadedBulbul, .brownBreastedBulbul:
                let vent=[d.bodyPoint(0.27,0.87),d.bodyPoint(0.49,0.83),
                          d.bodyPoint(0.62,0.96),d.bodyPoint(0.44,1.05),d.bodyPoint(0.25,0.97)]
                c.poly(vent,d.species == .sootyHeadedBulbul ? "red":"yellow")
                if d.species == .brownBreastedBulbul {
                    c.poly([d.bodyPoint(0.77,0.29),d.bodyPoint(1.02,0.3),
                            d.bodyPoint(1.01,0.45),d.bodyPoint(0.76,0.43)],"brown")
                }
            case .blueWhistlingThrush:
                for row in 0..<3 {
                    for column in 0..<4 {
                        let point=d.bodyPoint(0.76+Double(column)*0.055,0.22+Double(row)*0.17)
                        c.oval(point.0,point.1,0.65,0.8,"cyan")
                    }
                }
            case .taiwanBarbet:
                c.poly([d.bodyPoint(0.81,0.3),d.bodyPoint(0.96,0.28),
                        d.bodyPoint(0.98,0.42),d.bodyPoint(0.83,0.45)],"red")
            case .blueThroatedBarbet:
                c.poly([d.bodyPoint(0.84,0.28),d.bodyPoint(0.98,0.32),
                        d.bodyPoint(0.96,0.44),d.bodyPoint(0.81,0.4)],"red")
            default: break
            }
        }
    }

    private static func neck(_ c:BirdPainter, _ d:Drawing) {
        let a=d.anatomy
        let nape=d.headPoint(-a.headWidth*0.32,a.headHeight*0.24)
        let throat=d.headPoint(a.headWidth*0.32,a.headHeight*0.38)
        let edge=[d.bodyPoint(0.48,0.12),nape,throat,d.bodyPoint(0.96,0.57)]
        let color:String
        switch d.species {
        case .eurasianMagpie, .redBilledBlueMagpie, .yellowBilledBlueMagpie: color="black"
        case .greyTreepie: color="dark"
        case .sootyHeadedBulbul, .brownBreastedBulbul: color="white"
        case .taiwanBarbet: color="yellow"
        case .blueThroatedBarbet: color="cyan"
        default: color=d.colors.belly
        }
        c.poly(edge,color)
        c.within(edge) {
            c.poly([edge[0],nape,(nape.0+1.7,nape.1+1.8),d.bodyPoint(0.64,0.36)],d.colors.back)
            if d.species == .collaredFinchbill {
                // The collar crosses the actual neck, following both endpoints.
                c.line([(nape.0,nape.1+0.7),(throat.0-1,throat.1+1.8),
                        (throat.0+0.7,throat.1+0.8)],"white",width:1.55)
            } else if d.species == .redBilledBlueMagpie || d.species == .yellowBilledBlueMagpie {
                c.poly([nape,d.headPoint(-a.headWidth*0.42,-0.7),
                        d.headPoint(-a.headWidth*0.2,0.2),
                        d.headPoint(-a.headWidth*0.17,a.headHeight*0.5)],"white")
            }
        }
    }

    private static func wing(_ c:BirdPainter, _ d:Drawing, far:Bool) {
        let a=d.anatomy, p=d.pose, open=p.wing
        let root=d.bodyPoint(far ? 0.6:0.43,0.13)
        func w(_ u:Double, _ v:Double) -> Point {
            let side=far ? 0.48 : -1.0
            return (root.0+side*u*(5+a.wingReach*open)+v*open*2,
                    root.1+v*(a.primaryLength*(1-open)+5.6*open)-u*open*12.6)
        }
        let form:[Point]
        switch d.species {
        case .eurasianMagpie:
            form=[(-0.65,0.08),(-0.1,-0.08),(0.51,0.18),(1,0.93),
                  (0.81,1.06),(0.59,0.95),(0.37,1.03),(-0.12,0.83),(-0.67,0.43)]
        case .greyTreepie:
            form=[(-0.63,0.12),(-0.07,-0.04),(0.56,0.2),(1,1.01),
                  (0.76,1.06),(0.51,0.96),(0.12,0.9),(-0.65,0.49)]
        case .redBilledBlueMagpie:
            form=[(-0.56,0.04),(0,-0.09),(0.6,0.15),(1,1.06),
                  (0.81,1.09),(0.59,1),(0.2,0.87),(-0.59,0.4)]
        case .yellowBilledBlueMagpie:
            form=[(-0.6,0.09),(-0.05,-0.06),(0.53,0.2),(1,1),
                  (0.78,1.09),(0.54,0.94),(0.09,0.86),(-0.62,0.45)]
        case .ashyDrongo:
            form=[(-0.54,0.03),(0,-0.08),(0.58,0.15),(1,1.08),
                  (0.84,1.11),(0.61,0.99),(0.17,0.82),(-0.58,0.41)]
        case .blueWhistlingThrush:
            form=[(-0.7,0.12),(-0.12,-0.02),(0.58,0.2),(1,0.91),
                  (0.78,1.03),(0.5,1.01),(0.04,0.86),(-0.71,0.52)]
        case .sootyHeadedBulbul:
            form=[(-0.6,0.08),(-0.09,-0.06),(0.55,0.19),(1,0.99),
                  (0.78,1.05),(0.45,0.94),(-0.1,0.83),(-0.64,0.45)]
        case .brownBreastedBulbul:
            form=[(-0.65,0.11),(-0.13,-0.04),(0.58,0.21),(1,0.96),
                  (0.79,1.07),(0.42,0.99),(-0.16,0.81),(-0.67,0.49)]
        case .blackBulbul:
            form=[(-0.56,0.05),(-0.02,-0.08),(0.58,0.17),(1,1.03),
                  (0.82,1.1),(0.57,0.98),(0.14,0.86),(-0.59,0.42)]
        case .collaredFinchbill:
            form=[(-0.67,0.1),(-0.12,-0.05),(0.58,0.2),(1,0.91),
                  (0.77,1.04),(0.35,1.02),(-0.21,0.82),(-0.7,0.49)]
        case .taiwanBarbet:
            form=[(-0.73,0.12),(-0.17,-0.03),(0.58,0.22),(1,0.87),
                  (0.78,1.01),(0.28,1.03),(-0.25,0.8),(-0.74,0.5)]
        default:
            form=[(-0.7,0.08),(-0.1,-0.06),(0.62,0.2),(1,0.95),
                  (0.78,1.06),(0.34,1.02),(-0.19,0.84),(-0.72,0.47)]
        }
        let edge=form.map { w($0.0,$0.1) }
        c.poly(edge,far ? d.colors.back:d.colors.wing,outline:true)
        c.within(edge) {
            c.poly([w(-0.5,0.14),w(-0.04,0.03),w(0.53,0.21),
                    w(0.36,0.5),w(-0.31,0.6)],d.colors.back)
            let highlight:String
            switch d.species {
            case .eurasianMagpie: highlight="blue"
            case .redBilledBlueMagpie, .yellowBilledBlueMagpie: highlight="navy"
            case .ashyDrongo, .blackBulbul: highlight="gray"
            case .taiwanBarbet, .blueThroatedBarbet, .collaredFinchbill: highlight="olive"
            case .blueWhistlingThrush: highlight="navy"
            default: highlight="brown"
            }
            for i in 0..<4 {
                let u = -0.08+Double(i)*0.2
                c.line([w(u,0.32),w(u+0.23,0.97)],highlight,width:0.65)
            }
            switch d.species {
            case .eurasianMagpie:
                c.poly([w(-0.38,0.12),w(0.18,0.05),w(0.5,0.22),
                        w(0.27,0.46),w(-0.4,0.48)],"white")
            case .greyTreepie:
                c.poly([w(-0.32,0.26),w(0.43,0.29),w(0.58,0.48),w(-0.19,0.54)],"white")
            case .redBilledBlueMagpie:
                c.line([w(0.55,0.82),w(0.84,0.99)],"black",width:1.2)
                c.line([w(0.62,0.98),w(0.82,1.03)],"white",width:0.65)
            case .yellowBilledBlueMagpie:
                c.line([w(0.48,0.84),w(0.8,0.98)],"black",width:1)
                c.line([w(0.58,0.98),w(0.78,1.04)],"white",width:0.7)
            case .blueWhistlingThrush:
                for i in 0..<5 {
                    let point=w(-0.25+Double(i)*0.14,0.23+Double(i%2)*0.17)
                    c.oval(point.0,point.1,0.6,0.65,"cyan")
                }
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
        if a.crest > 0 {
            // Crest feathers are head anatomy. They flex slightly with posture
            // while keeping the black bulbul's established black-headed form.
            let rise=a.crest+p.crest
            let crest=[(x+0.1,y+2),(x+0.6,y-rise),(x+2.7,y-0.6),
                       (x+4.2,y-rise*0.28),(x+5.7,y+1.9)]
            c.poly(crest,d.colors.head,outline:true)
        }
        c.oval(x,y,w,h,d.colors.head,outline:true)
        c.ctx.saveGState()
        c.ctx.addEllipse(in:CGRect(x:x,y:y,width:w,height:h))
        c.ctx.clip()
        c.pigment {
            headMarks(c,d,w,h)
        }
        c.ctx.restoreGState()

        let bill=p.billVertices(anatomy:a), tip=bill[1]
        if p.gape > 0 {
            c.poly([(bill[0].0,0.6),(tip.0-0.4,0.85+p.gape*2.8),
                    (bill[0].0,a.billDepth+p.gape*0.9)],"eye")
            c.poly(p.lowerBillVertices(anatomy:a),d.colors.bill)
        }
        // The anchor is this polygon's vertex 1 under this exact head transform.
        c.poly(bill,d.colors.bill,outline:a.billDepth > 1.5)
        c.pigment {
            if a.billDepth > 1.5 {
                c.line([(bill[0].0+0.6,0.4),(tip.0-0.9,0.5)],
                       d.species == .collaredFinchbill ? "tan":"slate",width:0.45)
            }
            let ex=w*0.21-p.turn*0.65, ey = -h*0.12
            if d.species == .ashyDrongo {
                c.oval(ex-0.5,ey-0.5,2,2.1,"red")
            }
            if d.frame == "restTuck" || d.frame == "restLower" {
                c.line([(ex-0.2,ey+0.3),(ex+0.35,ey+0.65),(ex+1,ey+0.3)],"eye",width:0.65)
            } else {
                c.oval(ex,ey,1,1.1,"eye")
                c.oval(ex+0.4,ey,0.4,0.4,"white")
            }
        }
        c.ctx.restoreGState()
    }

    /// All marks are in the articulated head's local coordinates and clipped to
    /// its silhouette. Neck colours and vent patches have their own body paths.
    private static func headMarks(_ c:BirdPainter, _ d:Drawing, _ w:Double, _ h:Double) {
        let x = -w/2, y = -h/2
        func cheek(_ color:String) {
            c.poly([(x+0.9,y+h*0.5),(w/2-0.4,y+h*0.45),
                    (w/2-0.7,y+h*0.83),(x+2,y+h)],color)
        }
        func crown(_ color:String) {
            c.poly([(x,y+2),(x+2,y),(w/2-2,y),(w/2,y+2.1)],color)
        }
        func mask(_ color:String) {
            c.poly([(x,y+h*0.27),(w/2,y+h*0.31),
                    (w/2,y+h*0.54),(x+0.9,y+h*0.62)],color)
        }
        switch d.species {
        case .eurasianMagpie:
            c.line([(x+0.9,y+1.8),(x+3.5,y+0.8)],"navy",width:0.6)
        case .greyTreepie:
            cheek("gray")
            mask("black")
            c.line([(x+0.8,y+1.6),(x+4,y+0.8)],"gray",width:0.65)
        case .redBilledBlueMagpie:
            c.poly([(x,y+0.7),(x+2,y+0.5),(x+2.1,y+h*0.65),
                    (x+0.2,y+h),(x-0.5,y+h*0.66)],"white")
            c.line([(x+2.2,y+0.7),(x+4.3,y+0.4)],"silver",width:0.5)
        case .yellowBilledBlueMagpie:
            c.poly([(x,y+1),(x+1.8,y+0.5),(x+2.2,y+h*0.53),
                    (x+0.4,y+h),(x-0.4,y+h*0.7)],"white")
            c.line([(x+2,y+1.1),(x+3.8,y+0.7)],"gray",width:0.55)
        case .ashyDrongo:
            c.line([(x+0.7,y+1.8),(x+3.7,y+0.7)],"silver",width:0.6)
            c.line([(x+1,y+h*0.72),(x+3.4,y+h*0.66)],"slate",width:0.55)
        case .blueWhistlingThrush:
            c.line([(x+0.8,y+1.3),(x+5.3,y+0.8)],"blue",width:0.9)
            for i in 0..<3 {
                c.oval(x+1.5+Double(i)*1.4,y+h*0.64,0.55,0.65,"cyan")
            }
        case .sootyHeadedBulbul:
            cheek("silver")
            c.poly([(x+3,y+h*0.76),(w/2,y+h*0.67),
                    (w/2-0.6,y+h),(x+3.2,y+h)],"white")
        case .brownBreastedBulbul:
            cheek("brown")
            c.poly([(x+3.1,y+h*0.78),(w/2,y+h*0.67),
                    (w/2-0.3,y+h),(x+3,y+h)],"white")
            c.oval(w/2-0.6,y+h*0.65,0.7,0.7,"red")
        case .blackBulbul:
            c.line([(x+0.9,y+3),(x+3.2,y+1.9)],"gray",width:0.55)
            c.poly([(x+0.6,y+h*0.7),(x+3.1,y+h*0.61),
                    (x+4,y+h*0.87),(x+1.6,y+h)],"dark")
        case .collaredFinchbill:
            c.poly([(x,y+h*0.83),(x+2,y+h*0.85),(w/2,y+h*0.76),
                    (w/2,y+h),(x+1,y+h)],"white")
        case .taiwanBarbet:
            crown("yellow")
            cheek("cyan")
            mask("black")
            c.oval(w/2-2,y+1.9,2,2,"red")
            c.poly([(x+w*0.53,y+h*0.74),(w/2,y+h*0.64),
                    (w/2,y+h),(x+w*0.52,y+h)],"yellow")
        case .blueThroatedBarbet:
            crown("red")
            c.oval(x+3,y,3,1.5,"navy")
            cheek("cyan")
            mask("black")
            c.poly([(x+w*0.46,y+h*0.69),(w/2,y+h*0.62),
                    (w/2,y+h),(x+w*0.42,y+h)],"cyan")
        default: break
        }
    }
}
