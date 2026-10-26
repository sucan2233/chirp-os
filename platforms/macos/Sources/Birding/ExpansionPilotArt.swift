import AppKit
import BirdingCore

/// E0 additions only. Existing ExpansionBirdArt images are never input pixels.
/// Parts are drawn from local anatomy at catalog density, with fixed perch toes.
enum ExpansionPilotArt {
    private typealias Geometry = ExpansionPilotArtGeometry
    private typealias Pose = Geometry.Pose
    private typealias Anatomy = Geometry.Anatomy
    private typealias Point = (Double,Double)

    static func image(_ frame:String, species:SpeciesID) -> CGImage? {
        guard let p=Geometry.pose(species:species,frame:frame),
              let a=Geometry.anatomy(for:species),
              let colors=ExpansionBirdArt.profiles[species] else { return nil }
        let size=max(48,Int((48*SpeciesCatalog.standard.profile(species).relativeScale).rounded()))
        let c=BirdPainter(size:size)
        if p.side {
            sideNuthatch(c,p,a)
        } else {
            perched(c,p,a,colors,species,frame)
        }
        return c.image
    }

    private static func perched(_ c:BirdPainter, _ p:Pose, _ a:Anatomy,
                                _ colors:ExpansionBirdArt.Anatomy, _ id:SpeciesID, _ frame:String) {
        let egret=id == .greatEgret, b=p.body
        drawTail(c,p,a,colors,id)
        drawLegs(c,p,id)
        if p.wing>0.2 { drawWing(c,p,a,colors,id,far:true) }

        // Shoulder lean changes the torso contour; the lower flank does not
        // translate with it. Feather fullness changes only this local contour.
        func bodyPoint(_ u:Double, _ v:Double) -> Point {
            (34-a.width/2+u*(a.width/2+b.fluff)+b.lean*(1-v)*0.5,
             b.y+b.height*(v+1)/2)
        }
        let outline=(0..<20).map { i -> Point in
            let angle=Double(i)*Double.pi/10
            return bodyPoint(cos(angle),sin(angle))
        }
        c.poly(outline,colors.back,outline:true)
        c.within(outline) {
            let chest:[Point]=[bodyPoint(0,-0.75),bodyPoint(0.8,-0.8),bodyPoint(1.2,-0.2),
                               bodyPoint(0.9,1),bodyPoint(-0.15,1),bodyPoint(-0.1,0.3)]
            c.poly(chest,colors.belly)
            if id == .indianWhiteEye {
                // Gray belly stays gray; yellow is limited to throat and vent.
                c.oval(20+b.lean*0.25,b.y+b.height-3,5,2.6,"yellow")
                c.line([bodyPoint(0.65,0.15),bodyPoint(0.5,0.75)],"yellow",width:0.8)
            }
            if id == .eurasianNuthatch {
                c.line([bodyPoint(0.5,0.4),bodyPoint(0.6,0.9)],"rust",width:1)
            }
            if egret {
                c.curve([(17+b.lean,b.y+3),(20,b.y+6),(27,b.y+8),(31,b.y+5)],"silver",width:0.65)
            }
        }

        if egret {
            drawEgretNeck(c,p)
        } else {
            let rear=p.headPoint(-a.headWidth*0.3,a.headHeight*0.3)
            let throat=p.headPoint(a.headWidth*0.36,a.headHeight*0.4)
            c.poly([(24+b.lean,b.y+2),rear,throat,(33+b.lean*0.3,b.y+7)],colors.belly)
            if id == .eurasianGreatTit || id == .whiteWagtail {
                c.poly([p.headPoint(0,a.headHeight*0.36),throat,
                        (32+b.lean*0.3,b.y+6),(29+b.lean*0.4,b.y+5)],"black")
            } else if id == .indianWhiteEye {
                c.poly([p.headPoint(-1,a.headHeight*0.3),throat,
                        (32+b.lean*0.3,b.y+4.5),(29+b.lean*0.4,b.y+3)],"yellow")
            }
        }

        drawWing(c,p,a,colors,id,far:false)
        if id == .eurasianGreatTit {
            c.pigment {
                // This species' broad black belly stripe belongs to the torso.
                c.line([(32+b.lean*0.6,b.y+4),(31+b.lean*0.2,b.y+b.height-1)],"black",width:1.5)
            }
        }
        drawHead(c,p,a,colors.head,colors.bill,id,asleep:frame == "restTuck")
    }

    private static func drawTail(_ c:BirdPainter, _ p:Pose, _ a:Anatomy,
                                 _ colors:ExpansionBirdArt.Anatomy, _ id:SpeciesID) {
        let root=(23+p.body.lean*0.3,p.body.y+p.body.height*0.58)
        let tx=p.tail.x, ty=p.tail.y, width=a.tailWidth
        let edge:[Point]=[(root.0+1,root.1-1),(tx,ty-1),(tx+1.5,ty+2),
                           (tx+width,ty+1),(root.0+4,root.1+3)]
        c.poly(edge,colors.wing,outline:true)
        if id == .whiteWagtail {
            // Reserve a continuous black/dark tail core at every tail angle.
            // Feather bands occupy fractions of the actual local width, so
            // horizontal tail lifts cannot merge fixed-width white strokes.
            func featherPoint(_ along:Double, _ across:Double) -> Point {
                let upper=(edge[0].0+(edge[1].0-edge[0].0)*along,
                           edge[0].1+(edge[1].1-edge[0].1)*along)
                let lower=(edge[4].0+(edge[3].0-edge[4].0)*along,
                           edge[4].1+(edge[3].1-edge[4].1)*along)
                return (upper.0+(lower.0-upper.0)*across,
                        upper.1+(lower.1-upper.1)*across)
            }
            c.within(edge) {
                c.poly([featherPoint(0,0.10),featherPoint(0.98,0.10),
                        featherPoint(0.98,0.90),featherPoint(0,0.90)],"dark")
                // Two narrow outer vanes; leave black margins and the tip cap.
                for band in [(0.02,0.08),(0.92,0.98)] {
                    c.poly([featherPoint(0.08,band.0),featherPoint(0.96,band.0),
                            featherPoint(0.96,band.1),featherPoint(0.08,band.1)],"white")
                }
            }
            return
        }
        c.within(edge) {
            for i in 0..<3 {
                let offset=Double(i)*1.3
                c.line([(root.0+offset,root.1),(tx+1+offset,ty+0.5)],colors.back,width:0.7)
            }
            if id == .crestedMyna {
                c.line([(tx+0.8,ty+0.4),(tx+width-0.5,ty+0.8)],"white",width:1.4)
            } else if id == .greatEgret {
                c.line([(root.0,root.1),(tx+2,ty+0.5)],"silver",width:0.6)
            }
        }
    }

    private static func drawLegs(_ c:BirdPainter, _ p:Pose, _ id:SpeciesID) {
        let egret=id == .greatEgret
        let color=egret ? "dark" : (id == .crestedMyna ? "yellow":"brown")
        let hipY=p.body.y+p.body.height-1.5
        for x in [27.0,31.0] {
            let kneeY=egret ? hipY+(39-hipY)*0.58 : 36.1
            let hipX=x+p.body.lean*0.3
            c.line([(hipX,hipY),(x-0.8+p.stance,kneeY),(x,38.6)],color,width:egret ? 0.75:1)
            // Feet stay planted through crouch, push and every signature.
            c.line([(x-2,39),(x,38.5),(x+2,39)],color,width:0.75)
        }
    }

    private static func drawEgretNeck(_ c:BirdPainter, _ p:Pose) {
        let headRoot=p.headPoint(-1.2,1)
        let upper=p.headPoint(-5.5,3.5)
        let path:[Point]=[(29+p.body.lean*0.5,p.body.y+5),
                          (p.neck.x,p.neck.y),upper,headRoot]
        c.curve(path,"outline",width:2.6+Double(c.unit)*2)
        c.curve(path,"white",width:2.6)
        // A fine inner-neck feather edge follows the bend, not the body axis.
        c.pigment {
            c.curve([(29.2+p.body.lean*0.5,p.body.y+5.2),
                     (p.neck.x-0.6,p.neck.y),
                     (upper.0-0.45,upper.1),(headRoot.0-0.4,headRoot.1)],"silver",width:0.45)
        }
    }

    private static func drawWing(_ c:BirdPainter, _ p:Pose, _ a:Anatomy,
                                 _ colors:ExpansionBirdArt.Anatomy, _ id:SpeciesID, far:Bool) {
        let open=p.wing, rootX=23+p.body.lean, rootY=p.body.y+3
        let span=id == .greatEgret ? 19.0 : (id == .crestedMyna ? 18:15)
        func w(_ u:Double, _ v:Double) -> Point {
            // Articulate shoulder/wrist/primaries; opening replaces the folded
            // wing's downward axis with an upward fan. No bitmap transformation.
            let side=far ? 0.55 : -1.0
            return (rootX+side*u*(6+open*span)+v*open*(far ? -3:4),
                    rootY+v*((p.body.height-4)*(1-open)+9*open)-u*open*22)
        }
        let edge:[Point]=[w(-0.28,0),w(0.25,-0.28),w(0.65,0.08),
                           w(1,0.95),w(0.84,1.05),w(0.69,0.93),
                           w(0.53,1.08),w(0.12,0.88),w(-0.5,0.24)]
        c.poly(edge,far ? colors.back:colors.wing,outline:true)
        c.within(edge) {
            c.poly([w(-0.15,0.02),w(0.25,-0.12),w(0.59,0.13),
                    w(0.48,0.5),w(-0.15,0.55)],colors.back)
            for i in 0..<4 {
                let u=0.08+Double(i)*0.17
                c.line([w(u,0.26),w(u+0.24,0.96)],
                       id == .greatEgret ? "silver":colors.back,width:0.65)
            }
            if id == .eurasianGreatTit || id == .whiteWagtail {
                c.line([w(0.66,0.28),w(0.06,0.4)],"white",width:1.3)
            } else if id == .crestedMyna {
                c.poly([w(0.48,0.19),w(-0.1,0.23),w(-0.1,0.52),w(0.52,0.65)],"white")
            } else if id == .eurasianNuthatch {
                c.line([w(0.2,0.35),w(0.78,0.91)],"gray",width:0.7)
            }
        }
    }

    private static func drawHead(_ c:BirdPainter, _ p:Pose, _ a:Anatomy,
                                 _ color:String, _ bill:String, _ id:SpeciesID, asleep:Bool) {
        // Only this anatomical part rotates. Its marks and bill share the exact
        // local-to-world transform used by Geometry.beakAnchor.
        c.ctx.saveGState()
        c.ctx.translateBy(x:p.head.x,y:p.head.y)
        c.ctx.rotate(by:p.head.pitch)
        let w=a.headWidth, h=a.headHeight, x = -w/2, y = -h/2
        c.oval(x,y,w,h,color,outline:true)
        if id == .crestedMyna {
            c.poly([(w/2-4,y+2),(w/2-3,y-4),(w/2-1,y-3),(w/2,y+2)],"black")
        }
        c.pigment {
            switch id {
            case .eurasianGreatTit:
                c.poly([(x+1,0),(w/2-1,-h*0.05),(w/2-1,h*0.33),(x+2,h/2)],"white")
            case .whiteWagtail:
                c.poly([(x,y+2),(x+2,y),(w/2-2,y),(w/2,y+2)],"black")
                c.line([(w/2-2,0),(w/2,0)],"black",width:0.7)
            case .indianWhiteEye:
                c.line([(w/2-2,-0.5),(w/2,-0.5)],"dark",width:0.7)
            case .eurasianNuthatch:
                if p.side {
                    c.poly([(-3,0),(4,-1),(4,1),(-3,2)],"black")
                } else {
                    c.poly([(x,-h*0.25),(w/2,-h*0.18),(w/2,h*0.08),(x+1,h*0.15)],"black")
                    c.line([(x,0),(x+2,-0.3)],"black",width:1)
                }
            case .greatEgret:
                c.line([(w/2-3,0),(w/2,0)],"yellow",width:0.8)
            default: break
            }
        }
        c.poly(p.billVertices(anatomy:a),bill)
        let ex=p.side ? 1:w*0.2, ey=p.side ? -1 : -h*0.12
        c.pigment {
            if id == .indianWhiteEye {
                // Narrow white ring moves with the olive head throughout glean.
                c.oval(ex-0.65,ey-0.65,2.3,2.3,"white")
            } else if id == .crestedMyna {
                c.oval(ex-0.6,ey-0.6,2.2,2.2,"yellow")
            }
            if asleep {
                c.line([(ex-0.2,ey+0.5),(ex+1,ey+0.5)],"eye",width:0.7)
            } else {
                c.oval(ex,ey,1,1,"eye")
                c.oval(ex+0.4,ey,0.4,0.4,"white")
            }
        }
        c.ctx.restoreGState()
    }

    private static func sideNuthatch(_ c:BirdPainter, _ p:Pose, _ a:Anatomy) {
        let b=p.body, tx=p.tail.x, ty=p.tail.y
        // The tail balances freely away from x=29; it is not a third support.
        c.poly([(19+b.lean,24),(tx,ty),(tx+4,ty+3),(24+b.lean,25)],"slate",outline:true)
        c.oval(13+b.lean,b.y,13+b.fluff,b.height,"slate",outline:true)
        c.oval(22+b.lean,b.y+5,5,b.height-5,"buff")
        let wing:[Point]=[(15+b.lean,b.y+1),(20+b.lean,b.y+1),
                          (22+b.lean,b.y+10),(18+b.lean-p.wing*6,b.y+13),
                          (14+b.lean-p.wing*5,b.y+9)]
        c.poly(wing,"slate",outline:true)
        c.within(wing) {
            c.line([(17+b.lean,b.y+3),(19+b.lean-p.wing*4,b.y+11)],"gray",width:0.7)
        }
        let root=p.headPoint(-1,0)
        c.curve([(22+b.lean,28),(23+b.lean,31),(root.0-2,root.1-1),root],"buff",width:3)
        drawHead(c,p,a,"gray","dark",.eurasianNuthatch,asleep:false)
        // Preserve ExpansionBirdArt.nuthatch's two side contact chains exactly
        // at their terminal vertices; only hips reach with the moving body.
        c.line([(23+b.lean,25),(26,28),(29,28),(28,29)],"brown",width:0.8)
        c.line([(23+b.lean,30),(26,38),(29,38),(29,39)],"brown",width:0.8)
    }
}
