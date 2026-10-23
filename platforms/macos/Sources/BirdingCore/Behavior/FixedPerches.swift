import Foundation
import CoreGraphics

/// Persistent display-relative coordinates. Resolution never rewrites an anchor,
/// so a temporarily disconnected display can reclaim its perch when it returns.
public struct FixedPerchAnchor: Codable, Equatable {
    public let slot: Int
    public let displayID: String
    public let displayFrame: CGRect
    public let x: Double
    public let y: Double

    public init(slot:Int,displayID:String,displayFrame:CGRect,x:Double,y:Double) {
        self.slot=slot;self.displayID=displayID;self.displayFrame=displayFrame
        self.x=x;self.y=y
    }

    private enum CodingKeys:String,CodingKey {case slot,displayID,displayFrame,x,y}

    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        slot=try values.decode(Int.self,forKey:.slot)
        displayID=try values.decode(String.self,forKey:.displayID)
        displayFrame=try values.decode(CGRect.self,forKey:.displayFrame)
        x=try values.decode(Double.self,forKey:.x)
        y=try values.decode(Double.self,forKey:.y)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,
                debugDescription:"Fixed perch requires slot 1...3, a display ID of at most 128 characters, a finite positive display frame within ±1,000,000, and normalized coordinates 0...1."))
        }
    }

    var isValid:Bool {
        (1...FixedPerchLayout.maximumCount).contains(slot) && displayID.count<=128 &&
        Self.isValidFrame(displayFrame) && x.isFinite && y.isFinite &&
        (0...1).contains(x) && (0...1).contains(y)
    }

    static func isValidFrame(_ frame:CGRect) -> Bool {
        let components=[frame.origin.x,frame.origin.y,frame.size.width,frame.size.height,frame.maxX,frame.maxY]
        return frame.size.width>0 && frame.size.height>0 &&
            components.allSatisfy{$0.isFinite && abs($0)<=1_000_000}
    }

    public static func capture(slot:Int,point:CGPoint,displayIDs:[String],displays:[CGRect]) -> Self? {
        guard point.x.isFinite,point.y.isFinite,
              let index=displays.indices.first(where:{Self.isValidFrame(displays[$0]) && displays[$0].contains(point)}) else {return nil}
        let frame=displays[index]
        let anchor=Self(slot:slot,displayID:displayIDs.indices.contains(index) ? displayIDs[index]:"",
                        displayFrame:frame,x:Double((point.x-frame.minX)/frame.width),
                        y:Double((point.y-frame.minY)/frame.height))
        return anchor.isValid ? anchor:nil
    }
}

public struct ResolvedFixedPerch {
    public let slot: Int
    public let surface: Surface
    public let foot: CGPoint
    public let rect: CGRect
}

public enum FixedPerchLayout {
    public static let maximumCount=3

    public static func resolve(anchors:[FixedPerchAnchor],world:BehaviorWorld) -> [ResolvedFixedPerch] {
        let scale=world.scale
        guard scale.isFinite,scale>0 else {return []}
        let horizontal=max(64*scale,48),headroom=max(80*scale,48),bottom=max(24*scale,24)
        let surfaceWidth=84+96*scale
        guard [horizontal,headroom,bottom,surfaceWidth].allSatisfy(\.isFinite) else {return []}
        let displays=world.displays.indices.filter{FixedPerchAnchor.isValidFrame(world.displays[$0])}
        guard !displays.isEmpty else {return []}
        var result:[ResolvedFixedPerch]=[],occupied:[CGRect]=[],seen=Set<Int>()
        // Slot order, rather than display enumeration or saved array order,
        // determines which perch survives when available space contracts.
        for anchor in anchors.sorted(by:{$0.slot<$1.slot}) where anchor.isValid {
            guard seen.insert(anchor.slot).inserted else {continue}
            let id=UInt32(0xFF000000)+UInt32(anchor.slot)
            guard !world.surfaces.contains(where:{$0.id==id && !$0.isFixedPerch}),
                  let index=displays.sorted(by:{preferred($0,to:$1,anchor:anchor,world:world)}).first else {continue}
            let display=world.displays[index]
            // Work areas are matched geometrically so reordering either list
            // cannot accidentally apply a different monitor's Dock/menu inset.
            let areas=world.screens.filter{FixedPerchAnchor.isValidFrame($0)}
                .map{display.intersection($0)}.filter{!$0.isNull && !$0.isEmpty}
            let area:CGRect
            if world.screens.isEmpty {area=display}
            else {
                guard let match=areas.sorted(by:{
                    let a=$0.width*$0.height,b=$1.width*$1.height
                    return a==b ? framePrecedes($0,$1):a>b
                }).first else {continue}
                area=match
            }
            let left=area.minX+horizontal,right=area.maxX-horizontal
            let top=area.minY+headroom,floor=area.maxY-bottom
            guard right>left,floor>top else {continue}
            let foot=CGPoint(x:min(right,max(left,display.minX+CGFloat(anchor.x)*display.width)),
                             y:min(floor,max(top,display.minY+CGFloat(anchor.y)*display.height)))
            let rect=CGRect(x:foot.x-64*scale,y:foot.y,width:128*scale,height:24*scale)
            // Include the image, the complete ledge, and birds at either end of
            // its landing range, including head clearance and tail below feet.
            let halfWidth=max(surfaceWidth/2,max(77*scale,horizontal))
            let space=CGRect(x:foot.x-halfWidth,y:foot.y-headroom,width:2*halfWidth,height:headroom+bottom)
            guard !occupied.contains(where:{$0.intersects(space)}) else {continue}
            let surface=Surface(id:id,pid:Int32.min+18,
                                rect:CGRect(x:foot.x-surfaceWidth/2,y:foot.y,width:surfaceWidth,height:1),
                                isFixedPerch:true)
            result.append(ResolvedFixedPerch(slot:anchor.slot,surface:surface,foot:foot,rect:rect))
            occupied.append(space)
        }
        return result
    }

    private static func preferred(_ a:Int,to b:Int,anchor:FixedPerchAnchor,world:BehaviorWorld) -> Bool {
        let lhs=world.displays[a],rhs=world.displays[b]
        func displayID(_ index:Int) -> String {world.displayIDs.indices.contains(index) ? world.displayIDs[index]:""}
        let aID=displayID(a),bID=displayID(b)
        let aMatches = !anchor.displayID.isEmpty && aID==anchor.displayID
        let bMatches = !anchor.displayID.isEmpty && bID==anchor.displayID
        if aMatches != bMatches {return aMatches}
        let aFrame=lhs==anchor.displayFrame,bFrame=rhs==anchor.displayFrame
        if aFrame != bFrame {return aFrame}
        func overlap(_ frame:CGRect) -> CGFloat {
            let cut=frame.intersection(anchor.displayFrame)
            return cut.isNull || cut.isEmpty ? 0:cut.width*cut.height
        }
        let aArea=overlap(lhs),bArea=overlap(rhs)
        if aArea != bArea {return aArea>bArea}
        let center=CGPoint(x:anchor.displayFrame.midX,y:anchor.displayFrame.midY)
        let aDistance=Geometry.distance(center,CGPoint(x:lhs.midX,y:lhs.midY))
        let bDistance=Geometry.distance(center,CGPoint(x:rhs.midX,y:rhs.midY))
        if aDistance != bDistance {return aDistance<bDistance}
        if lhs != rhs {return framePrecedes(lhs,rhs)}
        if aID != bID {return aID<bID}
        return a<b
    }

    private static func framePrecedes(_ a:CGRect,_ b:CGRect) -> Bool {
        for (lhs,rhs) in zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]) {
            if lhs != rhs {return lhs<rhs}
        }
        return false
    }
}
