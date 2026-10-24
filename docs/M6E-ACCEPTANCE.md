# M6e 验收记录（已验证交付，未安装）

记录日期：2026-10-24。**状态：M6e阶段已验证交付，随本阶段记录本地提交、未安装。Release、核心826、原生鸟类2990、设置1695、48完整回放、素材回归、严格签名与三轮18次性能均通过。** 用户安装版仍为M6a/b；下一阶段M6f.1家燕捕虫，全部M6/M7目标继续进行。

依赖基线：M6d本地提交 `7eb6b26`，历史证据见 [M6d验收](M6D-ACCEPTANCE.md)。本批全部实现后由主会话统一构建、导出与验证；本记录保留首轮失败及最终复验，不沿用M6d数量。验收依据为 [内容规格](BEHAVIOR-CONTENT-SPEC.md) §2、§4.2、§5–6，当前阶段见 [实施进度](IMPLEMENTATION-PROGRESS.md)。

## 素材与几何合同

| 项目 | 冻结合同与验证范围 |
| --- | --- |
| 鸟体 | 麻雀carryLook/carryLower/carryGrip/carryPlace四帧独立姿态；48×48画布，脚(29,39)，body/feet/headNeck/bill四层；原生素材与实际图层通过。 |
| 接触帧 | Grip/Place喙右(40,39)、左(8,39)，新画头颈；柄与支撑同高，接触不用整体平移鸟。 |
| 叶片 | 独立16×16 leafToken，柄(3,12)、支撑(10,12)，完整轮廓含边框bottom12；叶体16×worldScale，不受carrier.relativeScale影响。 |
| 旧帧喙锚 | fly0…7、land0…2、glide0…2、bank0…2、bound、stand取真实绘制几何；不新增带叶烘焙图。stand右(40.5,20.5)、左(7.5,20.5)。 |
| 空间安全 | 鸟叶变换后取并集，检查两朝向、路线与旋转包络；实际M6e叶片rotation=0，不把叶片裁进48画布。核心小宿主/叶片独占空间遮挡与原生0.5×/1×/2×通过。 |

素材源码：`platforms/macos/Sources/Birding/DetailedBirdArt.swift`、`CarryArt.swift`，以及 `platforms/macos/Sources/BirdingCore/Behavior/CarryArtGeometry.swift`（含TransportArtGeometry）、`CarryPoseAnchors.swift`。入口 `CarryPoseAnchors.anchor(species:frame:) -> PoseClip.Anchor?`，本批仅麻雀；不提前开放灰喜鹊礼物或斑鸠运材。

本批恰增4张鸟体与leafToken 1张，累计144张新鸟体、6张道具，剩23张鸟体/10张道具；仍为46鸟种。历史像素对照不把左右镜像、复用旧帧或道具重复计作新鸟体。

## 必需验收项与最终证据

以下通过范围为核心模拟和原生隔离夹具；真实长期桌面与物理硬件边界单列。

| 编号 | 必需证据 | 最终覆盖 |
| --- | --- | --- |
| V01 | 仅麻雀、完整专用帧及transport锚，缺帧/错物种拒绝 | 核心逐必需帧与其余45种拒绝、同源喙锚及原生素材通过；动态落叶独立。 |
| V02 | 生产放置、自动机会、设置预览复用真实居民与合法宿主 | 核心自动调度及原生真实journeys通过；不补鸟、不传送，原settings放置失败第二轮通过。 |
| V03 | 各阶段及原子提交边界中断，无重复实体/所有权 | 核心逐阶段取消、超时、外部改路、宿主/鸟移除与叶片单独遮挡通过；原生中断及淡出通过。 |
| V04 | 暂停冻结、暂停删除、睡眠/退出/显示器失效清理 | 核心与原生注入生命周期通过，settings两项暂停原失败复验通过；真实睡眠/物理热插拔未验收。 |
| V05 | 30/60/120Hz接触、拾取、放下与终态稳定 | 16夹具48完整报告一致；核心另对完成/取消的分段实体和事件轨迹作独立断言。 |
| V06 | 左右、负坐标、三缩放、真实接触/图层/像素 | 核心变换与原生窗口0.5×/1×/2×双向、地面2×journeys通过；主会话查看样本正常。 |
| V07 | 24/64鸟、取消/到期/超时后最终无残留 | 专项实际carry工作负载各3completed+1attached取消，暂停/自然到期/零残留通过；25s硬期限另有测试；性能见下表。 |
| V08 | 放下并恢复结束才完成，失败/取消不计成功，来源正确 | 核心唯一终态、观察计数与原生一次完成通过；settings手册来源/搜索通过。 |
| V09 | 缺字段默认、历史归档保护、保存/取消/草稿 | 核心826项回归与原生设置1695项通过；仅持久化开关，不保存场景状态，不代表已安装替换。 |
| V10 | 原生设置中英文、放置/清除/预览、点击与实际截图 | leaf设置86项全过，含原4项失败；真实journeys与最终英文placed controls查看正常。 |
| V11 | 唯一sceneFocus、一次机会一个run、无积压、用户抑制 | 核心真实自动携带、随机流隔离、60s用户抑制与放下退出提频通过；恢复期间仍持有原run资源。 |
| V12 | 零物种/禁用/单鸟的真实结果，不擅改概率/创建鸟 | 核心错物种与禁用拒绝、单居民完整携带，以及settings拒绝/保存开关检查通过。 |

## 生命周期与物件守恒

同一实体ID贯穿available/attached/placed/retired；全局最多一枚携带叶片。仅合法普通窗口顶部或地面支撑，拾取前180s；预约80–240逻辑点同屏放下路线和两个落脚点，轻微宿主移动跟随、身份失效取消。观察0.4s/低头0.3s/拾取接触0.2s/抬头0.3s，真实短途飞行后放下0.4s/恢复0.3s，run硬上限25s。拾取原子停止旧寿命并附着；放下原子解绑，保持世界位置/叶体尺度连续，展示8s、最后0.2s淡出。放下前取消在当前可见位置淡出回收，放下后点击保留已提交叶片但不记该run成功。

清除静止叶片用removeCarryLeaf/clearCurrentScene/clearProps；旧clearLeaf仍只清动态落叶。暂停冻结倒计时、阶段、寿命与附着，暂停删除仍释放引用；取消恢复走已有运动入口。普通食盘可与叶片共存，浴盆与可拾取叶片争用唯一场景焦点，放下退出提频、恢复期间仍受原run资源约束。

新增24/64居民核心工作负载各以一只真实麻雀承运、其余居民保持隔离窗口：各完成3次、附着取消1次；共5个token依次覆盖3次完成、1次取消和1次未拾取自然到期。附着/放下/淡出/可用状态暂停冻结，放下8s和可用180s寿命自然推进结束；最终run、lease、落点/对象预约、道具、携带实体、focus及待放置均归零。证据为 `.build/m6e-tests-second.log` 中两个LeafCarryStressTests方法；这是功能压力覆盖，不是原生24/64鸟渲染性能或2h/8h长跑。

## 最终统一验证结果

| 检查 | 实际结果 | 本地证据 |
| --- | --- | --- |
| Release | 第二轮PASS | `.build/m6e-build-second.log` |
| 核心XCTest | 826项、0失败；首轮3个失败方法原断言复验通过，新增24/64实际carry工作负载 | `.build/m6e-tests-second.log` |
| 原生鸟类 | 完整2990项PASS，含carry素材/锚/实际journeys/图层 | `.build/m6e-birds-second/report.json` |
| 原生设置 | 完整1695项PASS；leafCarry专属86项含原4个失败全过 | `.build/m6e-settings-second/report.json` |
| 回放 | 第二轮16夹具×30/60/120Hz=48完整报告一致，模拟版本13 | `.build/m6e-replays-second.log`、`.build/m6e-replays/summary.json`及同目录报告 |
| 旧回放回归 | 旧15夹具60Hz报告去新增字段后与M6d完全一致，15/15 | `.build/m6e-delivery/legacy-replay-comparison.json` |
| 旧像素/索引与新增素材 | M6d 7eb6b26为基线，46鸟旧像素/索引不变，恰增麻雀4帧；leafToken单独导出1张 | `.build/m6e-delivery/legacy-pixel-comparison.json`、`shared/art/props/leafToken.png` |
| 公共数据parity | PASS（主会话报告，未单列日志路径） | 主会话统一验证结果 |
| 循环GIF | 72文件、7200帧完整解码，全部loop=0 | `.build/m6e-delivery/gif-validation.json` |
| 严格签名 | PASS（主会话执行，未单列验证日志） | 主会话最终签名结果；构建见第二轮日志 |
| 同机性能 | 三轮18/18 PASS，三组metrics/cleanup均一致，增幅全低于10% | `.build/m6e-performance/summary.json` |

旧回放比较仅去除新增 `carriedObjects`、`hasCarryLeafPlacement`、`sceneFocusKind` 和 `prop.mirrored`，其余旧报告完全一致。该结果是旧行为回归证据，不能替代新增附着、原子拾取/放下或物件守恒测试；新功能证据由上列专项核心与原生场景提供。

## 同机性能

M6d/M6e两版本、三场景各三轮，共18次全部通过。active advance单位毫秒，p50为三轮中位数，最差p95/p99取M6e三轮最大值；三组metricsUnchanged与cleanupUnchanged全部true。

| 场景 | M6d medianP50 | M6e medianP50 | 增幅 | M6e最差p95 / p99 |
| --- | --- | --- | --- | --- |
| ordinary：24鸟/2屏/600s | 0.019208 | 0.019334 | +0.655977% | 0.032291 / 0.039083 |
| crowded：64鸟/4屏/600s | 0.048042 | 0.050166 | +4.421132% | 0.076916 / 0.091417 |
| long：12鸟/2屏/3600s自主 | 0.013167 | 0.014125 | +7.275765% | 0.022375 / 0.028917 |

证据 `.build/m6e-performance/summary.json`（含18次独立结果，同目录保留逐次报告与资源记录）。全低于10%，按约定无需额外复测。该对照沿用既有工作负载7，不包含新carry专项性能，不能把其中相同metrics解释为自动携带完成；实际carry由24/64功能测试及原生journeys覆盖。测量是同机加速核心模拟，未量化原生绘制、真实长期内存或能耗。

## 首轮失败、根因与修正（保留历史）

首轮Release通过 `.build/m6e-build-initial.log`；XCTest824项有6个断言失败、涉及3个方法 `.build/m6e-tests-initial.log`；原生leaf230项有4个settings失败、汇总passed=false `.build/m6e-leaf-initial/report.json`，真实journeys当时均通过。以下为主会话确认的根因/修正；第二轮保留全部原断言并通过，未将首轮记录改写为成功。

| 首轮方法/检查 | 真实失败与根因 | 修正与最终复验 |
| --- | --- | --- |
| LeafCarryExecutionTests.testHardDeadlineAndExternalRouteReplacementFailWithoutCompletionOrDuplicateObjects | 1断言：实际cancelled、期望failed；Engine.refreshCarriedObjects丢弃reconcile返回的.failed并转成.cancelled | 改用Runtime.finish保留真实结果，第二轮方法通过。 |
| LeafCarryIntegrationTests.testHostFractionTracksLightMovementWhileInvalidIdentityCancelsWithoutTranslatingTheFoot | 3断言：run非nil、宿主偏移与布尔条件失败；约120pt剩余路线仍固定604.8巡航，ramp需约151.2pt，误拒轻移 | 按剩余路长计算可行peak/ramp，保留实际入速和25s期限，第二轮方法通过。 |
| LeafCarryIntegrationTests.testSmallHostRejectsTheTransportBeforePickupWithoutReclaimingTheAvailableEntity | 2断言失败；100pt宿主有效栖点x约133.33–166.67，原叶x170非法 | 夹具改165，明确放置/拾取合法而80pt运输不足；生产空间保护不削弱，第二轮方法通过。 |
| settings：NoEarlyPlacement / PendingPauseFreezes / PlacedLeafFreezes / ProductionLatestPointerPlacement（均带leafCarrySettings前缀） | 原夹具替换synthetic screen，触发生产保护合法取消pending；4项首轮失败 | 改desktop.syncWorld只替换pointer，保留生产保护与原断言；第二轮86项leaf设置全部通过。 |

首轮settings详细报告：`.build/m6e-leaf-initial/leaf-carry-settings-DC3F1072-16E4-48B5-AAC5-18797AECBA2F/report.json`。运行前静态审查还发现localFootprint要求stand但transport缺锚，已补同源stand几何；最终核心及原生验证通过，不改变旧绘制操作。

## 实际查看与未验收边界

主会话实际查看首轮 `.build/m6e-leaf-initial/leaf-carry-source-right.png`，以及 `.build/m6e-leaf-initial/leaf-carry-native-9F903A45-D67B-44FC-A6E8-C8E770FDC8DB/` 的2×右Grip、1×左flight、地面2×placed图，图像正常。最终另查看 `.build/m6e-birds-second/leaf-carry-native-AA1C62AF-6021-4CDD-89A8-8041D2E68993/leafCarryNative-window-2.0-left-attached-carryGrip-actual-layer.png` 和 `.build/m6e-settings-second/leaf-carry-settings-54D2ADE0-596F-4CCE-B431-EBB2A21F4CC1/leaf-carry-placed-en.png`，样本正常。本次文档owner仅读取既有证据，未另跑构建/测试/原生，也未代称亲自查看。

- 原生证据为附着显示器的实际模型图层合成及隔离宿主；真实桌面窗口移动/关闭/全屏、完整菜单流程及全部WindowServer遮挡尚未验收。
- 物理多屏、热插拔、真实睡眠唤醒，以及2h日常观察、8h浸泡、长期内存/能耗未验收，留在M6h/M7d；加速模拟不替代。
- 本批已验证交付，随本阶段记录本地提交、未安装/发布，安装版仍M6a/b；安装前保护最新设置与未保存草稿。不改历史M6d验收状态，不将整个M6/M7目标标为完成。
- 下一阶段M6f.1基线已由主会话备份至 `.build/m6f1-delivery/ChirpOS Dev before M6f1.app`，二进制hash `c00bf14bed5bc038cda348367b95213014a3fc82785563ffb945d8998e608ab3`；这是构建基线备份，不表示安装完成。
