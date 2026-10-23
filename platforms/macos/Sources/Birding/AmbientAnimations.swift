import AppKit
import BirdingCore

// Platform input/output only. Behavior instances, queues and timers live in BirdingCore.
extension DesktopController {
    var pointerPosition:CGPoint {
        let point=NSEvent.mouseLocation
        return CGPoint(x:point.x,y:primaryHeight-point.y)
    }
    var ambientBusy:Bool {engine.ambientBusy}
    func syncWorld(sampleDT:Double?=nil,at point:CGPoint?=nil,buttonsDown:Bool?=nil) {
        engine.updateWorld(BehaviorWorld(screens:screenRects,displays:displayRects,surfaces:surfaces,
            scale:scale,pointer:point ?? pointerPosition,buttonsDown:buttonsDown ?? (NSEvent.pressedMouseButtons != 0),availableFrames:frameCapabilities,localMinuteOfDay:activityMinuteOfDay()),sampleDT:sampleDT)
    }
    func renderSnapshot() -> [BirdRenderState] {syncWorld();return engine.renderSnapshot()}
    @discardableResult func startPointerVisit(at point:CGPoint) -> Bool {
        syncWorld(at:point)
        let result=engine.handle(.pointerVisit(.preview))
        if result.accepted {hoverTracker=HoverTracker<BirdID>();hoveredBird=nil}
        return result.accepted
    }
    @discardableResult func startFlockPass() -> Bool {
        syncWorld();return engine.handle(.flockPass(.preview)).accepted
    }
    func consumeBehaviorEvents() {
        for event in engine.events where event.sequence>lastBehaviorEvent {
            if event.type == .previewResult {
                settingsWindow?.message.stringValue=event.reason.map(behaviorMessage) ??
                    (event.kind == .leafPlay ? leafPlayMessage:pointerVisitPreviewMessage)
            }
            lastBehaviorEvent=event.sequence
        }
    }
    var leafPlayMessage:String {
        t("落叶游戏开始了：小鸟会追随叶片一小段，再回到停靠点。",
          "Leaf play started: a bird will follow the leaf briefly, then return to its perch.")
    }
    var pointerVisitPreviewMessage:String {
        settings.pointerFollowEnabled
            ? t("正在预览绕鼠标飞行。移动鼠标会继续跟随，点击可结束。","Pointer visit started. Moving keeps it following; click to end it.")
            : t("正在预览绕鼠标飞行。移动鼠标或点击可结束。","Pointer visit started. Move the pointer or click to end it.")
    }
    func behaviorMessage(_ reason:BehaviorReason) -> String {
        switch reason {
        case .paused:return t("请先继续动画。","Resume animation first.")
        case .disabled,.settingsChanged:return t("请先保存并开启对应互动。","Save and enable this interaction first.")
        case .busy:return t("请等待当前互动或预览结束。","Wait for the current encounter or preview to finish.")
        case .missingFrames:return t("当前鸟种暂不支持这个动作。","This activity is not yet available for this bird.")
        case .pointerNearby:return t("请先把鼠标移离小鸟，让它安静停留。","Move the pointer away from the bird so it can settle.")
        case .noSpecies:return t("请启用至少一种群飞鸟种。","Enable at least one flock species.")
        case .noCompanion:return t("请等待两只距离合适的小鸟在可见边缘停稳，再预览双鸟互动。","Wait for two suitably spaced birds to settle on visible edges, then try the two-bird interaction.")
        case .unavailableBird,.missingBird:
            return t("暂时没有合适的小鸟，请等它在可见位置停稳后再试。","No bird is ready yet. Wait for one to settle in a visible spot and try again.")
        case .userInput:return t("请先松开鼠标，再试一次。","Release the mouse button and try again.")
        case .noSpace:
            return t("可见空间不足。请等待小鸟在更开阔、未被遮挡的位置停稳。","Not enough visible space. Wait for birds to settle in a clear, unobstructed area.")
        default:return t("预览已取消，可以稍后重试。","Preview cancelled. You can try again later.")
        }
    }
}
