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
