# 共用资源 / Shared resources

`species.json` 面向 U 阶段 100 种目录保存的体长、动作参数和初始出现频率；`art/` 为横向 PNG 图集。`art/manifest.json` 的 `frames` 定义 34 个公共帧，`frameSizes` 定义各鸟种实际像素尺寸，逻辑尺寸为 48×48、足部锚点为 (29,39)。可选 `speciesFrames` 保存某个鸟种的完整帧序列，公共帧始终位于开头；本地原46种已累计追加187帧（早期20帧 + M6/M7新增167帧），覆盖同伴理羽、食盘、观察/警觉/休息/起飞、探头、洗澡、携带、捕虫、求偶与巢台动作。U整合须保留这些帧及其索引，目标为100 × 34 + 187 = 3587帧位；这是帧位数，不是不同图像数。旧消费者可继续按公共索引及图集高度取帧，新消费者优先读取对应的 `speciesFrames`。`AppIcon.ico` 是 Windows 多尺寸图标。资源纳入版本控制，Windows 构建不需要 Swift 或 macOS。

目前像素绘图的权威定义仍在 `platforms/macos/Sources/Birding/PixelArt.swift`、`SpeciesArt.swift`、`DetailedBirdArt.swift`、`ExpansionBirdArt.swift`，鸟种定义在 `platforms/macos/Sources/BirdingCore/Resources/species.json`。修改后在 Mac 执行 `./scripts/export-shared.sh`，一起提交生成结果。不要手工修改图集。macOS 运行时由同一份定义生成纹理；Windows 将导出的图集嵌入 exe 并在启动时缓存。

`species.json` targets the U integration catalog of 100 species, their sizes, animation parameters, and initial frequencies. The horizontal PNG atlases use 34 common `frames`; `frameSizes` provides actual pixel sizes, with a logical size of 48×48 and foot anchor (29,39). Optional `speciesFrames` entries contain the complete frame sequence for a species, always retaining the common prefix. The original cohort retains 187 appended frames (20 earlier frames plus 167 from M6/M7), including social, feeding, pose, bathing, carrying, catching, courtship, and nest actions. The U integration target is 100 × 34 + 187 = 3,587 frame slots, not distinct images. Existing consumers can keep indexing common frames using the atlas height; new consumers should prefer the species entry when present. `AppIcon.ico` is the multi-size Windows icon. These files are checked in so Windows builds need neither Swift nor macOS.

The authoritative drawings remain in the macOS `PixelArt.swift`, `SpeciesArt.swift`, `DetailedBirdArt.swift`, and `ExpansionBirdArt.swift` files, with species definitions in `BirdingCore/Resources/species.json`. After editing, run `./scripts/export-shared.sh` on macOS and commit the regenerated resources. macOS generates textures from these definitions; Windows embeds and caches the exported atlas images. The Windows behavior engine has not yet migrated to macOS semantics; shared resources alone do not establish behavioral parity.

固定栖木原图位于 `platforms/macos/Sources/BirdingCore/Resources/fixed-perch.png`，使用独立透明 PNG，不更改鸟图集索引。来源与脚锚规则见行为设计文档第 32 节；Windows 可复用同一素材，但固定栖木渲染和行为尚未迁移。

临时食盘原图位于 `platforms/macos/Sources/BirdingCore/Resources/food-tray.png`，透明 PNG 保持生成原图。来源与喙/种子接触规则见行为设计文档第 33 节；额外图集帧及物件素材不代表 Windows 已实现食盘行为。

U阶段已从合并绘制源码统一导出，并通过390项素材审计；原生行为验收边界见[交付记录](../docs/U-INTEGRATION-ACCEPTANCE.md)。原46种基础像素有上游修正，须检查差异，不能继续宣称旧像素完全不变。新增54种中的站立回退帧不代表真实动作支持；逐鸟能力以 `species-support.json` 的产品许可、内容审核和缺帧结果共同判定。Windows共享素材不代表其行为引擎已迁移。

U integration is in progress; these contracts await the unified export and acceptance run. Upstream changes affect original-species pixels and require a difference audit. Standing fallback slots do not grant behavior support. Shared assets do not establish Windows behavior parity.
