import AppKit
import BirdingCore

/// M8d's new drawings only. No historical image is used as a drawing input.
/// Feet retain the (29,39) presentation reference at every native density.
enum M8WetlandArt {
    private typealias Geometry = M8WetlandArtGeometry
    private typealias Pose = Geometry.Pose
    private typealias Anatomy = Geometry.Anatomy
    private typealias Point = (Double,Double)

    private struct Drawing {
        let species: SpeciesID
        let frame: String
        let pose: Pose
        let anatomy: Anatomy

        var heron: Bool { [.nightHeron,.greyHeron,.chinesePondHeron].contains(species) }
        var rail: Bool { species == .commonMoorhen || species == .eurasianCoot }
        var tucked: Bool { frame == "restTuck" }
        var x: Double { heron ? 17 : 34-anatomy.width }
        var y: Double { pose.body.y }
        var height: Double { pose.body.height }
        var width: Double { anatomy.width+pose.body.fluff }
        var back: String {
            switch species {
            case .nightHeron: return "navy"
            case .greyHeron: return "gray"
            case .chinesePondHeron: return "rust"
            case .blackWingedStilt: return "white"
            case .whimbrel: return "brown"
            case .littleRingedPlover: return "tan"
            default: return "dark"
            }
        }
        var feather: String {
            switch species {
            case .nightHeron,.greyHeron: return "gray"
            case .chinesePondHeron: return "white"
            case .blackWingedStilt: return "black"
            case .whimbrel: return "umber"
            case .littleRingedPlover: return "brown"
            default: return "slate"
            }
        }
        var breast: String {
            switch species {
            case .chinesePondHeron: return "rust"
            case .whimbrel: return "buff"
            case .commonMoorhen,.eurasianCoot: return "dark"
            default: return "white"
            }
        }
        var headFill: String {
            switch species {
            case .chinesePondHeron: return "rust"
            case .whimbrel,.littleRingedPlover: return "tan"
            case .commonMoorhen,.eurasianCoot: return "black"
            default: return "white"
            }
        }
        var billFill: String {
            switch species {
            case .greyHeron,.chinesePondHeron: return "yellow"
            case .commonMoorhen: return "red"
            case .eurasianCoot: return "white"
            default: return "dark"
            }
        }
        var legs: String {
            switch species {
            case .nightHeron,.chinesePondHeron: return "tan"
            case .blackWingedStilt: return "pink"
            case .commonMoorhen: return "yellow"
            default: return "brown"
            }
        }

        /// Shoulder lean leaves the belly over the supporting feet. Different
        /// body proportions are authored per species in Geometry, not scaled
        /// from a finished small-bird outline.
        func bodyPoint(_ u:Double, _ v:Double) -> Point {
            (x+anatomy.width/2+u*width/2+pose.body.lean*(1-v)*0.45,
             y+height*(v+1)/2)
        }
    }

    static func image(_ frame:String, species:SpeciesID) -> CGImage? {
        guard let a=Geometry.anatomy(for:species),
              let p=Geometry.pose(species:species,frame:frame) else { return nil }
        let density=SpeciesCatalog.standard.profile(species).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let d=Drawing(species:species,frame:frame,pose:p,anatomy:a)
        feet(c,d)
        tail(c,d)
        if p.wing>0.2 { openingWing(c,d,far:true) }
        torso(c,d)
        neck(c,d)
        foldedWing(c,d)
        head(c,d)
        if d.tucked { tuckedShoulder(c,d) }
        if p.wing>0.2 { openingWing(c,d,far:false) }
        return c.image
    }

    private static func withinOval(_ c:BirdPainter, _ x:Double, _ y:Double,
                                   _ w:Double, _ h:Double, _ paint:() -> Void) {
        c.ctx.saveGState()
        c.ctx.addEllipse(in:CGRect(x:x,y:y,width:w,height:h))
        c.ctx.clip()
        c.pigment(paint)
        c.ctx.restoreGState()
    }

    private static func feet(_ c:BirdPainter, _ d:Drawing) {
        let top=d.y+d.height-1.8
        let longLegs=d.heron || d.species == .blackWingedStilt
        for x in [27.0,31.0] {
            let kneeY=longLegs ? top+(38.6-top)*0.48 : max(top+0.5,35.7)
            c.line([(x-1+d.pose.body.lean*0.4,top),
                    (x+d.pose.stance,kneeY),(x-0.5,38.6)],
                   d.legs,width:longLegs ? 0.7:0.95)
            // Terminal toes never move with stance, body, head, or wing. No
            // lifted-step pose or travel route is introduced by this batch.
            let reach=d.rail ? 4.0:2.0
            c.line([(x-reach,39),(x,38.6),(x+reach,39)],d.legs,width:0.7)
            if d.rail {
                c.line([(x,38.6),(x-2.5,37.8)],d.legs,width:0.6)
            }
            if d.species == .eurasianCoot {
                // The existing silver toe-lobe cue stays on the perch band.
                c.oval(x-2,38.1,2,0.9,"silver")
                c.line([(x-2.6,38.9),(x-0.4,38.7)],"brown",width:0.45)
            }
        }
    }

    private static func tail(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, tx=p.tail.x, ty=p.tail.y, w=d.anatomy.tailWidth
        let root=d.bodyPoint(-0.40,0.12)
        let edge: [Point]
        if d.species == .commonMoorhen {
            // A short, raised fan rotates around the rump, revealing its pale
            // underside in the lift. It is not a passerine's elongated tail.
            edge=[(root.0+2,root.1),(tx,ty-1),(tx+w,ty-1.8),
                  (root.0+5,root.1+3.5),(root.0+1,root.1+4)]
        } else if d.species == .eurasianCoot {
            edge=[root,(tx,ty-0.5),(tx+w,ty),
                  (root.0+4,root.1+3),(root.0+1,root.1+3.5)]
        } else if d.heron {
            edge=[root,(tx,ty-1),(tx+w,ty),(root.0+5,root.1+4)]
        } else {
            edge=[root,(tx,ty-0.8),(tx+w,ty+1),(root.0+5,root.1+3.5)]
        }
        c.poly(edge,d.feather,outline:true)
        c.within(edge) {
            if d.species == .commonMoorhen {
                c.poly([(tx+0.5,ty),(tx+w-0.4,ty-0.8),
                        (root.0+4,root.1+2.8),(root.0+2,root.1+2)],"white")
                c.line([(tx+1.5,ty-0.3),(root.0+2.7,root.1+1.5)],"black",width:1)
            } else {
                let light=d.heron ? "silver":(d.species == .whimbrel ? "buff":d.back)
                c.line([(root.0+1,root.1+1),(tx+1,ty)],light,width:0.7)
                if d.species == .littleRingedPlover {
                    c.line([(tx+0.5,ty),(tx+w-0.5,ty+0.8)],"white",width:0.8)
                }
            }
        }
    }

    private static func torso(_ c:BirdPainter, _ d:Drawing) {
        let edge=(0..<24).map { i -> Point in
            let angle=Double(i)*Double.pi/12
            return d.bodyPoint(cos(angle),sin(angle))
        }
        c.poly(edge,d.back,outline:true)
        c.within(edge) {
            c.poly([d.bodyPoint(0,-0.85),d.bodyPoint(1.1,-0.65),
                    d.bodyPoint(1.1,0.9),d.bodyPoint(-0.25,1.1),
                    d.bodyPoint(-0.10,0.10)],d.breast)
            switch d.species {
            case .greyHeron:
                // Broad gray mantle, pale breast and short dark streaks remain
                // separate from the long, thin neck's own moving streaks.
                c.poly([d.bodyPoint(-0.8,-0.7),d.bodyPoint(0.1,-1),
                        d.bodyPoint(0.5,-0.1),d.bodyPoint(-0.5,0.45)],"slate")
                for n in 0..<3 {
                    let u=0.42+Double(n)*0.15
                    c.line([d.bodyPoint(u,-0.1),d.bodyPoint(u-0.12,0.6)],"dark",width:0.6)
                }
            case .nightHeron:
                c.poly([d.bodyPoint(-0.9,-0.7),d.bodyPoint(0,-1),
                        d.bodyPoint(0.4,-0.1),d.bodyPoint(-0.3,0.3)],"navy")
            case .chinesePondHeron:
                // Keep the baseline's rust head/neck/mantle and white folded
                // wing throughout; there is no plumage-season switch.
                c.line([d.bodyPoint(0.6,-0.1),d.bodyPoint(0.4,0.8)],"tan",width:0.7)
            case .whimbrel:
                for n in 0..<5 {
                    let u=0.12+Double(n)*0.15
                    c.line([d.bodyPoint(u,0.1),d.bodyPoint(u-0.08,0.50)],"brown",width:0.6)
                }
            case .commonMoorhen:
                c.line([d.bodyPoint(-0.55,0.28),d.bodyPoint(-0.05,0.38),
                        d.bodyPoint(0.35,0.49)],"white",width:0.95)
            case .eurasianCoot:
                c.curve([d.bodyPoint(0.10,-0.50),d.bodyPoint(0.8,-0.1),
                         d.bodyPoint(0.7,0.7),d.bodyPoint(0.10,0.82)],"slate",width:0.5)
            default: break
            }
        }
        if d.pose.ruffle>0 || d.pose.body.fluff>0.6 {
            // Anatomical feather tips are drawn outside the pigment pass.
            // They add small, local shoulder/belly contours, never motion rays.
            let amount=max(d.pose.ruffle,d.pose.body.fluff*0.35)
            for n in 0..<3 {
                let root=d.bodyPoint(-0.5+Double(n)*0.3,0.72)
                c.poly([(root.0-1,root.1),(root.0+1.1,root.1-0.4),
                        (root.0+0.4,root.1+amount)],d.breast)
            }
        }
    }

    private static func neck(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy
        let nape=p.headPoint(-p.headWidth(anatomy:a)*0.30,a.headHeight*0.2)
        let chin=p.headPoint(p.headWidth(anatomy:a)*0.28,a.headHeight*0.38)
        let root=d.bodyPoint(0.55,0.30)
        if d.species == .greyHeron || d.species == .chinesePondHeron {
            let joint=p.neck
            let thickness=d.species == .greyHeron ? 3.8:4.0
            let lower=[root,(root.0+6,root.1-1),
                       (joint.x+3,joint.y+3),(joint.x,joint.y)]
            let upper=[(joint.x,joint.y),(joint.x-3.6,joint.y-4),
                       (nape.0-2,nape.1+1),(nape.0+0.7,nape.1)]
            for path in [lower,upper] {
                c.curve(path,"outline",width:thickness+Double(c.unit)*1.3)
                c.curve(path,d.species == .greyHeron ? "gray":"rust",width:thickness)
                c.curve(path.map { ($0.0+0.35,$0.1) },d.breast,width:thickness-1)
            }
            if d.species == .greyHeron {
                // Neck streaks follow the authored bend, not fixed canvas y's.
                c.pigment {
                    for t in [0.30,0.63] {
                        let x=joint.x+(nape.0-joint.x)*t
                        let y=joint.y+(nape.1-joint.y)*t
                        c.line([(x+0.3,y-0.6),(x-0.1,y+0.5)],"dark",width:0.55)
                    }
                }
            }
        } else if d.species == .nightHeron {
            let edge=[d.bodyPoint(-0.05,-0.60),nape,chin,d.bodyPoint(0.92,0.65)]
            c.poly(edge,"white")
            let path=[root,(p.neck.x+3,p.neck.y+2),
                      (chin.0+3,chin.1+4),chin]
            c.curve(path,"silver",width:5.1)
            c.curve(path.map { ($0.0+0.35,$0.1-0.2) },"white",width:3.6)
            c.line([d.bodyPoint(0.1,-0.4),nape],"silver",width:0.6)
        } else if d.species == .blackWingedStilt {
            // Thin upright neck and shallow torso keep the long legs exposed.
            let path=[root,(root.0+2,d.y-1),(p.neck.x,p.neck.y),nape]
            c.curve(path,"outline",width:2.7+Double(c.unit)*1.4)
            c.curve(path,"white",width:2.7)
        } else if d.rail {
            // Rails have a broad rising forebody and a compact neck. In the
            // breast-preen pose the chin reaches the real chest, not empty air.
            let edge=[d.bodyPoint(0.05,-0.65),nape,chin,d.bodyPoint(0.94,0.65)]
            c.poly(edge,"dark")
            c.curve([root,(p.neck.x,p.neck.y),
                     (chin.0+0.8,chin.1+2),chin],"dark",width:4.8)
        } else {
            let edge=[d.bodyPoint(0,-0.65),nape,chin,d.bodyPoint(0.95,0.55)]
            c.poly(edge,d.breast)
            c.within(edge) {
                c.line([d.bodyPoint(0.10,-0.55),nape],d.back,width:1.5)
                if d.species == .littleRingedPlover {
                    let middle=p.headPoint(0,a.headHeight*0.75)
                    c.line([p.headPoint(-2,a.headHeight*0.5),middle,
                            p.headPoint(2.3,a.headHeight*0.52)],"white",width:2.3)
                    c.line([p.headPoint(-2,a.headHeight*0.8),
                            p.headPoint(0,a.headHeight*1.03),
                            p.headPoint(2.4,a.headHeight*0.8)],"black",width:1.4)
                } else {
                    c.line([chin,(root.0,root.1-1)],"brown",width:0.7)
                }
            }
        }
    }

    private static func foldedWing(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, b=d.pose.body
        let x=d.x+b.lean*0.65, y=d.y, h=d.height
        let shoulder=d.heron ? 11.0:(d.rail ? 15:12)
        let shift=p.wing*2.2, drop=p.ruffle*0.8
        let edge: [Point]
        if d.heron {
            edge=[(x+2,y+1),(x+7,y+0.4),(x+shoulder,y+3),
                  (x+8,y+h-1),(x-0.5-shift,y+h+0.3+drop),
                  (x+0.5,y+h*0.55)]
        } else if d.species == .blackWingedStilt {
            // Long pointed black primaries project behind a shallow white body.
            edge=[(x+3,y+0.5),(x+8,y),(x+12,y+2.8),
                  (x+7,y+h-0.5),(x-2-shift,y+h+1),(x,y+h*0.50)]
        } else if d.species == .eurasianCoot {
            // Broader, rounder coverts than the moorhen's narrow wing panel.
            edge=[(x+6,y+1),(x+12,y+0.5),(x+18,y+4),
                  (x+15,y+h-2),(x+6,y+h-0.5+drop),
                  (x+2-shift,y+h-2),(x+3,y+h*0.45)]
        } else {
            edge=[(x+3,y+1),(x+8,y+0.6),(x+shoulder,y+3.5),
                  (x+shoulder-2,y+h*0.66),(x+2-shift,y+h-0.5+drop),
                  (x,y+h-1),(x+1,y+h*0.48)]
        }
        c.poly(edge,d.feather,outline:true)
        c.within(edge) {
            let cover=d.heron ? "silver":d.back
            if d.species != .blackWingedStilt {
                c.poly([(x+3,y+1.4),(x+7,y+1),(x+shoulder-1,y+3.3),
                        (x+6,y+h*0.62),(x+2,y+h*0.6)],cover)
            }
            let count=d.rail ? 6:5
            for n in 0..<count {
                let xx=x+2+Double(n)*(d.rail ? 1.8:1.5)
                let ink=d.species == .blackWingedStilt ? "dark":
                    (d.heron ? "slate":d.back)
                c.line([(xx+4,y+3),(xx-shift,y+h-1+drop)],ink,width:0.65)
            }
            if d.species == .chinesePondHeron {
                // White wing panel stays dominant over its silver feather ribs.
                c.poly([(x+2,y+2),(x+6,y+1.5),(x+10,y+3),
                        (x+6,y+h-2),(x+1,y+h-1.3)],"white")
                c.line([(x+7,y+3),(x+2,y+h-1)],"silver",width:0.6)
            } else if d.species == .whimbrel {
                for row in 0..<3 {
                    for col in 0..<4 {
                        let xx=x+2+Double(col)*2.2, yy=y+2+Double(row)*1.9
                        c.line([(xx,yy),(xx+1,yy+0.65)],"buff",width:0.6)
                    }
                }
            } else if d.species == .littleRingedPlover {
                c.line([(x+1,y+h-2),(x+6,y+h*0.55),(x+10,y+4)],"tan",width:0.7)
            } else if d.species == .commonMoorhen {
                c.line([(x+3,y+h*0.68),(x+8,y+h*0.73),
                        (x+12,y+h*0.80)],"white",width:0.8)
            }
        }
        if d.species == .nightHeron && p.body.fluff>1 {
            c.poly([(x+5,y+1),(x+6,y-0.8),(x+8,y-0.2),
                    (x+10,y-0.6),(x+11,y+2),(x+8,y+3)],"gray")
            c.line([(x+6,y+0.5),(x+8,y+1.5),(x+10,y+0.8)],"silver",width:0.6)
        }
    }

    private static func head(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy
        let w=p.headWidth(anatomy:a), h=a.headHeight, x = -w/2, y = -h/2
        // Head anatomy alone rotates; world-space feet/torso never transform.
        // Geometry.beakAnchor applies this identical transform to billPath.
        c.ctx.saveGState()
        c.ctx.translateBy(x:p.head.x,y:p.head.y)
        c.ctx.rotate(by:CGFloat(p.head.pitch))
        if d.species == .nightHeron {
            c.curve([(x+0.5,y+1),(x-2,y+1),(x-2.5,y+3.5),(x-5.5,y+4.4)],"white",width:0.55)
            c.curve([(x,y+1),(x-2.8,y+1),(x-3,y+3),(x-6.5,y+3.5)],"silver",width:0.5)
        } else if d.species == .greyHeron {
            c.line([(x+1,y+1.6),(x-3.3,y+3.3)],"black",width:0.7)
        }
        c.oval(x,y,w,h,d.headFill,outline:true)
        withinOval(c,x,y,w,h) {
            switch d.species {
            case .nightHeron:
                c.poly([(x,y+2),(x+1,y),(x+w-2,y-0.3),
                        (x+w,y+1.3),(x+w,y+2.3),(x+2,y+2.2)],"navy")
            case .greyHeron:
                c.line([(x+0.2,y+1.5),(x+w-1.8,y+1.6)],"black",width:1.1)
            case .chinesePondHeron:
                c.line([(x+0.4,y+1.2),(x+3,y+0.6)],"tan",width:0.6)
                c.line([(x+1,y+3),(x+3,y+4)],"brown",width:0.5)
            case .blackWingedStilt:
                c.poly([(x,y+1),(x+2,y),(x+4,y+0.5),
                        (x+4,y+2),(x,y+3)],"black")
            case .whimbrel:
                c.line([(x+0.4,y+1),(x+w-1,y+0.7)],"cream",width:0.75)
                c.line([(x+1,y+2.4),(x+w-1,y+2)],"umber",width:0.75)
                c.line([(x+0.2,y+4.2),(x+2,y+5)],"buff",width:0.6)
            case .littleRingedPlover:
                c.line([(x,y+2),(x+w-1,y+2)],"black",width:1.05)
                c.poly([(x+2,y+0.6),(x+4.8,y+0.3),
                        (x+5,y+1.4),(x+2.4,y+1.7)],"white")
                c.line([(x+1,y+5),(x+4,y+6),(x+w,y+5)],"white",width:1.2)
            case .commonMoorhen:
                c.oval(w/2-2.1,y+1,2,3.5,"red")
            case .eurasianCoot:
                // Taller, white shield and bill, with no moorhen flank stripe.
                c.oval(w/2-2.1,y+0.3,2.1,4,"white")
            default: break
            }
        }
        let ex=w*0.20-p.turn*0.6, ey = -h*0.12
        c.pigment {
            if d.heron || d.species == .littleRingedPlover {
                c.oval(ex-0.5,ey-0.45,1.9,1.9,d.species == .nightHeron ? "red":"yellow")
            } else if d.species == .eurasianCoot {
                c.oval(ex-0.3,ey-0.3,1.55,1.55,"rust")
            }
            if p.eye<0.4 {
                c.line([(ex-0.15,ey+0.45),(ex+0.45,ey+0.65),
                        (ex+0.95,ey+0.4)],"eye",width:0.65)
            } else {
                c.oval(ex,ey+0.25*(1-p.eye),0.9,0.35+0.65*p.eye,"eye")
                c.oval(ex+0.35,ey+0.1,0.35,0.35,"white")
            }
        }
        let path=p.billPath(anatomy:a)
        if a.curvedBill {
            // The full cubic stays curved in Dip and Tuck as it articulates.
            // The round-capped endpoint, not a straight extrapolation, anchors.
            c.curve(path,"dark",width:0.9)
        } else {
            c.poly(path,d.billFill)
            c.within(path) {
                if d.species == .commonMoorhen {
                    let tip=path[1]
                    c.poly([(tip.0-1.3,tip.1-0.6),tip,
                            (tip.0-1.2,tip.1+0.8)],"yellow")
                } else if d.heron {
                    c.line([(path[0].0+0.6,-0.3),(path[1].0-1,0.25)],
                           d.billFill == "yellow" ? "buff":"slate",width:0.45)
                }
            }
        }
        c.ctx.restoreGState()
    }

    private static func tuckedShoulder(_ c:BirdPainter, _ d:Drawing) {
        let tx=d.pose.head.x, ty=d.pose.head.y
        // Leave the crown visible; the backward-pointing bill nestles in a
        // shoulder feather pocket. Its geometric endpoint remains authoritative.
        let left=tx-(d.anatomy.curvedBill ? 12:10)
        c.poly([(left,ty+2),(left+2,ty),(tx-1,ty+1),
                (tx+2,ty+3),(tx+1,ty+6),(left+1,ty+6)],d.feather,outline:true)
        for n in 0..<3 {
            let xx=left+3+Double(n)*2
            c.line([(xx,ty+1.5),(xx-0.7,ty+4.5)],d.heron ? "silver":d.back,width:0.6)
        }
    }

    private static func openingWing(_ c:BirdPainter, _ d:Drawing, far:Bool) {
        let amount=d.pose.wing
        let root=d.bodyPoint(far ? 0.20 : -0.05,-0.55)
        // Gray heron's wide scapular mass, stilt's slim pointed primaries and
        // the rails' broad short wings each have their own extension contour.
        let span=d.species == .greyHeron ? 19.0:
            (d.species == .blackWingedStilt ? 17:(d.rail ? 14:16))
        let rise=d.heron ? 14.0:(d.rail ? 12:15)
        let tipX=root.0-span*amount*(far ? 0.75:1)
        let tipY=root.1-rise*amount*(far ? 0.75:1)
        let fan=d.rail ? 6.0:4.5
        let edge: [Point]
        if d.species == .blackWingedStilt {
            edge=[root,(root.0-4*amount,root.1-4*amount),
                  (tipX,tipY),(tipX+1,tipY+2*amount),
                  (tipX+3,tipY+5*amount),(root.0-3,root.1+4)]
        } else {
            edge=[root,(root.0-5*amount,root.1-3*amount),
                  (tipX,tipY),(tipX+0.6,tipY+2*amount),
                  (tipX+2,tipY+fan*amount),(tipX+3.5,tipY+(fan-1)*amount),
                  (tipX+5,tipY+(fan+1)*amount),(root.0-3,root.1+4),
                  (root.0+1,root.1+2)]
        }
        c.poly(edge,d.feather,outline:true)
        c.within(edge) {
            for n in 0..<5 {
                let offset=Double(n)*1.1
                c.line([(root.0-2,root.1+offset*0.35),
                        (tipX+offset,tipY+1+offset*0.8)],
                       d.heron ? "silver":d.back,width:0.65)
            }
            if d.species == .whimbrel {
                c.line([(root.0-3,root.1-1),(tipX+4,tipY+4)],"buff",width:0.8)
            }
        }
    }
}
