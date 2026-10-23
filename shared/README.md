# 共用资源 / Shared resources

`species.json` 保存 46 种鸟的体长、动作参数和初始出现频率；`art/` 为横向 PNG 图集。`art/manifest.json` 的 `frames` 定义 34 个公共帧，`frameSizes` 定义各鸟种实际像素尺寸，逻辑尺寸为 48×48、足部锚点为 (29,39)。可选 `speciesFrames` 保存某个鸟种的完整帧序列，公共帧始终位于开头；目前家燕与暗绿绣眼鸟各追加 6 个同伴理羽帧。旧消费者可继续按公共索引及图集高度取帧，新消费者优先读取对应的 `speciesFrames`。`AppIcon.ico` 是 Windows 多尺寸图标。资源纳入版本控制，Windows 构建不需要 Swift 或 macOS。

目前像素绘图的权威定义仍在 `platforms/macos/Sources/Birding/PixelArt.swift`、`SpeciesArt.swift`、`DetailedBirdArt.swift`，鸟种定义在 `platforms/macos/Sources/BirdingCore/Resources/species.json`。修改后在 Mac 执行 `./scripts/export-shared.sh`，一起提交生成结果。不要手工修改图集。macOS 运行时由同一份定义生成纹理；Windows 将导出的图集嵌入 exe 并在启动时缓存。

`species.json` contains 46 species, their sizes, animation parameters, and initial frequencies. The horizontal PNG atlases use 34 common `frames`; `frameSizes` provides actual pixel sizes, with a logical size of 48×48 and foot anchor (29,39). Optional `speciesFrames` entries contain the complete frame sequence for a species, always retaining the common prefix. Barn Swallow and Swinhoe’s White-eye append six companion-preening poses. Existing consumers can keep indexing common frames using the atlas height; new consumers should prefer the species entry when present. `AppIcon.ico` is the multi-size Windows icon. These files are checked in so Windows builds need neither Swift nor macOS.

The authoritative drawings remain in the macOS `PixelArt.swift`, `SpeciesArt.swift`, and `DetailedBirdArt.swift` files, with species definitions in `BirdingCore/Resources/species.json`. After editing, run `./scripts/export-shared.sh` on macOS and commit the regenerated resources. macOS generates textures from these definitions; Windows embeds and caches the exported atlas images. The Windows behavior engine has not yet migrated to macOS semantics; shared resources alone do not establish behavioral parity.

固定栖木原图位于 `platforms/macos/Sources/BirdingCore/Resources/fixed-perch.png`，使用独立透明 PNG，不更改鸟图集索引。来源与脚锚规则见行为设计文档第 32 节；Windows 可复用同一素材，但固定栖木渲染和行为尚未迁移。
