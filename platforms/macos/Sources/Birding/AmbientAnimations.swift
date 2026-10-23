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
            scale:scale,pointer:point ?? pointerPosition,buttonsDown:buttonsDown ?? (NSEvent.pressedMouseButtons != 0)),sampleDT:sampleDT)
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
                    t("正在预览绕鼠标飞行。移动鼠标即可结束。","Pointer visit preview started. Move the pointer to end it.")
            }
            lastBehaviorEvent=event.sequence
        }
    }
    func behaviorMessage(_ reason:BehaviorReason) -> String {
        switch reason {
        case .paused:return t("请先继续动画。","Resume animation first.")
        case .disabled,.settingsChanged:return t("请先保存并开启对应互动。","Save and enable this interaction first.")
        case .busy:return t("请等待当前互动或预览结束。","Wait for the current encounter or preview to finish.")
        case .noSpecies:return t("请启用至少一种群飞鸟种。","Enable at least one flock species.")
        case .noSpace,.unavailableBird,.missingBird:
            return t("暂时无法开始：请将鼠标放在屏幕中部，并等待同屏的小鸟停稳。","Not available yet. Place the pointer near screen center and wait for a bird to perch on that screen.")
        default:return t("预览已取消，可以稍后重试。","Preview cancelled. You can try again later.")
        }
    }
}
