# M6f.1 验收记录（阶段验收通过、未安装）

记录日期：2026-10-24。**状态：M6f.1阶段验收通过，随本阶段记录本地提交、未安装。Release、严格签名、860核心、3156原生鸟类、1782设置、51完整回放、素材回归及三轮18次性能通过。** 当前安装版仍为M6a/b；下一阶段M6f.2白眉姬鹟出击返回捕虫，不将整个M6/M7目标标为完成。

本批仅家燕捕虫M6f.1，不包含白眉姬鹟M6f.2。依据 [内容规格](BEHAVIOR-CONTENT-SPEC.md) §2、§4.3及验收要求，历史结果见 [M6e验收](M6E-ACCEPTANCE.md)。本批新增3张鸟体/4张昆虫，累计147张新鸟体/10张道具，剩20/6张；仍为46鸟，左右镜像和复用帧不重复计数。

## 基线与版本

| 项目 | 冻结值与证据边界 |
| --- | --- |
| 源码基线 | M6e提交 `45ae138`；46鸟历史像素/索引比较通过。第二轮未改绘制或导出格式，首轮导出证据适用于最终素材；第二轮birds另重新执行原生素材检查。 |
| 构建备份 | 主会话已备份 `.build/m6f1-delivery/ChirpOS Dev before M6f1.app`，二进制hash `c00bf14bed5bc038cda348367b95213014a3fc82785563ffb945d8998e608ab3`；备份不表示安装。 |
| 回放版本 | 当前源码 `BehaviorRecording.currentVersion=1`、`engineVersion=14`，即模拟v14；第二轮17夹具×30/60/120Hz=51报告跨率一致，旧16报告兼容再次通过；真实v13录制拒绝。 |

## 素材与几何合同

| 项目 | 冻结合同 |
| --- | --- |
| 三张鸟体 | 仅barnSwallow的 `catchOpen` / `catchClose` / `catchRecover`；48×48逻辑画布、保持现有绘制密度与脚参考锚(29,39)。独立翼、躯干、叉尾、头颈和喙姿态，四语义层body/feet/headNeck/bill。 |
| 飞行脚与边界 | 空中脚收于腹部；参考脚锚保持不表示脚实际触地。整轮廓含描边须在画布内，头颈不穿脚平面，不复用旧帧冒充新姿态。 |
| 真实喙锚 | 锚取实际上喙尖顶点，张喙帧也不取口腔空白中心；右向逻辑坐标镜像为x→48−x，世界变换再应用尺度与旋转。 |
| 既有帧覆盖 | 家燕fly0…7、land0…2、glide0…2、bank0…2、bound、stand共19帧，加catch三帧，共22帧同源喙锚；保留旧绘制操作、旧像素与图集索引。 |
| 恢复参数 | 捕获后的 `catchClose` 0.18s + `catchRecover` 0.30s，两轮保持；生产catchOpen由拦截执行与连续接触判定控制。 |
| 四张昆虫 | 独立 `insect0`…`insect3`，16×16逻辑画布，胸部中心/锚(8,8)，碰撞半径3，均乘独立worldScale，不受鸟relativeScale影响。翼形变化保持中心不漂移、透明边距；碰撞圆不等同整幅可见翼轮廓。 |
| 昆虫时钟 | 12fps，每帧1/12s，四帧循环；全局最多1只，寿命12s，完整画布从所选屏外进入。 |
| 第二轮拦截候选 | contact候选时刻为1.2/2.0/2.8/3.6s，首段时长为候选时刻+0.25s，优先从鸟前侧斜入；保持实际初速/切线、原飞行目标及连续真实喙resolver。 |
| 第二轮虫速与可见性 | 虫速≤480×worldScale，完整画布可见至拦截窗口至少0.8s；碰撞仍用真实喙扫掠与原碰撞圆。六组实际虫速48–215pt/s、完整入屏到接触1.734–3.369s，连续图结合PNG时间戳通过可读性查看。 |

三张新帧喙锚如下，数值仅便于审阅；运行入口从绘制几何计算，不以表中舍入值替代源码。

| 帧 | 右向(x,y) | 左向(x,y) |
| --- | --- | --- |
| catchOpen | (41.818894738,18.569483802) | (6.181105262,18.569483802) |
| catchClose | (41.160660804,20.710913104) | (6.839339196,20.710913104) |
| catchRecover | (39.918490939,20.439483450) | (8.081509061,20.439483450) |

源码入口：`DetailedBirdArt.catchImage(_:species:part:)`、`catchBillAnchor(_:species:)`，并接入make/poseImage/poseBillAnchor；`CatchPoseAnchors.anchor(species:frame:) -> PoseClip.Anchor?`供PoseClip接入。共有几何位于 `BirdingCore/Behavior/CatchArtGeometry.swift`，既有飞行喙锚复用TransportArtGeometry的真实变换；昆虫由 `Birding/InsectArt.swift` 的 `image(_:)` 提供，frameNames/logicalSize/anchor/collisionRadius/frameDuration读取同源常量。

## 导出与预览静态核对

以下为文档owner的源码入口核对；导出与解码由主会话执行，不代称亲自运行或查看图像。第二轮只改规划、native验证资源释放/断言和测试，绘制及导出格式未改；首轮46鸟旧像素/parity/72 GIF证据直接适用于最终素材，未要求或声称重复导出。第二轮完整birds已重新执行素材原生检查。

| 输出 | 源码覆盖与待核对内容 |
| --- | --- |
| 公共图集/道具 | SharedArt追加家燕catch三帧并保留旧索引前缀；独立输出 `art/props/insect0.png`…`insect3.png`，manifest包含尺寸、中心、半径、时长及worldScale合同；主会话报告首轮导出完成、parity通过。 |
| catch联系表 | M6ContentVerification原生内容验证入口输出 `m6-content-<UUID>/barnSwallow-catch-contact-sheet.png`，三行、production/body/feet/headNeck/bill五列；同目录有左右0.5×/1×/2×六张catch静态PNG。该专用表不由pose预览GIF入口生成。 |
| 循环GIF | `--export-pose-previews`保留12鸟×3缩放×左右=72份既有文件名，家燕六份追加catch列；保留watch/alert/rest/takeoff及既有peek/bath/carry轨道。每份100帧、0.05s/帧、loop=0的源码设置仍在。 |
| 时长与旧文件边界 | GIF内catchOpen的0.24s仅供素材展示，恢复仍为0.18+0.30s。家燕GIF因追加列改变画布宽度，不能宣称全部旧GIF字节/尺寸不变；72份、7200帧、loop=0已通过，适用于最终素材。主会话已看实际catch联系表及0.5×连续原生图层。 |

M6e旧数量为72份/7200帧、loop=0，非32份；本批结果另见 `.build/m6f1-delivery/gif-validation.json`。源码静态审查、实际逐像素回归与原生视觉证据分别记录，不把源码保持代替像素或视觉验收。

## 统一验收覆盖（已通过范围）

| 检查 | 必需范围 | 本批结果/证据 |
| --- | --- | --- |
| Release与严格签名 | 全部实现后统一构建、严格签名验证 | 第二轮74.82s、严格签名PASS |
| 核心XCTest | 完整回归、仅家燕许可、缺帧/错物种/禁用拒绝 | 第二轮860项0失败，135.830s |
| 连续捕获 | 真实喙扫掠与半径3×worldScale；粗回调/跨tick顺序、命中/错过、一次拦截、无重复完成 | 核心resolver与成功/错过分段跨率报告通过；原生真实接触通过 |
| 真实飞行接续 | 复用已有普通飞行居民、不补鸟/传送；实际入速/切线与原目标连续，不可行拒绝；恢复完成才记成功，missedTarget不记成功 | 核心与原生完整journeys通过；第17夹具恢复原目标落稳、成功计数唯一 |
| 生命周期与守恒 | 点击取消、暂停冻结、删除/失屏/睡眠注入、禁用清理；取消后虫按原路线剩余寿命推进，无所有权/预约残留 | 核心、原生及24/64负载通过；注入不代表真实睡眠/物理热插拔验收 |
| 时限与调度 | 单次拦截≤4s、run≤35s、预览等自然飞行≤10s、虫寿命12s/最多1只；第二轮候选/速度/可见性合同见上；不追真实鼠标，无每帧随机改路 | 核心/原生通过；六组速度与可见提前量、自然等待/拒绝及独立调度通过 |
| 原生鸟类与设置 | 完整检查、真实journeys、中英文、左右/负坐标/0.5×/1×/2×、遮挡/锚/12fps与实际截图查看 | 第二轮3156鸟类/1782设置全通过；AG崩溃消除，实际查看范围见后文 |
| v14完整回放 | 全夹具30/60/120Hz完整报告对比，新增捕获/错过及旧行为回归，记录实际夹具/报告数 | 第二轮51报告一致；旧16份去7新增字段再次一致 |
| 历史素材与新增量 | 46鸟旧像素/索引对45ae138不变；恰增家燕3帧和独立昆虫4帧；四语义层与真喙锚 | 首轮导出证据适用于最终素材；第二轮完整birds重新通过素材检查 |
| 公共导出与parity | 图集/manifest/元数据一致，虫中心不漂移、透明边距、来源与尺度一致 | 首轮导出及parity通过，第二轮未改绘制/导出格式 |
| 联系表与GIF | 实际查看catch联系表及六向缩放预览；72GIF完整解码/loop=0/旧轨道保留 | 72GIF/7200帧/loop=0通过；主会看联系表/0.5×连续图，Euclid复核六组连续图及时间戳 |
| 压力与性能 | 24/64鸟实际捕虫完成/取消/到期/清理工作负载；同机基线性能、尾延迟和清理指标 | 各2completed/1cancel，暂停/虫自然到期零残留；三轮18次性能通过，见下表 |
| 安装 | 当前未安装；最终安装前保护最新设置与未保存草稿并单列结果 | 未安装 |

## 首轮实际结果（不代表本批验收完成）

| 检查 | 首轮真实结果 | 证据 |
| --- | --- | --- |
| Release / signature | Release通过，75.93s；signature通过（主会话报告） | `.build/m6f1-build-initial.log`、`.build/m6f1-signature.log` |
| 核心XCTest | 860项0失败，135.537s | `.build/m6f1-tests-initial.log` |
| v14回放 | 17夹具×3率=51报告，跨Hz一致 | `.build/m6f1-replays-initial/summary.json`、`.build/m6f1-replays-initial.log` |
| 旧回放回归 | 旧16份60Hz报告去7新增字段后与45ae138一致 | `.build/m6f1-delivery/legacy-replay-comparison.json` |
| 历史像素/索引 | 46鸟旧像素与索引不变；家燕50→53帧，其余旧帧不变 | `.build/m6f1-delivery/legacy-pixel-comparison.json` |
| 导出 / parity | 主会话报告导出完成、parity通过；未提供单独parity日志路径 | `.build/m6f1-export-initial.log`及主会话结果 |
| 循环GIF | 72份、7200帧，全部loop=0 | `.build/m6f1-delivery/gif-validation.json` |
| 原生鸟类 | 3159项仅1项false，整套passed=false；捕虫native全通过 | `.build/m6f1-birds-initial/report.json`、同目录 `insect-catch-native-F044FA8D-3A16-41B3-A9AA-E6C0DC5DBAAB/report.json` |
| 原生settings | 进程退出134 / SIGABRT，整套未完成，不能记为通过 | `.build/m6f1-settings-initial.log`、`.build/m6f1-delivery/settings-initial-crash.json` |
| 首轮未完成项 | 当时settings崩溃、feeding期望及速度观感待修，尚未做性能；后续结果另列 | 不改写首轮为整套通过 |

旧回放比较仅去除 `hasInsectCatchPreview`、`insect`、`insectCooldownRemaining`、`insectMissedTargetCount`、`insectPreviewRemaining`、`insectPreviewSpecies`、`lastInsectContact`。这是历史行为回归证据，不替代新增捕虫接触、恢复和实体守恒验收。

## 第二轮及最终结果

| 检查 | 最终真实结果 | 证据 |
| --- | --- | --- |
| Release / 严格签名 | 74.82s / PASS | `.build/m6f1-build-second.log`、`.build/m6f1-signature-second.log` |
| 核心XCTest | 860项0失败，135.830s | `.build/m6f1-tests-second.log` |
| 原生鸟类 / settings | 3156 / 1782全PASS，feeding原失败断言true、AG崩溃复验消除 | `.build/m6f1-birds-second/report.json`、`.build/m6f1-settings-second/report.json` |
| v14回放 / 旧回归 | 51报告跨率一致，旧16去7字段再次兼容 | `.build/m6f1-replays/summary.json`、`.build/m6f1-delivery/legacy-replay-comparison.json`；初轮保留在 `m6f1-replays-initial/` |
| 最终素材 | 沿用首轮46旧像素/索引、parity、72GIF证据；第二轮birds重新执行素材原生检查通过 | `.build/m6f1-delivery/legacy-pixel-comparison.json`、`gif-validation.json`及上列原生报告 |
| 六组运动证据 | 0.5×/1×/2×左右六组，虫速48–215pt/s、60Hz步位移/虫画布宽0.049–0.296、完整入屏到接触1.734–3.369s | `.build/m6f1-birds-second/insect-catch-native-0FF1FD32-6197-49E4-8158-5EFF0E1A30CA/report.json`及同目录连续PNG/GIF |
| 同机性能 | 三轮18/18通过，三组metricsUnchanged/cleanupUnchanged均true | `.build/m6f1-performance/summary.json` |

检查数3159→3156不是删测试：第二轮新增12条速度检查，旧allopreening镜像在首attempt已满足，少一次包含15项的重试；3159+12−15=3156。固定 `allopreeningMirroredHelperOnRightFacesLeftAtContact` 仍为true，镜像要求未放宽。

## 首轮问题、修正与复验（保留历史）

| 问题 | 定位与处理 | 当前状态 |
| --- | --- | --- |
| feedingArtAppendsAfterUnchangedCommon34AndAllopreeningIndices=false | FeedingArtVerification完整序列期望停在carry，漏家燕catch三帧尾段；增加仅家燕的精确catch期望，保留34帧数量、legacy/prior前缀和去重断言，并增加整个preCatch前缀检查。未修改生产素材。 | 第二轮原失败断言true、完整birds通过。 |
| settings新journal截图崩溃 | 诊断为EXC_CRASH / SIGABRT、exit134，栈含 `AG::data::table::grow_region()`，经SettingsVerification.snapshot到InsectCatchSettingsVerification.journal。Euclid为每个settings夹具加入autoreleasepool，并将新controls/journal分段释放；未缩减检查。 | 第二轮1782项全通过，AG崩溃复验消除；中英controls与英文journal经主会查看正常。 |
| 0.5×昆虫速度观感 | 首轮主会话报告虫速4615pt/s。第二轮采用1.2/2/2.8/3.6s候选、首段末端+0.25s、前侧斜入优先、速度≤480×worldScale及完整可见提前量≥0.8s，保持初速切线/原目标/连续真实喙resolver。 | 六组运动数据及连续图可读性复核通过，51回放与旧16兼容再次通过。 |

## 同机性能与功能压力

M6e→M6f.1两版本、三场景、各三轮，共18次全部通过，三组metricsUnchanged/cleanupUnchanged全部true。active advance单位ms；p50取三轮中位数，p95/p99取M6f.1三轮最差值。

| 场景 | M6e medianP50 | M6f.1 medianP50 | 变化 | M6f.1最差p95 / p99 |
| --- | --- | --- | --- | --- |
| ordinary：24鸟/2屏/600s | 0.019209 | 0.019333 | +0.64553% | 0.037917 / 0.051709 |
| crowded：64鸟/4屏/600s | 0.048958 | 0.049250 | +0.59643% | 0.074166 / 0.089625 |
| long：12鸟/2屏/3600s自主 | 0.013833 | 0.013416 | −3.01453% | 0.022083 / 0.029959 |

证据 `.build/m6f1-performance/summary.json`。增幅全低于10%，无需额外复测；这是既有工作负载的加速核心模拟，相同metrics不等于捕虫完成，不代表原生渲染、长期内存或能耗结论。实际捕虫由24/64居民专项各2次完成/1次点击取消覆盖：暂停冻结，取消后同一虫沿原轨迹自然到期，最终run/lease/预约/prop/等待与focus均零残留。专项为功能压力，不能当作18次性能已覆盖新捕虫负载。

## 实际查看与交付边界

主会话已看实际catch联系表及0.5×连续原生图层；Euclid对六组连续PNG/GIF及原时间戳复核可读性通过。0.5×虫体细节受小尺寸限制；原生approach GIF为20ms/帧，比60Hz约慢20%，感受结合PNG时间戳，不仅据GIF判断。此处approach GIF与上列72份姿态循环预览是不同证据。

主会另看中英settings controls与英文journal截图正常，位于 `.build/m6f1-settings-second/insect-catch-settings-19CAF1D4-FE69-46F5-B4D2-C8B691E9961B/`。原生证据是附着显示器上的生产模型图层与隔离夹具，不等于真实WindowServer全部遮挡、完整日常桌面或物理硬件验收。文档owner未代称亲自看图或运行验证。

负坐标屏的完整捕虫矩阵由核心测试覆盖：正屏及完全负坐标屏各自检查三种缩放与双朝向。原生六组使用当前附着显示器，不将这些结果称为物理负坐标多屏验收。

M6f.1阶段验收通过，随本阶段记录本地提交、未安装。安装版仍M6a/b，安装前保护最新设置与草稿。下一阶段M6f.2，全部M6/M7持续目标保持进行；历史M6e等验收不改写。

物理多屏/热插拔、真实睡眠唤醒、2h日常观察、8h浸泡及长期内存/能耗仍未验收；原生隔离夹具、生命周期注入和加速模拟不替代这些边界。本次文档工作仅读源码、既有日志和报告，未运行构建、测试、导出、原生或提交。
