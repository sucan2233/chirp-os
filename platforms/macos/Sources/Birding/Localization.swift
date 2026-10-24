import Foundation
import BirdingCore

enum AppLanguage: String {
    case chinese = "zh", english = "en"
    func text(_ zh:String,_ en:String) -> String { self == .chinese ? zh : en }
    var switchTitle: String { self == .chinese ? "English" : "中文" }
    var sceneBusyMessage:String {text("场景位已占用，请先清除当前场景再放置；固定栖木保留。","The scene slot is occupied. Clear the current scene before placing another; fixed perches remain.")}
    func habitatName(_ kind:HabitatObjectKind) -> String {
        switch kind {
        case .foodTray:return text("临时食盘","Temporary food tray")
        case .bath:return text("浴盆","Bath")
        }
    }
    /// Keep settings help and preview requirements in the product permission order.
    func supportedSpeciesNames(for kind:BehaviorKind) -> String {
        SpeciesBehaviorProfile.species(for:kind).map { name($0) }
            .joined(separator:text("、",", "))
    }
    var poseSpeciesNames:String {
        SpeciesBehaviorProfile.poseSpecies.map { name($0) }.joined(separator:text("、",", "))
    }
    /// One shared species list keeps the twelve English names readable without
    /// repeating them inside the shorter preview and takeoff help controls.
    var poseSupportReference:String {text("以上专用鸟种","the pose species listed above")}
    var leafCarrySupport:String {text("所需鸟种：","Required species: ")+supportedSpeciesNames(for:.leafCarry)+text("。",".")}
    var insectCatchSupport:String {text("所需鸟种：","Required species: ")+supportedSpeciesNames(for:.insectCatch)+text("。",".")}
    var visitorGiftSupport:String {text("所需鸟种：","Required species: ")+supportedSpeciesNames(for:.visitorGift)+text("。",".")}
    func giftAuthorizationMessage(_ reason:GiftAuthorizationDenial)->String {
        switch reason {
        case .invalidRequest:return text("礼物授权信息已失效，请重新预览；不会复用旧授权。","Gift authorization is no longer valid. Try again; old authorizations are never reused.")
        case .namespaceUnavailable:return text("熟客档案尚未安全保存，自动礼物暂不可用；已有记忆保留。","Returning-visitor identity is not safely saved. Automatic gifts are unavailable; existing memory is retained.")
        case .notEligible:return text("需要已有灰喜鹊熟客：至少来访3次、熟悉度达到0.6。","An existing returning Azure-winged Magpie needs at least 3 visits and familiarity of 0.6.")
        case .alreadyGranted:return text("这位熟客已使用本机自动礼物额度；模拟预览不消耗额度。","This visitor has already used its automatic gift allowance on this Mac. Simulated previews do not use allowances.")
        case .globalCooldown:return text("距离上次自动礼物授权不足24小时；取消不会返还已授予额度。","Automatic gift authorizations must be at least 24 hours apart. Cancellation does not refund an allowance.")
        case .clockRollback:return text("本机时间早于上次授权记录，自动礼物已停止；请检查系统时间。","This Mac's clock precedes its last gift authorization. Automatic gifts have stopped; check the system time.")
        case .storageUnavailable:return text("礼物额度无法安全保存，自动礼物已停止；普通鸟行为不受影响。","The gift allowance could not be saved safely. Automatic gifts have stopped; ordinary bird activity continues.")
        case .unsupportedVersion:return text("礼物账本来自较新版本，已保留原文件并停止自动礼物。","The gift ledger belongs to a newer version. Its file is preserved and automatic gifts have stopped.")
        case .invalidLedger:return text("礼物账本无法校验，已保留原文件并停止自动礼物。","The gift ledger could not be validated. Its file is preserved and automatic gifts have stopped.")
        case .ledgerFull:return text("礼物额度账本已达容量上限，停止自动礼物；不会删除历史额度。","The gift ledger is full. Automatic gifts have stopped; past allowances will not be deleted.")
        case .busy:return text("另一项礼物授权正在处理，请等待或取消当前申请。","Another gift authorization is being processed. Wait or cancel the current request.")
        case .timedOut:return text("礼物授权已超过5秒期限；迟到结果不会启动互动，已提交额度不返还。","Gift authorization exceeded its 5-second deadline. Late results cannot start an encounter; committed allowances are not refunded.")
        }
    }
    var flycatcherCatchPreviewTitle:String {text("预览","Preview ")+name(.yellowRumpedFlycatcher)+text("捕虫"," catch")}
    var flycatcherCatchRequirement:String {
        text("请启用白眉姬鹟并保存，等待已有居民在普通窗口顶部或地面停稳；固定树枝不适用，不等待自然飞行。",
             "Enable and save the flycatcher. Use a resident settled on a normal window top or ground edge; fixed branches are ineligible.")
    }
    func name(_ id:SpeciesID) -> String {
        if let p = SpeciesCatalog.standard.species.first(where: { $0.id == id }), let en = p.englishName { return text(p.name,en) }
        switch id {
        case .redWhiskeredBulbul: return text("红耳鹎","Red-whiskered Bulbul")
        case .treeSparrow: return text("麻雀","Eurasian Tree Sparrow")
        case .lightVentedBulbul: return text("白头鹎","Light-vented Bulbul")
        case .spottedDove: return text("珠颈斑鸠","Spotted Dove")
        case .chineseBlackbird: return text("乌鸫","Chinese Blackbird")
        case .magpieRobin: return text("鹊鸲","Oriental Magpie-Robin")
        case .longTailedShrike: return text("棕背伯劳","Long-tailed Shrike")
        default: return SpeciesCatalog.standard.profile(id).name
        }
    }
}
