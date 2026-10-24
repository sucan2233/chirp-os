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
        var world=BehaviorWorld(screens:screenRects,displays:displayRects,surfaces:surfaces,
            scale:scale,pointer:point ?? pointerPosition,buttonsDown:buttonsDown ?? pointerButtonsDown(),availableFrames:frameCapabilities,localMinuteOfDay:activityMinuteOfDay(),displayIDs:fixedPerchDisplayIDs,fixedPerchArtAvailable:FixedPerchArt.shared != nil)
        world.foodTrayArtAvailable=HabitatObjectRenderer.foodTrayArtAvailable
        world.bathArtAvailable=HabitatObjectRenderer.bathArtAvailable
        world.leafCarryArtAvailable=ScenePropRenderer.leafCarryArtAvailable
        world.insectArtAvailable=ScenePropRenderer.insectArtAvailable
        engine.updateWorld(world,sampleDT:sampleDT)
        reconcileGiftAuthorization()
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
            if event.kind == .visitorGift {
                switch event.type {
                case .completed:
                    settingsWindow?.message.stringValue=event.source == .preview ?
                        t("模拟虚拟礼物已在接收枝可见；预览单独计数，未使用自动额度。","The simulated virtual gift is visible on its receiving branch; only the preview count changed, with no automatic quota used."):
                        t("熟客的虚拟礼物已在接收枝可见并记入观察手册。","The returning visitor's virtual gift is visible on its receiving branch and recorded in the journal.")
                case .failed,.cancelled,.rejected,.previewResult:
                    if let reason=event.reason {
                        settingsWindow?.message.stringValue=settingsWindow?.visitorGiftMessage(reason) ?? behaviorMessage(reason)
                    }
                default:break
                }
                settingsWindow?.refreshVisitorGiftControls()
            } else if event.kind == .insectCatch,event.source == .preview {
                let species=event.participants.compactMap{engine.bird($0)?.profile.id}.first ?? .barnSwallow
                switch event.type {
                case .previewResult:
                    settingsWindow?.message.stringValue=event.reason.map {settingsWindow?.insectCatchMessage($0,species:species) ?? behaviorMessage($0)} ??
                        t("家燕捕虫预览已开始，将在真实接触后恢复原飞行目标。","Barn Swallow catch preview started; recovery follows real contact.")
                case .completed:
                    settingsWindow?.message.stringValue=species == .yellowRumpedFlycatcher ?
                        t("白眉姬鹟已捕获昆虫，安全返回并停稳，预览单独计数。","The flycatcher caught the insect, returned safely and settled; the preview is counted separately."):
                        t("家燕已捕获昆虫并安全恢复飞行，预览单独计数。","The Barn Swallow caught the insect and recovered safely; the preview is counted separately.")
                case .failed,.cancelled:
                    if let reason=event.reason {settingsWindow?.message.stringValue=settingsWindow?.insectCatchMessage(reason,species:species) ?? behaviorMessage(reason)}
                default:break
                }
                settingsWindow?.refreshInsectCatchControls();settingsWindow?.refreshBathControls()
            } else if event.type == .previewResult {
                if event.kind == .foodTrayVisit {
                    settingsWindow?.message.stringValue=event.reason.map {reason in
                        settingsWindow?.foodTrayMessage(reason,placing:true) ?? behaviorMessage(reason)
                    } ?? t("临时食盘已放置，请把鼠标移远后预览访问。","Temporary tray placed. Move the pointer away before previewing a visit.")
                    settingsWindow?.refreshFoodTrayControls()
                } else if event.kind == .bathVisit {
                    settingsWindow?.message.stringValue=event.reason.map {reason in
                        settingsWindow?.bathMessage(reason,placing:true) ?? behaviorMessage(reason)
                    } ?? t("临时浴盆已放置，请移开鼠标并让支持鸟种安静停稳后预览。","Temporary bath placed. Move the pointer away and let a supported bird settle calmly before previewing.")
                    settingsWindow?.refreshBathControls();settingsWindow?.refreshFoodTrayControls()
                } else if event.kind == .leafCarry {
                    settingsWindow?.message.stringValue=event.reason.map {reason in
                        settingsWindow?.leafCarryMessage(reason,placing:true) ?? behaviorMessage(reason)
                    } ?? t("静止叶片已放置，请移开鼠标，让麻雀停稳后预览携带。","Static leaf placed. Move the pointer away and let a sparrow settle before previewing carrying.")
                    settingsWindow?.refreshLeafCarryControls();settingsWindow?.refreshBathControls()
                } else {
                    settingsWindow?.message.stringValue=event.reason.map(behaviorMessage) ??
                        (event.kind == .leafPlay ? leafPlayMessage:pointerVisitPreviewMessage)
                }
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
