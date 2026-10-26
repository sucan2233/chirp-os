import AppKit
import BirdingCore

/// M8b additions only. No existing raster or standing pose enters this renderer.
/// Feet stay on the original perch while independently drawn parts articulate.
enum M8CommonArt {
    private typealias Geometry = M8CommonArtGeometry
    private typealias Point = (Double, Double)

    private struct Drawing {
        let species: SpeciesID
        let pose: Geometry.Pose
        let anatomy: Geometry.Anatomy

        var back: String {
            switch species {
            case .treeSparrow, .spottedDove: return "tan"
            case .redWhiskeredBulbul: return "brown"
            case .chineseBlackbird: return "dark"
            case .azureWingedMagpie: return "gray"
            default: return "olive"
            }
        }
        var breast: String {
            switch species {
            case .spottedDove: return "pink"
            case .chineseBlackbird: return "dark"
            case .redBilledLeiothrix: return "yellow"
            default: return "cream"
            }
        }
        var feather: String {
            switch species {
            case .treeSparrow, .spottedDove: return "brown"
            case .redWhiskeredBulbul: return "umber"
            case .chineseBlackbird: return "black"
            case .azureWingedMagpie: return "cyan"
            default: return "green"
            }
        }
        var headColor: String {
            switch species {
            case .treeSparrow: return "rust"
            case .spottedDove: return "gray"
            case .swinhoesWhiteEye, .redBilledLeiothrix: return "olive"
            default: return "black"
            }
        }
        var billColor: String {
            switch species {
            case .chineseBlackbird: return "yellow"
            case .redBilledLeiothrix: return "red"
            default: return "dark"
            }
        }
        func body(_ u: Double, _ v: Double) -> Point {
            let p = pose.bodyPoint(u,v,anatomy:anatomy)
            return (Double(p.x),Double(p.y))
        }
        func head(_ x: Double, _ y: Double) -> Point {
            let p = pose.headPoint(x,y)
            return (Double(p.x),Double(p.y))
        }
    }

    static func image(_ frame: String, species: SpeciesID) -> CGImage? {
        guard let a = Geometry.anatomy(for:species),
              let p = Geometry.pose(species:species,frame:frame) else { return nil }
        let density = SpeciesCatalog.standard.profile(species).relativeScale
        let c = BirdPainter(size:max(48,Int((48*density).rounded())))
        let d = Drawing(species:species,pose:p,anatomy:a)
        feet(c,d)
        tail(c,d)
        body(c,d)
        neck(c,d)
        wing(c,d)
        head(c,d)
        return c.image
    }

    private static func feet(_ c: BirdPainter, _ d: Drawing) {
        let top = min(34.5,d.pose.body.y+d.pose.body.height-1.8)
        for x in [27.0,31.0] {
            c.line([(x-1+d.pose.body.lean*0.3,top),(x-0.4,35.8),(x-0.5,38.5)],
                   "brown",width:1)
            // This whole toe band is constant, including the central (29,39)
            // presentation reference, irrespective of head direction or lean.
            c.line([(x-2,39),(x,38.5),(x+2,39)],"brown")
        }
    }

    private static func tail(_ c: BirdPainter, _ d: Drawing) {
        let p = d.pose, x = p.tail.x, y = p.tail.y, w = d.anatomy.tailWidth
        let root = d.body(0.33,0.49), lower = d.body(0.57,0.76)
        let edge: [Point]
        if d.species == .azureWingedMagpie {
            // A long parallel central vane, with a tapered rump attachment.
            edge = [root,(x,y-1.1),(x+0.4,y+0.6),(x+w,y+0.8),lower]
        } else if d.species == .swinhoesWhiteEye {
            edge = [root,(x,y-0.6),(x+0.5,y+1),(x+w,y+0.3),lower]
        } else if d.species == .spottedDove {
            edge = [root,(x,y-0.8),(x+0.3,y+0.9),(x+w,y+1.2),(lower.0+0.4,lower.1)]
        } else {
            edge = [root,(x,y-0.7),(x+0.4,y+0.7),(x+w,y+0.9),lower]
        }
        c.poly(edge,d.feather,outline:true)
        c.within(edge) {
            for n in 0..<3 {
                let t = Double(n+1)/4
                c.line([(root.0+(lower.0-root.0)*t,root.1+(lower.1-root.1)*t),
                        (x+w*t,y+0.3)],d.species == .chineseBlackbird ? "dark":d.back,width:0.65)
            }
            if d.species == .azureWingedMagpie {
                c.line([(root.0+2,root.1+1),(x+w*0.6,y-0.3)],"blue",width:0.8)
                c.line([(x+0.3,y),(x+w-0.2,y+0.5)],"silver",width:1)
            } else if d.species == .spottedDove {
                c.line([(x+0.2,y),(x+w,y+0.7)],"silver",width:1.1)
            } else if d.species == .lightVentedBulbul {
                c.line([(x+0.3,y),(x+w-0.4,y+0.5)],"silver",width:0.75)
            }
        }
    }

    private static func body(_ c: BirdPainter, _ d: Drawing) {
        let edge = d.anatomy.bodyOutline.map { d.body($0.0,$0.1) }
        c.poly(edge,d.back,outline:true)
        c.within(edge) {
            c.poly([d.body(0.53,0.08),d.body(1.08,0.18),d.body(1.08,0.90),
                    d.body(0.62,1.08),d.body(0.45,0.72)],d.breast)
            switch d.species {
            case .treeSparrow:
                for n in 0..<4 {
                    let u = 0.15+Double(n)*0.12
                    c.line([d.body(u,0.12),d.body(u-0.06,0.48)],"umber",width:0.8)
                }
            case .redWhiskeredBulbul:
                c.poly([d.body(0.17,0.76),d.body(0.43,0.83),d.body(0.34,1.03),d.body(0.13,0.95)],"red")
                c.line([d.body(0.78,0.22),d.body(0.92,0.42)],"black",width:0.8)
            case .swinhoesWhiteEye:
                c.poly([d.body(0.64,0.10),d.body(1,0.22),d.body(0.89,0.41),d.body(0.62,0.31)],"yellow")
            case .redBilledLeiothrix:
                c.poly([d.body(0.57,0.08),d.body(1.02,0.17),d.body(0.94,0.41),d.body(0.59,0.34)],"orange")
            case .chineseBlackbird:
                c.curve([d.body(0.67,0.17),d.body(0.88,0.37),d.body(0.87,0.69),d.body(0.69,0.89)],"slate",width:0.45)
            case .spottedDove:
                c.curve([d.body(0.69,0.28),d.body(0.94,0.45),d.body(0.90,0.72),d.body(0.71,0.86)],"tan",width:0.6)
            default: break
            }
        }
        if d.pose.body.fluff > 0.6 {
            // Silhouette feathers are anatomy, drawn outside the pigment pass.
            for n in 0..<3 {
                let u = 0.35+Double(n)*0.12
                c.poly([d.body(u-0.06,0.91),d.body(u+0.06,0.95),d.body(u,1.03)],
                       n == 2 ? d.breast:d.back)
            }
        }
    }

    private static func neck(_ c: BirdPainter, _ d: Drawing) {
        let a = d.anatomy
        let rear = d.head(-a.headWidth*0.32,0.8)
        let chin = d.head(a.headWidth*0.28,a.headHeight*0.36)
        let edge: [Point]
        if d.species == .spottedDove {
            // Narrow neck above a broad body; no courtship body bow.
            edge = [d.body(0.67,0.33),d.body(0.64,0.10),rear,chin,d.body(0.91,0.53)]
        } else if d.species == .azureWingedMagpie {
            edge = [d.body(0.48,0.21),rear,chin,d.body(0.96,0.49),d.body(0.76,0.71)]
        } else {
            edge = [d.body(0.48,0.18),rear,chin,d.body(0.98,0.57),d.body(0.77,0.65)]
        }
        c.poly(edge,d.breast)
        c.within(edge) {
            c.poly([d.body(0.48,0.18),rear,(rear.0+0.7,rear.1+1.5),d.body(0.66,0.55)],d.back)
            switch d.species {
            case .treeSparrow:
                c.poly([d.head(1,1.7),chin,d.body(0.86,0.37),d.body(0.72,0.25)],"black")
            case .lightVentedBulbul:
                c.poly([d.head(-0.7,1.9),chin,d.body(0.89,0.33),d.body(0.72,0.30)],"silver")
            case .redWhiskeredBulbul:
                c.line([d.head(-1,2.5),d.body(0.80,0.32),d.body(0.92,0.39)],"black",width:1.2)
            case .swinhoesWhiteEye:
                c.poly([d.head(-1,2.5),chin,d.body(0.94,0.27),d.body(0.72,0.31)],"yellow")
            case .redBilledLeiothrix:
                c.poly([d.head(-0.8,1.6),chin,d.body(0.95,0.27),d.body(0.66,0.30)],"orange")
            case .spottedDove:
                c.poly([d.head(-3,1.5),d.head(-0.5,2.2),d.head(-0.7,4.6),d.head(-3.4,3.7)],"black")
                for q in [(-2.7,2.0),(-1.4,2.6),(-2.7,3.2),(-1.3,3.6)] {
                    let dot = d.head(q.0,q.1)
                    c.oval(dot.0-0.3,dot.1-0.3,0.65,0.65,"white")
                }
            default: break
            }
        }
    }

    private static func wing(_ c: BirdPainter, _ d: Drawing) {
        let shoulder = d.pose.shoulder, sweep = d.pose.sweep
        // Each species' wing has its own shoulder, chord and primary endpoint.
        // These coordinates move with the torso, while the foot contacts do not.
        let normalized: [Point]
        switch d.species {
        case .treeSparrow:
            normalized = [(0.16,0.08),(0.48,0.05),(0.72,0.30),(0.57,0.68),(0.18,0.91),(0.03,0.76),(0.08,0.38)]
        case .lightVentedBulbul:
            normalized = [(0.15,0.06),(0.47,0.02),(0.72,0.28),(0.55,0.71),(0.08,1.02),(-0.02,0.91),(0.05,0.42)]
        case .redWhiskeredBulbul:
            normalized = [(0.18,0.04),(0.49,0.02),(0.75,0.29),(0.55,0.68),(0.05,1.05),(-0.04,0.91),(0.07,0.43)]
        case .chineseBlackbird:
            normalized = [(0.12,0.12),(0.45,0.04),(0.72,0.27),(0.55,0.69),(0.06,1.02),(-0.03,0.87),(0.04,0.43)]
        case .spottedDove:
            normalized = [(0.13,0.11),(0.43,0.04),(0.69,0.25),(0.56,0.60),(0.08,1.07),(-0.03,0.96),(0.03,0.43)]
        case .swinhoesWhiteEye:
            normalized = [(0.18,0.10),(0.48,0.08),(0.72,0.34),(0.53,0.72),(0.15,0.87),(0.02,0.71),(0.06,0.40)]
        case .redBilledLeiothrix:
            normalized = [(0.15,0.08),(0.49,0.04),(0.73,0.30),(0.57,0.68),(0.12,0.96),(0.01,0.78),(0.06,0.41)]
        case .azureWingedMagpie:
            normalized = [(0.14,0.10),(0.51,0.03),(0.77,0.29),(0.55,0.70),(-0.01,1.14),(-0.10,1.01),(0.02,0.45)]
        default: return
        }
        func w(_ u: Double, _ v: Double) -> Point {
            let p = d.body(u,v)
            return (p.0+sweep*v,p.1-shoulder*(1-v))
        }
        let edge = normalized.map { w($0.0,$0.1) }
        c.poly(edge,d.feather,outline:true)
        c.within(edge) {
            c.poly([w(0.18,0.12),w(0.48,0.08),w(0.65,0.30),w(0.41,0.60),w(0.12,0.62)],d.back)
            for n in 0..<5 {
                let u = 0.15+Double(n)*0.085
                c.line([w(u+0.23,0.34),w(u-0.09,0.93)],
                       d.species == .chineseBlackbird ? "dark":d.back,width:0.65)
            }
            switch d.species {
            case .treeSparrow:
                c.line([w(0.16,0.33),w(0.53,0.41)],"cream",width:1)
                c.line([w(0.12,0.52),w(0.43,0.60)],"buff",width:0.8)
                for n in 0..<3 {
                    let u = 0.19+Double(n)*0.11
                    c.line([w(u,0.17),w(u-0.03,0.29)],"umber",width:0.8)
                }
            case .spottedDove:
                for n in 0..<9 {
                    let u = 0.16+Double(n%3)*0.12, v = 0.22+Double(n/3)*0.15
                    c.line([w(u,v),w(u+0.04,v-0.03),w(u+0.08,v+0.05)],"buff",width:0.65)
                }
            case .redBilledLeiothrix:
                c.line([w(0.20,0.30),w(0.59,0.39)],"red",width:1.2)
                c.line([w(0.14,0.51),w(0.46,0.61)],"yellow",width:0.9)
            case .azureWingedMagpie:
                c.line([w(0.20,0.21),w(0.54,0.28)],"gray",width:1)
                c.line([w(0.08,0.65),w(0.35,0.45)],"blue",width:0.9)
            case .lightVentedBulbul, .swinhoesWhiteEye:
                c.line([w(0.13,0.61),w(0.43,0.43)],"olive",width:0.7)
            default: break
            }
        }
    }

    private static func head(_ c: BirdPainter, _ d: Drawing) {
        let a = d.anatomy, p = d.pose, w = a.headWidth, h = a.headHeight
        let x = -w/2, y = -h/2
        c.ctx.saveGState()
        c.ctx.translateBy(x:p.head.x,y:p.head.y)
        c.ctx.rotate(by:CGFloat(p.head.pitch))
        c.ctx.scaleBy(x:p.lookingBack ? -1:1,y:1)
        c.oval(x,y,w,h,d.headColor,outline:true)
        if d.species == .redWhiskeredBulbul {
            // Keep the accepted tall crown silhouette rigid on the head.
            c.poly([(x,y+2),(x+2,y-6),(x+4,y-3),(x+6,y+1)],"black",outline:true)
        }
        c.ctx.saveGState()
        c.ctx.addEllipse(in:CGRect(x:x,y:y,width:w,height:h))
        c.ctx.clip()
        c.pigment {
            switch d.species {
            case .treeSparrow:
                c.poly([(x,y+4),(x+4,y+3),(x+w,y+4),(x+w-1,y+7),(x+2,y+7)],"cream")
                c.oval(x+2,y+4,2,2,"black")
                c.poly([(x+5,y+6),(x+w,y+5),(x+w,y+8),(x+5,y+8)],"black")
            case .lightVentedBulbul:
                c.poly([(x,y+1),(x+3,y+1),(x+4,y+4),(x+2,y+6),(x,y+4)],"white")
                c.poly([(x+3,y+5),(x+w,y+4),(x+w,y+7),(x+4,y+7.5)],"silver")
                c.line([(x+4,y+3),(x+6,y+3.5)],"black",width:0.8)
            case .redWhiskeredBulbul:
                c.poly([(x+1,y+4),(x+4,y+3),(x+w,y+4),(x+5,y+7),(x+2,y+6)],"white")
                c.oval(x+2,y+3,2,2,"red")
            case .spottedDove:
                c.poly([(x,y+4),(x+3,y+4.8),(x+3.5,y+7),(x,y+6.5)],"black")
                for q in [(x+0.6,y+4.8),(x+2,y+5.5),(x+0.9,y+6)] {
                    c.oval(q.0,q.1,0.65,0.65,"white")
                }
            case .swinhoesWhiteEye:
                c.poly([(x+3,y+5),(x+w,y+4),(x+w-1,y+7),(x+4,y+7)],"yellow")
            case .redBilledLeiothrix:
                c.poly([(x+2,y+4),(x+w,y+4),(x+w-1,y+7),(x+3,y+6)],"orange")
                c.line([(x+1,y+1.5),(x+w-1,y+1)],"yellow",width:0.8)
            case .azureWingedMagpie:
                c.poly([(x+1,y+4),(x+w-1,y+4),(x+w-1,y+6),(x+2,y+7)],"cream")
            case .chineseBlackbird:
                c.line([(x+1,y+1.8),(x+4,y+0.8)],"dark",width:0.6)
            default: break
            }
            let ex = x+w*0.72, ey = y+h*0.38
            if d.species == .swinhoesWhiteEye { c.oval(ex-1.1,ey-1.1,2.9,2.9,"white") }
            if d.species == .chineseBlackbird { c.oval(ex-0.8,ey-0.8,2.3,2.3,"yellow") }
            c.oval(ex,ey,1,1.1,"eye")
            c.oval(ex+0.4,ey,0.45,0.45,"white")
        }
        c.ctx.restoreGState()
        // The tip is the same polygon vertex consumed by beakAnchor. Opening
        // adds a second mandible instead of moving an unrelated metadata point.
        if p.gape > 0 {
            let root = w/2-0.5
            c.poly([(root,0),(root+a.billLength-0.6,0.7),(root,1.5)],"eye")
        }
        c.poly(p.billVertices(anatomy:a),d.billColor)
        let lower = p.lowerBillVertices(anatomy:a)
        if !lower.isEmpty { c.poly(lower,d.billColor) }
        c.ctx.restoreGState()
    }
}
