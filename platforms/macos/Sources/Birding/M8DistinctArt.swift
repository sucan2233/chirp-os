import AppKit
import BirdingCore

/// M8f's new drawings only. All parts are authored as logical vector anatomy
/// and rasterized directly at catalog density; no existing image is an input.
enum M8DistinctArt {
    private typealias Geometry = M8DistinctArtGeometry
    private typealias Point = (Double, Double)

    private struct Drawing {
        let species: SpeciesID
        let frame: String
        let pose: Geometry.Pose
        let anatomy: Geometry.Anatomy

        var back: String {
            switch species {
            case .barnSwallow: return "navy"
            case .blackHeadedGull: return "white"
            case .hoopoe: return "orange"
            case .commonKingfisher: return "cyan"
            case .eurasianWoodcock: return "tan"
            case .blackCollaredStarling: return "brown"
            default: return "dark"
            }
        }
        var breast: String {
            switch species {
            case .barnSwallow, .blackCollaredStarling: return "cream"
            case .blackHeadedGull: return "white"
            case .hoopoe, .eurasianWoodcock: return "buff"
            case .commonKingfisher: return "orange"
            default: return "dark"
            }
        }
        var feather: String {
            switch species {
            case .barnSwallow, .commonKingfisher: return "blue"
            case .blackHeadedGull: return "silver"
            case .eurasianWoodcock: return "brown"
            case .blackCollaredStarling: return "dark"
            default: return "black"
            }
        }
        var head: String {
            switch species {
            case .barnSwallow: return "navy"
            case .blackHeadedGull: return "white"
            case .hoopoe: return "orange"
            case .commonKingfisher: return "blue"
            case .eurasianWoodcock: return "tan"
            case .blackCollaredStarling: return "cream"
            default: return "black"
            }
        }
        var bill: String {
            species == .asianKoel ? "cream" : (species == .blackHeadedGull ? "red" : "dark")
        }

        /// Lean displaces shoulders more than the low flank. Fullness changes
        /// the torso contour without translating the fixed supporting feet.
        func bodyPoint(_ u: Double, _ v: Double) -> Point {
            let b=pose.body
            return (34-anatomy.width-b.fluff/2 + u*(anatomy.width+b.fluff) + b.lean*(1-v),
                    b.y + b.height*v)
        }
    }

    static func image(_ frame: String, species: SpeciesID) -> CGImage? {
        guard let p=Geometry.pose(species:species,frame:frame),
              let a=Geometry.anatomy(for:species) else { return nil }
        let density=SpeciesCatalog.standard.profile(species).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let d=Drawing(species:species,frame:frame,pose:p,anatomy:a)
        tail(c,d)
        feet(c,d)
        if p.wing > 0.04 { wing(c,d,far:true) }
        torso(c,d)
        neck(c,d)
        wing(c,d,far:false)
        head(c,d)
        if frame == "restTuck" { tuckedShoulder(c,d) }
        return c.image
    }

    private static func feet(_ c: BirdPainter, _ d: Drawing) {
        let p=d.pose
        let hipY=min(36.1,p.body.y+p.body.height-1.7)
        let heavy=d.species == .largeBilledCrow
        for x in [27.0,31.0] {
            c.line([(x-0.8+p.body.lean*0.35,hipY),
                    (x-0.6+p.stance,hipY+(38-hipY)*0.55),(x,38.5)],
                   "brown",width:heavy ? 1.15 : 0.85)
            // Both entire toe chains are identical in every frame. Their
            // shared terminal vertex is the logical foot reference (29,39).
            c.line([(x-2,39),(x,38.5),(x+2,39)],"brown",width:heavy ? 0.95 : 0.75)
        }
    }

    private static func tail(_ c: BirdPainter, _ d: Drawing) {
        let p=d.pose, a=d.anatomy, tx=p.tail.x, ty=p.tail.y
        let root=d.bodyPoint(0.28,0.56)
        let edge: [Point]
        switch d.species {
        case .barnSwallow:
            // Two long streamers with an actual concave fork, not a dark mark.
            edge=[root,(tx,ty-2.4),(tx+6.2,ty-1.1),(tx+0.4,ty+2.4),
                  (root.0+4.2,root.1+3)]
        case .largeBilledCrow:
            // A broad short fan carries the heavy torso; no magpie-like shaft.
            edge=[root,(tx+0.7,ty-1.4),(tx,ty+0.1),(tx+2.3,ty+1.6),
                  (tx+5.6,ty+1.4),(tx+a.tailWidth,ty),
                  (root.0+5.6,root.1+3.5)]
        case .asianKoel:
            edge=[root,(tx,ty-0.7),(tx+0.5,ty+0.8),(tx+3.5,ty+1.1),
                  (tx+a.tailWidth,ty),(root.0+4,root.1+3)]
        case .commonKingfisher:
            edge=[root,(tx,ty-0.8),(tx+0.3,ty+1.1),(tx+a.tailWidth,ty+1),
                  (root.0+3.8,root.1+2.2)]
        case .blackHeadedGull:
            edge=[root,(tx-0.6,ty-0.7),(tx+1.5,ty+1.7),
                  (tx+a.tailWidth,ty+1),(root.0+4.8,root.1+2)]
        default:
            edge=[root,(tx,ty-0.8),(tx+0.5,ty+1.5),
                  (tx+a.tailWidth,ty+1),(root.0+4.5,root.1+3)]
        }
        let fill=d.species == .blackHeadedGull ? "white" : d.feather
        c.poly(edge,fill,outline:true)
        c.within(edge) {
            for n in 0..<3 {
                let offset=Double(n)*1.25
                c.line([(root.0+offset,root.1+1),(tx+0.9+offset,ty+0.1)],
                       d.species == .blackHeadedGull ? "silver" : d.back,width:0.6)
            }
            switch d.species {
            case .hoopoe:
                c.line([(tx+1.5,ty-3),(tx+6.5,ty-1)],"white",width:1.2)
            case .eurasianWoodcock:
                c.line([(tx+0.4,ty-0.2),(tx+a.tailWidth,ty+0.4)],"buff",width:0.8)
                c.line([(tx+1.4,ty-2),(tx+a.tailWidth+1,ty-1)],"umber",width:0.7)
            case .barnSwallow:
                c.line([(root.0,root.1),(tx+0.6,ty-2.2)],"navy",width:0.8)
            default: break
            }
        }
    }

    private static func torso(_ c: BirdPainter, _ d: Drawing) {
        let contour: [Point]
        switch d.species {
        case .barnSwallow:
            contour=[(0,0.43),(0.18,0.11),(0.56,0),(0.86,0.12),(1,0.45),
                     (0.9,0.77),(0.63,1),(0.25,0.88),(0.06,0.67)]
        case .blackHeadedGull:
            contour=[(0,0.45),(0.14,0.15),(0.43,0),(0.77,0.07),(0.97,0.29),
                     (1,0.62),(0.84,0.9),(0.44,1),(0.13,0.81)]
        case .commonKingfisher:
            contour=[(0,0.39),(0.17,0.08),(0.51,0),(0.87,0.16),(1,0.49),
                     (0.9,0.85),(0.65,1),(0.28,0.94),(0.06,0.71)]
        case .eurasianWoodcock:
            contour=[(0,0.47),(0.10,0.17),(0.37,0),(0.72,0.05),(0.94,0.28),
                     (1,0.6),(0.83,0.91),(0.46,1),(0.16,0.87),(0.03,0.68)]
        case .largeBilledCrow:
            contour=[(0,0.41),(0.13,0.09),(0.44,0),(0.74,0.04),(0.95,0.25),
                     (1,0.58),(0.87,0.87),(0.62,1),(0.24,0.91),(0.06,0.7)]
        case .asianKoel:
            contour=[(0,0.48),(0.16,0.14),(0.5,0),(0.8,0.12),(1,0.42),
                     (0.93,0.75),(0.67,1),(0.32,0.93),(0.08,0.73)]
        case .hoopoe:
            contour=[(0,0.4),(0.20,0.08),(0.56,0),(0.88,0.17),(1,0.5),
                     (0.87,0.85),(0.55,1),(0.19,0.83),(0.03,0.62)]
        default:
            contour=[(0,0.43),(0.17,0.10),(0.48,0),(0.81,0.12),(1,0.46),
                     (0.91,0.79),(0.64,1),(0.26,0.91),(0.05,0.67)]
        }
        let edge=contour.map { d.bodyPoint($0.0,$0.1) }
        c.poly(edge,d.back,outline:true)
        c.within(edge) {
            let breast:[Point]=[(0.54,0.1),(0.9,0.1),(1.12,0.5),
                                (0.89,1.1),(0.39,1.1),(0.46,0.58)]
            c.poly(breast.map { d.bodyPoint($0.0,$0.1) },d.breast)
            switch d.species {
            case .eurasianWoodcock:
                for row in 0..<5 {
                    let v=0.42+Double(row)*0.105
                    c.line([d.bodyPoint(0.56,v),d.bodyPoint(0.8,v+0.035),
                            d.bodyPoint(0.96,v+0.01)],row%2 == 0 ? "umber" : "tan",width:0.6)
                }
            case .largeBilledCrow, .asianKoel:
                for n in 0..<3 {
                    let u=0.71+Double(n)*0.065
                    c.line([d.bodyPoint(u,0.30),d.bodyPoint(u+0.025,0.46)],"slate",width:0.5)
                }
            case .barnSwallow:
                c.poly([d.bodyPoint(0.65,0.05),d.bodyPoint(1.04,0.12),
                        d.bodyPoint(0.96,0.42),d.bodyPoint(0.70,0.3)],"navy")
            case .commonKingfisher:
                c.line([d.bodyPoint(0.12,0.18),d.bodyPoint(0.18,0.65)],"cyan",width:1.1)
            case .blackHeadedGull:
                c.curve([d.bodyPoint(0.16,0.6),d.bodyPoint(0.4,0.96),
                         d.bodyPoint(0.72,0.96),d.bodyPoint(0.91,0.7)],"silver",width:0.5)
            default: break
            }
        }
    }

    private static func neck(_ c: BirdPainter, _ d: Drawing) {
        let a=d.anatomy, p=d.pose
        let rear=p.headPoint(-a.headWidth*0.30,a.headHeight*0.15)
        let throat=p.headPoint(a.headWidth*0.30,a.headHeight*0.38)
        let shoulder=d.bodyPoint(0.57,0.13), chest=d.bodyPoint(0.96,0.59)
        if d.species == .blackHeadedGull {
            // Gull's long torso keeps its own articulated curved neck rather
            // than inheriting the upright passerine wedge below.
            let route:[Point]=[d.bodyPoint(0.83,0.48),
                               (chest.0+1.8,p.body.y-0.4),
                               (rear.0-2.1,rear.1+1.8),rear]
            c.curve(route,"outline",width:4.3+Double(c.unit)*2)
            c.curve(route,"white",width:4.3)
            c.poly([rear,throat,chest,shoulder],"white")
        } else if d.species == .eurasianWoodcock {
            // A low, thick neck joins the rounded back; the long bill, not an
            // artificially stretched neck, supplies the downward reach.
            c.poly([d.bodyPoint(0.55,0.12),rear,throat,chest],"buff")
            c.pigment {
                c.line([(rear.0+0.2,rear.1+1),(throat.0-0.2,throat.1+1)],"umber",width:0.6)
            }
        } else {
            let edge:[Point]=[shoulder,rear,throat,chest]
            c.poly(edge,d.breast)
            c.within(edge) {
                c.poly([shoulder,rear,(rear.0+1,rear.1+1.2),d.bodyPoint(0.64,0.43)],d.back)
                if d.species == .blackCollaredStarling {
                    // Collar follows the moving head onto the neck, so it stays
                    // legible in a high call as well as a tucked head.
                    c.poly([p.headPoint(-3,2.3),p.headPoint(3.5,2.1),
                            p.headPoint(3.1,4.2),p.headPoint(-2.6,4.6)],"black")
                } else if d.species == .barnSwallow {
                    c.poly([p.headPoint(-0.5,1.4),throat,d.bodyPoint(0.9,0.24),
                            d.bodyPoint(0.72,0.24)],"rust")
                    c.line([d.bodyPoint(0.70,0.32),d.bodyPoint(0.95,0.36)],"navy",width:1.1)
                }
            }
            if d.species == .largeBilledCrow {
                // Slightly loose throat feathers belong to the broad crow
                // neck; the koel retains a smooth slender throat contour.
                c.poly([throat,(throat.0-0.3,throat.1+2.1),
                        (throat.0-1.2,throat.1+1.4),(throat.0-1.8,throat.1+2.5),
                        d.bodyPoint(0.87,0.4)],"dark")
            }
        }
    }

    private static func wing(_ c: BirdPainter, _ d: Drawing, far: Bool) {
        let p=d.pose, open=p.wing*(far ? 0.77 : 1)
        let root=d.bodyPoint(far ? 0.68 : 0.57,far ? 0.12 : 0.20)
        let broad=d.species == .largeBilledCrow || d.species == .eurasianWoodcock
        let pointed=d.species == .barnSwallow || d.species == .blackHeadedGull
        let span=d.species == .blackHeadedGull ? 13.0 : (broad ? 11.0 : 10.0)
        let tip:Point=(root.0-7-open*span,
                       root.1+(p.body.height-3)*(1-open)-14*open+p.droop*(far ? 0.4 : 1))
        // Wing-local u is along the humerus/primaries, v is chord width.
        // Independent wrist position changes the outline as the wing opens.
        func w(_ u:Double, _ v:Double) -> Point {
            (root.0+(tip.0-root.0)*u-v*(broad ? 3.5 : 2.5),
             root.1+(tip.1-root.1)*u+v*(4.1+open*2))
        }
        let local:[Point]
        if pointed {
            local=[(-0.10,0.12),(0.12,-0.48),(0.51,-0.40),(1,0),
                   (0.67,0.34),(0.30,0.70),(-0.15,0.60)]
        } else if broad {
            local=[(-0.13,0.1),(0.16,-0.48),(0.54,-0.44),(0.96,-0.07),
                   (1,0.16),(0.82,0.25),(0.87,0.40),(0.65,0.48),
                   (0.42,0.76),(-0.16,0.65)]
        } else {
            local=[(-0.12,0.1),(0.17,-0.43),(0.55,-0.36),(1,0),
                   (0.92,0.19),(0.68,0.40),(0.36,0.69),(-0.16,0.60)]
        }
        let edge=local.map { w($0.0,$0.1) }
        c.poly(edge,far ? d.back : d.feather,outline:true)
        c.within(edge) {
            c.poly([w(-0.08,0.12),w(0.15,-0.25),w(0.48,-0.2),
                    w(0.47,0.20),w(0.08,0.5)],d.back)
            let shaft=d.species == .hoopoe ? "dark" :
                (d.species == .blackHeadedGull ? "gray" : d.back)
            for n in 0..<5 {
                let u=0.30+Double(n)*0.13
                c.line([w(u,-0.20),w(min(1,u+0.22),0.25)],shaft,width:0.65)
            }
            switch d.species {
            case .hoopoe:
                for u in [0.24,0.50,0.77] {
                    c.line([w(u,-0.50),w(u+0.025,0.65)],"white",width:0.9)
                }
            case .blackCollaredStarling:
                c.line([w(0.30,-0.34),w(0.38,0.57)],"white",width:1.25)
            case .commonKingfisher:
                c.line([w(0.1,-0.29),w(0.72,-0.15)],"cyan",width:1.15)
                for row in 0..<3 {
                    for col in 0..<3 {
                        let q=w(0.12+Double(row)*0.16,Double(col)*0.17-0.12)
                        c.oval(q.0,q.1,0.55,0.55,"cyan")
                    }
                }
            case .eurasianWoodcock:
                for row in 0..<4 {
                    for col in 0..<3 {
                        let u=0.12+Double(row)*0.21, v = -0.19+Double(col)*0.23
                        c.line([w(u,v),w(u+0.055,v+0.08),w(u+0.11,v)],
                               (row+col)%2 == 0 ? "buff" : "umber",width:0.65)
                    }
                }
            case .blackHeadedGull:
                c.poly([w(0.72,-0.18),w(1,0),w(0.76,0.24),w(0.63,0.21)],"dark")
                c.oval(w(0.87,0.035).0,w(0.87,0.035).1,0.8,0.65,"white")
            case .barnSwallow:
                c.line([w(0.15,-0.31),w(0.66,-0.12)],"navy",width:0.8)
            case .largeBilledCrow:
                c.line([w(0.18,-0.30),w(0.50,-0.18)],"slate",width:0.7)
            case .asianKoel:
                c.line([w(0.15,-0.29),w(0.62,-0.12)],"dark",width:0.65)
            default: break
            }
        }
    }

    private static func head(_ c: BirdPainter, _ d: Drawing) {
        let p=d.pose, a=d.anatomy, w=a.headWidth, h=a.headHeight
        let x = -w/2, y = -h/2
        // Only local head anatomy rotates. Feather marks and the bill use the
        // same transform as Geometry.Pose.headPoint; no completed raster moves.
        c.ctx.saveGState()
        c.ctx.translateBy(x:p.head.x,y:p.head.y)
        c.ctx.rotate(by:p.head.pitch)
        if d.species == .hoopoe {
            // Closely gathered, backward feathers, with only a small separation
            // across these designed poses. Never the legacy fully spread fan.
            for n in 0..<6 {
                let angle = -2.96 + Double(n)*(0.025+p.crest*0.065)
                let length=5.7+Double(n)*0.12+p.crest*0.8
                let tip:Point=(-0.8+cos(angle)*length,-1.5+sin(angle)*length)
                c.line([(-0.8,-1.5),tip],"orange",width:1.15)
                c.line([tip,(tip.0-cos(angle)*1.4,tip.1-sin(angle)*1.4)],"black",width:1.15)
            }
        }
        c.oval(x,y,w,h,d.head,outline:true)
        c.ctx.saveGState()
        c.ctx.addEllipse(in:CGRect(x:x,y:y,width:w,height:h))
        c.ctx.clip()
        c.pigment {
            switch d.species {
            case .barnSwallow:
                c.poly([(-1.1,0.35),(w/2,0.1),(w/2-0.4,h/2),(-0.8,2.8)],"rust")
                c.line([(-1,y+0.7),(1.6,y+1)],"rust",width:0.7)
                c.line([(-1.5,h/2-0.2),(1.6,h/2)],"navy",width:1)
            case .blackHeadedGull:
                // Preserve the current white head and small dark ear spot.
                c.oval(x+0.8,-0.45,1.4,2,"dark")
            case .hoopoe:
                c.line([(x+0.6,1.3),(0.5,1.8)],"buff",width:0.65)
            case .commonKingfisher:
                c.poly([(x+0.8,0.3),(x+3.8,-0.1),(x+4.8,1.2),(x+2.8,2.2)],"orange")
                c.poly([(x+4,1),(x+8,0.5),(x+8,2),(x+5,3)],"white")
                for n in 0..<6 {
                    c.oval(x+0.8+Double(n)*1.35,y+1.25,0.55,0.55,"cyan")
                }
            case .eurasianWoodcock:
                for n in 0..<3 {
                    let yy=y+0.5+Double(n)*1.3
                    c.line([(x+0.3,yy),(x+2.9,yy+0.5)],"umber",width:0.85)
                }
                c.line([(0.8,0.4),(w/2-0.2,0.9)],"buff",width:0.6)
            case .blackCollaredStarling:
                c.poly([(x,2),(0,2.8),(w/2,2),(w/2,4.2),(x,4.2)],"black")
            case .largeBilledCrow, .asianKoel:
                c.line([(x+1,y+2),(x+4,y+1)],"dark",width:0.65)
            default: break
            }
        }
        c.ctx.restoreGState()

        if a.billDrop > 0 {
            c.curve(a.billCurve,d.bill,width:a.billDepth)
        } else {
            c.poly(p.upperBillVertices(anatomy:a),d.bill)
            if p.gape > 0 {
                // Transparent gap between jaws; no backdrop or sound glyph.
                c.poly(p.lowerBillVertices(anatomy:a),d.bill)
            }
            c.pigment {
                if d.species == .largeBilledCrow {
                    c.line([(a.billRoot+0.2,-0.7),(a.billRoot+3.4,-0.3)],"slate",width:0.5)
                } else if d.species == .commonKingfisher || d.species == .eurasianWoodcock {
                    c.line([(a.billRoot+0.6,-0.3),(a.billTip.0-1,0.3)],"slate",width:0.5)
                }
            }
        }

        let ex=d.species == .eurasianWoodcock ? -0.5 : w*0.20
        let ey=d.species == .eurasianWoodcock ? -h*0.24 : -h*0.12
        c.pigment {
            if d.species == .asianKoel { c.oval(ex-0.6,ey-0.6,2.1,2.1,"red") }
            if d.frame == "restTuck" {
                c.line([(ex-0.2,ey+0.5),(ex+1,ey+0.5)],"eye",width:0.7)
            } else {
                c.oval(ex,ey,1,1.05,"eye")
                c.oval(ex+0.4,ey,0.4,0.4,"white")
            }
        }
        c.ctx.restoreGState()
    }

    private static func tuckedShoulder(_ c: BirdPainter, _ d: Drawing) {
        let q=d.bodyPoint(0.49,0.19)
        // A small newly drawn scapular overlap, never a pasted preen raster.
        // Long bills keep their authored endpoint even under these feathers.
        c.poly([(q.0-2,q.1+1),(q.0-0.5,q.1-0.5),(q.0+1,q.1+0.6),
                (q.0+2.5,q.1-0.3),(q.0+4,q.1+2),(q.0+1,q.1+3.5),
                (q.0-2,q.1+2.8)],d.feather)
        c.line([(q.0-1,q.1+1.5),(q.0+1,q.1+2),(q.0+2.5,q.1+1.1)],d.back,width:0.6)
    }
}
