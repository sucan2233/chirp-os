import AppKit
import BirdingCore

// Rasterize anatomy directly at each species' desktop pixel density. The paths
// use logical 48-unit coordinates; outlines and feather shafts stay one pixel.
private final class BirdPainter {
    let ctx:CGContext
    let size:Int
    let unit:CGFloat
    var palette:[String:UInt32] = [
        "outline":0x303943FF,"black":0x27313AFF,"dark":0x414E59FF,"slate":0x687D8CFF,
        "gray":0x9DAEB4FF,"silver":0xCED7D5FF,"white":0xF7F7ECFF,"cream":0xE4DBBFFF,
        "brown":0x806350FF,"umber":0x574A40FF,"tan":0xAD8D66FF,"buff":0xD3B58AFF,
        "rust":0xA65537FF,"orange":0xCE8A4FFF,"blue":0x386A93FF,"navy":0x28455FFF,
        "cyan":0x61A3B5FF,"green":0x697E47FF,"olive":0x899961FF,"yellow":0xE4C951FF,
        "red":0xC74F43FF,"pink":0xCB8E87FF,"eye":0x121C25FF]
    init(size:Int){
        self.size=size;unit=48/CGFloat(size)
        ctx=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setShouldAntialias(false);ctx.translateBy(x:0,y:CGFloat(size));ctx.scaleBy(x:CGFloat(size)/48,y:-CGFloat(size)/48)
        ctx.setLineJoin(.round);ctx.setLineCap(.round)
    }
    func color(_ key:String)->CGColor {
        let p=palette[key]!
        return CGColor(red:CGFloat((p>>24)&255)/255,green:CGFloat((p>>16)&255)/255,blue:CGFloat((p>>8)&255)/255,alpha:1)
    }
    func poly(_ pts:[(Double,Double)],_ fill:String,outline:Bool=false) {
        guard let first=pts.first else{return};ctx.beginPath();ctx.move(to:CGPoint(x:first.0,y:first.1))
        for p in pts.dropFirst(){ctx.addLine(to:CGPoint(x:p.0,y:p.1))};ctx.closePath()
        ctx.setFillColor(color(fill));ctx.setStrokeColor(color("outline"));ctx.setLineWidth(unit)
        ctx.drawPath(using:outline ? .fillStroke:.fill)
    }
    func oval(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ fill:String,outline:Bool=false) {
        ctx.setFillColor(color(fill));ctx.setStrokeColor(color("outline"));ctx.setLineWidth(unit)
        ctx.addEllipse(in:CGRect(x:x,y:y,width:w,height:h));ctx.drawPath(using:outline ? .fillStroke:.fill)
    }
    func line(_ pts:[(Double,Double)],_ fill:String,width:Double?=nil) {
        guard let p=pts.first else{return};ctx.beginPath();ctx.move(to:CGPoint(x:p.0,y:p.1))
        for p in pts.dropFirst(){ctx.addLine(to:CGPoint(x:p.0,y:p.1))}
        ctx.setStrokeColor(color(fill));ctx.setLineWidth(width.map{CGFloat($0)} ?? unit);ctx.strokePath()
    }
    func curve(_ points:[(Double,Double)],_ fill:String,width:Double) {
        guard points.count == 4 else{return}
        ctx.beginPath();ctx.move(to:CGPoint(x:points[0].0,y:points[0].1))
        ctx.addCurve(to:CGPoint(x:points[3].0,y:points[3].1),control1:CGPoint(x:points[1].0,y:points[1].1),control2:CGPoint(x:points[2].0,y:points[2].1))
        ctx.setStrokeColor(color(fill));ctx.setLineWidth(width);ctx.strokePath()
    }
    var image:CGImage {ctx.makeImage()!}
}

enum DetailedBirdArt {
    private static let owls:Set<SpeciesID>=[.collaredScopsOwl,.asianBarredOwlet,.littleOwl]
    private static let herons:Set<SpeciesID>=[.nightHeron,.littleEgret,.greyHeron,.chinesePondHeron]
    private static let raptors:Set<SpeciesID>=[.commonKestrel,.peregrineFalcon,.blackKite,.commonBuzzard]
    private static let waders:Set<SpeciesID>=[.whimbrel,.eurasianWoodcock,.blackWingedStilt,.littleRingedPlover]
    private static let water:Set<SpeciesID>=[.mallard,.commonMoorhen,.eurasianCoot,.blackHeadedGull]
    private struct Shape {
        let width, height, headWidth, headHeight, headY, tailX, tailY: Double
    }
    private static func shape(_ id: SpeciesID) -> Shape {
        switch id {
        case .collaredScopsOwl: return Shape(width: 18, height: 19, headWidth: 17, headHeight: 13, headY: 10, tailX: 19, tailY: 38)
        case .asianBarredOwlet: return Shape(width: 20, height: 16, headWidth: 18, headHeight: 14, headY: 12, tailX: 16, tailY: 39)
        case .littleOwl: return Shape(width: 22, height: 15, headWidth: 19, headHeight: 12, headY: 14, tailX: 17, tailY: 37)
        case .nightHeron: return Shape(width: 16, height: 12, headWidth: 8, headHeight: 6, headY: 15, tailX: 12, tailY: 32)
        case .plumbeousWaterRedstart: return Shape(width: 17, height: 14, headWidth: 9, headHeight: 8, headY: 16, tailX: 10, tailY: 39)
        case .littleEgret: return Shape(width: 16, height: 9, headWidth: 7, headHeight: 4, headY: 5, tailX: 14, tailY: 28)
        case .greyHeron: return Shape(width: 17, height: 9, headWidth: 7, headHeight: 4, headY: 6, tailX: 14, tailY: 28)
        case .commonKestrel: return Shape(width: 17, height: 14, headWidth: 8, headHeight: 7, headY: 12, tailX: 7, tailY: 43)
        case .peregrineFalcon: return Shape(width: 20, height: 15, headWidth: 9, headHeight: 8, headY: 12, tailX: 10, tailY: 40)
        case .blackKite: return Shape(width: 19, height: 14, headWidth: 7.5, headHeight: 7, headY: 13, tailX: 3, tailY: 42)
        case .commonBuzzard: return Shape(width: 22, height: 16, headWidth: 8, headHeight: 7, headY: 12, tailX: 10, tailY: 39)
        case .orientalMagpie: return Shape(width: 18, height: 12, headWidth: 8, headHeight: 7, headY: 14, tailX: 1, tailY: 45)
        case .azureWingedMagpie: return Shape(width: 17, height: 11, headWidth: 7.5, headHeight: 7, headY: 15, tailX: 2, tailY: 44)
        case .largeBilledCrow: return Shape(width: 22, height: 15, headWidth: 10, headHeight: 8, headY: 12, tailX: 8, tailY: 41)
        case .hoopoe: return Shape(width: 19, height: 11, headWidth: 7, headHeight: 6, headY: 15, tailX: 7, tailY: 39)
        case .barnSwallow: return Shape(width: 18, height: 9,
            headWidth: CatchArtGeometry.swallowHeadWidth, headHeight: CatchArtGeometry.swallowHeadHeight,
            headY: CatchArtGeometry.swallowHeadY, tailX: 2, tailY: 43)
        case .mallard: return Shape(width: 26, height: 12, headWidth: 8, headHeight: 8, headY: 18, tailX: 10, tailY: 32)
        case .asianKoel: return Shape(width: 18, height: 12, headWidth: 7.5, headHeight: 7, headY: 14, tailX: 2, tailY: 44)
        case .swinhoesWhiteEye: return Shape(width: 15, height: 12, headWidth: 8.5, headHeight: 8, headY: 16, tailX: 12, tailY: 39)
        case .blackHeadedGull: return Shape(width: 24, height: 10, headWidth: 7, headHeight: 6, headY: 17, tailX: 9, tailY: 33)
        case .whimbrel: return Shape(width: 20, height: 10, headWidth: 7, headHeight: 6, headY: 15, tailX: 10, tailY: 31)
        case .piedKingfisher: return Shape(width: 17, height: 12, headWidth: 11, headHeight: 8, headY: 13, tailX: 13, tailY: 33)
        case .eurasianWoodcock: return Shape(width: 22, height: 13, headWidth: 8, headHeight: 7, headY: 20, tailX: 12, tailY: 33)
        case .blackDrongo: return Shape(width: 16, height: 12, headWidth: 7, headHeight: 6, headY: 14, tailX: 2, tailY: 44)
        case .chinesePondHeron: return Shape(width: 16, height: 10, headWidth: 7, headHeight: 5, headY: 13, tailX: 12, tailY: 31)
        case .yellowRumpedFlycatcher: return Shape(width: 16, height: 11, headWidth: 8, headHeight: 7, headY: 15, tailX: 10, tailY: 40)
        case .yellowBrowedWarbler: return Shape(width: 17, height: 10, headWidth: 7, headHeight: 6, headY: 16, tailX: 9, tailY: 38)
        case .greatTit: return Shape(width: 17, height: 13, headWidth: 8.5, headHeight: 8, headY: 14, tailX: 8, tailY: 41)
        case .commonMoorhen: return Shape(width: 22, height: 12, headWidth: 7, headHeight: 7, headY: 17, tailX: 12, tailY: 30)
        case .greatSpottedWoodpecker: return Shape(width: 17, height: 15, headWidth: 8, headHeight: 7, headY: 12, tailX: 10, tailY: 42)
        case .vinousThroatedParrotbill: return Shape(width: 15, height: 13, headWidth: 9, headHeight: 8, headY: 15, tailX: 3, tailY: 44)
        case .blackWingedStilt: return Shape(width: 17, height: 8, headWidth: 6, headHeight: 5, headY: 9, tailX: 12, tailY: 28)
        case .eurasianCoot: return Shape(width: 25, height: 13, headWidth: 7, headHeight: 7, headY: 18, tailX: 12, tailY: 32)
        case .redBilledLeiothrix: return Shape(width: 17, height: 12, headWidth: 8, headHeight: 7, headY: 15, tailX: 9, tailY: 40)
        case .blackCollaredStarling: return Shape(width: 19, height: 13, headWidth: 8, headHeight: 8, headY: 12, tailX: 10, tailY: 39)
        case .commonKingfisher: return Shape(width: 16, height: 13, headWidth: 11, headHeight: 8, headY: 13, tailX: 14, tailY: 32)
        case .littleRingedPlover: return Shape(width: 16, height: 9, headWidth: 7, headHeight: 6, headY: 16, tailX: 12, tailY: 31)
        case .yellowBilledGrosbeak: return Shape(width: 20, height: 14, headWidth: 10, headHeight: 9, headY: 12, tailX: 11, tailY: 39)
        case .redFlankedBluetail: return Shape(width: 16, height: 12, headWidth: 8, headHeight: 7, headY: 16, tailX: 10, tailY: 40)
        case .redWhiskeredBulbul: return Shape(width: 17, height: 13, headWidth: 7.5, headHeight: 7, headY: 14, tailX: 6, tailY: 42)
        case .treeSparrow: return Shape(width: 17, height: 13,
            headWidth: CarryArtGeometry.sparrowHeadWidth, headHeight: CarryArtGeometry.sparrowHeadHeight,
            headY: CarryArtGeometry.sparrowHeadY, tailX: 12, tailY: 39)
        case .lightVentedBulbul: return Shape(width: 19, height: 12, headWidth: 8, headHeight: 7, headY: 14, tailX: 7, tailY: 41)
        case .spottedDove: return Shape(width: 23, height: 13, headWidth: 7, headHeight: 6, headY: 14, tailX: 6, tailY: 42)
        case .chineseBlackbird: return Shape(width: 21, height: 13, headWidth: 8, headHeight: 7, headY: 14, tailX: 7, tailY: 41)
        case .magpieRobin: return Shape(width: 17, height: 12, headWidth: 8, headHeight: 7, headY: 14, tailX: 6, tailY: 43)
        case .longTailedShrike: return Shape(width: 18, height: 12, headWidth: 8.5, headHeight: 7, headY: 13, tailX: 2, tailY: 45)
        }
    }
    static func make(_ frame:String,species id:SpeciesID)->CGImage {
        if let image=catchImage(frame,species:id) {return image}
        if let image=carryImage(frame,species:id) {return image}
        if let image=bathImage(frame,species:id) {return image}
        // M6b has its own anatomy; no existing stand/idle raster is reused.
        if let image=poseImage(frame,species:id) {return image}
        // B14 is an independent native drawing; old peck/common poses do not
        // enter this path and retain their original raster operations.
        if let image=feedingImage(frame,species:id) {return image}
        // Only the six new names take this path. Every existing frame retains
        // its original raster operations, order and species pixel density.
        if let image=allopreeningImage(frame,species:id) {return image}
        let density=SpeciesCatalog.standard.profile(id).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let phase=TransportArtGeometry.phase(frame)
        let flying=frame.hasPrefix("fly") || phase >= 8,landing=frame.hasPrefix("land")
        let bob=frame == "breathe" ? -0.4:0.0
        if owls.contains(id) || herons.contains(id) {
            if flying && phase >= 8 && phase < 14 {
                c.ctx.translateBy(x:27,y:24);c.ctx.rotate(by:phase == 11 ? -0.16:(phase == 13 ? -0.02:-0.09));c.ctx.translateBy(x:-27,y:-24)
            }
            if owls.contains(id) {owl(c,id,frame,phase,flying,landing)} else {heron(c,id,frame,phase,flying,landing)}
            return c.image
        }
        if id == .greatSpottedWoodpecker && (frame.hasPrefix("cling") || frame.hasPrefix("peck")) {woodpecker(c,frame);return c.image}
        let style=colours(id), anatomy=shape(id)
        let action=SpeciesBehavior.motion(id).action
        let active=frame.hasPrefix("idle")
        let amount=active ? [0.25, 0.65, 1.0][min(2,phase)] : 0.0
        let waterBird=water.contains(id),wader=waders.contains(id),raptor=raptors.contains(id)
        if flying {
            c.ctx.saveGState();c.ctx.translateBy(x:27,y:24)
            c.ctx.rotate(by:CGFloat(TransportArtGeometry.pitch(phase:phase)))
            c.ctx.translateBy(x:-27,y:-24+CGFloat(TransportArtGeometry.bob(phase:phase)))
            wing(c,species:id,phase:phase,fill:style.1,light:style.0,pointed:id == .barnSwallow || id == .peregrineFalcon || id == .commonKestrel,far:true,bar:wingBar(id))
            // Keep the flight torso compact inside the spread wings. Applying
            // this to every flight frame avoids a size jump when flapping ends.
            c.ctx.saveGState();c.ctx.translateBy(x:27,y:24)
            let torsoScale=TransportArtGeometry.bodyScale(raptor:raptor)
            c.ctx.scaleBy(x:torsoScale.width,y:torsoScale.height);c.ctx.translateBy(x:-27,y:-24)
        }
        let tailTip=flying ? (max(3, anatomy.tailX-2),27.0):(anatomy.tailX,anatomy.tailY)
        let tailFill=id == .plumbeousWaterRedstart ? "rust":(id == .azureWingedMagpie ? "cyan":style.1)
        var tip=tailTip
        if active && action == .tail { tip.1 -= amount * (id == .magpieRobin ? 21 : 11); tip.0 += amount * 2 }
        if [.barnSwallow,.blackDrongo,.blackKite].contains(id) {
            let notch=id == .blackKite ? 4.0 : 8.0
            c.poly([(21,25),(tip.0,tip.1-4),(tip.0+notch,tip.1),(tip.0,tip.1+4),(24,30)],tailFill,outline:true)
        } else {
            c.poly([(21,27),(24,31),(tip.0+4,tip.1+1),(tip.0,tip.1)],tailFill,outline:true)
            c.line([(21,29),(tip.0+1,tip.1)],style.0)
        }
        if id == .commonKestrel {c.line([(tip.0+1,tip.1-1),(tip.0+4,tip.1)],"black",width:1.8)}
        if id == .magpieRobin {c.line([(tip.0,tip.1),(19,30)],"white",width:0.8)}
        if !flying {
            let legTop=wader ? (id == .blackWingedStilt ? 25.0:(id == .eurasianWoodcock ? 35.0:29.0)):33.0
            let leg=id == .blackWingedStilt ? "pink":(raptor || id == .commonMoorhen ? "yellow":"brown")
            for x in [27.0,31.0] {
                let lift=active && action == .stalk && x == 27 ? amount*4 : 0
                c.line([(x-1,legTop),(x,35-lift),(x-0.5,38.5-lift)],leg,width:id == .blackWingedStilt ? 0.7:1)
                let toe=id == .commonMoorhen || id == .eurasianCoot ? 4.0 : 2.0
                c.line([(x-toe,39-lift),(x,38.5-lift),(x+toe,39-lift)],leg)
                if id == .eurasianCoot {c.oval(x-2,38-lift,2,1,"silver")}
            }
            if id == .mallard {c.poly([(27,35),(29,39),(24,39)],"orange");c.poly([(31,35),(35,39),(29,39)],"orange")}
        } else if wader || waterBird {c.line([(20,27),(5,29),(3,28)],id == .blackWingedStilt ? "pink":"brown");c.line([(20,28),(4,31),(2,30)],"brown")}
        var bodyY=flying ? 21.0 : (wader ? (id == .blackWingedStilt ? 19.0:(id == .eurasianWoodcock ? 25.0:23.0)):(waterBird ? 26.0:22.0))+bob
        if active && action == .rock { bodyY -= amount * 1.8 }
        let bodyH=flying ? anatomy.height * 0.65 : anatomy.height
        let bodyW=anatomy.width, bodyX=34-anatomy.width
        c.oval(bodyX,bodyY,bodyW,bodyH,style.0,outline:true)
        c.oval(bodyX+bodyW*0.48,bodyY+2,bodyW*0.52-1,bodyH-2,style.3)
        let headOrigin=TransportArtGeometry.headOrigin(flying:flying,headWidth:anatomy.headWidth,headY:anatomy.headY,bob:bob)
        var hx=headOrigin.x,hy=headOrigin.y
        let headW=anatomy.headWidth, headH=anatomy.headHeight
        if active {
            switch action {
            case .probe, .peck, .hammer: hx += amount * 2; hy += amount * (action == .probe ? 10 : 7)
            case .dabble: hx += amount; hy += amount * 10
            case .bow: hx += amount * 2.5; hy += amount * 4
            case .glean: hx += amount * 2; hy -= amount * 3
            case .scan: hx -= amount * 2; hy -= amount
            case .watch: hx += amount * 2; hy += amount * 3
            case .stalk: hx += amount * 2; hy -= amount * 2
            case .call: hx -= amount; hy -= amount * 2.5
            case .rock: hx -= amount; hy -= amount * 1.8
            case .crack: hy += amount * 2
            case .tail, .wing: hy -= amount
            }
        }
        if frame.hasPrefix("preen") {hx-=7;hy+=9+Double(phase)*0.5}
        if wader || waterBird {
            c.curve([(29,bodyY+4),(34,bodyY),(29,hy+6),(hx+3,hy+4)],style.3,width:waterBird ? 4:2.4)
        } else {c.poly([(26,24),(hx+1,hy+4),(hx+headW-1,hy+5),(33,29)],style.3)}
        if !flying {
            c.poly([(19,bodyY+1),(24,bodyY+1),(29,bodyY+4),(27,bodyY+8),(18,bodyY+bodyH-1),(16,bodyY+bodyH-1),(18,bodyY+5)],style.1,outline:true)
            c.poly([(20,bodyY+2),(24,bodyY+2),(26,bodyY+4),(23,bodyY+7),(18,bodyY+8)],style.0)
            for n in 0..<5 {let x=18+Double(n)*1.6;c.line([(x+4,bodyY+4),(x,bodyY+bodyH-1)],n%2 == 0 ? style.0:"dark")}
            if let bar=wingBar(id) {c.line([(19,bodyY+4),(25,bodyY+5)],bar,width:1.2)}
        }
        if active && action == .wing {
            c.poly([(22,bodyY+2),(12-amount*5,bodyY-amount*8),(15,bodyY+8),(26,bodyY+5)],style.1,outline:true)
            if let bar=wingBar(id) {c.line([(17,bodyY-amount*3),(22,bodyY+3)],bar,width:1.2)}
        }
        c.oval(hx,hy,headW,headH,style.2,outline:true)
        marks(c,id,hx,hy,headW,bodyY,flying)
        let billOrigin=TransportArtGeometry.billOrigin(headX:hx,headY:hy,headWidth:headW,headHeight:headH)
        let billX=billOrigin.x,billY=billOrigin.y
        let billFill:[SpeciesID:String]=[.mallard:"yellow",.blackHeadedGull:"red",.commonMoorhen:"red",.eurasianCoot:"white",.redBilledLeiothrix:"red",.yellowBilledGrosbeak:"yellow",.chineseBlackbird:"yellow",.asianKoel:"cream"]
        if id == .whimbrel || id == .hoopoe {
            c.curve([(billX,billY),(43,billY+0.4),(46,billY+3),(45,billY+7)],"dark",width:0.9)
        } else if id == .eurasianWoodcock || id == .commonKingfisher || id == .piedKingfisher {
            c.poly([(billX,billY-0.7),(47,billY+0.4),(billX,billY+1)],"dark")
            c.line([(billX,billY-0.5),(45,billY)],"slate")
        } else if raptor || id == .longTailedShrike {
            c.poly([(billX,billY-1),(billX+3,billY),(billX+3,billY+2),(billX+1.5,billY+3),(billX+1.8,billY+1),(billX,billY+1)],"dark")
            c.oval(billX-0.5,billY-1,1.5,2,"yellow")
        } else if id == .yellowBilledGrosbeak || id == .vinousThroatedParrotbill {
            c.poly([(billX,billY-1.4),(billX+4,billY+0.3),(billX+0.4,billY+2)],id == .vinousThroatedParrotbill ? "cream":"yellow",outline:true)
        } else {
            let length=TransportArtGeometry.ordinaryBillLength(species:id)
            c.poly([(billX,billY-0.7),(billX+length,billY+0.5),(billX+length-1,billY+1.2),(billX,billY+1.3)],billFill[id] ?? "dark")
        }
        if active && (action == .call || action == .crack) {
            c.poly([(billX,billY+1),(billX+3,billY+2+amount*2),(billX,billY+2+amount*2)],billFill[id] ?? "dark")
        }
        let eyeX=hx+headW*0.72,eyeY=hy+headH*0.38
        if id == .swinhoesWhiteEye {c.oval(eyeX-1.1,eyeY-1.1,2.9,2.9,"white")}
        if id == .littleRingedPlover || id == .chineseBlackbird {c.oval(eyeX-0.8,eyeY-0.8,2.3,2.3,"yellow")}
        if id == .asianKoel {c.oval(eyeX-0.7,eyeY-0.7,2.1,2.1,"red")}
        if frame == "blink" {c.line([(eyeX-0.4,eyeY+0.5),(eyeX+1,eyeY+0.5)],"eye")}
        else {c.oval(eyeX,eyeY,1,1.1,"eye");c.oval(eyeX+0.4,eyeY,0.45,0.45,"white")}
        if flying {c.ctx.restoreGState()}
        if flying || landing {wing(c,species:id,phase:flying ? phase:[4,6,7][min(2,phase)],fill:style.1,light:style.0,pointed:[.barnSwallow,.peregrineFalcon,.commonKestrel,.blackHeadedGull].contains(id),far:false,bar:wingBar(id))}
        if flying {c.ctx.restoreGState()}
        return c.image
    }
    enum FeedingPart:CaseIterable {case body,feet,headNeck,bill}

    /// Logical, top-down 48-unit anatomy. Right-facing foot anchor is (29,39).
    /// Both down poses put the ordinary bill's tip at (40,39): eleven units
    /// ahead of the feet, with no sprite translation or elongated bill.
    static func feedingImage(_ frame:String,species id:SpeciesID,
                             part:FeedingPart?=nil)->CGImage? {
        guard id == .treeSparrow || id == .spottedDove,
              BirdArt.feedingNames.contains(frame) else {return nil}
        let density=SpeciesCatalog.standard.profile(id).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let a=shape(id),s=colours(id),dove=id == .spottedDove
        let down=frame == "feedDown0" || frame == "feedDown1"
        let second=frame == "feedDown1",lift=frame == "feedLift"
        let tilt=down ? (second ? 1.10:0.88):(lift ? -0.32:0.08)
        let billRoot=a.headWidth/2-0.5,billLength=dove ? 4.0:3.5
        let tipX=billRoot+billLength,tipY=0.5
        // Solve the head position from a fixed ground contact. The two down
        // phases rotate crown, eye, cheek and bill together around this head.
        let hx=down ? 40-tipX*cos(tilt)+tipY*sin(tilt):32.0
        let hy=down ? 39-tipX*sin(tilt)-tipY*cos(tilt):(lift ? 18.5:21.0)
        func headTransform() {
            c.ctx.translateBy(x:hx,y:hy);c.ctx.rotate(by:CGFloat(tilt))
        }
        if part == nil || part == .body {
            let by=down ? (second ? 24.8:24.0):22.0
            let tailY=down ? a.tailY-2:a.tailY
            c.poly([(21,27),(25,31),(a.tailX+4,tailY+1),(a.tailX,tailY)],s.1,outline:true)
            c.line([(21,29),(a.tailX+1,tailY)],s.0)
            if dove {c.line([(a.tailX,tailY),(a.tailX+3,tailY+0.7)],"silver")}
            // The shoulder rolls forward while the belly stays over the legs.
            c.oval(34-a.width,by,a.width+(down ? 2:0),35-by,s.0,outline:true)
            c.oval(dove ? 25:27,by+2,down ? 9:7,33-by,s.3)
            c.poly([(18,by+1),(24,by),(30,by+4),(27,32),(18,34),(16,32),(17,by+5)],s.1,outline:true)
            c.poly([(19,by+1),(24,by+1),(27,by+4),(22,31),(18,32)],s.0)
            for n in 0..<5 {
                let x=18+Double(n)*1.6
                c.line([(x+4,by+3),(x,33)],n%2 == 0 ? s.0:"umber")
            }
            if dove {
                for n in 0..<8 {
                    let x=19+Double(n%3)*2.5,y=by+2+Double(n/3)*2
                    c.line([(x,y),(x+1,y-0.5),(x+2,y+0.5)],"buff")
                }
            } else {
                c.line([(19,by+3),(25,by+4)],"cream")
                c.line([(18,by+5),(23,by+6)],"buff")
            }
        }
        if part == nil || part == .feet {
            // Identical lower-leg/toe operations in every feeding pose and in
            // common34 stand. The (29,39) draw anchor never moves with the head.
            for x in [27.0,31.0] {
                c.line([(x-1,33),(x,35),(x-0.5,38.5)],"brown",width:1)
                c.line([(x-2,39),(x,38.5),(x+2,39)],"brown")
            }
        }
        if part == nil || part == .headNeck {
            // Rebuild the nape and throat between the shoulder and bowed head;
            // translating an upright head would leave a vertical neck behind.
            c.poly([(26,down ? 26:24),(hx-2,hy-2),(hx+2,hy),
                    (hx+2,hy+3),(33,down ? 33:29)],s.3,outline:true)
            c.poly([(26,down ? 26:24),(hx-2,hy-2),(hx-1,hy+1),(29,29)],s.0)
            if lift {
                // A visible throat bulge and raised, closed bill read as a
                // swallow, followed by the open-eyed feedLook observation.
                c.oval(31,24,3,dove ? 4:3,s.3)
            }
            c.ctx.saveGState();headTransform()
            let x = -a.headWidth/2,y = -a.headHeight/2
            c.oval(x,y,a.headWidth,a.headHeight,s.2,outline:true)
            if dove {
                c.poly([(x,y+3),(x+3,y+4),(x+3,y+7),(x,y+6)],"black")
                for p in [(x+0.5,y+4),(x+1.8,y+4.7),(x+0.7,y+5.7)] {
                    c.oval(p.0,p.1,0.8,0.8,"white")
                }
                c.poly([(x+3,y+4),(x+6,y+4),(x+5,y+6),(x+3,y+6)],"silver")
            } else {
                c.poly([(x,y+4),(x+4,y+3),(x+a.headWidth,y+4),
                        (x+a.headWidth-1,y+7),(x+2,y+7)],"cream")
                c.oval(x+2,y+4,2,2,"black")
                c.poly([(x+5,y+6),(x+a.headWidth,y+5),
                        (x+a.headWidth,y+8),(x+5,y+8)],"black")
            }
            let ex=x+a.headWidth*0.72,ey=y+a.headHeight*0.38
            if lift {c.line([(ex-0.2,ey+0.6),(ex+1,ey+0.6)],"eye")}
            else {c.oval(ex,ey,1,1.1,"eye");c.oval(ex+0.4,ey,0.45,0.45,"white")}
            c.ctx.restoreGState()
        }
        if part == nil || part == .bill {
            c.ctx.saveGState();headTransform()
            c.poly([(billRoot,-0.7),(tipX,tipY),(tipX-1,1.2),(billRoot,1.3)],"dark")
            if second {
                // A small lower-mandible opening, still above the contact
                // plane; the upper bill keeps exactly the same target tip.
                c.line([(billRoot+0.4,0.8),(tipX-1,0.8)],"cream",width:0.45)
            }
            c.ctx.restoreGState()
        }
        return c.image
    }

    // App-only semantic layers let the art verifier measure the actual raster
    // silhouette independently of the pose's intended contact landmarks.
    enum AllopreeningPart:CaseIterable {case body,feet,headNeck,bill}
    static func allopreeningImage(_ frame:String,species id:SpeciesID,
                                 part:AllopreeningPart?=nil)->CGImage? {
        guard id == .barnSwallow || id == .swinhoesWhiteEye,
              BirdArt.allopreeningNames.contains(frame) else {return nil}
        let density=SpeciesCatalog.standard.profile(id).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let anatomy=shape(id),style=colours(id)
        let giving=frame.hasPrefix("allopreenGive"),phase=Int(String(frame.last!)) ?? 0
        // A short reach comes from a forward shoulder and a nod at the neck,
        // never from stretching the bill or translating the entire sprite.
        let shoulderX=giving ? 2.3:0.0,settle=giving ? 0.0:0.3
        let hx=giving ? 43.3-anatomy.headWidth:37-anatomy.headWidth
        let hy=giving ? 20-anatomy.headHeight/2:20-anatomy.headHeight*0.1464466094
        let pivot=giving ? CGPoint(x:34,y:24):CGPoint(x:31,y:25)
        let tilt=giving ? [0.0,0.10,0.06][phase]:[0.18,0.25,0.12][phase]
        func headTransform() {
            c.ctx.translateBy(x:pivot.x,y:pivot.y);c.ctx.rotate(by:CGFloat(tilt))
            c.ctx.translateBy(x:-pivot.x,y:-pivot.y)
        }
        if part == nil || part == .body {
            c.ctx.saveGState();c.ctx.translateBy(x:shoulderX,y:settle)
            if id == .barnSwallow {
                c.poly([(21,25),(anatomy.tailX,anatomy.tailY-4),
                        (anatomy.tailX+8,anatomy.tailY),(anatomy.tailX,anatomy.tailY+4),(24,30)],style.1,outline:true)
            } else {
                c.poly([(21,27),(24,31),(anatomy.tailX+4,anatomy.tailY+1),
                        (anatomy.tailX,anatomy.tailY)],style.1,outline:true)
                c.line([(21,29),(anatomy.tailX+1,anatomy.tailY)],style.0)
            }
            let bx=34-anatomy.width,by=22.0
            c.oval(bx,by,anatomy.width,anatomy.height,style.0,outline:true)
            c.oval(bx+anatomy.width*0.48,by+2,anatomy.width*0.52-1,anatomy.height-2,style.3)
            c.poly([(19,by+1),(24,by+1),(29,by+4),(27,by+8),
                    (18,by+anatomy.height-1),(16,by+anatomy.height-1),(18,by+5)],style.1,outline:true)
            c.poly([(20,by+2),(24,by+2),(26,by+4),(23,by+7),(18,by+8)],style.0)
            for n in 0..<5 {
                let x=18+Double(n)*1.6
                c.line([(x+4,by+4),(x,by+anatomy.height-1)],n%2 == 0 ? style.0:"dark")
            }
            c.ctx.restoreGState()
        }
        if part == nil || part == .feet {
            // The lower legs and toes match the old perched path exactly.
            // Only the upper attachment extends into the leaning shoulder.
            for x in [27.0,31.0] {
                c.line([(x-1,29),(x-1,33),(x,35),(x-0.5,38.5)],"brown",width:1)
                c.line([(x-2,39),(x,38.5),(x+2,39)],"brown")
            }
        }
        if part == nil || part == .headNeck {
            c.ctx.saveGState();headTransform()
            c.poly([(27+shoulderX,24),(hx+1,hy+anatomy.headHeight*0.55),
                    (hx+anatomy.headWidth-1,hy+anatomy.headHeight*0.8),
                    (33+shoulderX,29)],style.3)
            c.poly([(27+shoulderX,24),(hx+1,hy+anatomy.headHeight*0.55),
                    (hx+2,hy+anatomy.headHeight),(30+shoulderX,27)],style.0)
            c.oval(hx,hy,anatomy.headWidth,anatomy.headHeight,style.2,outline:true)
            marks(c,id,hx,hy,anatomy.headWidth,22+settle,false)
            let ex=hx+anatomy.headWidth*0.72,ey=hy+anatomy.headHeight*0.38
            if id == .swinhoesWhiteEye {c.oval(ex-1.1,ey-1.1,2.9,2.9,"white")}
            if giving {
                c.oval(ex,ey,1,1.1,"eye");c.oval(ex+0.4,ey,0.45,0.45,"white")
            } else {
                // Shut lid and a few lifted nape feathers expose the crown to
                // the partner; the bill points down, away from the giver.
                c.line([(ex-0.5,ey+0.5),(ex+0.25,ey+0.8),(ex+1,ey+0.45)],"eye",width:0.8)
                let lift=[0.0,0.45,0.8][phase]
                c.line([(hx+1,hy+2),(hx+0.4-lift,hy+0.7)],style.0)
                c.line([(hx+2.2,hy+1),(hx+1.8,hy-lift)],style.0)
            }
            c.ctx.restoreGState()
        }
        if part == nil || part == .bill {
            c.ctx.saveGState();headTransform()
            let bx=hx+anatomy.headWidth-0.5,by=hy+anatomy.headHeight*0.5
            if giving {
                // The ordinary 2.2-unit bill gently opens and closes around
                // crown feathers. Give0 remains a compact approach pose.
                let opening=[0.25,0.0,0.55][phase]
                c.poly([(bx,by-0.7),(bx+2.2,by+0.5),(bx+1.2,by+1.2),(bx,by+1.3)],"dark")
                if opening > 0 {c.line([(bx+0.25,by+0.9),(bx+1.7,by+0.6+opening)],style.3,width:0.45)}
            } else {
                // On the swallow's shallow head, tuck the closed upper bill
                // into the lower face. Its old root rasterized into (37,22)
                // in Receive2, meeting Give1's lower bill after reflection.
                let upperRoot=by+(id == .barnSwallow ? 0.5:-0.2)
                c.poly([(bx,upperRoot),(bx+1.8,by+1.6),(bx+1.1,by+2.1),(bx-0.2,by+1.2)],"dark")
            }
            c.ctx.restoreGState()
        }
        return c.image
    }
    // Anatomical wing: shoulder -> elbow -> wrist -> fanned primaries. Each
    // primary has its own tapered tip; no translated rectangular slab.
    private static func wing(_ c:BirdPainter,species id:SpeciesID,phase:Int,fill:String,light:String,pointed:Bool=false,far:Bool=false,bar:String?=nil) {
        let broad = id == .blackKite || id == .commonBuzzard || herons.contains(id) || owls.contains(id) || id == .largeBilledCrow
        let pointed = pointed || [.commonKingfisher,.piedKingfisher,.mallard,.blackCollaredStarling,.whimbrel,.blackWingedStilt].contains(id)
        let rounded = [.treeSparrow,.swinhoesWhiteEye,.vinousThroatedParrotbill,.eurasianWoodcock,.redBilledLeiothrix].contains(id)
        if phase == 14 {
            // Folded recovery between bounding bursts, still a horizontal bird.
            c.poly([(27,23),(20,21),(13,25),(12,28),(22,27),(28,25)],far ? light:fill,outline:true)
            return
        }
        let gliding = phase >= 8
        // Three-quarter projection: the near wing opens toward the viewer and
        // forward/right; the far wing recedes left/up, with a shorter span and
        // narrower chord. Flapping returns through this same spread-wing pose.
        let lift = [-0.94,-0.62,0,0.65,0.94,0.58,0.05,-0.65][phase%8]
        let bank = phase >= 11 ? Double(phase-12) : (gliding ? Double(phase-9)*0.18 : 0)
        let span = broad ? ([SpeciesID.blackKite,.commonBuzzard].contains(id) ? 25.0:22.0) : (pointed ? (raptors.contains(id) ? 23.0:21.0) : (rounded ? 16.0 : 18.5))
        let neutral = far ? -(0.65-bank*0.10) : (0.83+bank*0.06)
        let reach = span * (gliding ? neutral : lift*0.81 + neutral*(1-abs(lift)))
        let spread = (far ? -0.63 : 0.68) * span * (gliding ? 1 : 1-abs(lift)*0.58)
        let chord = (broad ? (id == .commonBuzzard ? 10.5 : 9.0) : (pointed ? 4.8 : 6.5)) * (far ? 0.65 : 1.1)
        let fold = !gliding && phase >= 5 ? 0.78 : 1.0
        func p(_ spanwise:Double,_ trailing:Double)->(Double,Double) {
            (27 + spread*spanwise*fold - trailing*chord, 24 + reach*spanwise + trailing*1.8 + (far ? -1.2:0))
        }
        var outline:[(Double,Double)] = [(0,0),(0.30,-0.18),(0.62,-0.13),(0.90,-0.03),(1,0.06)]
        if pointed {
            outline += [(0.82,0.45),(0.52,0.85),(0.20,0.95),(0,0.45)]
        } else if broad {
            outline += [(0.98,0.25),(0.83,0.23),(0.94,0.48),(0.78,0.43),(0.86,0.71),(0.68,0.60),(0.73,0.89),(0.56,0.73),(0.55,1.03),(0.39,0.90),(0.20,0.85),(0,0.45)]
        } else {
            outline += [(0.97,0.35),(0.86,0.60),(0.70,0.80),(0.49,0.96),(0.23,0.92),(0,0.45)]
        }
        func shade(_ source:String,_ key:String) -> String {
            let value=c.palette[source]!
            let r=UInt32(Double((value>>24)&255)*0.78),g=UInt32(Double((value>>16)&255)*0.78),b=UInt32(Double((value>>8)&255)*0.78)
            c.palette[key]=(r<<24)|(g<<16)|(b<<8)|255;return key
        }
        let base=far ? shade(fill,"farWing"):fill, coverts=far ? shade(light,"farCoverts"):light
        c.poly(outline.map{p($0.0,$0.1)},base,outline:true)
        c.poly([(0,0),(0.3,-0.12),(0.62,-0.06),(0.64,0.3),(0.35,0.5),(0,0.38)].map{p($0.0,$0.1)},coverts)
        for n in 0..<6 {
            let u=0.30+Double(n)*0.11
            c.line([p(u,0.18),p(u+0.04,pointed ? 0.50 : 0.76)],far ? fill:"dark")
        }
        if id == .commonBuzzard {
            // Feather-aligned mottling, not a single pale panel pasted across
            // the wing. Close brown tones retain the continuous feather fan.
            let mottled=far ? shade("tan","farMottling"):"tan"
            for n in 0..<7 {
                let u=0.23+Double(n)*0.075
                c.line([p(u,0.24+Double(n%2)*0.06),p(u+0.025,0.43+Double(n%3)*0.05)],mottled,width:Double(c.unit)*1.4)
                c.line([p(u+0.02,0.56),p(u+0.04,0.66)],far ? base:"umber")
            }
        }
        if let bar {c.line([p(0.23,0.4),p(0.55,0.35),p(0.72,0.25)],bar,width:1.2)}
    }
    private static func heron(_ c:BirdPainter,_ id:SpeciesID,_ frame:String,_ phase:Int,_ flying:Bool,_ landing:Bool) {
        let night=id == .nightHeron,egret=id == .littleEgret,pond=id == .chinesePondHeron
        let back=egret ? "white":(night ? "navy":(pond ? "rust":"gray"))
        let wingFill=egret || pond ? "white":"gray"
        let light=egret || pond ? "silver":"slate"
        let neck=pond ? "rust":"white"
        let action=frame.hasPrefix("preen"),stretch=frame == "stretch"
        let breathe=frame == "breathe" ? -0.25:0.0
        if flying {
            c.ctx.saveGState();c.ctx.translateBy(x:0,y:CGFloat(phase >= 8 ? 0 : [0,-0.3,-0.5,0,0.4,0.6,0.2,-0.2][phase%8]))
            wing(c,species:id,phase:phase,fill:wingFill,light:light,far:true)
            c.ctx.saveGState();c.ctx.translateBy(x:27,y:24);c.ctx.scaleBy(x:0.92,y:0.94);c.ctx.translateBy(x:-27,y:-24)
            c.line([(23,25),(12,27),(2,28),(0.8,27)],egret ? "dark":"tan",width:0.65)
            c.line([(22,26),(10,29),(1,30)],egret ? "dark":"tan",width:0.65)
            c.poly([(20,23),(14,25),(17,27),(23,27)],wingFill,outline:true)
            c.oval(19,20,15,8,back,outline:true);c.oval(25,23,9,4,"silver")
            // Neck folded in flight, with a visible forward bulge below the head.
            c.curve([(30,24),(37,31),(38,25),(35,23)],neck,width:3.3)
            c.curve([(35,23),(32,21),(35,19),(38,20)],neck,width:2.5)
            headHeron(c,id,x:35,y:17.5,frame:frame)
            c.ctx.restoreGState()
            wing(c,species:id,phase:phase,fill:wingFill,light:egret ? "white":(pond ? "silver":"gray"),bar:egret ? nil:"slate")
            c.ctx.restoreGState();return
        }
        let base=night ? 32.0:(pond ? 30.0:26.0)
        let legs=egret ? "dark":(night || pond ? "tan":"brown")
        for x in [27.0,31.0] {
            let lift=frame.hasPrefix("idle") && egret && x == 27 ? Double(phase)*1.5 : 0
            c.line([(x-1,base),(x+lift,base+4),(x-0.5+lift,38.7-lift)],legs,width:0.7)
            c.line([(x-2+lift,39-lift),(x+lift,38.6-lift),(x+2+lift,39-lift)],egret ? "yellow":legs,width:0.7)
        }
        let by=night ? 20.5:(pond ? 22.0:19.0)
        c.poly([(17,by+4),(14,base-1),(18,base),(23,base-2)],wingFill,outline:true)
        c.oval(17,by+breathe,16,base-by,back,outline:true)
        c.oval(27,by+2,7,base-by-1,neck)
        var hx=32.0,hy=night ? 15.5:(pond ? 13.5:5.0)
        if id == .greyHeron {hx=33;hy=6.5}
        if stretch {hy-=night ? 7:1}
        if frame.hasPrefix("idle") {
            let reach=[0.25,0.65,1.0][min(2,phase)]
            hx += reach * (egret ? 3 : 1.5)
            hy += reach * (pond ? 6 : (egret ? 4 : -2))
        }
        if action {hx=23;hy=22+Double(phase)*0.7}
        if frame.hasPrefix("poop") {hy+=2}
        if night && !stretch && !action {
            c.oval(25.5,19.5,9.5,11.5,"white")
            c.curve([(30,29),(36,27),(34,23),(35,20)],"silver",width:5)
            c.curve([(31,29),(36,27),(34,23),(35,20)],"white",width:3.5)
        } else {
            // Narrow S-shaped neck: shoulder, forward knee, tucked middle, head.
            c.curve([(30,base-2),(36,base-6),(32,hy+13),(30,hy+10)],egret ? "silver":"gray",width:3.2)
            c.curve([(30,hy+10),(27,hy+6),(31,hy+4),(hx+2,hy+3)],egret ? "silver":"gray",width:3.2)
            c.curve([(30.6,base-2),(36,base-6),(33,hy+13),(30.7,hy+10)],neck,width:2.1)
            c.curve([(30.7,hy+10),(28,hy+6),(31,hy+4),(hx+2,hy+3)],neck,width:2.1)
        }
        c.poly([(19,by+1),(25,by+0.5),(29,by+3),(26,base-1),(17,base),(18,by+5)],wingFill,outline:true)
        c.poly([(20,by+1.4),(24,by+1),(27,by+3),(23,base-2),(19,base-2)],egret ? "white":"silver")
        for n in 0..<6 {let x=18+Double(n)*1.4;c.line([(x+4,by+3),(x,base-0.5)],egret ? "silver":"slate")}
        if egret {for n in 0..<4 {c.curve([(23,by+3),(23,base),(20,base+1),(17-Double(n),base+1+Double(n)*0.5)],"white",width:0.5)}}
        if id == .greyHeron {c.line([(31,19),(30,21)],"dark");c.line([(32,21),(31,23)],"dark");c.line([(32,24),(31.5,25)],"dark")}
        headHeron(c,id,x:hx,y:hy,frame:frame)
        if landing {wing(c,species:id,phase:[4,6,7][min(2,phase)],fill:wingFill,light:light)}
        if frame == "shake" {for n in 0..<5 {let y=by+Double(n);c.line([(18,y),(16.5,y+1.5)],wingFill)}}
        if night && frame.hasPrefix("poop") {c.curve([(18,31),(14,34),(16,39),(12+Double(phase),44)],"white",width:1.2);c.line([(13,42),(12,46)],"silver",width:0.7)}
    }
    private static func headHeron(_ c:BirdPainter,_ id:SpeciesID,x:Double,y:Double,frame:String) {
        let night=id == .nightHeron,egret=id == .littleEgret,pond=id == .chinesePondHeron
        let w=night ? 7.5:6.5,h=night ? 5.5:4.1
        c.oval(x,y,w,h,pond ? "rust":"white",outline:true)
        if night {c.poly([(x,y+2),(x+1,y),(x+5,y-0.3),(x+w,y+1.3),(x+w,y+2.3),(x+2,y+2.2)],"navy")}
        if id == .greyHeron {c.line([(x+0.2,y+1.5),(x+4.7,y+1.6)],"black",width:1.1);c.line([(x+1,y+1.3),(x-3,y+3.5)],"black",width:0.7)}
        if night || egret {c.curve([(x+0.5,y+1),(x-2,y+1),(x-2,y+4),(x-6,y+5)],"white",width:0.55);c.curve([(x,y+1),(x-3,y+1),(x-3,y+3),(x-7,y+3.5)],"silver",width:0.5)}
        let bill=egret || night ? "dark":"yellow",by=y+h*0.55
        c.poly([(x+w-0.5,by-0.8),(min(47,x+w+8),by+0.2),(x+w-0.5,by+1)],bill)
        c.line([(x+w,by-0.5),(min(46,x+w+6),by)],egret ? "slate":(night ? "slate":"buff"))
        let ex=x+w-2.2,ey=y+1.6
        c.oval(ex-0.5,ey-0.4,1.8,1.8,night ? "red":"yellow")
        if frame == "blink" {c.line([(ex-0.2,ey+0.5),(ex+0.7,ey+0.5)],"dark")}
        else {c.oval(ex,ey,0.8,0.9,"eye");c.oval(ex+0.35,ey,0.35,0.35,"white")}
    }
    private static func colours(_ id:SpeciesID)->(String,String,String,String) {
        switch id {
        case .redWhiskeredBulbul:return ("brown","umber","black","cream")
        case .treeSparrow:return ("tan","brown","rust","cream")
        case .lightVentedBulbul:return ("olive","green","black","cream")
        case .magpieRobin:return ("black","navy","black","white")
        case .littleRingedPlover:return ("tan","brown","tan","white")
        case .whimbrel:return ("brown","umber","tan","buff")
        case .commonKestrel:return ("orange","rust","gray","cream")
        case .peregrineFalcon:return ("slate","navy","navy","cream")
        case .blackKite:return ("brown","umber","tan","brown")
        case .commonBuzzard:return ("umber","brown","brown","cream")
        case .orientalMagpie:return ("black","navy","black","white")
        case .azureWingedMagpie:return ("gray","cyan","black","cream")
        case .largeBilledCrow,.asianKoel,.blackDrongo:return ("dark","black","black","dark")
        case .mallard:return ("gray","brown","green","silver")
        case .commonMoorhen,.eurasianCoot:return ("dark","slate","black","dark")
        case .blackHeadedGull:return ("white","silver","white","white")
        case .plumbeousWaterRedstart:return ("blue","slate","blue","blue")
        case .commonKingfisher:return ("cyan","blue","blue","orange")
        case .piedKingfisher,.greatSpottedWoodpecker:return ("silver","black","black","white")
        case .yellowRumpedFlycatcher:return ("black","black","black","yellow")
        case .redFlankedBluetail:return ("blue","navy","blue","white")
        case .swinhoesWhiteEye:return ("olive","green","olive","cream")
        case .yellowBrowedWarbler:return ("olive","green","olive","cream")
        case .greatTit:return ("green","slate","black","yellow")
        case .redBilledLeiothrix:return ("olive","green","olive","yellow")
        case .blackCollaredStarling:return ("brown","dark","cream","cream")
        case .yellowBilledGrosbeak:return ("gray","black","gray","cream")
        case .barnSwallow:return ("navy","blue","navy","cream")
        case .blackWingedStilt:return ("white","black","white","white")
        case .hoopoe:return ("orange","black","orange","buff")
        case .eurasianWoodcock:return ("tan","brown","tan","buff")
        case .vinousThroatedParrotbill:return ("tan","brown","orange","pink")
        case .chineseBlackbird:return ("dark","black","black","dark")
        case .spottedDove:return ("tan","brown","gray","pink")
        case .longTailedShrike:return ("orange","dark","gray","cream")
        default:return ("tan","brown","tan","cream")
        }
    }
    private static func wingBar(_ id:SpeciesID)->String? {
        switch id {
        case .magpieRobin,.hoopoe,.orientalMagpie,.greatTit,.yellowRumpedFlycatcher,.greatSpottedWoodpecker,.piedKingfisher,.yellowBilledGrosbeak,.blackCollaredStarling:return "white"
        case .yellowBrowedWarbler:return "cream"
        case .redBilledLeiothrix:return "red"
        default:return nil
        }
    }
    private static func marks(_ c:BirdPainter,_ id:SpeciesID,_ x:Double,_ y:Double,_ w:Double,_ bodyY:Double,_ flying:Bool) {
        func torso(_ offset:Double) -> Double { bodyY + offset * (flying ? 0.60 : 1) }
        switch id {
        case .redWhiskeredBulbul:
            c.poly([(x,y+2),(x+2,y-6),(x+4,y-3),(x+6,y+1)],"black")
            c.poly([(x+1,y+4),(x+4,y+3),(x+w,y+4),(x+5,y+7),(x+2,y+6)],"white")
            c.oval(x+2,y+3,2,2,"red")
            c.poly([(20,torso(10)),(24,torso(11)),(22,torso(13)),(19,torso(12))],"red")
        case .treeSparrow:
            c.poly([(x,y+4),(x+4,y+3),(x+w,y+4),(x+w-1,y+7),(x+2,y+7)],"cream")
            c.oval(x+2,y+4,2,2,"black")
            c.poly([(x+5,y+6),(x+w,y+5),(x+w,y+8),(x+5,y+8)],"black")
            if !flying {for i in 0..<4 {c.line([(18+Double(i)*2,torso(2)),(17+Double(i)*2,torso(6))],"umber")}}
        case .lightVentedBulbul:
            c.poly([(x,y+1),(x+3,y+1),(x+4,y+4),(x+2,y+6),(x,y+4)],"white")
            c.poly([(x+3,y+5),(x+w,y+4),(x+w,y+7),(x+4,y+8)],"silver")
        case .magpieRobin:
            c.poly([(27,torso(5)),(34,torso(4)),(33,torso(11)),(27,torso(12))],"white")
        case .orientalMagpie:
            c.oval(19,torso(1),6,4,"white")
            c.line([(18,torso(7)),(22,torso(4))],"cyan",width:1.2)
        case .commonKestrel,.peregrineFalcon:
            c.poly([(x+1,y+4),(x+w-1,y+3.5),(x+w-1,y+6.5),(x+3,y+7)],"cream")
            c.poly([(x+w-3,y+3),(x+w-1.5,y+3.5),(x+w-2,y+7),(x+w-3.5,y+6)],"black")
            for row in 0..<5 {let yy=torso(4+Double(row)*1.6);for col in 0..<3 {let xx=28+Double(col)*1.7;c.line([(xx,yy),(xx+0.7,yy+0.3)],id == .commonKestrel ? "rust":"slate")}}
            if id == .commonKestrel && !flying {for i in 0..<7 {let xx=19+Double(i%3)*2,yy=torso(3)+Double(i/3)*2;c.line([(xx,yy),(xx+0.6,yy+1)],"umber")}}
        case .commonBuzzard:
            c.poly([(29,torso(4)),(32,torso(3)),(33,torso(7)),(29,torso(8)),(27,torso(6))],"brown")
            for i in 0..<4 {c.line([(28,torso(9+Double(i))),(31,torso(9+Double(i)))],"tan")}
        case .blackKite:
            for i in 0..<4 {c.line([(x+1+Double(i),y+2),(x+1.5+Double(i),y+4.5)],"brown")}
            c.line([(30,torso(3)),(29,torso(7))],"tan")
        case .largeBilledCrow,.asianKoel:
            c.line([(x+1,y+2),(x+4,y+1)],"dark")
            if !flying {for i in 0..<3 {c.line([(27+Double(i),torso(4)),(28+Double(i),torso(6))],"slate")}}
        case .blackDrongo:c.poly([(x+0.5,y+1),(x+1,y-1),(x+4,y),(x+6,y+1)],"black");c.line([(x+1,y+2),(x+3,y+1)],"slate")
        case .azureWingedMagpie:c.poly([(x+1,y+4),(x+w-1,y+4),(x+w-1,y+6),(x+2,y+7)],"cream")
        case .mallard:
            c.line([(x+0.5,y+6),(x+4,y+7),(x+7,y+6)],"white",width:1)
            c.poly([(30,bodyY),(34,torso(1)),(34,torso(5)),(30,torso(6))],"rust")
            if !flying {c.poly([(16,torso(2)),(23,torso(2)),(24,torso(5)),(17,torso(5))],"navy");c.line([(16,torso(1.6)),(23,torso(1.6))],"white");c.line([(17,torso(5.5)),(24,torso(5.5))],"white")}
            c.oval(x+2,y+1,4,2,"olive")
        case .commonMoorhen:c.oval(x+w-2,y+1,2,3.5,"red");c.line([(16,torso(7)),(24,torso(8))],"white")
        case .eurasianCoot:c.oval(x+w-2,y+0.3,2,4,"white")
        case .blackHeadedGull:c.oval(x+1,y+2.6,1.4,2,"dark")
        case .swinhoesWhiteEye:c.poly([(x+3,y+5),(x+w,y+4),(x+w-1,y+7),(x+4,y+7)],"yellow")
        case .yellowBrowedWarbler:
            c.line([(x+0.5,y+2),(x+w-0.5,y+1.7)],"cream",width:0.8)
            c.line([(x+2,y+3),(x+w,y+2.7)],"brown")
            if !flying {c.line([(19,torso(7)),(24,torso(8))],"cream")}
        case .yellowRumpedFlycatcher:c.line([(x+0.5,y+1.5),(x+w-1,y+1)],"white",width:0.8);c.poly([(17,torso(9)),(21,torso(8)),(22,torso(11)),(18,torso(12))],"yellow")
        case .greatTit:
            c.poly([(x+1,y+4),(x+5,y+3),(x+w-1,y+4),(x+w-1,y+6),(x+3,y+7)],"white")
            c.line([(x+4,y+6.5),(31,torso(4)),(30,torso(11))],"black",width:1.4)
        case .redFlankedBluetail:
            c.poly([(30,torso(4)),(33,torso(3)),(33,torso(9)),(30,torso(10))],"orange")
            c.poly([(x+3,y+5),(x+w,y+4.5),(x+w-1,y+7),(x+4,y+7)],"white")
            c.line([(x+1,y+1.5),(x+5,y+1)],"cyan")
        case .redBilledLeiothrix:c.poly([(x+2,y+4),(x+w,y+4),(x+w-1,y+7),(x+3,y+6)],"orange");c.line([(x+1,y+1.5),(x+w-1,y+1)],"yellow");if !flying {c.line([(18,torso(7)),(24,torso(8))],"yellow")}
        case .blackCollaredStarling:c.poly([(x,y+6),(x+4,y+7),(x+w,y+6),(x+w-0.5,y+8),(x+3,y+9),(x,y+8)],"black")
        case .yellowBilledGrosbeak:c.poly([(x+w-3,y+2),(x+w,y+2),(x+w,y+5),(x+w-2,y+5)],"black")
        case .barnSwallow:c.poly([(x+3,y+4),(x+w,y+4),(x+w-1,y+7),(x+3,y+6)],"rust");c.line([(x+3,y+0.5),(x+6,y+1)],"rust");c.line([(x+2,y+7),(x+6,y+8)],"navy",width:1.2)
        case .hoopoe:
            for i in 0..<6 {
                let a = -2.7+Double(i)*0.29,tip=(x+3+cos(a)*9,y+3+sin(a)*9)
                c.line([(x+3,y+2),tip],"orange",width:1.2)
                c.line([tip,(tip.0-cos(a)*1.6,tip.1-sin(a)*1.6)],"black",width:1.2)
            }
            if !flying {
                // Separate bands follow the tapered folded wing; do not stack
                // them over the generic wing bar or spill onto the buff breast.
                let edge:[(Double,Double)]=[(19,torso(1)),(24,torso(1)),(29,torso(4)),(27,torso(8)),(18,torso(11)),(16,torso(11)),(18,torso(5))]
                c.poly(edge,"black",outline:true)
                c.ctx.saveGState()
                c.ctx.beginPath();c.ctx.move(to:CGPoint(x:edge[0].0,y:edge[0].1))
                for p in edge.dropFirst(){c.ctx.addLine(to:CGPoint(x:p.0,y:p.1))}
                c.ctx.closePath();c.ctx.clip()
                for i in 0..<3 {
                    let yy=torso(2.5+Double(i)*3.2)
                    c.line([(16,yy),(21,yy+0.5),(28,yy+2)],"white",width:0.85)
                }
                c.ctx.restoreGState()
            }
        case .piedKingfisher:
            c.poly([(x,y+2),(x-1,y),(x+2,y+0.5),(x+2,y-1.4),(x+5,y+0.4),(x+7,y)],"black")
            c.poly([(x+1,y+4),(x+5,y+3.5),(x+w-1,y+4),(x+w-2,y+6),(x+2,y+6)],"white")
            c.line([(28,torso(2)),(33,torso(3))],"black",width:1.5)
            c.line([(29,torso(5)),(33,torso(6))],"black")
            if !flying {for i in 0..<9 {c.oval(18+Double(i%3)*2,torso(2)+Double(i/3)*2,0.8,0.8,"white")}}
        case .commonKingfisher:
            c.poly([(x+1,y+4),(x+4,y+3.5),(x+5,y+5),(x+3,y+6)],"orange")
            c.poly([(x+4,y+5),(x+8,y+4.5),(x+8,y+6),(x+5,y+7)],"white")
            c.line([(19,torso(1)),(18,torso(8))],"cyan",width:1.4)
            for i in 0..<5 {c.oval(x+1+Double(i)*1.3,y+1.3,0.5,0.5,"cyan")}
        case .greatSpottedWoodpecker:
            c.poly([(x+1,y+3.5),(x+w-1,y+3),(x+w-1,y+5.5),(x+3,y+6.5)],"white")
            c.line([(x+1,y+1),(x,y+3)],"red",width:1.3)
            c.poly([(27,torso(8)),(33,torso(8)),(31,torso(12)),(26,torso(11))],"red")
            if !flying {c.oval(20,torso(2),5,3.5,"white");for i in 0..<3 {c.oval(18+Double(i),torso(7+Double(i)),0.8,0.8,"white")}}
        case .whimbrel:
            c.line([(x+0.4,y+1),(x+w-1,y+0.7)],"cream")
            c.line([(x+1,y+2.4),(x+w-1,y+2)],"umber")
            for i in 0..<12 {let xx=18+Double(i%4)*2.3,yy=torso(1)+Double(i/4)*2;c.line([(xx,yy),(xx+1,yy+0.7)],"buff")}
        case .eurasianWoodcock:
            for i in 0..<3 {c.line([(x+0.5,y+Double(i)*1.5),(x+3,y+Double(i)*1.5+0.5)],"umber",width:1)}
            for i in 0..<18 {let xx=17+Double(i%5)*2.8,yy=torso(1)+Double(i/5)*1.8;c.line([(xx,yy),(xx+1.5,yy+0.5)],i%2 == 0 ? "buff":"umber")}
        case .vinousThroatedParrotbill:c.poly([(x+1,y+4),(x+w-1,y+3.5),(x+w-1,y+6),(x+3,y+7)],"pink")
        case .blackWingedStilt:c.poly([(x,y+1),(x+2,y),(x+4,y+0.5),(x+4,y+2),(x,y+3)],"black")
        case .littleRingedPlover:
            c.line([(x,y+2),(x+w-1,y+2)],"black",width:1)
            c.line([(x+1,y+5),(x+4,y+6),(x+w,y+5)],"white",width:1.2)
            c.line([(x+1,y+7),(x+4,y+8),(x+w,y+7)],"black",width:1.4)
        case .spottedDove:
            c.poly([(x,y+4),(x+4,y+5),(x+4,y+8),(x,y+7)],"black")
            for (xx,yy) in [(x+0.7,y+5),(x+2,y+5.8),(x+3,y+6.7),(x+1,y+6.5)] {c.oval(xx,yy,0.7,0.7,"white")}
            if !flying {for i in 0..<10 {let xx=19+Double(i%3)*2,yy=torso(2)+Double(i/3)*1.8;c.line([(xx,yy),(xx+1,yy-0.4),(xx+1.5,yy+0.5)],"buff")}}
        case .longTailedShrike:c.poly([(x,y+2),(x+w,y+2),(x+w,y+3.7),(x+1,y+4)],"black");c.poly([(x+2,y+4),(x+w,y+4),(x+w-1,y+6.5),(x+3,y+7)],"cream")
        default:break
        }
    }
    private static func owl(_ c:BirdPainter,_ id:SpeciesID,_ frame:String,_ phase:Int,_ flying:Bool,_ landing:Bool) {
        let scops=id == .collaredScopsOwl, barred=id == .asianBarredOwlet
        let a=shape(id), active=frame.hasPrefix("idle")
        let amount=active ? [0.25,0.65,1.0][min(phase,2)] : 0.0
        let back=scops ? "gray" : (barred ? "rust" : "brown")
        let feather=scops ? "umber" : "brown"
        let breath=frame == "breathe" ? -0.4 : 0.0
        if flying {
            wing(c,species:id,phase:phase,fill:feather,light:back,far:true,bar:"buff")
            c.ctx.saveGState();c.ctx.translateBy(x:27,y:24);c.ctx.scaleBy(x:0.82,y:0.84);c.ctx.translateBy(x:-27,y:-24)
            c.poly([(22,23),(7,25),(7,30),(23,29)],feather,outline:true)
            for x in [10.0,14,18] {c.line([(x,25),(x,29)],"buff")}
            c.oval(16,20,20,11,back,outline:true)
            c.oval(25,23,11,7,"buff")
            owlFace(c,id,x:30,y:15,w:12,h:11,frame:frame,turn:0.7)
            c.ctx.restoreGState()
            wing(c,species:id,phase:phase,fill:feather,light:back,bar:"buff")
            return
        }
        // The feet stay planted while the torso bows or the head turns.
        for x in [26.0,32.0] {
            c.line([(x,33),(x,38.5)],scops ? "gray" : "cream",width:2)
            c.line([(x-2,39),(x,38.5),(x+2,39)],"tan",width:0.8)
        }
        c.poly([(21,29),(28,30),(25,39),(a.tailX,39)],feather,outline:true)
        c.line([(19,35),(26,35)],"buff")
        let dip=scops ? amount*1.5 : (barred ? 0 : amount*2.8)
        let bodyY=36-a.height+breath+dip
        c.oval(28-a.width/2,bodyY,a.width,a.height-dip,back,outline:true)
        c.oval(23,bodyY+3,12,a.height-4-dip,scops || barred ? "cream" : "buff")
        for row in 0..<5 {
            let yy=bodyY+4+Double(row)*2.2
            if barred {
                if row < 2 {c.line([(24,yy),(33,yy)],"brown",width:0.7)}
                else {
                    for col in 0..<3 {
                        let xx=25+Double(col)*3+Double(row%2)*0.5
                        c.line([(xx,yy),(xx-0.3,yy+1.2)],"brown",width:0.7)
                    }
                }
            } else {
                for col in 0..<3 {
                    let xx=25+Double(col)*3+Double(row%2)*0.6
                    c.line([(xx,yy),(xx+0.3,yy+1.2+Double(col%2)*0.3)],"umber",width:0.7)
                    if scops {c.line([(xx-0.5,yy+0.5),(xx+0.6,yy+0.9)],"brown")}
                }
            }
        }
        c.poly([(20,bodyY+1),(24,bodyY+3),(23,32),(19,35),(18,27)],feather,outline:true)
        c.poly([(35,bodyY+2),(38,bodyY+4),(37,32),(34,35),(33,27)],feather,outline:true)
        for n in 0..<5 {
            let yy=bodyY+3+Double(n)*2.3
            if barred {c.line([(19,yy),(23,yy+0.4)],"buff")}
            else {c.oval(20,yy,1.5,1.1,scops ? "tan" : "cream")}
        }
        let preen=frame.hasPrefix("preen")
        c.ctx.saveGState()
        let cx=28.0,cy=a.headY+a.headHeight/2+breath+dip
        c.ctx.translateBy(x:cx,y:cy)
        let tilt=preen ? 0.55+Double(phase)*0.12 : (barred ? amount*0.16 : 0)
        c.ctx.rotate(by:CGFloat(tilt));c.ctx.translateBy(x:-cx,y:-cy)
        let headX=cx-a.headWidth/2+(preen ? -3 : 0)
        owlFace(c,id,x:headX,y:a.headY+breath+dip+(preen ? 5 : 0),w:a.headWidth,h:a.headHeight,frame:frame,turn:barred ? amount*0.85 : 0)
        c.ctx.restoreGState()
        if landing {wing(c,species:id,phase:[4,6,7][min(2,phase)],fill:feather,light:back,bar:"buff")}
    }
    private static func owlFace(_ c:BirdPainter,_ id:SpeciesID,x:Double,y:Double,w:Double,h:Double,frame:String,turn:Double) {
        let scops=id == .collaredScopsOwl,barred=id == .asianBarredOwlet
        let active=frame.hasPrefix("idle"),phase=Int(String(frame.last!)) ?? 0
        let crown=scops ? "gray" : (barred ? "rust" : "brown")
        c.oval(x,y,w,h,crown,outline:true)
        if scops {
            let raise=active ? Double(phase)*0.5 : 0
            c.poly([(x+1,y+5),(x,y-4-raise),(x+5,y+1)],"umber",outline:true)
            c.poly([(x+w-5,y+1),(x+w,y-4-raise),(x+w-1,y+5)],"umber",outline:true)
            c.line([(x+1,y-2),(x+3,y+2)],"buff")
            c.line([(x+w-1,y-2),(x+w-3,y+2)],"buff")
        }
        // Head turn compresses the far disc and shifts the bill, rather than
        // making the pupils slide independently inside an immobile face.
        let mid=x+w*(0.5+turn*0.17), eyeY=y+h*0.48
        let farW=w*(0.38-turn*0.12),nearW=w*0.4
        c.oval(mid-farW-0.5,y+h*0.25,farW,h*0.66,scops ? "silver" : "buff",outline:scops)
        c.oval(mid+0.5,y+h*0.25,nearW,h*0.66,scops ? "silver" : "buff",outline:scops)
        if barred {
            for row in 0..<3 {let yy=y+1.3+Double(row)*1.2,inset=5-Double(row)*0.7;c.line([(x+inset,yy),(x+w-inset,yy)],"buff",width:0.6)}
        } else if !scops {
            for n in 0..<5 {c.oval(x+2+Double(n)*2.8,y+1.5,1.3,0.8,"cream")}
        }
        let eyeSize=w*0.19
        for ex in [mid-farW*0.55,mid+nearW*0.55] {
            if frame == "blink" || frame.hasPrefix("preen") {
                c.line([(ex-eyeSize/2,eyeY+1),(ex+eyeSize/2,eyeY+1)],"eye",width:0.9)
            } else {
                c.oval(ex-eyeSize/2,eyeY-eyeSize/2,eyeSize,eyeSize,scops ? "orange" : "yellow",outline:true)
                c.oval(ex-eyeSize*0.23,eyeY-eyeSize*0.3,eyeSize*0.46,eyeSize*0.65,"eye")
                c.oval(ex,eyeY-eyeSize*0.23,0.55,0.55,"white")
            }
        }
        c.line([(mid-farW+0.5,eyeY-2),(mid-1,eyeY-1)],scops ? "white" : "cream",width:scops ? 1 : 1.3)
        c.line([(mid+1,eyeY-1),(mid+nearW-0.5,eyeY-2)],scops ? "white" : "cream",width:scops ? 1 : 1.3)
        c.poly([(mid-1,eyeY+1),(mid+1,eyeY+1),(mid+0.3,eyeY+4)],scops ? "cream" : "yellow",outline:true)
        if scops && active {c.oval(mid-0.6,eyeY+3,1.4,1+Double(phase)*0.5,"eye")}
        if !scops && !barred {c.line([(x+3,y+h-2),(mid,y+h-0.7),(x+w-3,y+h-2)],"white",width:1)}
    }
    private static func woodpecker(_ c:BirdPainter,_ frame:String) {
        let reach=frame == "peck1" ? 2.0:0.0
        c.poly([(18,28),(23,30),(27,43),(25,44),(20,37),(16,32)],"black",outline:true)
        c.line([(20,31),(25,42)],"slate")
        c.oval(13,18,12,18,"black",outline:true)
        c.oval(20,20,6,13,"white")
        c.poly([(15,18),(21,20),(22,27),(17,33),(13,30)],"black")
        c.oval(16,21,4,5,"white")
        for i in 0..<4 {c.line([(15+Double(i),28),(14+Double(i),31)],i%2 == 0 ? "white":"slate")}
        c.poly([(20,31),(25,31),(23,36),(19,34)],"red")
        c.curve([(22,22),(25,19),(22+reach,17),(23+reach,15)],"white",width:3)
        c.oval(20+reach,10,8,7,"black",outline:true)
        c.poly([(20+reach,13),(26+reach,13),(27+reach,15),(22+reach,17)],"white")
        c.line([(20+reach,11),(20+reach,13)],"red",width:1.1)
        c.poly([(27+reach,12.5),(35+reach,13.7),(27+reach,14.3)],"dark")
        c.oval(25+reach,12,1,1,"eye");c.oval(25.4+reach,12,0.4,0.4,"white")
        c.line([(23,29),(25,33),(29,33),(28,34)],"brown",width:0.8)
        c.line([(23,34),(26,38),(29,38),(29,39)],"brown",width:0.8)
    }
}

// M6b: independent perched key poses. All geometry is in top-down 48-unit
// coordinates; native density and the (29,39) foot anchor match the old art.
extension DetailedBirdArt {
    private struct FoundationPose {
        let body:(y:Double,height:Double,lean:Double,fluff:Double)
        let head:(x:Double,y:Double,pitch:Double)
        let tail:(x:Double,y:Double)
        let wing:Double

        init(_ body:(Double,Double,Double,Double),_ head:(Double,Double,Double),
             _ tail:(Double,Double),_ wing:Double = 0) {
            self.body=body;self.head=head;self.tail=tail;self.wing=wing
        }

        func headPoint(_ x:Double,_ y:Double)->CGPoint {
            CGPoint(x:head.x+x*cos(head.pitch)-y*sin(head.pitch),
                    y:head.y+x*sin(head.pitch)+y*cos(head.pitch))
        }
    }

    // Each row is deliberately authored for its species, not a stand-frame
    // transform. Body height/width, neck reach, tail carriage and wing opening
    // vary independently. Head triples are centre X/Y and clockwise radians.
    private static func foundationPose(_ frame:String,species id:SpeciesID)->FoundationPose? {
        switch id {
        case .treeSparrow:
            switch frame {
            case "lookNear":return FoundationPose((22.5,12.5,0.5,0),(33,22,0.32),(12,38))
            case "lookFar":return FoundationPose((21.5,13,0,0),(32,18.5,-0.18),(11,39))
            case "alertRise":return FoundationPose((20.5,14,0,0),(32.5,17,-0.24),(12,40),0.12)
            case "alertHold":return FoundationPose((19.5,15,0.5,-0.5),(33,15.5,-0.12),(13,41),0.18)
            case "alertRelax":return FoundationPose((22,13,-0.5,0.6),(31.5,20,-0.04),(11,38.5))
            case "restLower":return FoundationPose((24,12,-0.5,1.5),(31,23,0.18),(11,38))
            case "restTuck":return FoundationPose((24.5,12,-1,2),(26,25,2.48),(12,37))
            case "restWake":return FoundationPose((22.5,13,0,1),(31,19.5,-0.32),(10.5,39),0.10)
            case "takeoffCrouch":return FoundationPose((26,10.5,1.5,0.5),(34,25,0.16),(10,35),0.24)
            case "takeoffPush":return FoundationPose((19.5,12,2,0),(35,17.5,-0.24),(10,34),1)
            default:return nil
            }
        case .spottedDove:
            switch frame {
            case "lookNear":return FoundationPose((22.5,12.5,0.8,0),(35,21,0.28),(6,41))
            case "lookFar":return FoundationPose((21.5,13,0,0),(33.5,15,-0.16),(5.5,42))
            case "alertRise":return FoundationPose((20.5,14,0.3,0),(34,13.5,-0.20),(7,43),0.08)
            case "alertHold":return FoundationPose((19.5,15,0.6,-0.3),(34.5,11.5,-0.10),(8,43.5),0.12)
            case "alertRelax":return FoundationPose((22,13,-0.3,0.5),(32.5,17.5,0.06),(5,41))
            case "restLower":return FoundationPose((24,11.5,-0.8,1),(31.5,22,0.20),(5,40.5))
            case "restTuck":return FoundationPose((25,11.5,-1.5,1.8),(25,24.5,2.68),(6,40))
            case "restWake":return FoundationPose((22,13,-0.2,0.8),(32,16,-0.27),(4.5,42),0.08)
            case "takeoffCrouch":return FoundationPose((25.5,10.5,1.2,0.3),(35,22.5,0.12),(4,37),0.18)
            case "takeoffPush":return FoundationPose((18.5,12.5,2,0),(35.5,14,-0.24),(4,35),1)
            default:return nil
            }
        case .barnSwallow:
            switch frame {
            case "lookNear":return FoundationPose((23,9,0.5,0),(34,22,0.30),(2.5,42))
            case "lookFar":return FoundationPose((21.5,10,0,0),(33,18,-0.22),(2,42.5))
            case "alertRise":return FoundationPose((20.5,11,0.4,0),(33.5,16.5,-0.26),(3,43),0.14)
            case "alertHold":return FoundationPose((19.5,12,0.8,-0.3),(34,15,-0.14),(4,43),0.20)
            case "alertRelax":return FoundationPose((22,9.5,-0.2,0.3),(32.5,20,0.04),(2,41.5))
            case "restLower":return FoundationPose((25,9,-0.5,0.7),(31.5,24,0.16),(2,41))
            case "restTuck":return FoundationPose((25.5,9,-0.8,1),(27,26,2.58),(3,40.5))
            case "restWake":return FoundationPose((22.5,10,0,0.5),(32,19,-0.30),(2,42),0.12)
            case "takeoffCrouch":return FoundationPose((27,8,1.8,0),(34.5,25.5,0.10),(2,37),0.30)
            case "takeoffPush":return FoundationPose((19,9.5,2.2,0),(35.5,17,-0.22),(2,35),1)
            default:return nil
            }
        case .nightHeron:
            switch frame {
            case "lookNear":return FoundationPose((21.5,11.5,0.5,0),(35,21,0.30),(14,32))
            case "lookFar":return FoundationPose((20,12,0,0),(34,15,-0.12),(13,31.5))
            case "alertRise":return FoundationPose((18.5,13,0.5,0),(34,11.5,-0.18),(14,32),0.06)
            case "alertHold":return FoundationPose((17.5,14,1,-0.4),(34,8.5,-0.08),(14.5,33),0.10)
            case "alertRelax":return FoundationPose((20.5,12,-0.5,0.6),(33,17,0.08),(12.5,31.5))
            case "restLower":return FoundationPose((23,11.5,-0.7,1),(32,23,0.18),(13,33))
            case "restTuck":return FoundationPose((24,11,-1,1.8),(27,25,2.72),(13.5,33.5))
            case "restWake":return FoundationPose((21,12.5,0,0.7),(32.5,15,-0.24),(12.5,32),0.06)
            case "takeoffCrouch":return FoundationPose((25,10.5,1,0.5),(35,24,0.12),(12,31),0.20)
            case "takeoffPush":return FoundationPose((17,11.5,2,0),(35,15,-0.22),(11.5,29.5),1)
            default:return nil
            }
        default:return nil
        }
    }

    /// Exact authored bill tip, before raster rounding, in right-facing logical
    /// coordinates. Reflect with x -> 48-x, just like BirdRenderState. A tucked
    /// bill still has an anchor even though scapular feathers cover its tip.
    static func poseBillAnchor(_ frame:String,species id:SpeciesID)->CGPoint? {
        if let anchor=catchBillAnchor(frame,species:id) {return anchor}
        if let anchor=carryBillAnchor(frame,species:id) {return anchor}
        if let anchor=transportBillAnchor(frame,species:id) {return anchor}
        if let anchor=bathBillAnchor(frame,species:id) {return anchor}
        if let a=M6cPoseGeometry.anatomy(id),let pose=M6cPoseGeometry.pose(species:id,frame:frame) {
            return pose.billTip(species:id,anatomy:a)
        }
        guard let pose=foundationPose(frame,species:id) else {return nil}
        let bill=foundationBill(id)
        return pose.headPoint(bill.root+bill.length,bill.tipY)
    }

    private static func foundationBill(_ id:SpeciesID)->(root:Double,length:Double,tipY:Double) {
        if id == .nightHeron {return (3.25,8,0.2)}
        return (shape(id).headWidth/2-0.5,id == .barnSwallow ? 2.2:4,0.5)
    }

    // Semantic layers support the main session's later geometry acceptance.
    // Keeping feet separate permits a raster comparison without belly/wing
    // pixels obscuring the fixed toes in a resting or crouching silhouette.
    enum FoundationPosePart:CaseIterable {case body,feet,headNeck,bill}

    static func poseImage(_ frame:String,species id:SpeciesID,
                          part:FoundationPosePart?=nil)->CGImage? {
        if let image=catchImage(frame,species:id,part:part) {return image}
        if let image=carryImage(frame,species:id,part:part) {return image}
        if let image=bathImage(frame,species:id,part:part) {return image}
        if let image=m6cPoseImage(frame,species:id,part:part) {return image}
        guard let pose=foundationPose(frame,species:id) else {return nil}
        let density=SpeciesCatalog.standard.profile(id).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let tucked=frame == "restTuck",drowsy=frame == "restLower"
        let a=shape(id),s=colours(id),night=id == .nightHeron
        let bx=(night ? 17:34-a.width)+pose.body.lean-pose.body.fluff/2
        let bw=a.width+pose.body.fluff,by=pose.body.y,bh=pose.body.height
        let back=night ? "navy":s.0,feather=night ? "gray":s.1
        let breast=night ? "white":s.3

        if part == nil || part == .feet {
            // No context/body transform ever touches the feet. Lower legs and
            // toes retain the original species operations, even in Push.
            for x in [27.0,31.0] {
                let top=by+bh-2
                let kneeX=x+(frame == "takeoffCrouch" ? 1.5:0)
                if night {
                    c.line([(x-1+pose.body.lean,top),(kneeX,max(top+1,36)),
                            (x-0.5,38.7)],"tan",width:0.7)
                    c.line([(x-2,39),(x,38.6),(x+2,39)],"tan",width:0.7)
                } else {
                    c.line([(x-1+pose.body.lean,top),(kneeX,35),(x-0.5,38.5)],"brown",width:1)
                    c.line([(x-2,39),(x,38.5),(x+2,39)],"brown")
                }
            }
        }
        if part == nil || part == .body {
            foundationTail(c,id,pose,bx:bx,by:by,bh:bh,fill:feather)
            // Far wing opens behind the torso; the near wing opens above it.
            if pose.wing > 0 {foundationWing(c,id,pose,bx:bx,by:by,bh:bh,far:true)}
            c.oval(bx,by,bw,bh,back,outline:true)
            c.oval(bx+bw*0.48,by+2,bw*0.52-0.7,bh-2,breast)
            if pose.body.fluff > 0.6 {
                for n in 0..<4 {
                    let x=bx+5+Double(n)*2.2,y=by+bh-1
                    c.poly([(x-1,y-2),(x+1,y-1),(x+0.2,y+0.6)],n > 1 ? breast:back)
                }
            }
            foundationFoldedWing(c,id,pose,bx:bx,by:by,bh:bh)
        }
        if part == nil || part == .headNeck {
            // Neck joins world-space shoulder to the rotated head's nape and
            // chin; changing head pitch cannot leave an old vertical neck.
            let nape=pose.headPoint(-a.headWidth*0.32,1)
            let chin=pose.headPoint(a.headWidth*0.28,a.headHeight*0.38)
            if night {
                let fold=tucked ? 1.5:(frame.hasPrefix("alert") ? 0:3)
                c.curve([(bx+11,by+bh-2),(bx+20,by+bh-3),
                         (chin.x+fold,chin.y+4),(chin.x,chin.y)],"silver",width:5)
                c.curve([(bx+11.5,by+bh-2),(bx+19,by+bh-3),
                         (chin.x+fold-0.5,chin.y+4),(chin.x,chin.y)],"white",width:3.5)
                c.poly([(bx+7,by+3),(nape.x,nape.y),(chin.x,chin.y),
                        (bx+15,by+bh-2)],"white")
                c.line([(bx+10,by+5),(nape.x,nape.y)],"silver",width:0.7)
            } else {
                c.poly([(bx+bw*0.52,by+2),(nape.x,nape.y),
                        (chin.x,chin.y),(bx+bw-1,by+bh*0.65)],breast)
                c.poly([(bx+bw*0.52,by+2),(nape.x,nape.y),
                        (nape.x+1,nape.y+2),(bx+bw*0.62,by+6)],back)
            }
            c.ctx.saveGState()
            c.ctx.translateBy(x:pose.head.x,y:pose.head.y);c.ctx.rotate(by:CGFloat(pose.head.pitch))
            foundationHead(c,id,tucked:tucked,drowsy:drowsy)
            c.ctx.restoreGState()
        }
        if part == nil || part == .bill {
            let bill=foundationBill(id)
            c.ctx.saveGState()
            c.ctx.translateBy(x:pose.head.x,y:pose.head.y);c.ctx.rotate(by:CGFloat(pose.head.pitch))
            c.poly([(bill.root,-0.7),(bill.root+bill.length,bill.tipY),
                    (bill.root+bill.length-1,1.0),(bill.root,1.2)],"dark")
            if night {c.line([(bill.root+0.4,-0.35),(bill.root+6,0)],"slate",width:0.5)}
            c.ctx.restoreGState()
        }
        if part == nil || part == .body {
            if tucked {
                // A real backwards head turn with the closed bill hidden in
                // raised scapulars. The crown remains visible above the wing.
                let tx=pose.head.x,ty=pose.head.y,left=tx-(night ? 12:8)
                c.poly([(left+1,ty+1),(tx-2,ty+1),(tx+2,ty+3),
                        (tx+2,ty+7),(left+1,ty+7),(left,ty+4)],feather,outline:true)
                for n in 0..<3 {
                    let x=tx-5+Double(n)*2
                    c.line([(x,ty+2),(x-1,ty+5)],night ? "silver":s.0)
                }
            }
            if pose.wing > 0 {foundationWing(c,id,pose,bx:bx,by:by,bh:bh,far:false)}
        }
        return c.image
    }

    private static func foundationTail(_ c:BirdPainter,_ id:SpeciesID,_ p:FoundationPose,
                                       bx:Double,by:Double,bh:Double,fill:String) {
        let x=p.tail.x,y=p.tail.y,rootX=bx+5,rootY=by+bh*0.5
        if id == .barnSwallow {
            // Two slender streamers and a deep, open fork; crouch fans them
            // horizontally to keep both tips clear of the perch plane.
            c.poly([(rootX,rootY),(x,y-5),(x+8,y),(x,y+4),(rootX+5,rootY+4)],"navy",outline:true)
            c.line([(rootX+1,rootY+1),(x+1,y-4)],"blue")
            c.line([(rootX+4,rootY+3),(x+1,y+3)],"slate")
        } else if id == .nightHeron {
            c.poly([(bx+3,by+5),(x,y-1),(x+4,y),(bx+8,by+bh-2)],fill,outline:true)
            c.line([(x+1,y-1),(bx+5,by+bh-3)],"silver")
        } else {
            let fan=id == .spottedDove ? 5.0:4.0
            c.poly([(rootX,rootY),(rootX+5,rootY+4),(x+fan,y+1),(x,y)],fill,outline:true)
            c.line([(rootX+2,rootY+2),(x+1,y)],id == .spottedDove ? "tan":"buff")
            if id == .spottedDove {c.line([(x,y),(x+fan,y+1)],"silver",width:1.1)}
        }
    }

    private static func foundationFoldedWing(_ c:BirdPainter,_ id:SpeciesID,_ p:FoundationPose,
                                             bx:Double,by:Double,bh:Double) {
        let night=id == .nightHeron,swallow=id == .barnSwallow,dove=id == .spottedDove
        let s=colours(id),fill=night ? "gray":s.1,light=night ? "silver":s.0
        // Swallow primaries taper well behind the belly; the sparrow's wing
        // rounds off before its short tail. Dove coverts retain scalloped edges.
        let tipX=bx+(swallow ? -2:0),tipY=by+bh+(swallow ? 3:-1)
        c.poly([(bx+3,by+1),(bx+8,by+0.5),(bx+13,by+4),
                (bx+10,by+bh*0.7),(tipX+2,tipY),(tipX,tipY-0.3),
                (bx+1,by+bh*0.5)],fill,outline:true)
        c.poly([(bx+4,by+1.5),(bx+8,by+1),(bx+11,by+4),
                (bx+6,by+bh*0.65),(bx+2,by+bh*0.7)],light)
        for n in 0..<5 {
            let x=bx+3+Double(n)*1.5
            c.line([(x+4,by+4),(max(tipX+1,x-1),tipY-1)],n%2 == 0 ? light:(night ? "slate":"dark"))
        }
        if dove {
            for n in 0..<9 {
                let x=bx+3+Double(n%3)*2.2,y=by+2+Double(n/3)*1.9
                c.line([(x,y),(x+0.9,y-0.4),(x+1.7,y+0.6)],"buff",width:0.65)
            }
        } else if id == .treeSparrow {
            c.line([(bx+3,by+4),(bx+9,by+5)],"cream",width:1)
            c.line([(bx+2,by+6),(bx+7,by+7)],"buff",width:0.8)
        } else if swallow {c.line([(bx+4,by+2),(bx+9,by+3)],"blue",width:0.65)}
    }

    private static func foundationWing(_ c:BirdPainter,_ id:SpeciesID,_ p:FoundationPose,
                                       bx:Double,by:Double,bh:Double,far:Bool) {
        let night=id == .nightHeron,swallow=id == .barnSwallow
        let s=colours(id),lift=p.wing,shoulderX=bx+10,shoulderY=by+3
        let span=swallow ? 21.0:(night ? 19:(id == .treeSparrow ? 14:18))
        let tipX=shoulderX-span*(far ? 0.42:0.72)*lift
        let tipY=shoulderY-span*(far ? 0.76:1)*lift
        let chord=(swallow ? 3.0:(night ? 7:5))*lift
        let fill=far ? (night ? "slate":s.1):(night ? "gray":s.1)
        let light=night ? "silver":s.0
        if swallow {
            c.poly([(shoulderX,shoulderY),(shoulderX-4*lift,shoulderY-9*lift),
                    (tipX,tipY),(tipX+chord,tipY+9*lift),
                    (shoulderX+2,shoulderY+3)],fill,outline:true)
        } else {
            c.poly([(shoulderX,shoulderY),(shoulderX-3*lift,shoulderY-8*lift),
                    (tipX+2*lift,tipY),(tipX,tipY+1.5*lift),
                    (tipX+chord*0.2,tipY+4*lift),(tipX+chord*0.5,tipY+3*lift),
                    (tipX+chord*0.7,tipY+7*lift),(tipX+chord,tipY+6*lift),
                    (shoulderX+2,shoulderY+4)],fill,outline:true)
        }
        c.poly([(shoulderX,shoulderY),(shoulderX-3*lift,shoulderY-7*lift),
                (tipX+chord*0.7,tipY+8*lift),(shoulderX+1,shoulderY+2)],light)
        for n in 0..<4 {
            let f=Double(n)/4
            c.line([(shoulderX-1,shoulderY-2*lift),
                    (tipX+chord*f,tipY+(2+f*6)*lift)],night ? "slate":s.1)
        }
        if id == .treeSparrow {c.line([(shoulderX-2,shoulderY-3*lift),(tipX+chord*0.7,tipY+7*lift)],"cream",width:0.8)}
    }

    private static func foundationHead(_ c:BirdPainter,_ id:SpeciesID,tucked:Bool,drowsy:Bool) {
        let night=id == .nightHeron,a=shape(id),s=colours(id)
        let w=night ? 7.5:a.headWidth,h=night ? 5.5:a.headHeight,x = -w/2,y = -h/2
        c.oval(x,y,w,h,night ? "white":s.2,outline:true)
        switch id {
        case .treeSparrow:
            c.poly([(x,y+4),(x+4,y+3),(x+w,y+4),(x+w-1,y+7),(x+2,y+7)],"cream")
            c.oval(x+2,y+4,2,2,"black")
            c.poly([(x+5,y+6),(x+w,y+5),(x+w,y+8),(x+5,y+8)],"black")
        case .spottedDove:
            c.poly([(x,y+4),(x+3,y+4.8),(x+3.5,y+7),(x,y+6.5)],"black")
            for point in [(x+0.6,y+4.8),(x+2,y+5.5),(x+0.9,y+6)] {
                c.oval(point.0,point.1,0.65,0.65,"white")
            }
        case .barnSwallow:
            c.poly([(x+3,y+3.6),(x+w,y+3.8),(x+w-1,y+6),(x+3,y+5.7)],"rust")
            c.line([(x+3,y+0.5),(x+6,y+1)],"rust",width:0.65)
            c.line([(x+2,y+6),(x+5.5,y+6.7)],"navy",width:1)
        case .nightHeron:
            c.poly([(x,y+2),(x+1,y),(x+5,y-0.3),(x+w,y+1.3),
                    (x+w,y+2.3),(x+2,y+2.2)],"navy")
            c.curve([(x+0.5,y+1),(x-2,y+1),(x-2,y+4),(x-6,y+5)],"white",width:0.55)
            c.curve([(x,y+1),(x-3,y+1),(x-3,y+3),(x-7,y+3.5)],"silver",width:0.5)
        default:break
        }
        let ex=night ? x+w-2.2:x+w*0.72,ey=night ? y+1.6:y+h*0.38
        if night {c.oval(ex-0.5,ey-0.4,1.8,1.8,"red")}
        if tucked || drowsy {
            c.line([(ex-0.3,ey+0.5),(ex+0.3,ey+0.75),(ex+1,ey+0.45)],"eye",width:0.7)
        } else {
            c.oval(ex,ey,night ? 0.8:1,night ? 0.9:1.1,"eye")
            c.oval(ex+0.35,ey,0.4,0.4,"white")
        }
    }
}

// M6c enters only for the eight new species and their authored names. Keeping
// this renderer separate leaves the accepted M6b raster operations untouched.
extension DetailedBirdArt {
    private struct M6cDrawing {
        let id:SpeciesID
        let frame:String
        let pose:M6cPoseGeometry.Pose
        let anatomy:M6cPoseGeometry.Anatomy
        var owl:Bool {id == .littleOwl}
        var tucked:Bool {frame == "restTuck"}
        var sleepy:Bool {frame == "restLower" || tucked}
        var style:(String,String,String,String) {DetailedBirdArt.colours(id)}
        var back:String {owl ? "brown":style.0}
        var breast:String {owl ? "buff":style.3}
        var feather:String {owl ? "brown":style.1}
        var wingLight:String {owl ? "tan":style.0}
        var bx:Double {(owl ? 17:34-anatomy.width)+pose.body.lean-pose.body.fluff/2}
        var by:Double {pose.body.y}
        var bw:Double {anatomy.width+pose.body.fluff}
        var bh:Double {pose.body.height}
    }

    private static func m6cPoseImage(_ frame:String,species id:SpeciesID,
                                    part:FoundationPosePart?)->CGImage? {
        guard let a=M6cPoseGeometry.anatomy(id),let pose=M6cPoseGeometry.pose(species:id,frame:frame) else {return nil}
        let density=SpeciesCatalog.standard.profile(id).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let d=M6cDrawing(id:id,frame:frame,pose:pose,anatomy:a)
        if part == nil || part == .feet {m6cFeet(c,d)}
        if part == nil || part == .body {
            m6cTail(c,d)
            if pose.wing>0 {m6cRaisedWing(c,d,far:true)}
            m6cBody(c,d)
            m6cFoldedWing(c,d)
        }
        if part == nil || part == .headNeck {
            m6cNeck(c,d)
            c.ctx.saveGState()
            c.ctx.translateBy(x:pose.head.x,y:pose.head.y);c.ctx.rotate(by:CGFloat(pose.head.pitch))
            if d.owl {m6cOwlFace(c,d)} else {m6cPasserineHead(c,d)}
            c.ctx.restoreGState()
        }
        if part == nil || part == .bill {
            c.ctx.saveGState()
            c.ctx.translateBy(x:pose.head.x,y:pose.head.y);c.ctx.rotate(by:CGFloat(pose.head.pitch))
            m6cBill(c,d)
            c.ctx.restoreGState()
        }
        if part == nil || part == .body {
            if d.tucked {m6cScapulars(c,d)}
            if pose.wing>0 {m6cRaisedWing(c,d,far:false)}
        }
        return c.image
    }

    private static func m6cFeet(_ c:BirdPainter,_ d:M6cDrawing) {
        let xs:[Double]=d.owl ? [26,32]:[27,31]
        for x in xs {
            // Only the upper attachment bends. The complete foot/toe band is
            // identical across all 10/13 poses and matches the old species.
            let top=min(34.5,d.by+d.bh-2),knee=d.frame == "takeoffCrouch" ? 1.5:0
            if d.owl {
                c.line([(x+d.pose.body.lean,top),(x+knee,35),(x,38.5)],"cream",width:2)
                c.line([(x-2,39),(x,38.5),(x+2,39)],"tan",width:0.8)
            } else {
                c.line([(x-1+d.pose.body.lean,top),(x+knee,35),(x-0.5,38.5)],"brown",width:1)
                c.line([(x-2,39),(x,38.5),(x+2,39)],"brown")
            }
        }
    }

    private static func m6cTail(_ c:BirdPainter,_ d:M6cDrawing) {
        let x=d.pose.tail.x,y=d.pose.tail.y,w=d.anatomy.tailWidth
        let rootX=d.bx+(d.owl ? 5:6),rootY=d.by+d.bh*0.48
        let fill=d.id == .azureWingedMagpie ? "cyan":d.feather
        c.poly([(rootX,rootY),(rootX+5,rootY+4),(x+w,y+1),(x,y)],fill,outline:true)
        c.line([(rootX+2,rootY+2),(x+1,y)],d.owl ? "buff":d.wingLight)
        if d.id == .magpieRobin {
            // White outer rectrices follow the full cocked tail, not a white
            // mark at an obsolete horizontal tail position.
            c.line([(rootX,rootY+0.5),(x,y)],"white",width:0.9)
            c.line([(rootX+4.5,rootY+3.5),(x+w,y+0.8)],"white",width:0.8)
        } else if d.id == .azureWingedMagpie {
            c.line([(x,y),(x+w,y+1)],"silver",width:1.0)
            c.line([(rootX+3,rootY+2),(x+w*0.55,y)],"blue",width:0.8)
        } else if d.owl {
            for n in 0..<3 {
                let t=0.45+Double(n)*0.18
                let xx=rootX+(x-rootX)*t,yy=rootY+(y-rootY)*t
                c.line([(xx,yy),(xx+w-0.8,yy+1)],"buff",width:0.7)
            }
        }
    }

    private static func m6cBody(_ c:BirdPainter,_ d:M6cDrawing) {
        let x=d.bx,y=d.by,w=d.bw,h=d.bh
        c.oval(x,y,w,h,d.back,outline:true)
        if d.owl {
            c.oval(x+w*0.28,y+2,w*0.57,h-2,d.breast)
            // Longitudinal marks stay on the compressed belly in the crouch.
            for row in 0..<4 {for col in 0..<3 {
                let xx=x+w*0.39+Double(col)*2.6+Double(row%2)*0.4
                let yy=y+3+Double(row)*(h-4)/4
                c.line([(xx,yy),(xx+0.3,yy+1.1)],"umber",width:0.7)
            }}
        } else {
            c.oval(x+w*0.48,y+2,w*0.52-0.8,h-2,d.breast)
            switch d.id {
            case .magpieRobin:
                c.poly([(x+w*0.56,y+1),(x+w-1,y+2),(x+w-1,y+5),(x+w*0.62,y+6)],"black")
            case .redWhiskeredBulbul:
                c.poly([(x+3,y+h-4),(x+7,y+h-3),(x+5,y+h-0.5),(x+2,y+h-1)],"red")
            case .swinhoesWhiteEye:
                c.poly([(x+w*0.63,y+2),(x+w-1,y+3),(x+w-2,y+6),(x+w*0.62,y+5)],"yellow")
            case .redBilledLeiothrix:
                c.poly([(x+w*0.60,y+1),(x+w-1,y+2),(x+w-2,y+5),(x+w*0.63,y+5)],"orange")
            default:break
            }
        }
        if d.pose.body.fluff>0.6 {
            for n in 0..<4 {
                let xx=x+w*0.24+Double(n)*w*0.12,yy=y+h-1
                c.poly([(xx-1,yy-1),(xx+1.3,yy),(xx+0.2,yy+0.6)],n>1 ? d.breast:d.back)
            }
        }
    }

    private static func m6cFoldedWing(_ c:BirdPainter,_ d:M6cDrawing) {
        let x=d.bx,y=d.by,h=d.bh
        if d.owl {
            // Separate lateral wings frame the barred belly and preserve the
            // broad, frontal owl silhouette even when its face turns aside.
            for right in [false,true] {
                let outer=right ? x+d.bw-1:x+1,inner=right ? outer-5:outer+5
                c.poly([(outer,y+1),(inner,y+3),(inner,y+h-4),
                        (outer,y+h-1),(outer+(right ? 1:-1),y+h*0.55)],d.feather,outline:true)
                for n in 0..<4 {
                    let yy=y+3+Double(n)*(h-4)/4
                    c.oval(right ? outer-3:outer+0.5,yy,1.5,0.9,"cream")
                }
            }
            return
        }
        let slender=d.id == .azureWingedMagpie || d.id == .magpieRobin
        let tipX=x+(slender ? -0.5:0),tipY=y+h-0.5
        c.poly([(x+3,y+1),(x+8,y+0.5),(x+13,y+4),(x+10,y+h*0.72),
                (tipX+2,tipY),(tipX,tipY-0.6),(x+1,y+h*0.5)],d.feather,outline:true)
        c.poly([(x+4,y+1.6),(x+8,y+1),(x+11,y+4),
                (x+6,y+h*0.64),(x+2,y+h*0.7)],d.wingLight)
        for n in 0..<5 {
            let xx=x+3+Double(n)*1.5
            c.line([(xx+4,y+4),(max(tipX+1,xx-1),tipY-1)],n%2 == 0 ? d.wingLight:"dark")
        }
        switch d.id {
        case .magpieRobin:
            c.poly([(x+4,y+2.5),(x+9,y+3.5),(x+10,y+5),
                    (x+5,y+7),(x+2,y+6)],"white")
        case .redBilledLeiothrix:
            c.line([(x+4,y+3.5),(x+10,y+4.5)],"red",width:1.2)
            c.line([(x+3,y+6),(x+8,y+7)],"yellow",width:0.9)
        case .azureWingedMagpie:
            c.line([(x+3,y+2),(x+8,y+3)],"gray",width:1)
            c.line([(x+2,y+5),(x+6,y+6)],"blue",width:0.8)
        case .chineseBlackbird:
            for n in 0..<3 {c.line([(x+4+Double(n)*2,y+3),(x+3+Double(n)*2,y+6)],"dark",width:0.6)}
        default:break
        }
    }

    private static func m6cNeck(_ c:BirdPainter,_ d:M6cDrawing) {
        let a=d.anatomy,p=d.pose
        if d.owl {
            // A feathered neck collar joins the broad face to both shoulders.
            let left=p.headPoint(-a.headWidth*0.30,a.headHeight*0.30)
            let right=p.headPoint(a.headWidth*0.32,a.headHeight*0.30)
            c.poly([(d.bx+4,d.by+4),(left.x,left.y),(right.x,right.y),
                    (d.bx+d.bw-3,d.by+6),(d.bx+d.bw*0.52,d.by+d.bh*0.65)],"buff")
        } else {
            let nape=p.headPoint(-a.headWidth*0.32,1)
            let chin=p.headPoint(a.headWidth*0.28,a.headHeight*0.38)
            c.poly([(d.bx+d.bw*0.50,d.by+2),(nape.x,nape.y),
                    (chin.x,chin.y),(d.bx+d.bw-1,d.by+d.bh*0.65)],d.breast)
            c.poly([(d.bx+d.bw*0.50,d.by+2),(nape.x,nape.y),
                    (nape.x+1,nape.y+2),(d.bx+d.bw*0.63,d.by+6)],d.back)
            if d.id == .chineseBlackbird {
                c.line([(d.bx+d.bw*0.70,d.by+3),(chin.x-1,chin.y)],"dark",width:0.6)
            }
        }
    }

    private static func m6cPasserineHead(_ c:BirdPainter,_ d:M6cDrawing) {
        let w=d.anatomy.headWidth,h=d.anatomy.headHeight,x = -w/2,y = -h/2
        c.oval(x,y,w,h,d.style.2,outline:true)
        switch d.id {
        case .lightVentedBulbul:
            c.poly([(x,y+1),(x+3,y+1),(x+4,y+4),(x+2,y+6),(x,y+4)],"white")
            c.poly([(x+3,y+5),(x+w,y+4),(x+w,y+7),(x+4,y+7.5)],"silver")
        case .redWhiskeredBulbul:
            c.poly([(x,y+2),(x+2,y-6),(x+4,y-3),(x+6,y+1)],"black",outline:true)
            c.poly([(x+1,y+4),(x+4,y+3),(x+w,y+4),(x+5,y+7),(x+2,y+6)],"white")
            c.oval(x+2,y+3,2,2,"red")
        case .magpieRobin:
            c.line([(x+1,y+1.5),(x+4,y+0.7)],"slate",width:0.6)
        case .swinhoesWhiteEye:
            c.poly([(x+3,y+5),(x+w,y+4),(x+w-1,y+7),(x+4,y+7)],"yellow")
        case .azureWingedMagpie:
            c.poly([(x+1,y+4),(x+w-1,y+4),(x+w-1,y+6),(x+2,y+7)],"cream")
        case .redBilledLeiothrix:
            c.poly([(x+2,y+4),(x+w,y+4),(x+w-1,y+7),(x+3,y+6)],"orange")
            c.line([(x+1,y+1.5),(x+w-1,y+1)],"yellow",width:0.8)
        default:break
        }
        let ex=x+w*0.72,ey=y+h*0.38
        if d.id == .swinhoesWhiteEye {c.oval(ex-1.1,ey-1.1,2.9,2.9,"white")}
        if d.id == .chineseBlackbird {c.oval(ex-0.8,ey-0.8,2.3,2.3,"yellow")}
        if d.sleepy {c.line([(ex-0.25,ey+0.5),(ex+0.3,ey+0.7),(ex+1,ey+0.45)],"eye",width:0.7)}
        else {c.oval(ex,ey,1,1.1,"eye");c.oval(ex+0.4,ey,0.45,0.45,"white")}
    }

    private static func m6cOwlFace(_ c:BirdPainter,_ d:M6cDrawing) {
        let w=d.anatomy.headWidth,h=d.anatomy.headHeight,x = -w/2,y = -h/2,turn=d.pose.turn
        let mid=w*0.17*turn,eyeY=y+h*0.48
        let leftW=w*(0.38-max(0,turn)*0.12),rightW=w*(0.38+min(0,turn)*0.12)
        c.oval(x,y,w,h,"brown",outline:true)
        c.oval(mid-leftW-0.5,y+h*0.25,leftW,h*0.66,"buff")
        c.oval(mid+0.5,y+h*0.25,rightW,h*0.66,"buff")
        for n in 0..<5 {c.oval(x+2+Double(n)*2.8,y+1.5,1.3,0.8,"cream")}
        let eyeSize=w*0.19
        for ex in [mid-leftW*0.55,mid+rightW*0.55] {
            if d.sleepy {
                c.line([(ex-eyeSize/2,eyeY+1),(ex,eyeY+1.35),(ex+eyeSize/2,eyeY+1)],"eye",width:0.9)
            } else {
                c.oval(ex-eyeSize/2,eyeY-eyeSize/2,eyeSize,eyeSize,"yellow",outline:true)
                c.oval(ex-eyeSize*0.23,eyeY-eyeSize*0.3,eyeSize*0.46,eyeSize*0.65,"eye")
                c.oval(ex,eyeY-eyeSize*0.23,0.55,0.55,"white")
            }
        }
        c.line([(mid-leftW+0.5,eyeY-2),(mid-1,eyeY-1)],"cream",width:1.3)
        c.line([(mid+1,eyeY-1),(mid+rightW-0.5,eyeY-2)],"cream",width:1.3)
        c.line([(x+3,y+h-2),(mid,y+h-0.7),(x+w-3,y+h-2)],"white",width:1)
    }

    private static func m6cBill(_ c:BirdPainter,_ d:M6cDrawing) {
        if d.owl {
            let mid=d.anatomy.headWidth*0.17*d.pose.turn,eyeY=d.anatomy.headHeight*(-0.02)
            c.poly([(mid-1,eyeY+1),(mid+1,eyeY+1),(mid+0.3,eyeY+4)],"yellow",outline:true)
        } else {
            let root=d.anatomy.headWidth/2-0.5,length=d.id == .swinhoesWhiteEye ? 2.2:4
            let fill=d.id == .chineseBlackbird ? "yellow":(d.id == .redBilledLeiothrix ? "red":"dark")
            c.poly([(root,-0.7),(root+length,0.5),(root+length-1,1.2),(root,1.3)],fill)
        }
    }

    private static func m6cScapulars(_ c:BirdPainter,_ d:M6cDrawing) {
        let tip=d.pose.billTip(species:d.id,anatomy:d.anatomy)
        let x=min(d.pose.head.x-5,Double(tip.x)-1),y=d.pose.head.y+1
        // The raised shoulder feathers cover the reversed bill, including the
        // owl's short hook. The authored bill layer remains available to QA.
        c.poly([(x,y),(d.pose.head.x-1,y),(d.pose.head.x+3,y+2),
                (d.pose.head.x+2,y+6),(x,y+6),(x-1,y+3)],d.feather,outline:true)
        for n in 0..<3 {
            let xx=x+1+Double(n)*2
            c.line([(xx,y+1),(xx-0.8,y+4)],d.wingLight)
        }
        if d.id == .magpieRobin {c.line([(x+1,y+3),(x+5,y+4)],"white",width:0.8)}
        if d.id == .redBilledLeiothrix {c.line([(x+1,y+3),(x+5,y+4)],"red",width:0.8)}
    }

    private static func m6cRaisedWing(_ c:BirdPainter,_ d:M6cDrawing,far:Bool) {
        let lift=d.pose.wing,span=d.anatomy.wingSpan
        let shoulderX=d.owl ? d.bx+(far ? 3:d.bw-3):d.bx+10
        // The owl's broad trailing edge adds chord on top of lateral reach.
        // In Push, (u:0.73,v:0.84) must fit too, not only the primary tip:
        // 37.5 + 0.18*19*0.73 + 0.84*8 = 46.7166, plus <=0.5 outline.
        let shoulderY=d.by+3,direction=d.owl && !far ? 0.18:(far ? -0.42:-0.72)
        let chord=(d.owl ? 8.0:(d.id == .chineseBlackbird ? 6.5:5.5))*lift
        func p(_ u:Double,_ v:Double)->(Double,Double) {
            (shoulderX+direction*span*lift*u+v*chord,
             shoulderY-span*lift*(far ? 0.83:1)*u+v*2*lift)
        }
        let edge:[(Double,Double)]
        if d.owl {
            edge=[(0,0),(0.35,-0.12),(0.72,-0.10),(1,0),(1,0.16),
                  (0.88,0.17),(0.96,0.36),(0.80,0.35),(0.88,0.58),
                  (0.69,0.56),(0.73,0.84),(0.52,0.78),(0.36,0.94),(0,0.45)]
        } else {
            edge=[(0,0),(0.30,-0.12),(0.66,-0.10),(0.95,0),(1,0.18),
                  (0.91,0.45),(0.72,0.70),(0.47,0.88),(0.20,0.85),(0,0.4)]
        }
        let base:String,light:String
        if far {
            func shade(_ key:String,_ output:String)->String {
                let value=c.palette[key]!
                let r=UInt32(Double((value>>24)&255)*0.78),g=UInt32(Double((value>>16)&255)*0.78),b=UInt32(Double((value>>8)&255)*0.78)
                c.palette[output]=(r<<24)|(g<<16)|(b<<8)|255
                return output
            }
            base=shade(d.feather,"m6cFarWing");light=shade(d.wingLight,"m6cFarCoverts")
        } else {base=d.feather;light=d.wingLight}
        c.poly(edge.map{p($0.0,$0.1)},base,outline:true)
        c.poly([(0,0),(0.30,-0.07),(0.61,0.02),(0.60,0.32),(0.30,0.48),(0,0.32)].map{p($0.0,$0.1)},light)
        for n in 0..<5 {
            let u=0.30+Double(n)*0.12
            c.line([p(u,0.18),p(u+0.02,0.67)],d.owl ? "umber":"dark")
        }
        switch d.id {
        case .magpieRobin:c.line([p(0.22,0.42),p(0.52,0.34),p(0.68,0.22)],"white",width:1.3)
        case .redBilledLeiothrix:
            c.line([p(0.23,0.40),p(0.57,0.32)],"red",width:1.2)
            c.line([p(0.35,0.64),p(0.66,0.48)],"yellow",width:0.8)
        case .littleOwl:
            for n in 0..<4 {let u=0.25+Double(n)*0.13;c.line([p(u,0.20),p(u+0.04,0.30)],"cream",width:0.8)}
        default:break
        }
    }
}

// M6d uses newly authored wet plumage, wing strokes and head/neck geometry.
// The raw source and all four semantic layers remain unmasked. Only a settled
// bath visit may apply BathArt's contextual water/feet/front-wall occlusion.
extension DetailedBirdArt {
    private struct BathPose {
        let body:CGRect
        let head:CGPoint
        let pitch:Double
        let tail:CGPoint
        let stroke:Int // 0 folded, 1 downward fan, 2 raised, 3 second downstroke
        func headPoint(_ x:Double,_ y:Double)->CGPoint {
            CGPoint(x:Double(head.x)+x*cos(pitch)-y*sin(pitch),
                    y:Double(head.y)+x*sin(pitch)+y*cos(pitch))
        }
    }

    private static func bathPose(_ frame:String,_ id:SpeciesID)->BathPose? {
        guard id == .treeSparrow || id == .lightVentedBulbul,
              let index=BathGeometry.frameNames.firstIndex(of:frame) else {return nil}
        // body x/y/w/h, head center x/y/pitch, tail tip x/y, wing stroke.
        // These values also generate BathPoseAnchors; no old raster is reused.
        let poses:[[Double]]
        if id == .treeSparrow {
            poses=[
                [16.5,26,18.5,12,32,23,0.35,11,31,0],
                [17,27.5,19,10.5,0,0,0.88,11,32,0],
                [16,30,20,12,32,28,0.24,10.5,31,0],
                [15.5,31,21,12,31,29,0.18,10,30,1],
                [16,30,20,12,32,27,-0.12,10.5,29,2],
                [16.5,31.5,20.5,12,33,30,0.32,9.5,33,3],
                [16,25.5,19,12.5,32.5,21.5,-0.14,12,33.5,0]
            ]
        } else {
            poses=[
                [14,25.5,20,12.5,32,21.5,0.25,6,28,0],
                [14.5,27,20.5,11,0,0,0.98,6.5,29.5,0],
                [13.5,29,22,13,32,27,0.22,5.5,29,0],
                [13,30.5,23,13,31.5,27.5,0.12,5,27.5,1],
                [13.5,29.5,22,13,32,25.5,-0.18,6,26,2],
                [14,31,22.5,13,33,29,0.28,4.5,30,3],
                [14,25,20.5,13,32.5,20,-0.18,5,31,0]
            ]
        }
        let p=poses[index],pitch=p[6]
        let head:CGPoint
        if frame == "bathTouch" {
            let tip=shape(id).headWidth/2-0.5+4
            // Solve the rotated head from the frozen bill tip. The torso and
            // toes stay planted; only the newly drawn head and neck reach water.
            head=CGPoint(x:Double(BathGeometry.rightBeak.x)-tip*cos(pitch)+0.5*sin(pitch),
                         y:Double(BathGeometry.rightBeak.y)-tip*sin(pitch)-0.5*cos(pitch))
        } else {head=CGPoint(x:p[4],y:p[5])}
        return BathPose(body:CGRect(x:p[0],y:p[1],width:p[2],height:p[3]),head:head,
                        pitch:pitch,tail:CGPoint(x:p[7],y:p[8]),stroke:Int(p[9]))
    }

    static func bathBillAnchor(_ frame:String,species id:SpeciesID)->CGPoint? {
        guard let p=bathPose(frame,id) else {return nil}
        if frame == "bathTouch" {return BathGeometry.rightBeak}
        return p.headPoint(shape(id).headWidth/2-0.5+4,0.5)
    }

    /// Exact intersections of the newly authored belly/wing contours with y39.
    /// Inspect/Rise have no feather-water contact; the feet are masked separately.
    /// Mirror each x as 48-x before using a left-facing contact.
    static func bathWaterContacts(_ frame:String,species id:SpeciesID)->[CGPoint] {
        guard let p=bathPose(frame,id) else {return []}
        if frame == "bathTouch" {return [BathGeometry.rightBeak]}
        let y=BathGeometry.birdWaterlineY,b=p.body
        guard b.maxY>y else {return []}
        let dy=(y-b.midY)/(b.height/2)
        let dx=b.width/2*sqrt(max(0,1-dy*dy))
        var contacts=[CGPoint(x:b.midX-dx,y:y),CGPoint(x:b.midX+dx,y:y)]
        if p.stroke == 1 || p.stroke == 3 {
            for far in [false,true] {
                let edge=bathWingEdge(p,id,far:far)
                for i in edge.indices {
                    let a=edge[i],b=edge[(i+1)%edge.count],water=Double(y)
                    if abs(a.1-water)<0.000001 {
                        contacts.append(CGPoint(x:a.0,y:water))
                    } else if (a.1<water && b.1>water) || (a.1>water && b.1<water) {
                        let t=(water-a.1)/(b.1-a.1)
                        contacts.append(CGPoint(x:a.0+(b.0-a.0)*t,y:water))
                    }
                }
            }
        }
        return contacts
    }

    static func bathImage(_ frame:String,species id:SpeciesID,
                          part:FoundationPosePart?=nil)->CGImage? {
        guard let p=bathPose(frame,id) else {return nil}
        let density=SpeciesCatalog.standard.profile(id).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let s=colours(id),b=p.body
        let x=Double(b.minX),y=Double(b.minY),w=Double(b.width),h=Double(b.height)
        let bulbul=id == .lightVentedBulbul
        if part == nil || part == .feet {
            for xx in [27.0,31.0] {
                c.line([(xx-1,min(34,y+h-2)),(xx,35),(xx-0.5,38.5)],"brown",width:1)
                c.line([(xx-2,39),(xx,38.5),(xx+2,39)],"brown")
            }
        }
        if part == nil || part == .body {
            let tx=Double(p.tail.x),ty=Double(p.tail.y),tw=bulbul ? 4.5:3.5
            c.poly([(x+6,y+h*0.45),(x+10,y+h*0.69),(tx+tw,ty+1),(tx,ty)],s.1,outline:true)
            c.line([(x+7,y+h*0.5),(tx+0.8,ty)],s.0,width:0.8)
            if bulbul {c.line([(tx,ty),(tx+tw,ty+1)],"silver",width:0.8)}
            if p.stroke>0 {bathWing(c,p,id,far:true)}
            c.oval(x,y,w,h,s.0,outline:true)
            c.oval(x+w*0.48,y+1.5,w*0.52-0.8,h-1.8,s.3)
            // Wet belly feathers remain visible below y39 in the raw source.
            // Their radial edges follow this compressed torso, not a stand pose.
            for n in 0..<4 {
                let xx=x+w*0.40+Double(n)*2.3,yy=y+h-2.2
                c.line([(xx,yy-1.2),(xx-0.3,yy)],n<2 ? s.0:"buff",width:0.6)
            }
            if p.stroke == 0 {bathFoldedWing(c,p,id)}
        }
        if part == nil || part == .headNeck {
            let a=shape(id),nape=p.headPoint(-a.headWidth*0.32,1)
            let chin=p.headPoint(a.headWidth*0.28,a.headHeight*0.38)
            // Every neck endpoint is above the water/foot plane, including
            // Touch; the forward bill alone reaches the exact y39 contact.
            c.poly([(x+w*0.50,y+2),(nape.x,nape.y),(chin.x,chin.y),
                    (x+w-1,min(37.5,y+h*0.58))],s.3)
            c.poly([(x+w*0.50,y+2),(nape.x,nape.y),(nape.x+1,nape.y+1),
                    (x+w*0.63,min(37.5,y+5))],s.0)
            c.ctx.saveGState();c.ctx.translateBy(x:p.head.x,y:p.head.y);c.ctx.rotate(by:CGFloat(p.pitch))
            if bulbul {bathBulbulHead(c)}
            else {foundationHead(c,id,tucked:false,drowsy:false)}
            c.ctx.restoreGState()
        }
        if part == nil || part == .bill {
            let root=shape(id).headWidth/2-0.5
            c.ctx.saveGState();c.ctx.translateBy(x:p.head.x,y:p.head.y);c.ctx.rotate(by:CGFloat(p.pitch))
            // Both edges rise toward the tip. No bill vertex falls below y39
            // in Touch, so the immersion mask cannot erase the contact point.
            c.poly([(root,-0.7),(root+4,0.5),(root+3,1.2),(root,1.3)],"dark")
            c.ctx.restoreGState()
        }
        if (part == nil || part == .body) && p.stroke>0 {bathWing(c,p,id,far:false)}
        return c.image
    }

    private static func bathBulbulHead(_ c:BirdPainter) {
        c.oval(-4,-3.5,8,7,"black",outline:true)
        c.poly([(-4,-2.5),(-1,-2.5),(0,0.5),(-2,2.5),(-4,0.5)],"white")
        c.poly([(-1,1.5),(4,0.5),(4,3.5),(0,4)],"silver")
        c.oval(1.76,-0.84,1,1.1,"eye");c.oval(2.16,-0.84,0.45,0.45,"white")
    }

    private static func bathFoldedWing(_ c:BirdPainter,_ p:BathPose,_ id:SpeciesID) {
        let x=Double(p.body.minX),y=Double(p.body.minY),h=Double(p.body.height),s=colours(id)
        c.poly([(x+3,y+1),(x+8,y+0.5),(x+12,y+3),(x+9,y+h*0.69),
                (x+1,y+h-1),(x,y+h-2),(x+1,y+5)],s.1,outline:true)
        c.poly([(x+4,y+1.5),(x+8,y+1),(x+10,y+3),(x+5,y+h*0.61),(x+2,y+h*0.66)],s.0)
        for n in 0..<5 {
            let xx=x+2+Double(n)*1.5
            c.line([(xx+4,y+3.5),(xx,y+h-2)],n%2 == 0 ? s.0:"dark")
        }
        if id == .treeSparrow {
            c.line([(x+3,y+3.5),(x+9,y+4.2)],"cream",width:1)
            c.line([(x+2,y+5.5),(x+7,y+6.2)],"buff",width:0.8)
        } else {c.line([(x+3,y+3),(x+8,y+4)],"olive",width:0.9)}
    }

    private static func bathWingEdge(_ p:BathPose,_ id:SpeciesID,far:Bool)->[(Double,Double)] {
        let bulbul=id == .lightVentedBulbul
        switch p.stroke {
        case 1:
            if far {return bulbul ? [(29,33),(36,32),(41,39),(44,41),(42,43),(38,42),(32,37)] :
                [(30,33),(35,33),(39,39),(41,41),(38,42),(34,40),(30,37)]}
            return bulbul ? [(23,33),(16,34),(12,39),(8,41),(11,44),(16,43),(26,38)] :
                [(24,33),(17,35),(14,39),(12,41),(18,43),(22,42),(27,39)]
        case 2:
            if far {return bulbul ? [(29,32),(35,25),(41,18),(44,18),(43,24),(40,29),(33,36)] :
                [(29,32),(34,26),(39,20),(42,22),(40,27),(36,31),(31,36)]}
            return bulbul ? [(23,32),(16,26),(9,16),(6,15),(7,23),(12,29),(19,36),(26,37)] :
                [(24,32),(17,27),(12,19),(9,17),(10,23),(13,28),(19,36),(26,37)]
        default:
            if far {return bulbul ? [(30,34),(37,35),(40,39),(44,42),(41,44),(37,42),(31,38)] :
                [(31,34),(35,35),(38,39),(41,42),(38,43),(34,41),(30,38)]}
            return bulbul ? [(25,34),(19,36),(15,39),(11,43),(15,45),(21,44),(28,39)] :
                [(25,34),(20,36),(17,39),(14,43),(19,44),(24,43),(28,39)]
        }
    }

    private static func bathWing(_ c:BirdPainter,_ p:BathPose,_ id:SpeciesID,far:Bool) {
        let edge=bathWingEdge(p,id,far:far),s=colours(id)
        let base:String,light:String
        if far {
            for (key,name) in [(s.1,"bathFarFeather"),(s.0,"bathFarCovert")] {
                let v=c.palette[key]!,r=UInt32(Double((v>>24)&255)*0.78)
                let g=UInt32(Double((v>>16)&255)*0.78),b=UInt32(Double((v>>8)&255)*0.78)
                c.palette[name]=(r<<24)|(g<<16)|(b<<8)|255
            }
            base="bathFarFeather";light="bathFarCovert"
        } else {base=s.1;light=s.0}
        c.poly(edge,base,outline:true)
        let root=edge[0],wrist=edge[2]
        c.poly([root,edge[1],wrist,((root.0+wrist.0)/2+1,(root.1+wrist.1)/2+2)],light)
        for i in 3..<(edge.count-1) {
            let tip=edge[i]
            c.line([((root.0+wrist.0)*0.5,(root.1+wrist.1)*0.5),
                    (tip.0*0.88+root.0*0.12,tip.1*0.88+root.1*0.12)],i%2 == 0 ? light:"dark",width:0.65)
        }
        if id == .treeSparrow {
            c.line([(root.0-0.5,root.1+0.7),((root.0+wrist.0)*0.5,(root.1+wrist.1)*0.5)],"cream",width:0.9)
        }
    }
}

// M6e: authored pickup/release anatomy. The token is always a separate image;
// only its grip follows the bill. No carrier-relative scale enters prop art.
extension DetailedBirdArt {
    static func carryBillAnchor(_ frame:String,species id:SpeciesID)->CGPoint? {
        CarryArtGeometry.pose(species:id,frame:frame)?.billTip
    }

    /// Exact tip of the existing transport drawing, including the compressed
    /// flight torso, outer pitch and bob. This batch only enables the sparrow;
    /// later carriers supply their own anatomy to the same transport geometry.
    static func transportBillAnchor(_ frame:String,species id:SpeciesID)->CGPoint? {
        guard id == .treeSparrow else {return nil}
        let a=shape(id)
        return TransportArtGeometry.billAnchor(frame:frame,species:id,
            headWidth:a.headWidth,headHeight:a.headHeight,headY:a.headY)
    }

    static func carryImage(_ frame:String,species id:SpeciesID,
                           part:FoundationPosePart?=nil)->CGImage? {
        guard let p=CarryArtGeometry.pose(species:id,frame:frame) else {return nil}
        let density=SpeciesCatalog.standard.profile(id).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let b=p.body,x=Double(b.minX),y=Double(b.minY),w=Double(b.width),h=Double(b.height)
        let lower=frame == "carryLower",grip=frame == "carryGrip",release=p.release
        if part == nil || part == .feet {
            // No head/body transform touches these lower legs or toe vertices.
            for xx in [27.0,31.0] {
                c.line([(xx-1,33),(xx,35),(xx-0.5,38.5)],"brown",width:1)
                c.line([(xx-2,39),(xx,38.5),(xx+2,39)],"brown")
            }
        }
        if part == nil || part == .body {
            let tx=Double(p.tail.x),ty=Double(p.tail.y)
            c.poly([(x+5,y+h*0.42),(x+10,y+h*0.64),(tx+4,ty+1),(tx,ty)],"brown",outline:true)
            c.line([(x+6,y+h*0.48),(tx+1,ty)],"tan",width:0.8)
            c.line([(x+7,y+h*0.57),(tx+2.8,ty+0.7)],"umber",width:0.7)
            c.oval(x,y,w,h,"tan",outline:true)
            c.oval(x+w*0.49,y+1.8,w*0.51-0.6,h-2,"cream")
            // Each new pose rolls its shoulder independently of its head. The
            // short rounded sparrow primaries retain two pale covert bars.
            let roll=grip ? 1.2:(release ? 0.7:(lower ? 0.45:0))
            c.poly([(x+3+roll,y+1),(x+8+roll,y+0.5),(x+12,y+3),
                    (x+9,y+h*0.70),(x+1,y+h-1),(x,y+h-2),(x+1,y+5)],"brown",outline:true)
            c.poly([(x+4+roll,y+1.5),(x+8,y+1),(x+10,y+3),
                    (x+5,y+h*0.62),(x+2,y+h*0.67)],"tan")
            for n in 0..<5 {
                let xx=x+2+Double(n)*1.5
                c.line([(xx+4+roll*0.3,y+3.5),(xx,y+h-2)],n%2 == 0 ? "tan":"umber")
            }
            c.line([(x+3+roll,y+3.5),(x+9,y+4.2)],"cream",width:1)
            c.line([(x+2,y+5.5),(x+7,y+6.2)],"buff",width:0.8)
        }
        if part == nil || part == .headNeck {
            let nape=p.headPoint(-CarryArtGeometry.sparrowHeadWidth*0.32,1)
            let chin=p.headPoint(CarryArtGeometry.sparrowHeadWidth*0.28,
                                 CarryArtGeometry.sparrowHeadHeight*0.38)
            // The neck is rebuilt between shoulder and pitched head; every
            // endpoint stays above the fixed y39 foot/contact plane.
            c.poly([(x+w*0.5,y+2),(nape.x,nape.y),(chin.x,chin.y),
                    (x+w-1,y+h*0.72)],"cream")
            c.poly([(x+w*0.5,y+2),(nape.x,nape.y),(nape.x+1,nape.y+1),
                    (x+w*0.65,y+5)],"tan")
            c.ctx.saveGState();c.ctx.translateBy(x:p.head.x,y:p.head.y);c.ctx.rotate(by:CGFloat(p.pitch))
            carrySparrowHead(c,release:release)
            c.ctx.restoreGState()
        }
        if part == nil || part == .bill {
            let root=CarryArtGeometry.sparrowHeadWidth/2-0.5,length=TransportArtGeometry.ordinaryBillLength(species:id)
            c.ctx.saveGState();c.ctx.translateBy(x:p.head.x,y:p.head.y);c.ctx.rotate(by:CGFloat(p.pitch))
            // The upper tip is the attachment anchor, including during release.
            // Place opens only the lower mandible, keeping its tip above y39.
            if release {
                c.poly([(root,-0.7),(root+length,0.5),(root+2.7,1.0),(root,0.9)],"dark")
                c.poly([(root,1.5),(root+2.5,1.65),(root+2.1,2.05),(root,1.9)],"dark")
                c.poly([(root+0.2,1.1),(root+1.8,1.35),(root+0.2,1.55)],"cream")
            } else {
                c.poly([(root,-0.7),(root+length,0.5),(root+length-1,1.2),(root,1.3)],"dark")
                if grip {c.line([(root+0.3,0.7),(root+2.7,0.7)],"umber",width:0.4)}
            }
            c.ctx.restoreGState()
        }
        return c.image
    }

    private static func carrySparrowHead(_ c:BirdPainter,release:Bool) {
        let w=CarryArtGeometry.sparrowHeadWidth,h=CarryArtGeometry.sparrowHeadHeight
        let x = -w/2,y = -h/2
        c.oval(x,y,w,h,"rust",outline:true)
        // Cheek/bib field marks are clipped to the new tilted crown; a steep
        // pickup must not leave rectangular plumage below the head contour.
        c.ctx.saveGState();c.ctx.addEllipse(in:CGRect(x:x,y:y,width:w,height:h));c.ctx.clip()
        c.poly([(x,y+4),(x+4,y+3),(x+w,y+4),(x+w-1,y+7),(x+2,y+7)],"cream")
        c.oval(x+2,y+4,2,2,"black")
        c.poly([(x+5,y+6),(x+w,y+5),(x+w,y+8),(x+5,y+8)],"black")
        c.line([(x+1,y+1.5),(x+4,y+0.8)],"orange",width:0.6)
        let ex=x+w*0.72,ey=y+h*0.38
        c.oval(ex,ey,1,1.1,"eye");c.oval(ex+0.35,ey,0.4,0.4,"white")
        if release {c.line([(x+4,y+6.8),(x+6,y+6.8)],"buff",width:0.55)}
        c.ctx.restoreGState()
    }
}


// M6f.1: three independent airborne capture drawings. Wings, body carriage,
// forked tail, head pitch and gape are authored anew; no old image is overpainted.
extension DetailedBirdArt {
    static func catchBillAnchor(_ frame:String,species id:SpeciesID)->CGPoint? {
        CatchArtGeometry.billAnchor(species:id,frame:frame)
    }

    static func catchImage(_ frame:String,species id:SpeciesID,
                           part:FoundationPosePart?=nil)->CGImage? {
        guard let p=CatchArtGeometry.pose(species:id,frame:frame) else {return nil}
        let density=SpeciesCatalog.standard.profile(id).relativeScale
        let c=BirdPainter(size:max(48,Int((48*density).rounded())))
        let b=p.body,x=Double(b.minX),y=Double(b.minY),w=Double(b.width),h=Double(b.height)
        let open=frame == "catchOpen",recover=frame == "catchRecover"
        if part == nil || part == .feet {
            // Airborne claws are tucked rather than extended to a nonexistent
            // support. The image reference/engine foot remains exactly (29,39).
            for xx in [26.5,29.0] {
                c.line([(xx+0.6,26.7),(xx-0.8,28),(xx-1.6,27.8)],"brown",width:0.65)
                c.line([(xx-0.8,28),(xx-1.5,28.5)],"umber",width:0.5)
            }
        }
        if part == nil || part == .body {
            catchWing(c,p.farWing,far:true)
            let tx=Double(p.tail.x),ty=Double(p.tail.y)
            // Two long, pointed streamers and a deep open fork distinguish the
            // swallow from the short rounded tails of the carry/bath species.
            c.poly([(x+5,y+2),(tx,ty-2),(13.2,ty-0.2),(tx+0.7,ty+4.5),
                    (x+6,y+h-0.3),(x+9,y+4)],"navy",outline:true)
            c.line([(x+5,y+3),(tx+1,ty-1.3)],"blue",width:0.7)
            c.line([(x+5,y+h-1),(tx+1.8,ty+3.5)],"blue",width:0.7)
            c.poly([(12.6,ty-0.2),(9.5,ty-1.4),(11,ty-0.3),(9.8,ty+1.1)],"cream")
            c.oval(x,y,w,h,"navy",outline:true)
            c.oval(x+w*0.39,y+1.8,w*0.60,h-2.1,"cream")
            c.poly([(x+w*0.42,y+1.2),(x+w-0.5,y+1),(x+w-1,y+3.2),
                    (x+w*0.5,y+4.1)],"white")
            c.line([(x+3,y+0.8),(x+9,y+0.4),(x+13,y+1.1)],"blue",width:0.9)
            if recover {c.oval(x+w-4.8,y+1.8,2.8,2.2,"buff")}
            catchWing(c,p.nearWing,far:false)
        }
        if part == nil || part == .headNeck {
            let nape=p.headPoint(-CatchArtGeometry.swallowHeadWidth*0.34,0.5)
            let chin=p.headPoint(CatchArtGeometry.swallowHeadWidth*0.28,2.4)
            c.poly([(x+w*0.62,y+0.8),(nape.x,nape.y),(chin.x,chin.y),
                    (x+w-1,y+h*0.72)],"cream")
            c.poly([(x+w*0.62,y+0.8),(nape.x,nape.y),(nape.x+0.8,nape.y+1.2),
                    (x+w*0.70,y+3)],"navy")
            c.poly([(chin.x-0.8,chin.y-0.5),(chin.x+0.4,chin.y),
                    (x+w-0.6,y+3.4),(x+w-3,y+3.8)],"rust")
            c.line([(x+w-3.6,y+4.4),(x+w-0.7,y+4.0)],"navy",width:0.9)
            c.ctx.saveGState();c.ctx.translateBy(x:p.head.x,y:p.head.y);c.ctx.rotate(by:CGFloat(p.pitch))
            let hw=CatchArtGeometry.swallowHeadWidth,hh=CatchArtGeometry.swallowHeadHeight
            c.oval(-hw/2,-hh/2,hw,hh,"navy",outline:true)
            c.ctx.saveGState();c.ctx.addEllipse(in:CGRect(x:-hw/2,y:-hh/2,width:hw,height:hh));c.ctx.clip()
            c.line([(-2.5,-1.4),(0,-2.2),(2,-1.7)],"blue",width:0.8)
            c.poly([(1.1,-2),(3.4,-1.5),(3.7,0.2),(1.7,-0.1)],"rust")
            c.poly([(-0.2,0.7),(3.5,0.2),(3.8,3.2),(0.3,3.2)],"rust")
            c.line([(-0.1,2.7),(2.5,2.8)],"navy",width:0.65)
            c.oval(1.1,-1.05,1.05,1.05,"eye");c.oval(1.45,-1.05,0.4,0.4,"white")
            if recover {c.line([(0.8,1.5),(2.1,1.3)],"orange",width:0.5)}
            c.ctx.restoreGState();c.ctx.restoreGState()
        }
        if part == nil || part == .bill {
            c.ctx.saveGState();c.ctx.translateBy(x:p.head.x,y:p.head.y);c.ctx.rotate(by:CGFloat(p.pitch))
            // Both mandibles are filled paths. The upper tip is exactly the
            // source anchor, with no centered outline extending beyond it.
            if open {
                c.poly([(p.billRoot-0.2,0.6),(p.billRoot+p.billLength-0.1,1.2),
                        (p.billRoot+p.billLength-0.4,3.4),(p.billRoot-0.3,1.8)],"rust")
            }
            c.poly(p.upperBill.map{(Double($0.x),Double($0.y))},"dark")
            c.poly(p.lowerBill.map{(Double($0.x),Double($0.y))},"dark")
            if open {c.line([(p.billRoot+0.1,1.1),(p.billRoot+1,1.8)],"orange",width:0.45)}
            c.ctx.restoreGState()
        }
        return c.image
    }

    private static func catchWing(_ c:BirdPainter,_ vertices:[CGPoint],far:Bool) {
        let points=vertices.map{(Double($0.x),Double($0.y))}
        c.poly(points,far ? "dark":"navy",outline:true)
        // Insets and feather shafts remain convex combinations of original
        // vertices, so the complete stroke has the same safe canvas margin.
        let root=CGPoint(x:far ? 29:25,y:24)
        let inset=vertices.map {v in (Double(root.x+(v.x-root.x)*0.82),Double(root.y+(v.y-root.y)*0.82))}
        c.poly(inset,far ? "navy":"blue")
        for tip in vertices.dropFirst().prefix(4) {
            let start=CGPoint(x:root.x+(tip.x-root.x)*0.30,y:root.y+(tip.y-root.y)*0.30)
            let end=CGPoint(x:root.x+(tip.x-root.x)*0.88,y:root.y+(tip.y-root.y)*0.88)
            c.line([(Double(start.x),Double(start.y)),(Double(end.x),Double(end.y))],far ? "slate":"navy",width:0.6)
        }
    }
}
