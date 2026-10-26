import AppKit
import BirdingCore

/// Appended M8a drawings. Anatomy is rasterized at the species' native density;
/// no stand/idle bitmap, whole-bird affine transform or substituted old pose is
/// used. BirdArt owns the resulting cache once the coordinator wires this in.
enum M8PilotArt {
    private struct Drawing {
        let species: SpeciesID
        let frame: String
        let pose: M8PilotArtGeometry.Pose
        let anatomy: M8PilotArtGeometry.Anatomy

        var egret: Bool { species == .littleEgret }
        var duck: Bool { species == .mallard }
        var woodpecker: Bool { species == .greatSpottedWoodpecker }
        var tucked: Bool { frame == "restTuck" }
        var bodyX: Double { (egret ? 17 : 34-anatomy.width) + pose.body.lean-pose.body.fluff/2 }
        var bodyY: Double { pose.body.y }
        var width: Double { anatomy.width+pose.body.fluff }
        var height: Double { pose.body.height }
        var back: String {
            switch species {
            case .greatTit: return "green"
            case .mallard: return "gray"
            case .littleEgret: return "white"
            case .greatSpottedWoodpecker: return "silver"
            default: return "black"
            }
        }
        var breast: String { species == .greatTit || duck ? "silver" : "white" }
        var feather: String {
            switch species {
            case .greatTit: return "slate"
            case .mallard: return "brown"
            case .littleEgret: return "white"
            case .greatSpottedWoodpecker: return "black"
            default: return "navy"
            }
        }
        var featherLight: String {
            switch species {
            case .greatTit: return "gray"
            case .mallard: return "tan"
            case .littleEgret: return "silver"
            case .greatSpottedWoodpecker: return "slate"
            default: return "blue"
            }
        }
    }

    static func image(_ frame: String, species: SpeciesID) -> CGImage? {
        guard let anatomy = M8PilotArtGeometry.anatomy(for: species),
              let pose = M8PilotArtGeometry.pose(species: species, frame: frame) else { return nil }
        let density = SpeciesCatalog.standard.profile(species).relativeScale
        let c = BirdPainter(size: max(48, Int((48*density).rounded())))
        let d = Drawing(species: species, frame: frame, pose: pose, anatomy: anatomy)
        if pose.side {
            sideWoodpecker(c, d)
        } else {
            feet(c, d)
            tail(c, d)
            if pose.wing > 0 { raisedWing(c, d, far: true) }
            body(c, d)
            neck(c, d)
            foldedWing(c, d)
            head(c, d)
            if d.tucked { scapulars(c, d) }
            if pose.wing > 0 { raisedWing(c, d, far: false) }
        }
        return c.image
    }

    private static func withinOval(_ c: BirdPainter, _ x: Double, _ y: Double,
                                   _ w: Double, _ h: Double, _ paint: () -> Void) {
        c.ctx.saveGState()
        c.ctx.addEllipse(in: CGRect(x: x, y: y, width: w, height: h))
        c.ctx.clip()
        c.pigment(paint)
        c.ctx.restoreGState()
    }

    private static func feet(_ c: BirdPainter, _ d: Drawing) {
        let top = min(35, d.bodyY+d.height-2)
        let knee = d.frame == "takeoffCrouch" ? 1.3 : 0.0
        for x in [27.0,31.0] {
            let fill = d.egret ? "dark" : (d.duck ? "orange" : "brown")
            let joint = d.egret ? top+4 : 35
            c.line([(x-1+d.pose.body.lean,top),(x+knee,joint),(x-0.5,38.5)],
                   fill, width: d.egret ? 0.7 : 1)
            if !d.duck {
                // The entire toe band stays fixed while the knees flex.
                c.line([(x-2,39),(x,38.5),(x+2,39)],d.egret ? "yellow" : "brown",
                       width: d.egret ? 0.7 : 1)
            }
        }
        if d.duck {
            c.poly([(27,35),(29,39),(24,39)],"orange")
            c.poly([(31,35),(35,39),(29,39)],"orange")
            c.line([(27,36),(26,38.5)],"rust",width:0.5)
            c.line([(31,36),(32,38.5)],"rust",width:0.5)
        }
    }

    private static func tail(_ c: BirdPainter, _ d: Drawing) {
        let x = d.pose.tail.x, y = d.pose.tail.y, w = d.anatomy.tailWidth
        let rootX = d.bodyX+(d.duck ? 5 : 6), rootY = d.bodyY+d.height*0.48
        let edge = [(rootX,rootY),(rootX+5,rootY+3.5),(x+w,y+0.8),(x,y)]
        c.poly(edge,d.feather,outline:true)
        c.within(edge) {
            c.line([(rootX+1.5,rootY+1),(x+1,y)],d.featherLight,width:0.8)
            if d.species == .orientalMagpie {
                c.line([(rootX+3,rootY+2),(x+w-1,y)],"cyan",width:0.8)
                c.line([(rootX+1,rootY),(x+0.5,y)],"green",width:0.7)
            } else if d.species == .magpieRobin {
                c.line([(rootX,rootY+0.4),(x,y)],"white",width:1)
                c.line([(rootX+4.5,rootY+3),(x+w,y+0.7)],"white",width:1)
            } else if d.woodpecker {
                c.line([(rootX+3.5,rootY+2.5),(x+w-0.5,y)],"white",width:0.8)
            }
        }
        if d.duck {
            // The short drake tail curls move with the rump, not with his head.
            c.curve([(rootX,rootY),(x+1,y-4),(x-2,y-3),(x,y-1)],"black",width:0.8)
            c.curve([(rootX+1,rootY),(x+3,y-4),(x,y-4),(x+1,y-2)],"black",width:0.7)
        }
    }

    private static func body(_ c: BirdPainter, _ d: Drawing) {
        let x = d.bodyX, y = d.bodyY, w = d.width, h = d.height
        c.oval(x,y,w,h,d.back,outline:true)
        withinOval(c,x,y,w,h) {
            c.oval(x+w*0.48,y+1.6,w*0.54,h-1.6,d.breast)
            switch d.species {
            case .greatTit:
                // Preserve the U baseline's pale belly, olive back and black tie.
                c.poly([(x+w*0.80,y+2),(x+w*0.88,y+3),(x+w*0.80,y+h),
                        (x+w*0.71,y+h),(x+w*0.74,y+4)],"black")
            case .orientalMagpie, .magpieRobin:
                c.poly([(x+w*0.55,y),(x+w,y),(x+w,y+4.2),(x+w*0.72,y+6),
                        (x+w*0.56,y+4)],"black")
            case .greatSpottedWoodpecker:
                c.poly([(x+2,y+h-4),(x+9,y+h-3.5),(x+10,y+h),(x+3,y+h)],"red")
                c.poly([(x,y),(x+10,y),(x+9,y+5),(x+2,y+7)],"black")
            case .mallard:
                c.oval(x+w-8,y-1,9,8,"rust")
                for n in 0..<5 {
                    let yy = y+5+Double(n)*1.1
                    c.line([(x+w*0.6,yy),(x+w-2,yy+0.3)],"gray",width:0.4)
                }
            case .littleEgret:
                c.oval(x+7,y+4,w-5,h-2,"silver")
                c.oval(x+7,y+3,w-5,h-2.3,"white")
            default: break
            }
        }
        if d.pose.body.fluff > 0.6 {
            for n in 0..<3 {
                let xx = x+w*0.30+Double(n)*2.3
                c.poly([(xx-1,y+h-1),(xx+1.3,y+h-0.6),(xx+0.4,y+h+0.2)],d.breast)
            }
        }
    }

    private static func neck(_ c: BirdPainter, _ d: Drawing) {
        let p = d.pose, a = d.anatomy
        let nape = p.headPoint(-a.headWidth*0.30,1)
        let chin = p.headPoint(a.headWidth*0.28,a.headHeight*0.36)
        if d.egret {
            // Two joined cubic sections author the S-neck. The middle joint is
            // explicit in each row, so extending the head cannot stretch a bitmap.
            let joint = p.neck
            let lower = [(d.bodyX+13,d.bodyY+5),(d.bodyX+19,d.bodyY+1),
                         (joint.x+3,joint.y+3),(joint.x,joint.y)]
            let upper = [(joint.x,joint.y),(joint.x-4,joint.y-4),
                         (Double(nape.x)-2,Double(nape.y)+1),(Double(nape.x)+1,Double(nape.y))]
            c.curve(lower,"silver",width:3.3)
            c.curve(upper,"silver",width:3.3)
            c.curve(lower.map { ($0.0+0.45,$0.1-0.1) },"white",width:2.15)
            c.curve(upper.map { ($0.0+0.45,$0.1-0.1) },"white",width:2.15)
        } else if d.duck {
            let lower = [(d.bodyX+d.width-5,d.bodyY+4),(d.bodyX+d.width+1,d.bodyY),
                         (Double(nape.x)-1,Double(nape.y)+3),(Double(nape.x)+1,Double(nape.y))]
            c.curve(lower,"rust",width:5)
            c.curve([lower[1],lower[2],lower[2],lower[3]],"green",width:3.8)
        } else {
            let edge = [(d.bodyX+d.width*0.50,d.bodyY+2),(Double(nape.x),Double(nape.y)),
                        (Double(chin.x),Double(chin.y)),(d.bodyX+d.width-1,d.bodyY+d.height*0.65)]
            c.poly(edge,d.breast)
            c.within(edge) {
                c.poly([edge[0],edge[1],(Double(nape.x)+1,Double(nape.y)+2),
                        (d.bodyX+d.width*0.64,d.bodyY+6)],d.back)
                if d.species == .greatTit {
                    c.line([(Double(chin.x)-1,Double(chin.y)),
                            (d.bodyX+d.width*0.80,d.bodyY+4)],"black",width:1.5)
                } else if d.species == .orientalMagpie || d.species == .magpieRobin {
                    c.poly([edge[0],edge[1],edge[2],(d.bodyX+d.width-2,d.bodyY+5)],"black")
                }
            }
        }
    }

    private static func foldedWing(_ c: BirdPainter, _ d: Drawing) {
        let x = d.bodyX, y = d.bodyY, h = d.height, drop = d.pose.droop
        let start = d.duck ? 6.0 : 3.0
        let shoulder = d.duck ? 17.0 : (d.egret ? 11.0 : 13.0)
        let tipY = y+h-0.5+drop
        let edge = [(x+start,y+1),(x+start+5,y+0.6),(x+shoulder,y+3.5),
                    (x+shoulder-3,y+h*0.68+drop*0.5),(x+1.5,tipY),
                    (x,tipY-0.8),(x+1,y+h*0.48)]
        c.poly(edge,d.feather,outline:true)
        c.within(edge) {
            c.poly([(x+start+1,y+1.5),(x+start+5,y+1),(x+shoulder-1,y+4),
                    (x+5,y+h*0.65+drop*0.4),(x+2,y+h*0.68)],d.egret ? "white" : d.back)
            for n in 0..<5 {
                let xx = x+2+Double(n)*1.6
                c.line([(xx+5,y+4),(xx-0.5,tipY-0.8)],d.featherLight,width:0.7)
            }
            switch d.species {
            case .greatTit:
                c.line([(x+3,y+4),(x+10,y+5)],"white",width:1.2)
                c.line([(x+2,y+6),(x+7,y+7)],"silver",width:0.8)
            case .orientalMagpie:
                c.poly([(x+3,y+1.5),(x+8,y+1),(x+10,y+4),(x+6,y+5.5),(x+3,y+4)],"white")
                c.line([(x+2,tipY-1),(x+7,y+6)],"cyan",width:1)
            case .magpieRobin:
                c.poly([(x+4,y+2.5),(x+9,y+3.5),(x+10,y+5+drop*0.3),
                        (x+5,y+7+drop*0.3),(x+2,y+6)],"white")
            case .greatSpottedWoodpecker:
                c.oval(x+4,y+1.5,4.5,5,"white")
                for n in 0..<4 {
                    let xx = x+1.5+Double(n)*1.9
                    c.line([(xx+2,y+h*0.65),(xx,tipY-1)],"white",width:0.9)
                }
            case .mallard:
                c.poly([(x+7,y+3),(x+15,y+3.5),(x+13,y+6.5+drop*0.4),
                        (x+6,y+6+drop*0.4)],"navy")
                c.line([(x+7,y+2.7),(x+15,y+3.2)],"white",width:0.9)
                c.line([(x+6,y+6.4+drop*0.4),(x+13,y+6.9+drop*0.4)],"white",width:0.9)
            default: break
            }
        }
        if d.egret {
            for n in 0..<3 {
                let xx = x+5-Double(n)
                c.curve([(x+8,y+3),(x+7,y+h),(xx,y+h+1),(xx-2,y+h+1.3)],"white",width:0.55)
            }
        }
    }

    private static func head(_ c: BirdPainter, _ d: Drawing) {
        let a = d.anatomy, p = d.pose, w = a.headWidth, h = a.headHeight
        let x = -w/2, y = -h/2
        // Only the head's local vectors rotate. The anchor uses this exact
        // rotation through Pose.headPoint, including the actual bill vertex.
        c.ctx.saveGState()
        c.ctx.translateBy(x:p.head.x,y:p.head.y)
        c.ctx.rotate(by:CGFloat(p.head.pitch))
        if d.egret {
            c.curve([(x+0.5,y+1),(x-2,y+1),(x-2,y+4),(x-5,y+4.5)],"white",width:0.55)
            c.curve([(x,y+1),(x-2,y+1),(x-3,y+2.5),(x-6,y+3)],"silver",width:0.5)
        }
        c.oval(x,y,w,h,d.egret ? "white" : (d.duck ? "green" : "black"),outline:true)
        withinOval(c,x,y,w,h) {
            if d.species == .greatTit {
                c.poly([(x+1,y+4),(x+5,y+3),(x+w-1,y+4),(x+w-1,y+6),(x+3,y+7)],"white")
            } else if d.woodpecker {
                c.poly([(x+0.5,y+3),(x+6,y+3),(x+7,y+5),(x+2,y+7)],"white")
                c.line([(x+4,y+4),(x+5,y+6.5)],"black",width:1)
                c.line([(x+0.5,y+1),(x+0.5,y+3)],"red",width:1.1)
            } else if d.duck {
                c.oval(x+1.5,y+1,4.5,2,"olive")
                c.line([(x+0.5,y+6),(x+4,y+7),(x+7,y+6)],"white",width:1)
            } else if !d.egret {
                c.line([(x+1,y+1.5),(x+4,y+0.8)],"slate",width:0.6)
            }
        }
        let ex = x+w*0.72, ey = y+h*0.38
        if d.egret { c.oval(ex-0.45,ey-0.4,1.7,1.7,"yellow") }
        if d.tucked || d.frame == "restLower" {
            c.line([(ex-0.2,ey+0.4),(ex+0.3,ey+0.65),(ex+1,ey+0.4)],"eye",width:0.7)
        } else {
            c.oval(ex,ey,1,1.1,"eye")
            c.oval(ex+0.4,ey,0.45,0.45,"white")
        }
        let root = a.billRoot, tip = Double(a.localBillTip.x)
        c.poly(a.billVertices(flat:d.duck),d.duck ? "yellow" : "dark")
        if d.duck {
            c.line([(root+0.7,0.8),(tip-0.7,0.8)],"tan",width:0.5)
            c.oval(root+1,-0.2,0.8,0.5,"dark")
        } else {
            if d.egret || d.woodpecker {
                c.line([(root+0.5,-0.3),(tip-1,0.4)],"slate",width:0.5)
            }
        }
        c.ctx.restoreGState()
    }

    private static func scapulars(_ c: BirdPainter, _ d: Drawing) {
        // Small shoulder feathers overlap the tucked bill's root. Its endpoint
        // remains the same geometric landmark, even when partly occluded.
        let x = d.bodyX+d.width*0.41, y = d.bodyY+2
        c.poly([(x-1,y+2),(x+1,y-0.5),(x+3,y+1),(x+4,y-0.5),
                (x+6,y+3),(x+4,y+5),(x,y+5)],d.feather)
        c.line([(x,y+2),(x+3,y+3),(x+5,y+2)],d.featherLight,width:0.7)
    }

    private static func raisedWing(_ c: BirdPainter, _ d: Drawing, far: Bool) {
        let amount = d.pose.wing
        let shoulderX = d.bodyX+d.width*0.55+(far ? 3 : 0)
        let shoulderY = d.bodyY+3
        let span = d.duck ? 20.0 : (d.egret ? 19.0 : 16.0)
        let tipX = max(2,shoulderX-span*amount)
        let tipY = shoulderY-(far ? 13.0 : 16.0)*amount
        let edge = [(shoulderX,shoulderY),(shoulderX-5*amount,shoulderY-4*amount),
                    (tipX,tipY),(tipX+1,tipY+4*amount),
                    (tipX+3,tipY+6*amount),(shoulderX-4,shoulderY+5),(shoulderX+1,shoulderY+3)]
        c.poly(edge,far ? d.featherLight : d.feather,outline:true)
        c.within(edge) {
            for n in 0..<4 {
                let offset = Double(n)*1.25
                c.line([(shoulderX-2,shoulderY+offset*0.5),
                        (tipX+offset,tipY+2+offset*0.8)],d.egret ? "silver" : d.featherLight,width:0.65)
            }
            if d.duck {
                c.poly([(shoulderX-9*amount,shoulderY-4*amount),
                        (shoulderX-14*amount,shoulderY-8*amount),
                        (shoulderX-15*amount,shoulderY-5*amount),
                        (shoulderX-10*amount,shoulderY-1*amount)],"navy")
                c.line([(shoulderX-10*amount,shoulderY-1*amount),
                        (shoulderX-15*amount,shoulderY-5*amount)],"white",width:0.9)
            } else if !d.egret {
                c.line([(shoulderX-5*amount,shoulderY),
                        (shoulderX-10*amount,shoulderY-5*amount)],"white",width:1.2)
            }
        }
    }

    private static func sideWoodpecker(_ c: BirdPainter, _ d: Drawing) {
        let p = d.pose, x = 13+p.body.lean, y = p.body.y, h = p.body.height
        let tx = p.tail.x, ty = p.tail.y
        c.poly([(x+5,y+10),(x+10,y+12),(tx+1.5,ty-1),(tx,ty),
                (x+7,y+19),(x+3,y+14)],"black",outline:true)
        c.line([(x+7,y+13),(tx,ty-2)],"slate",width:0.8)
        c.oval(x,y,12+p.body.fluff,h,"black",outline:true)
        withinOval(c,x,y,12+p.body.fluff,h) {
            c.oval(x+7,y+2,6,h-5,"white")
            c.poly([(x+7,y+h-5),(x+12,y+h-5),(x+10,y+h),(x+6,y+h-2)],"red")
        }
        let nape = p.headPoint(-2,1), chin = p.headPoint(2,2.5)
        c.poly([(x+7,y+4),(Double(nape.x),Double(nape.y)),
                (Double(chin.x),Double(chin.y)),(x+12,y+6)],"white")
        c.line([(x+7,y+4),(Double(nape.x),Double(nape.y))],"black",width:1.8)
        let wing = [(x+2,y),(x+8,y+2),(x+9,y+9),(x+4,y+h-2+p.droop),
                    (x,y+h-5),(x+1,y+5)]
        c.poly(wing,"black",outline:true)
        c.within(wing) {
            c.oval(x+3,y+3,4,5,"white")
            for n in 0..<4 {
                let xx = x+1+Double(n)*1.6
                c.line([(xx+1,y+10),(xx,y+h-3+p.droop)],n%2 == 0 ? "white" : "slate",width:0.8)
            }
        }
        head(c,d)
        // Preserve the existing cling drawing's complete terminal grip paths,
        // including the lower (29,39) reference and upper toe curl to (28,34).
        let upper = M8PilotArtGeometry.sideUpperGrip
        let lower = M8PilotArtGeometry.sideLowerGrip
        c.line([(x+10,29),(25,33),(Double(upper.x),Double(upper.y)),(28,34)],"brown",width:0.8)
        c.line([(x+10,34),(26,38),(Double(lower.x),38),(Double(lower.x),Double(lower.y))],"brown",width:0.8)
    }
}
