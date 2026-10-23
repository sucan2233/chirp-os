import Foundation
import CoreGraphics

struct DestinationPlan {
    let point: CGPoint
    let host: Surface?
    let fraction: CGFloat
    let edge: PerchEdge
    let duration: Double
    let arc: CGFloat
    let airspace: CGRect?
    let urgent: Bool

    func apply(to bird: Bird, random: EngineRandom) {
        bird.fraction=fraction;bird.edge=edge
        bird.fly(to:point,host:host,duration:duration,arc:arc,airspace:airspace,urgent:urgent,random:random.unit)
    }
}

// Geometry-only planning. No AppKit or state changes before a plan is accepted.
enum DestinationPlanner {
    static func plan(for bird: Bird, birds: [Bird], world: BehaviorWorld, entering: Bool = false, avoiding: CGPoint? = nil, reserved:[CGRect]=[], random: EngineRandom) -> DestinationPlan? {
        let screenRects=world.screens, displayRects=world.displays, surfaces=world.surfaces
        func spriteScale(for bird: Bird) -> CGFloat {world.scale * bird.profile.relativeScale}
        guard !bird.isDeparting else { return nil }
        let scale = spriteScale(for:bird)
        func airspace(_ point: CGPoint) -> CGRect? {
            guard let index=displayRects.firstIndex(where:{$0.contains(point)}),screenRects.indices.contains(index) else { return nil }
            let screen=screenRects[index],display=displayRects[index]
            let top=screen.minY+39*scale,bottom=min(screen.maxY,display.maxY-9*scale)
            return CGRect(x:screen.minX+29*scale,y:top,width:max(0,screen.width-58*scale),height:max(0,bottom-top))
        }
        func duration(to point: CGPoint) -> Double {
            if avoiding != nil {return max(0.9,Double(Geometry.distance(bird.position,point))/500 * Bird.flightSpeedMultiplier)}
            return entering ? max(2.8, Double(Geometry.distance(bird.position,point))/400 * Bird.flightSpeedMultiplier) : random.value(in:2.6...4.8)
        }
        var occupied = birds.filter { $0 !== bird && !$0.isDeparting }.compactMap { other -> CGRect? in
            guard let id = other.hostID, let host = surfaces.first(where: { $0.id == id }) else { return nil }
            let foot = Geometry.foot(on:host,fraction:other.fraction,edge:other.edge,scale:spriteScale(for:other))
            return Geometry.landingFootprint(at: foot, scale: spriteScale(for: other)).insetBy(dx: -8, dy: -8)
        }
        occupied.append(contentsOf:reserved)
        if let avoiding {
            // Reserve the area the user wants to uncover, so a click cannot
            // select the same perch or a point only a few pixels away.
            occupied.append(CGRect(x:avoiding.x-100*scale,y:avoiding.y-48*scale,width:200*scale,height:96*scale))
        }
        if bird.profile.id == .greatSpottedWoodpecker {
            var sides:[(Surface,PerchEdge,ClosedRange<CGFloat>)]=[]
            for host in surfaces where !host.isGround && !host.isFixedPerch && host.layer == 0 && host.rect.height >= 180 {
                for edge in [PerchEdge.left,.right] { for screen in screenRects {
                    for range in Geometry.sideRanges(on:host,edge:edge,surfaces:surfaces,screen:screen,scale:scale,occupied:occupied) { sides.append((host,edge,range)) }
                }}
            }
            let length=sides.reduce(CGFloat.zero){$0+$1.2.upperBound-$1.2.lowerBound}
            var ticket=CGFloat(random.unit()) * max(0,length)
            for (host,edge,range) in sides {
                let n=range.upperBound-range.lowerBound
                if ticket<n {
                    let fraction=(range.lowerBound+ticket-host.rect.minY-42)/(host.rect.height-84)
                    let point=Geometry.foot(on:host,fraction:fraction,edge:edge)
                    return DestinationPlan(point:point,host:host,fraction:fraction,edge:edge,duration:duration(to:point),arc:90,airspace:airspace(point),urgent:avoiding != nil)
                };ticket-=n
            }
        }
        var choices: [(Surface, ClosedRange<CGFloat>)] = []
        for host in surfaces where !host.isGround && !host.isFixedPerch && host.layer == 0 && host.rect.width >= 180 && host.rect.height >= 100 {
            for screen in screenRects {
                for range in Geometry.landingRanges(on: host, surfaces: surfaces, screen: screen, scale: scale, occupied: occupied) {
                    choices.append((host, range))
                }
            }
        }
        if choices.isEmpty {
            for host in surfaces where host.isGround {
                for screen in displayRects {
                    for range in Geometry.landingRanges(on:host,surfaces:surfaces,screen:screen,scale:scale,occupied:occupied) { choices.append((host,range)) }
                }
            }
        }
        let total = choices.reduce(CGFloat.zero) { $0 + $1.1.upperBound - $1.1.lowerBound }
        if total > 0 {
            var ticket = CGFloat(random.unit()) * total
            for (host, range) in choices {
                let length = range.upperBound - range.lowerBound
                if ticket < length {
                    let foot = CGPoint(x: range.lowerBound + ticket, y: Geometry.foot(on:host,fraction:0.5,edge:.top,scale:scale).y)
                    let start = Geometry.perchX(0, rect: host.rect), end = Geometry.perchX(1, rect: host.rect)
                    let fraction = (foot.x - start) / (end - start)
                    return DestinationPlan(point:foot,host:host,fraction:fraction,edge:.top,duration:duration(to:foot),arc:90,airspace:airspace(foot),urgent:avoiding != nil)
                }
                ticket -= length
            }
        }
        guard let screen = random.element(screenRects) else { return nil }
        var foot = CGPoint(x: random.value(in: (screen.minX+70)...max(screen.minX+71,screen.maxX-70)),
                           y: random.value(in: (screen.minY+110)...max(screen.minY+111,screen.maxY-80)))
        if let avoiding {
            let candidates=screenRects.compactMap {airspace(CGPoint(x:$0.midX,y:$0.midY))}.flatMap { area in
                [CGPoint(x:area.minX,y:area.minY),CGPoint(x:area.maxX,y:area.minY),
                 CGPoint(x:area.minX,y:area.maxY),CGPoint(x:area.maxX,y:area.maxY)]
            }
            guard let alternative=candidates.max(by:{Geometry.distance($0,avoiding)<Geometry.distance($1,avoiding)}) else {return nil}
            foot=alternative
        }
        return DestinationPlan(point:foot,host:nil,fraction:bird.fraction,edge:.top,duration:entering || avoiding != nil ? duration(to:foot) : 4.5,arc:40,airspace:airspace(foot),urgent:avoiding != nil)
    }
}
