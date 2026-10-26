import AppKit
import BirdingCore

/// M8e's new drawings only. Paths are rasterized at catalog density without
/// loading, rotating or scaling any old frame. The canvas is 48 logical units.
enum M8RaptorArt {
    private typealias Geometry = M8RaptorArtGeometry
    private typealias Point = (Double, Double)

    private struct Colors {
        let back, wing, head, breast: String

        init(_ back: String, _ wing: String, _ head: String, _ breast: String) {
            self.back = back; self.wing = wing; self.head = head; self.breast = breast
        }
    }

    private struct Drawing {
        let id: SpeciesID
        let pose: Geometry.Pose
        let anatomy: Geometry.Anatomy
        let colors: Colors

        var owl: Bool { anatomy.owl }
        var centerX: Double { owl ? 28 : 34 - anatomy.width / 2 }

        /// The torso leans at its shoulder while the lower belly remains over
        /// the planted legs. Broad buzzard shoulders are separate from falcons.
        func bodyPoint(_ u: Double, _ v: Double) -> Point {
            let b = pose.body
            let shoulderWidth = id == .commonBuzzard && v < 0 ? 1.06 : 1.0
            return (centerX + u * (anatomy.width / 2 + b.fluff / 2) * shoulderWidth
                        + b.lean * (1 - v) / 2,
                    b.y + b.height * (v + 1) / 2)
        }
    }

    static func image(_ frame: String, species: SpeciesID) -> CGImage? {
        guard let a = Geometry.anatomy(for: species),
              let p = Geometry.pose(species: species, frame: frame),
              let colors = colors(for: species) else { return nil }
        let density = SpeciesCatalog.standard.profile(species).relativeScale
        let c = BirdPainter(size: max(48, Int((48 * density).rounded())))
        let d = Drawing(id: species, pose: p, anatomy: a, colors: colors)
        tail(c, d)
        legs(c, d)
        if !d.owl && p.wing > 0.18 {
            wing(c, d, far: true)
        }
        // The neck joins behind the torso so its fill cannot erase the chest
        // bars or longitudinal streaks when the head lowers over the shoulder.
        neck(c, d)
        body(c, d)
        if d.owl {
            owlWing(c, d, right: true)
            owlWing(c, d, right: false)
        } else {
            wing(c, d, far: false)
        }
        head(c, d)
        toes(c, d)
        return c.image
    }

    /// Identical palette keys to the existing species drawings. Owl colors
    /// follow DetailedBirdArt.owl rather than its generic fallback palette.
    private static func colors(for species: SpeciesID) -> Colors? {
        switch species {
        case .commonKestrel: return Colors("orange", "rust", "gray", "cream")
        case .peregrineFalcon: return Colors("slate", "navy", "navy", "cream")
        case .blackKite: return Colors("brown", "umber", "tan", "brown")
        case .commonBuzzard: return Colors("umber", "brown", "brown", "cream")
        case .littleOwl: return Colors("brown", "brown", "brown", "buff")
        case .collaredScopsOwl: return Colors("gray", "umber", "gray", "cream")
        case .asianBarredOwlet: return Colors("rust", "brown", "rust", "cream")
        case .piedKingfisher: return Colors("silver", "black", "black", "white")
        default: return nil
        }
    }

    private static func tail(_ c: BirdPainter, _ d: Drawing) {
        let p = d.pose, a = d.anatomy
        let root = d.bodyPoint(-0.42, 0.04), x = p.tail.x, y = p.tail.y
        let edge: [Point]
        if d.id == .blackKite {
            // Two tips and a concave notch: pigment is clipped so the fork's
            // transparent negative space survives every perch/preen pose.
            edge = [(root.0,root.1), (x,y-a.tailWidth/2), (x+4,y),
                    (x,y+a.tailWidth/2), (root.0+5,root.1+3.5)]
        } else if d.owl {
            edge = [(root.0,root.1), (root.0+6,root.1+2),
                    (x+a.tailWidth,y), (x+1,y+0.5), (x,y-1)]
        } else {
            edge = [(root.0,root.1), (root.0+5,root.1+3),
                    (x+a.tailWidth,y+0.8), (x,y)]
        }
        c.poly(edge, d.colors.wing, outline: true)
        c.within(edge) {
            c.line([(root.0+1,root.1+0.5),(x+1,y-0.2)],d.colors.back,width:0.7)
            if d.id == .blackKite {
                c.line([(root.0+3,root.1+2),(x+0.6,y+2.6)],"brown",width:0.8)
            } else if d.id == .commonKestrel {
                c.line([(x+0.3,y-0.7),(x+a.tailWidth-0.3,y+0.3)],"black",width:1.8)
            } else {
                let bars = d.owl || d.id == .commonBuzzard || d.id == .piedKingfisher
                if bars {
                    for n in 0..<3 {
                        let t = 0.50 + Double(n) * 0.17
                        let px = root.0 + (x-root.0)*t
                        let py = root.1 + (y-root.1)*t
                        c.line([(px,py),(px+a.tailWidth*t,py+0.8)],
                               d.id == .piedKingfisher ? "white" : "buff",width:0.65)
                    }
                }
            }
        }
    }

    private static func legs(_ c: BirdPainter, _ d: Drawing) {
        let p = d.pose, top = min(34.5, p.body.y + p.body.height - 2)
        let xs: [Double] = d.owl ? [26,32] : [27,31]
        let color = d.owl ? (d.id == .collaredScopsOwl ? "gray" : "cream")
            : (d.id == .piedKingfisher ? "brown" : "yellow")
        for x in xs {
            let kneeX = x - 0.6 + p.body.lean * 0.32
            c.line([(x+p.body.lean*0.45,top),(kneeX,35.7),(x,38.5)],
                   color,width:d.owl ? 1.8 : 1)
        }
    }

    private static func toes(_ c: BirdPainter, _ d: Drawing) {
        let xs: [Double] = d.owl ? [26,32] : [27,31]
        let color = d.owl ? "tan" : (d.id == .piedKingfisher ? "brown" : "yellow")
        // Immutable contact chains around the established (29,39) reference.
        // Drawn last so a relaxed wing cannot cover a supporting toe.
        for x in xs {
            c.line([(x-2,39),(x,38.5),(x+2,39)],color,width:d.owl ? 0.8 : 0.75)
        }
    }

    private static func body(_ c: BirdPainter, _ d: Drawing) {
        let edge = (0..<24).map { n -> Point in
            let angle = Double(n) * .pi / 12
            return d.bodyPoint(cos(angle), sin(angle))
        }
        c.poly(edge,d.colors.back,outline:true)
        c.within(edge) {
            if d.owl {
                let b = d.pose.body
                c.oval(22.5+b.lean*0.35,b.y+2.4,12.5,b.height-2.6,d.colors.breast)
                for row in 0..<5 {
                    let yy = b.y + 4 + Double(row) * (b.height-5) / 5
                    if d.id == .asianBarredOwlet && row < 2 {
                        c.line([(24+b.lean*0.3,yy),(33+b.lean*0.3,yy+0.3)],"brown",width:0.7)
                    } else {
                        for col in 0..<3 {
                            let xx = 25 + Double(col)*3 + Double(row%2)*0.45 + b.lean*0.3
                            c.line([(xx,yy),(xx+0.2,yy+1.3)],
                                   d.id == .asianBarredOwlet ? "brown" : "umber",width:0.7)
                            if d.id == .collaredScopsOwl {
                                c.line([(xx-0.6,yy+0.5),(xx+0.7,yy+0.9)],"brown",width:0.6)
                            }
                        }
                    }
                }
                return
            }
            c.poly([d.bodyPoint(0,-0.76),d.bodyPoint(0.9,-0.85),d.bodyPoint(1.1,0),
                    d.bodyPoint(0.9,1.1),d.bodyPoint(-0.05,1.1),d.bodyPoint(-0.15,0.2)],d.colors.breast)
            switch d.id {
            case .commonKestrel, .peregrineFalcon:
                for row in 0..<5 {
                    let v = -0.35 + Double(row)*0.24
                    for col in 0..<3 {
                        let u = 0.35 + Double(col)*0.18
                        c.line([d.bodyPoint(u,v),d.bodyPoint(u+0.07,v+0.045)],
                               d.id == .commonKestrel ? "rust" : "slate",width:0.65)
                    }
                }
            case .commonBuzzard:
                c.poly([d.bodyPoint(0.3,-0.6),d.bodyPoint(0.78,-0.65),
                        d.bodyPoint(0.87,-0.1),d.bodyPoint(0.36,0.06),d.bodyPoint(0.1,-0.2)],"brown")
                for row in 0..<4 {
                    let v = 0.25 + Double(row)*0.14
                    c.line([d.bodyPoint(0.25,v),d.bodyPoint(0.73,v+0.02)],"tan",width:0.65)
                }
            case .blackKite:
                for n in 0..<3 {
                    let u = 0.25 + Double(n)*0.2
                    c.line([d.bodyPoint(u,-0.5),d.bodyPoint(u-0.08,0.25)],"tan",width:0.6)
                }
            case .piedKingfisher:
                c.line([d.bodyPoint(0.2,-0.62),d.bodyPoint(0.9,-0.4)],"black",width:1.5)
                c.line([d.bodyPoint(0.34,-0.12),d.bodyPoint(0.93,0.08)],"black",width:0.9)
            default: break
            }
        }
    }

    private static func neck(_ c: BirdPainter, _ d: Drawing) {
        let p = d.pose, a = d.anatomy
        let nape = p.headPoint(-a.headWidth*0.30,a.headHeight*0.2)
        let chin = p.headPoint(a.headWidth*0.30,a.headHeight*0.34)
        let left = d.bodyPoint(d.owl ? -0.55 : -0.05,-0.4)
        let right = d.bodyPoint(0.82,0.4)
        let edge = [left,nape,chin,right]
        c.poly(edge,d.colors.breast)
        c.within(edge) {
            c.poly([left,nape,(nape.0+1.3,nape.1+1.8),d.bodyPoint(0.18,0)],d.colors.back)
            if d.id == .blackKite {
                c.line([(chin.0-1,chin.1),(right.0-1,right.1-1)],"tan",width:0.6)
            } else if d.id == .collaredScopsOwl {
                c.line([p.headPoint(-5,4),p.headPoint(0,5.3),p.headPoint(5,4)],"buff",width:1)
            }
        }
    }

    private static func wing(_ c: BirdPainter, _ d: Drawing, far: Bool) {
        let p = d.pose, b = p.body, open = p.wing
        let kite = d.id == .blackKite, buzzard = d.id == .commonBuzzard
        let rootX = (far ? 28.0 : 25.0) + b.lean
        let rootY = b.y + 1 + p.shoulder * 0.4
        let span = ((kite || buzzard ? 9.0 : 7.5) + open * 15) * (far ? 0.63 : 1)
        let length = (b.height-2)*(1-open) + 7*open
        func w(_ u: Double, _ v: Double) -> Point {
            (rootX + (far ? 1 : -1)*u*span + v*(far ? 0.4 : -1.4),
             rootY + v*length - u*open*17 + p.shoulder*v)
        }
        let edge: [Point]
        if kite {
            edge = [w(-0.35,0.13),w(0.12,-0.04),w(0.53,0.12),w(1,1.28),
                    w(0.83,1.22),w(0.64,1.16),w(0.15,0.64),w(-0.42,0.26)]
        } else if buzzard {
            edge = [w(-0.43,0.16),w(0.05,-0.06),w(0.60,0.05),w(1,0.85),
                    w(0.87,1.04),w(0.73,0.94),w(0.59,1.08),w(0.33,0.98),
                    w(-0.22,0.58),w(-0.47,0.30)]
        } else if d.id == .piedKingfisher {
            edge = [w(-0.33,0.10),w(0.08,-0.02),w(0.53,0.13),w(0.98,1.02),
                    w(0.68,0.96),w(0.12,0.66),w(-0.4,0.28)]
        } else {
            // Narrower tapered primaries in the kestrel; the peregrine has a
            // broader compact shoulder and its own shorter terminal contour.
            let peregrine = d.id == .peregrineFalcon
            edge = [w(peregrine ? -0.46 : -0.32,0.12),w(0.08,-0.02),
                    w(peregrine ? 0.62 : 0.47,0.13),w(1,peregrine ? 1.02 : 1.17),
                    w(0.76,1),w(0.16,0.65),w(-0.4,0.27)]
        }
        c.poly(edge,far ? d.colors.back : d.colors.wing,outline:true)
        c.within(edge) {
            c.poly([w(-0.25,0.18),w(0.1,0.07),w(0.49,0.19),
                    w(0.43,0.50),w(0.03,0.61)],d.colors.back)
            for n in 0..<5 {
                let u = 0.12 + Double(n)*0.14
                c.line([w(u,0.32),w(u+0.19,kite ? 1.21 : 1)],
                       kite ? "brown" : d.colors.back,width:0.65)
            }
            if d.id == .commonKestrel {
                for n in 0..<7 {
                    let u = Double(n%3)*0.18
                    let v = 0.22 + Double(n/3)*0.14
                    c.line([w(u,v),w(u+0.035,v+0.07)],"umber",width:0.65)
                }
            } else if d.id == .piedKingfisher {
                c.line([w(-0.15,0.39),w(0.55,0.46)],"white",width:1.1)
                for n in 0..<9 {
                    let q = w(Double(n%3)*0.20,0.16+Double(n/3)*0.18)
                    c.oval(q.0,q.1,0.8,0.8,"white")
                }
            } else if buzzard {
                c.line([w(0.25,0.62),w(0.81,0.72)],"buff",width:0.7)
                c.line([w(0.4,0.79),w(0.86,0.90)],"umber",width:0.8)
            }
        }
    }

    private static func owlWing(_ c: BirdPainter, _ d: Drawing, right: Bool) {
        let p = d.pose, b = p.body, sign = right ? 1.0 : -1.0
        let rootX = 28 + sign * d.anatomy.width * 0.31 + b.lean * 0.7
        let rootY = b.y + 1.8 + p.shoulder*0.4
        let reach = 3.5 + p.wing * (right ? 8 : 11)
        func w(_ u: Double, _ v: Double) -> Point {
            (rootX + sign*u*reach - sign*v*0.8,
             rootY + v*(b.height-3)*(1-p.wing*0.38) - u*p.wing*15 + p.shoulder*v)
        }
        let edge = [w(-0.5,0.05),w(0.24,0.02),w(0.85,0.30),w(1,0.80),
                    w(0.7,1),w(0.3,1.04),w(-0.25,0.75),w(-0.55,0.26)]
        c.poly(edge,d.colors.wing,outline:true)
        c.within(edge) {
            for n in 0..<5 {
                let v = 0.18 + Double(n)*0.16
                if d.id == .asianBarredOwlet {
                    c.line([w(-0.2,v),w(0.8,v+0.045)],"buff",width:0.7)
                } else {
                    let q = w(0.2,v)
                    c.oval(q.0-0.4,q.1,1.4,1.0,
                           d.id == .collaredScopsOwl ? "tan" : "cream")
                }
            }
        }
    }

    private static func withinOval(_ c: BirdPainter, _ x: Double, _ y: Double,
                                   _ w: Double, _ h: Double, draw: () -> Void) {
        c.ctx.saveGState()
        c.ctx.addEllipse(in:CGRect(x:x,y:y,width:w,height:h)); c.ctx.clip()
        c.pigment(draw)
        c.ctx.restoreGState()
    }

    private static func head(_ c: BirdPainter, _ d: Drawing) {
        let p = d.pose
        c.ctx.saveGState()
        c.ctx.translateBy(x:p.head.x,y:p.head.y)
        c.ctx.rotate(by:p.head.pitch)
        if d.owl { owlFace(c,d) } else { profileHead(c,d) }
        let billColor = d.owl ? (d.id == .collaredScopsOwl ? "cream" : "yellow") : "dark"
        c.poly(p.billVertices(anatomy:d.anatomy),billColor,outline:d.owl)
        if !d.owl && d.id != .piedKingfisher {
            let root = p.headWidth(anatomy:d.anatomy)/2-0.5
            c.pigment { c.oval(root-0.5,-1,1.5,2,"yellow") }
        }
        c.ctx.restoreGState()
    }

    private static func profileHead(_ c: BirdPainter, _ d: Drawing) {
        let p = d.pose, a = d.anatomy
        let w = p.headWidth(anatomy:a), h = a.headHeight, x = -w/2, y = -h/2
        if d.id == .piedKingfisher {
            c.poly([(x,y+2),(x-1,y),(x+2,y+0.5),(x+2,y-1.4),
                    (x+5,y+0.4),(x+7,y),(x+6,y+2)],"black",outline:true)
        }
        c.oval(x,y,w,h,d.colors.head,outline:true)
        withinOval(c,x,y,w,h) {
            switch d.id {
            case .commonKestrel, .peregrineFalcon:
                c.poly([(x+1,0.5),(w/2-1,0),(w/2-1,h*0.38),(x+3,h/2)],"cream")
                let cheek = w/2-2.6+p.turn*0.4
                let cheekWidth = d.id == .peregrineFalcon ? 1.8 : 1.15
                c.poly([(cheek,-0.6),(cheek+cheekWidth,0),(cheek+cheekWidth-0.5,h/2),
                        (cheek-0.6,h/2-0.8)],"black")
            case .blackKite:
                for n in 0..<4 {
                    let xx = x+1+Double(n)*1.1
                    c.line([(xx,y+1.7),(xx+0.5,y+4.4)],"brown",width:0.6)
                }
            case .commonBuzzard:
                c.line([(x+1,y+1.4),(w/2-1,y+1.8)],"umber",width:0.65)
            case .piedKingfisher:
                c.poly([(x+1,0),(x+5,-0.5),(w/2-1,0),(w/2-2,2),(x+2,2)],"white")
                c.line([(x+2,y+1.2),(x+5,y+0.8)],"silver",width:0.6)
            default: break
            }
            let eyeX = w*0.22+p.turn*0.45, eyeY = -h*0.12
            if p.eyesClosed {
                c.line([(eyeX-0.25,eyeY+0.5),(eyeX+1.1,eyeY+0.6)],"eye",width:0.7)
            } else {
                c.oval(eyeX,eyeY,1,1.1,"eye")
                c.oval(eyeX+0.4,eyeY,0.45,0.45,"white")
            }
        }
    }

    private static func owlFace(_ c: BirdPainter, _ d: Drawing) {
        let p = d.pose, a = d.anatomy, w = a.headWidth, h = a.headHeight
        let x = -w/2, y = -h/2, scops = d.id == .collaredScopsOwl
        if scops {
            // Fixed ear-feather anatomy in head space, with no per-frame raise.
            c.poly([(x+1,y+5),(x,y-4),(x+5,y+1)],"umber",outline:true)
            c.poly([(w/2-5,y+1),(w/2,y-4),(w/2-1,y+5)],"umber",outline:true)
            c.pigment {
                c.line([(x+1,y-2),(x+3,y+2)],"buff",width:0.7)
                c.line([(w/2-1,y-2),(w/2-3,y+2)],"buff",width:0.7)
            }
        }
        c.oval(x,y,w,h,d.colors.head,outline:true)
        withinOval(c,x,y,w,h) {
            let mid = p.faceMid(anatomy:a), eyeY = h * -0.02
            let leftW = w*(0.38-max(0,p.turn)*0.12)
            let rightW = w*(0.38+min(0,p.turn)*0.12)
            c.oval(mid-leftW-0.5,y+h*0.25,leftW,h*0.66,scops ? "silver" : "buff",outline:scops)
            c.oval(mid+0.5,y+h*0.25,rightW,h*0.66,scops ? "silver" : "buff",outline:scops)
            if d.id == .asianBarredOwlet {
                for row in 0..<3 {
                    let yy = y+1.3+Double(row)*1.2, inset = 5-Double(row)*0.7
                    c.line([(x+inset,yy),(w/2-inset,yy)],"buff",width:0.6)
                }
            } else if !scops {
                for n in 0..<5 { c.oval(x+2+Double(n)*2.8,y+1.5,1.3,0.8,"cream") }
            }
            let eyeSize = w*0.19
            for ex in [mid-leftW*0.55,mid+rightW*0.55] {
                if p.eyesClosed {
                    c.line([(ex-eyeSize/2,eyeY+1),(ex,eyeY+1.3),(ex+eyeSize/2,eyeY+1)],"eye",width:0.9)
                } else {
                    c.oval(ex-eyeSize/2,eyeY-eyeSize/2,eyeSize,eyeSize,scops ? "orange" : "yellow",outline:true)
                    c.oval(ex-eyeSize*0.23,eyeY-eyeSize*0.3,eyeSize*0.46,eyeSize*0.65,"eye")
                    c.oval(ex,eyeY-eyeSize*0.23,0.55,0.55,"white")
                }
            }
            c.line([(mid-leftW+0.5,eyeY-2),(mid-1,eyeY-1)],scops ? "white" : "cream",width:scops ? 1 : 1.3)
            c.line([(mid+1,eyeY-1),(mid+rightW-0.5,eyeY-2)],scops ? "white" : "cream",width:scops ? 1 : 1.3)
            if d.id == .littleOwl {
                c.line([(x+3,y+h-2),(mid,y+h-0.7),(w/2-3,y+h-2)],"white",width:1)
            }
        }
    }
}
