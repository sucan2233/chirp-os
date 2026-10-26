import AppKit
import BirdingCore

/// E2 additions rasterized from original articulated paths at catalog density.
/// Historical sprites are neither inputs nor targets of this drawing source.
enum ExpansionGroundArt {
    private typealias Geometry = ExpansionGroundArtGeometry
    private typealias Point = (Double,Double)

    private struct Drawing {
        let species: SpeciesID
        let frame: String
        let pose: Geometry.Pose
        let anatomy: Geometry.Anatomy
        let colors: ExpansionBirdArt.Anatomy

        func b(_ u:Double, _ v:Double) -> Point { pose.bodyPoint(u,v,anatomy:anatomy) }
        func h(_ x:Double, _ y:Double) -> Point { pose.headPoint(x,y) }

        var legColor: String {
            switch species {
            case .redBilledChough: return "red"
            case .whiteCheekedStarling: return "orange"
            case .henricsLaughingthrush: return "yellow"
            default: return "brown"
            }
        }

        var featherEdge: String {
            switch species {
            case .carrionCrow, .daurianJackdaw: return "dark"
            case .redBilledChough: return "navy"
            case .plainLaughingthrush: return "tan"
            case .henricsLaughingthrush: return "slate"
            case .whiteBrowedLaughingthrush: return "brown"
            case .groundTit, .hornedLark: return "tan"
            case .rufousBreastedAccentor: return "buff"
            default: return colors.back
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
        tail(c,d)
        legs(c,d)
        if p.wing > 0.18 { wing(c,d,far:true) }
        torso(c,d)
        neck(c,d)
        wing(c,d,far:false)
        head(c,d)
        return c.image
    }

    private static func legs(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy
        for (index,x) in [27.0,31.0].enumerated() {
            let hip=d.b(index == 0 ? 0.65:0.82,0.86)
            // The long-legged ground tit has a higher hock and longer shank;
            // every species flexes the hip/hock above the planted toe bands.
            c.line([hip,(x-0.7+p.stance,a.kneeHeight),(x,38.5)],d.legColor,
                   width:d.species == .groundTit ? 0.85:1)
        }
        for path in Geometry.toePaths { c.line(path,d.legColor,width:0.75) }
    }

    private static func tail(_ c:BirdPainter, _ d:Drawing) {
        let p=d.pose, a=d.anatomy, tx=p.tail.x, ty=p.tail.y
        let root=d.b(0.24,0.57), endWidth=a.tailWidth+p.fan*2.2
        let edge:[Point]
        switch d.species {
        case .silkyStarling:
            edge=[root,(tx,ty-0.7),(tx+0.8,ty+0.9),(tx+endWidth,ty+0.6),d.b(0.5,0.88)]
        case .whiteCheekedStarling:
            edge=[root,(tx+0.3,ty-1),(tx,ty+0.6),(tx+endWidth-0.7,ty+1),d.b(0.51,0.91)]
        case .carrionCrow:
            edge=[root,(tx+0.7,ty-1.1),(tx,ty),(tx+1.5,ty+1.3),
                  (tx+endWidth,ty+0.8),d.b(0.54,0.9)]
        case .daurianJackdaw:
            edge=[root,(tx,ty-0.6),(tx+0.5,ty+1),(tx+endWidth-0.3,ty+1.1),d.b(0.55,0.89)]
        case .redBilledChough:
            edge=[root,(tx,ty-0.8),(tx+0.4,ty+0.9),(tx+endWidth,ty+0.3),d.b(0.51,0.86)]
        case .plainLaughingthrush:
            edge=[root,(tx+0.6,ty-1),(tx,ty+0.1),(tx+1.3,ty+1.5),
                  (tx+endWidth,ty+0.9),d.b(0.5,0.9)]
        case .henricsLaughingthrush:
            edge=[root,(tx,ty-0.9),(tx+0.1,ty+0.8),(tx+endWidth,ty+1.2),d.b(0.49,0.92)]
        case .whiteBrowedLaughingthrush:
            edge=[root,(tx+0.8,ty-1),(tx,ty),(tx+1.4,ty+1.4),
                  (tx+endWidth,ty+0.7),d.b(0.52,0.91)]
        case .groundTit:
            edge=[root,(tx,ty-0.5),(tx+0.5,ty+0.7),(tx+endWidth,ty+0.8),d.b(0.49,0.87)]
        case .rufousBreastedAccentor:
            edge=[root,(tx+0.3,ty-0.8),(tx,ty+0.4),(tx+endWidth,ty+0.9),d.b(0.5,0.9)]
        case .hornedLark:
            edge=[root,(tx,ty-0.6),(tx+0.4,ty+0.9),(tx+endWidth,ty+0.5),d.b(0.48,0.86)]
        default: // Thrush: broad, rounded rectrices, with its established rust edge.
            edge=[root,(tx+0.6,ty-0.9),(tx,ty+0.1),(tx+1,ty+1.3),
                  (tx+endWidth,ty+0.9),d.b(0.53,0.91)]
        }
        c.poly(edge,d.colors.wing,outline:true)
        c.within(edge) {
            for i in 0..<3 {
                let t=Double(i)/2
                c.line([(root.0+0.4+t*3,root.1+0.5+t*2),
                        (tx+0.8+t*(endWidth-1.4),ty+0.4)],d.featherEdge,width:0.65)
            }
            if d.species == .henricsLaughingthrush {
                c.line([(tx+0.4,ty+0.05),(tx+endWidth-0.5,ty+0.75)],"white",width:0.9)
            } else if d.species == .redThroatedThrush {
                c.line([(tx+0.7,ty),(root.0+0.7,root.1+0.6)],"rust",width:1.3)
            }
        }
    }

    private static func torso(_ c:BirdPainter, _ d:Drawing) {
        let edge=d.anatomy.bodyContour.map { d.b($0.0,$0.1) }
        c.poly(edge,d.colors.back,outline:true)
        c.within(edge) {
            let chest=[d.b(0.6,0.05),d.b(0.94,0.14),d.b(1.08,0.65),
                       d.b(0.76,1.03),d.b(0.42,0.98),d.b(0.47,0.46)]
            c.poly(chest,d.colors.belly)
            switch d.species {
            case .silkyStarling:
                c.poly([d.b(0.7,0.13),d.b(0.96,0.22),d.b(0.93,0.66),d.b(0.73,0.55)],"silver")
                c.line([d.b(0.79,0.17),d.b(0.85,0.53)],"white",width:0.65)
            case .whiteCheekedStarling:
                c.poly([d.b(0.01,0.51),d.b(0.27,0.48),d.b(0.31,0.73),d.b(0.08,0.81)],"white")
                c.line([d.b(0.8,0.45),d.b(0.75,0.86)],"silver",width:0.65)
            case .carrionCrow:
                c.line([d.b(0.82,0.16),d.b(0.91,0.41),d.b(0.83,0.7)],"slate",width:0.55)
            case .daurianJackdaw:
                // The cream apron extends from the moving collar to the keel.
                c.poly([d.b(0.48,0.22),d.b(0.85,0.14),d.b(1.05,0.58),
                        d.b(0.75,1.02),d.b(0.47,0.93)],"cream")
            case .redBilledChough:
                c.line([d.b(0.78,0.2),d.b(0.88,0.55)],"navy",width:0.7)
            case .plainLaughingthrush:
                c.line([d.b(0.75,0.32),d.b(0.88,0.65),d.b(0.73,0.88)],"silver",width:0.65)
            case .henricsLaughingthrush:
                c.poly([d.b(0.16,0.73),d.b(0.43,0.76),d.b(0.49,1),d.b(0.2,0.95)],"rust")
                c.line([d.b(0.81,0.45),d.b(0.75,0.81)],"silver",width:0.6)
            case .whiteBrowedLaughingthrush:
                c.poly([d.b(0.18,0.75),d.b(0.45,0.78),d.b(0.5,1),d.b(0.23,0.97)],"rust")
            case .groundTit:
                c.line([d.b(0.73,0.13),d.b(0.86,0.49)],"buff",width:0.7)
            case .rufousBreastedAccentor:
                c.poly([d.b(0.61,0.06),d.b(0.96,0.17),d.b(1,0.49),
                        d.b(0.81,0.62),d.b(0.57,0.42)],"rust")
                for i in 0..<5 {
                    let u=0.62+Double(i%3)*0.12, v=0.55+Double(i/3)*0.18
                    c.line([d.b(u,v),d.b(u-0.015,v+0.13)],"umber",width:0.6)
                }
            case .hornedLark:
                c.poly([d.b(0.68,0.06),d.b(0.96,0.16),d.b(1,0.33),
                        d.b(0.81,0.45),d.b(0.64,0.31)],"black")
                c.line([d.b(0.8,0.53),d.b(0.77,0.85)],"buff",width:0.65)
            case .redThroatedThrush:
                c.poly([d.b(0.65,0.05),d.b(0.95,0.14),d.b(1.02,0.48),
                        d.b(0.83,0.65),d.b(0.59,0.36)],"rust")
                for i in 0..<3 {
                    let u=0.71+Double(i)*0.09
                    c.line([d.b(u,0.64),d.b(u-0.02,0.75)],"brown",width:0.6)
                }
            default: break
            }
        }
    }

    private static func neck(_ c:BirdPainter, _ d:Drawing) {
        let a=d.anatomy
        let nape=d.h(-a.headWidth*0.33,a.headHeight*0.12)
        let chin=d.h(a.headWidth*0.3,a.headHeight*0.37)
        let edge=[d.b(0.46,0.13),nape,chin,d.b(0.95,0.55)]
        c.poly(edge,d.colors.belly)
        c.within(edge) {
            c.poly([edge[0],nape,(nape.0+1,nape.1+2),d.b(0.66,0.36)],d.colors.head)
            switch d.species {
            case .daurianJackdaw:
                c.poly([edge[0],nape,d.h(-a.headWidth*0.12,a.headHeight*0.46),
                        d.b(0.73,0.49)],"cream")
            case .redThroatedThrush:
                c.poly([d.h(-0.1,a.headHeight*0.26),chin,d.b(0.95,0.43),d.b(0.69,0.31)],"rust")
            case .rufousBreastedAccentor:
                c.poly([d.h(0,a.headHeight*0.4),chin,d.b(0.94,0.35),d.b(0.7,0.3)],"rust")
            case .hornedLark:
                c.poly([d.h(-0.5,a.headHeight*0.28),chin,d.b(0.94,0.29),d.b(0.7,0.25)],"buff")
            case .silkyStarling:
                c.line([chin,d.b(0.88,0.43)],"silver",width:1.3)
            default: break
            }
        }
    }

    private static func wing(_ c:BirdPainter, _ d:Drawing, far:Bool) {
        let p=d.pose, a=d.anatomy, open=p.wing
        let root=d.b(far ? 0.62:0.43,0.13)
        func w(_ u:Double, _ v:Double) -> Point {
            let side=far ? 0.48 : -1.0
            return (root.0+side*u*(5+a.wingReach*open)+v*open*1.5,
                    root.1+v*(a.primaryLength*(1-open)+5.2*open)-u*open*17)
        }
        let form:[Point]
        switch d.species {
        case .silkyStarling:
            form=[(-0.63,0.08),(-0.04,-0.08),(0.57,0.18),(1,0.96),
                  (0.83,1.04),(0.59,0.94),(0.08,0.84),(-0.64,0.44)]
        case .whiteCheekedStarling:
            form=[(-0.65,0.1),(-0.1,-0.06),(0.54,0.2),(1,0.92),
                  (0.8,1.06),(0.36,1.02),(-0.15,0.82),(-0.67,0.48)]
        case .carrionCrow:
            form=[(-0.68,0.02),(-0.1,-0.08),(0.6,0.17),(1,0.92),
                  (0.86,1.07),(0.7,0.96),(0.54,1.09),(0.07,0.84),(-0.7,0.45)]
        case .daurianJackdaw:
            form=[(-0.65,0.06),(-0.12,-0.08),(0.57,0.18),(1,0.86),
                  (0.85,1.01),(0.62,1.07),(0.16,0.91),(-0.68,0.49)]
        case .redBilledChough:
            form=[(-0.62,0.03),(-0.04,-0.1),(0.58,0.14),(1,0.98),
                  (0.86,1.08),(0.7,0.97),(0.52,1.04),(0.04,0.78),(-0.62,0.4)]
        case .plainLaughingthrush:
            form=[(-0.7,0.12),(-0.13,-0.04),(0.52,0.22),(1,0.9),
                  (0.76,1.08),(0.33,1.04),(-0.16,0.83),(-0.71,0.52)]
        case .henricsLaughingthrush:
            form=[(-0.67,0.1),(-0.08,-0.08),(0.58,0.2),(1,0.93),
                  (0.79,1.07),(0.43,1.02),(-0.09,0.86),(-0.68,0.5)]
        case .whiteBrowedLaughingthrush:
            form=[(-0.72,0.1),(-0.14,-0.05),(0.55,0.19),(1,0.91),
                  (0.77,1.05),(0.38,1.08),(-0.15,0.85),(-0.72,0.53)]
        case .groundTit:
            form=[(-0.6,0.04),(-0.02,-0.09),(0.57,0.18),(1,0.94),
                  (0.78,1.03),(0.3,0.91),(-0.16,0.76),(-0.61,0.41)]
        case .rufousBreastedAccentor:
            form=[(-0.64,0.09),(-0.1,-0.06),(0.51,0.21),(1,0.89),
                  (0.77,1.05),(0.34,1),(-0.13,0.8),(-0.65,0.46)]
        case .hornedLark:
            form=[(-0.59,0.06),(-0.03,-0.08),(0.56,0.17),(1,0.96),
                  (0.81,1.04),(0.43,0.93),(-0.1,0.78),(-0.6,0.41)]
        default:
            form=[(-0.68,0.1),(-0.1,-0.07),(0.55,0.2),(1,0.95),
                  (0.79,1.07),(0.38,1.03),(-0.12,0.84),(-0.69,0.49)]
        }
        let edge=form.map { w($0.0,$0.1) }
        c.poly(edge,far ? d.colors.back:d.colors.wing,outline:true)
        c.within(edge) {
            c.poly([w(-0.52,0.1),w(-0.08,0.02),w(0.48,0.18),
                    w(0.38,0.52),w(-0.34,0.58)],d.colors.back)
            for i in 0..<4 {
                let u = -0.12+Double(i)*0.21
                c.line([w(u,0.31),w(u+0.28,0.98)],d.featherEdge,width:0.65)
            }
            switch d.species {
            case .silkyStarling:
                c.line([w(-0.34,0.33),w(0.52,0.43)],"white",width:1.2)
            case .whiteCheekedStarling:
                c.line([w(-0.33,0.35),w(0.56,0.44)],"silver",width:0.8)
            case .henricsLaughingthrush:
                c.line([w(0.28,0.31),w(0.89,0.95)],"slate",width:1)
                c.line([w(-0.35,0.37),w(0.4,0.46)],"gray",width:0.7)
            case .rufousBreastedAccentor:
                for i in 0..<3 {
                    let u = -0.28+Double(i)*0.22
                    c.line([w(u,0.17),w(u+0.16,0.43)],"umber",width:1)
                }
                c.line([w(-0.4,0.56),w(0.46,0.63)],"buff",width:0.65)
            case .groundTit, .hornedLark:
                c.line([w(-0.36,0.34),w(0.48,0.43)],"buff",width:0.8)
                c.line([w(-0.17,0.57),w(0.63,0.66)],"tan",width:0.65)
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

        if d.species == .hornedLark {
            // Both small feather horns belong to the pitched head, never to
            // the torso or eye marks. Their silhouette is intentionally separate.
            c.poly([(x+0.8,y+1.7),(x-0.3,y-2.7),(x+2.3,y-0.2),(x+2.8,y+1.3)],"black")
            c.poly([(x+3.4,y+1),(x+4.5,y-2.1),(x+5.4,y+0.3),(x+5.8,y+1.6)],"black")
        }

        let contour:[Point]
        switch d.species {
        case .carrionCrow:
            // Relatively shallow forehead and narrower bill than large-billed crow.
            contour=[(-0.5,-0.21),(-0.32,-0.47),(0.08,-0.5),(0.39,-0.28),
                     (0.5,-0.02),(0.42,0.29),(0.1,0.49),(-0.27,0.44),(-0.5,0.16)]
        case .daurianJackdaw:
            contour=[(-0.5,-0.1),(-0.37,-0.39),(-0.07,-0.5),(0.28,-0.42),
                     (0.49,-0.1),(0.46,0.24),(0.17,0.5),(-0.21,0.46),(-0.48,0.2)]
        case .redBilledChough:
            contour=[(-0.5,-0.11),(-0.34,-0.4),(0.03,-0.5),(0.34,-0.31),
                     (0.5,-0.01),(0.39,0.3),(0.02,0.5),(-0.34,0.35)]
        case .plainLaughingthrush:
            contour=[(-0.5,-0.06),(-0.36,-0.38),(-0.01,-0.5),(0.33,-0.34),
                     (0.5,-0.03),(0.43,0.28),(0.11,0.48),(-0.29,0.44),(-0.49,0.21)]
        case .henricsLaughingthrush:
            contour=[(-0.5,-0.07),(-0.37,-0.36),(-0.08,-0.5),(0.28,-0.43),
                     (0.48,-0.15),(0.47,0.19),(0.19,0.48),(-0.19,0.5),(-0.47,0.25)]
        case .whiteBrowedLaughingthrush:
            contour=[(-0.5,-0.12),(-0.34,-0.41),(0.02,-0.5),(0.35,-0.34),
                     (0.5,-0.03),(0.43,0.29),(0.1,0.5),(-0.28,0.46),(-0.5,0.18)]
        case .groundTit:
            contour=[(-0.5,-0.03),(-0.35,-0.36),(-0.04,-0.5),(0.31,-0.36),
                     (0.5,-0.07),(0.4,0.23),(0.06,0.48),(-0.3,0.4)]
        case .rufousBreastedAccentor:
            contour=[(-0.5,-0.08),(-0.36,-0.39),(-0.02,-0.5),(0.33,-0.37),
                     (0.5,-0.06),(0.42,0.28),(0.09,0.49),(-0.27,0.45),(-0.48,0.2)]
        case .hornedLark:
            contour=[(-0.5,-0.02),(-0.33,-0.37),(-0.01,-0.5),(0.34,-0.33),
                     (0.5,-0.02),(0.41,0.28),(0.04,0.49),(-0.33,0.36)]
        case .silkyStarling:
            contour=[(-0.5,-0.11),(-0.32,-0.42),(0.06,-0.5),(0.37,-0.32),
                     (0.5,-0.02),(0.4,0.31),(0.03,0.5),(-0.34,0.37)]
        case .whiteCheekedStarling:
            contour=[(-0.5,-0.09),(-0.35,-0.38),(-0.03,-0.5),(0.31,-0.4),
                     (0.5,-0.09),(0.46,0.24),(0.13,0.5),(-0.25,0.44),(-0.48,0.2)]
        default:
            contour=[(-0.5,-0.09),(-0.34,-0.39),(0,-0.5),(0.35,-0.35),
                     (0.5,-0.03),(0.43,0.27),(0.1,0.5),(-0.29,0.43),(-0.49,0.17)]
        }
        let edge=contour.map { ($0.0*w,$0.1*h) }
        c.poly(edge,d.colors.head,outline:true)
        c.within(edge) {
            // All facial patches use head-local coordinates, including turn.
            switch d.species {
            case .silkyStarling:
                c.line([(x+0.9,y+1.9),(x+4,y+0.9)],"white",width:0.8)
                c.poly([(-w*0.13,0.9),(w*0.43,0.4),(w*0.3,h*0.42),(-w*0.2,h*0.4)],"silver")
            case .whiteCheekedStarling:
                c.poly([(x+1.2,0.7),(w*0.46,-0.1),(w*0.4,h*0.34),
                        (x+2.2,h*0.49),(x+0.9,h*0.23)],"white")
                c.line([(x+1.3,y+2),(x+3,y+1.3)],"dark",width:0.6)
            case .carrionCrow:
                c.line([(x+0.7,y+2.7),(x+4,y+1.4)],"slate",width:0.6)
                c.line([(w*0.16,h*0.27),(w*0.37,h*0.13)],"dark",width:0.6)
            case .daurianJackdaw:
                c.poly([(x,h*0.2),(x+1.7,h*0.27),(x+2.2,h*0.5),(x,h*0.5)],"cream")
                c.line([(x+0.8,y+2),(x+3.5,y+1.1)],"dark",width:0.65)
            case .redBilledChough:
                c.line([(x+1,y+2.2),(x+4,y+1)],"navy",width:0.8)
            case .plainLaughingthrush:
                c.line([(x+1,y+2),(w/2-0.8,y+1.5)],"silver",width:0.7)
                c.poly([(w*0.19,h*0.2),(w*0.46,h*0.21),(w*0.3,h*0.5)],"dark")
            case .henricsLaughingthrush:
                c.poly([(x+1,0.6),(w*0.45,-0.1),(w*0.38,h*0.3),(x+2,h*0.44)],"rust")
                c.line([(x+0.6,y+1.9),(w/2-0.6,y+1.4)],"white",width:0.8)
                c.line([(x+1.1,h*0.35),(w*0.3,h*0.34)],"white",width:0.9)
            case .whiteBrowedLaughingthrush:
                c.poly([(x,-h*0.22),(w/2,-h*0.15),(w/2,h*0.08),(x+1,h*0.12)],"umber")
                c.poly([(x+1,h*0.15),(w*0.43,h*0.07),(w*0.35,h*0.35),(x+2,h*0.49)],"cream")
                c.line([(x+0.6,y+1.8),(w/2-0.6,y+1.3)],"cream",width:1)
            case .groundTit:
                c.poly([(w*0.03,y+0.6),(w*0.38,y+1.2),(w*0.4,y+2.7),(w*0.02,y+2)],"cream")
                c.poly([(x+1,0.6),(w*0.43,0.4),(w*0.3,h*0.37),(x+2,h*0.47)],"buff")
                c.line([(x+0.8,-h*0.05),(w*0.45,-h*0.05)],"brown",width:0.7)
            case .rufousBreastedAccentor:
                c.line([(x+0.5,y+1.6),(w*0.02,y+0.9)],"buff",width:0.9)
                c.line([(w*0.02,y+0.9),(w*0.4,y+1)],"white",width:0.8)
                c.poly([(x+1,h*0.12),(w*0.42,h*0.07),(w*0.33,h*0.35),(x+2,h*0.43)],"buff")
            case .hornedLark:
                c.poly([(x,-h*0.17),(w*0.48,-h*0.16),(w*0.47,h*0.08),(x+0.8,h*0.13)],"black")
                c.poly([(x+1,h*0.2),(w*0.45,h*0.09),(w*0.34,h*0.41),(x+1.8,h*0.47)],"buff")
                c.line([(x+1,y+1.5),(w*0.4,y+1.2)],"cream",width:0.7)
            case .redThroatedThrush:
                c.poly([(-w*0.15,h*0.19),(w*0.45,h*0.1),(w*0.34,h*0.47),(-w*0.2,h*0.45)],"rust")
                c.line([(x+0.9,y+1.7),(w*0.4,y+1.2)],"silver",width:0.65)
            default: break
            }
        }

        let bill=p.billVertices(anatomy:a)
        c.poly(bill,d.colors.bill)
        c.within(bill) {
            if d.species == .silkyStarling || d.species == .whiteCheekedStarling {
                c.poly([bill[2],bill[3],bill[4],
                        (bill[2].0-0.35,bill[2].1+0.7)],"black")
            } else if d.species == .carrionCrow || d.species == .daurianJackdaw {
                c.line([(bill[0].0+0.5,0.45),(bill[3].0-0.8,bill[3].1*0.6)],"black",width:0.55)
            }
        }

        let ex=w*0.21-p.turn*0.6, ey = -h*0.12
        c.within(edge) {
            if d.frame == "restTuck" {
                c.line([(ex-0.3,ey+0.35),(ex+0.35,ey+0.7),(ex+1,ey+0.3)],"eye",width:0.7)
            } else {
                c.oval(ex,ey,1,1.1,"eye")
                c.oval(ex+0.4,ey,0.4,0.4,"white")
            }
        }
        c.ctx.restoreGState()
    }
}
