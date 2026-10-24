# M6h 隔离真实墙钟长跑：实现记录与待验收项

记录日期：2026-10-24。**状态栏隔离修正后真实30秒smoke退出0、离线22/22通过。第八轮M7b/c候选的8h默认工作负载已于2026-10-25 06:37:40自然退出0，完整事件、资源与隔离审阅通过。控制窗关闭与应用菜单Quit已完成实际退出检查；2h人工观察、外部终止/启动中途失败及硬件验收仍待执行，M6h未通过。** 用户文件隔离哈希证据有限，不能标为全通过。以下保留各轮实现、失败与smoke历史；最新8h启动记录见末节。

## 实现范围与接线

本实现拥有 `platforms/macos/Sources/Birding/DesktopSoakSession.swift`、独立 `SoakVerification.swift` 与本文件。Desktop/main/Core的接线由主会负责，未在这些文件内替代生产timer或直接调用 `engine.advance`。

- `DesktopSoakSession(output: URL, duration: Double, birds: Int) throws`；公开 `desktop`，以及 `start() throws`、幂等 `finish(reason:)`、`prepareForTermination() -> NSApplication.TerminateReply`。
- main解析 `--soak-desktop <绝对新目录>`、`--soak-duration 30|7200|28800`、`--soak-birds 1...50`（默认12），并强持有session。soak分支在普通desktop启动、更新安装健康确认和updater创建之前返回。
- Desktop提供 `isolatedSession`，所有种群偏好读写使用注入的 `preferences`，隔离模式跳过旧域迁移及新鸟提示。session提供无ServiceManagement读写的 `LoginItemManaging` 实现；不注册/注销登录项。start前注入状态栏项，并立即明确指定 `ChirpOS.Soak.<本次UUID>`，不使用生产名称 `ChirpOS.Main`。这不是禁用 autosave：AppKit 的默认应用偏好域另作记录与清理检查，详见下文修订。
- Desktop的 `tickObserver: ((Double, Double) -> Void)?` 在生产tick末尾传 `(uptime, rawDT)`，其中rawDT未经过0.05s裁剪。session保留原有回调链；tick里只做时间和tick缺口计数，较重的图层和进程采样每10秒进行。
- Engine公开原有 `eventObserver: ((BehaviorEvent) -> Void)?`，session保留原有observer链并逐事件写盘。另提供只读 `giftReceiverReservationCount`，返回runtime当前接收枝预约数量；不得让观测改变随机流或模拟顺序。
- `applicationShouldTerminate` 返回 `soakSession?.prepareForTermination() ?? .terminateNow`。已有finished状态返回terminateNow；其余状态先启动清理并返回terminateLater，等待异步IO后由session回复终止。
- `applicationShouldHandleReopen` 对soak先返回 `soakSession.handleReopen()`；运行中只展示控制窗，收尾中拒绝重开窗口，防止异步flush期间重新建立状态项或设置输入。
- `applicationWillTerminate` 对soak调用 `finish(reason: "applicationTermination")` 后直接return，避免普通退出再次取消/持久化。隔离模式 `Desktop.quit()` 直接请求 `NSApp.terminate`，不能提前取消，否则无法保存自然终态。
- `start()` 途中失败会启动相同清理。main catch打印错误；已持有session时不能立即exit截断IO，初始化尚未产生session时才可直接失败退出。

## 数据隔离与真实运行

输出目录必须新建或为空；`session.claim`以排他创建防止两个实例共用目录。非空目录和已有证据拒绝覆盖。全部五个持久化路径都在输出目录内：`settings.json`、`legacy.json`、`visitors.json`、`journal.json`、`gifts.json`。legacy保持不存在，绝不导入用户文件。无发现时journal、无自动授权时gifts可以不存在，报告记录实际存在性，不生成伪造的“已用账本”。

首次启动从bundled BirdSettings默认值写入隔离settings，创建随机独立UserDefaults域，controller 的语言和数量上下限读写使用该域。注入 suite 不会重定向 AppKit 自身的 `UserDefaults.standard`。session在 `desktop.start()` 前注入全部路径，并显式启用真实visitors/journal/gifts persistence；访客稳定namespace必须初始化成功才继续。结束保存隔离偏好快照后移除本次UserDefaults域，并单独审计默认应用域。源码审计通过：上述五文件接线未发现访问用户settings、草稿、访客、观察手册或礼物账本的路径；这与实际用户文件前后哈希验证是不同层次的证据，后者限制见下节。

使用普通DesktopController初始化，不指定验证seed、不注入fixture鸟、不补鸟、不构造伪窗口宿主。保留真实生产timer、窗口采样、鼠标输入、种群到达、ambient与autonomous路由。固定上下限只设置目标数量，居民由原种群调度自然进入。默认关闭的功能仍关闭；未在本次真实运行发生的行为不因此获得覆盖。控制窗是本进程窗口，依照生产窗口采样规则不充当鸟的宿主。

## 证据与时长口径

`manifest.json`记录输出/五个隔离路径、独立域、状态栏唯一名称、默认应用偏好域、`preferenceIsolationVersion=1`、binary路径及流式SHA-256、bundle版本、OS、PID、实际engine seed、模拟版本和请求时长。不读取窗口标题或记录桌面截图。

`telemetry.jsonl`每10秒追加一条，另记起点、自然终点、清理后及通知：

- 连续墙钟（包含sleep）、awake uptime、模拟时间、暂停状态及采样暂停墙钟、sleep/wake次数与时间、锁屏/未知状态及累计时间。暂停、sleep、锁屏可重叠，不能把这些数直接相加当总时长。锁状态来自session字典与通知；不可读时保留unknown，不能推断为未锁屏，更不能推断有人观察。
- 当前RSS字节、进程累计user+system CPU、session CPU增量、区间CPU%。一个核为100%；分母为含sleep的连续墙钟，sleep期间可稀释百分比，报告同时给出sleep信息。RSS为采样值及采样峰值，不是泄漏证明或系统energy验收。
- tick数量、未裁剪间隔峰值、超过50ms/250ms/1s/10s次数、距最后tick时间。sleep/wake通知单独记录，生产wake重置timer不被伪称为连续运行。
- run、租约、落点/栖息地/接收枝预约、鸟/待入场鸟、道具/携带叶/虫、场景焦点、各类pending与gift token/platform attempt；图层/遮罩/动画计数及持久化状态。

`events.jsonl`记录每一条行为事件及sequence、模拟时间、墙钟偏移、natural/cleanup阶段、kind/source/reason/run/参与者ID；不使用256环回读。计数按有限枚举组合累计，事件流最多64KiB缓冲，到限写出且10秒同步。摘要对sequence缺口计数；IO失败终止运行并保留错误，不能静默丢事件。磁盘证据随事件数增长，内存不保存全量事件列表。

`summary.json`保存清理前自然状态、清理后状态、累计事件及计数、采样RSS峰值、采样资源峰值、持久化flush/窗口/图层释放结果和错误。`wallDurationReached`只说明请求墙钟达到，`awakeDurationReached`另列。`manualTwoHourObservation`始终明确需要独立人工记录；8h仅可显示“时长达到，待审证据”，不会自动授予阶段验收。

## 结束与持久化顺序

1. 保存自然终态与累计时间，先于任何取消命令。
2. 为防等待IO期间wake/鼠标/菜单重入，立即冻结本session的timer与监听，再取消gift pending、shutdown取消全部run、clearProps、逐只通过公开remove命令移除剩余鸟。绝不注入空fixture冒充清理。
关闭本session设置窗口及其延时捕获、图鉴计时器，禁用状态栏/应用菜单，防止异步收尾期间再输入；这些关闭产生的取消仍计入cleanup事件。
3. 刷新真实图层，先记录资源清理后状态；动画主体/道具层应为零。可保留静态背景层，最终关窗后再检查全部图层归零。
4. 在session拥有的ledger串行队列后排barrier，等之前已开始的持久化事务结束及主队列迟到回调处理。取消不退款；晚到授权不会复活已清理的core request。
5. 捕获不可变访客档案，在稳定visitors锁下按现有CAS持久化；不受周期flush重试节流导致退出漏保存。journal走既有终止flush。失败落盘，不伪称成功。
6. 保存最终资源与事件，恢复原observer链，关闭控制窗/测试overlay，移除状态项和隔离偏好域。仅清理默认应用域中包含本次唯一状态栏名称的键，并记录清理前后差异；不覆盖整个默认域，不恢复用户或并发实例的修改。写 `preference-isolation.json` 和summary后才允许退出。重复finish不再次取消或累计。

## 首次真实30秒smoke实际结果

主会报告第三轮Release构建耗时 **89.63s**、strict签名通过。本次真实运行输出为 `.build/m6h-smoke-initial`，进程退出码 **0**；只读核对该目录 `manifest.json`、`summary.json`、`telemetry.jsonl` 与 `verification.json`，离线结果为 **16/16通过**。本次文档更新未重新构建或执行任何测试。

manifest记录二进制为 `dist/ChirpOS.app/Contents/MacOS/Birding`，版本0.6.0（60）、simulationVersion 17、PID **63271**；SHA-256为 `ce7e23f099134f974cc92fb4129d4d2f0e6ad850170ac51b1bc978a13e342020`。请求30秒、目标12只；实际自然到达8只，未为达到目标补鸟。

| 指标 | 实际证据 |
| --- | --- |
| 结束原因与时长 | `durationReached`；清理前墙钟 **30.103703791668522s**，awake uptime **30.103703708329704s**；两项durationReached均为true |
| 模拟与生产tick | 模拟 **29.999999999999577s**；**1799**次tick；最大rawDT **0.034653208334930241s**；超过50ms/250ms/1s/10s均为0 |
| CPU | 自然终态进程累计 **1.328893s**、session增量 **1.173420s**；IO排空后分别为 **1.333399s / 1.177926s**。三个约10秒periodic区间CPU为 **3.486571% / 3.350565% / 4.260636%**（单核100%） |
| CPU口径限制 | naturalEnd及afterCleanup的相邻短间隔CPU字段分别为 **91.802561% / 107.102172%**；这是紧邻采样间的百分比，不能当作整个30秒平均CPU |
| RSS | 自然终态 **168,673,280 bytes**；采样峰值 **169,279,488 bytes**（本次IO排空后值）；仅是短时采样，不构成长期泄漏结论 |
| 自然状态与资源峰值 | 到达8、离开0；自然终态8居民/8活跃访客，run与租约均0；采样run峰值1、租约峰值1，居民/活跃访客峰值8 |
| 全量事件 | 共 **14**条、sequence缺口 **0**；自然终态已观察6条，清理再产生8条birdRemoved。分类：preen started 3、completed 2、cancelled/userInput 1，birdRemoved/removed 8；全部为automatic来源 |
| 清理 | IO排空后所有resourceCounts均0；`zeroResources`、`zeroDynamicLayersAfterRefresh`、`cleanupSucceeded`均true。刷新后剩2个静态层，关窗后total/masks/dynamicContainers/animations全部0 |
| 退出与flush | windowsClosed、timerStopped、mouseMonitorsStopped、visitorFlushSucceeded、journalFlushSucceeded均true；errors为空 |
| 实际文件 | settings/visitors/journal存在；legacy/gifts不存在。未发生自动礼物授权，不能据此声称真实礼物事务已被本次smoke覆盖 |
| 环境与观察限制 | 1个display、2个surface；暂停与sleep时间均0，sleep/wake次数均0。locked为null，unknownLockWallSeconds **30.103703791668522s**；不能将knownLocked=0解读为已解锁或有人观察 |

用户文件哈希证据为 `.build/m7a-delivery/user-data-after-smoke.json`：`settings.json`前后相同；`species.json`与`gifts.json`前后均不存在；`visitors.json`与`observations.json`哈希发生变化，报告明确 `unchanged=false`。主会记录旧安装app **PID 13106** 在此期间一直运行；现有前后哈希不能将变化归因于smoke，也不能据此认定由旧app造成，更不能写成“用户文件hash全通过”。未读取或改写用户草稿来补证。

本次manifest五个持久化路径均落在独立输出目录，preferences为独立suite，源码隔离审计通过；真实文件隔离哈希证据仍有限。另，summary两份状态中的 `statusAutosaveDisabled=false`，离线16项未单独验证该字段，不能把16/16扩展成状态栏偏好无写入的动态证明。

## 状态栏与默认偏好隔离修订（历史实现，复验见末节）

本机 SDK `NSStatusItem.h` 明确 `autosaveName` 为 `null_resettable`：未指定时自动选名，设为 nil 会重置自动名并清除保存信息。因此旧注释“无名称即不保存”以及 `statusAutosaveDisabled:(name==nil)` 的判据不成立；上述历史报告原样保留，不追加通过结论。

当前源码为每次运行生成一个 UUID：controller suite 为 `dev.birding.desktop.soak.<UUID>`，状态栏名称为 `ChirpOS.Soak.<UUID>`。创建状态项后、生产 `makeMenu` 之前赋值，并在生产 start 返回后检查实际名称一致。运行采样如实记录 `statusItemPresent`、`statusAutosaveName`、`statusAutosaveMode=sessionUniqueName`、`statusAutosaveIsolated`；`standardDefaultsRedirected=false` 明确 AppKit 默认域没有被 suite 重定向，不再输出误导性的 disabled 判据。

结束时先记录移除前实际名称，再移除状态项；只删除默认应用域中包含本次 UUID 名称的键。`preference-isolation.json` 记录本次名称、默认应用域、清理前后变化的键名、已删除/残留的会话键、生产名称及语言/种群偏好是否变化、suite 是否移除，并与 summary 内同一份记录对应。不会导出用户偏好值。任何清理后默认应用域差异、残留或名称不符都会令 `preferenceIsolationSucceeded` 和 `cleanupSucceeded` 失败并保留错误，不回写原快照来取得通过。

新离线检查保留原16项，另增加六项：隔离报告与manifest/summary一致；名称含合法且与suite相同的UUID；只清理本次键且无残留；默认应用域及生产偏好未变；suite移除及隔离清理成功；所有生命周期采样的实际状态项名称保持隔离。旧报告缺少本次证据，不能被新版检查补授状态栏隔离通过。

此审计只比较本进程启动前与清理后的默认**应用域**快照，不保证全局偏好域或进程退出后的磁盘状态。并发旧实例若改变同域键，也会报告差异；不能由此归因于 soak，更不能覆盖该变化。后续真实smoke还需审阅这些新字段；本次只完成源码、静态核对和文档，未构建、运行离线检查或触发系统UI事件。2h/8h与硬件验收缺口不变。

## 运行方式与尚待执行项

以下为运行方式；30秒复验已完成，8h首轮已启动、待收尾，2h人工观察尚未运行。每次必须使用全新绝对输出目录，直接启动二进制以保留其真实参数与终止路径：

```sh
"<候选.app>/Contents/MacOS/Birding" --soak-desktop /absolute/new/m6h-smoke --soak-duration 30 --soak-birds 12
"<候选.app>/Contents/MacOS/Birding" --soak-desktop /absolute/new/m6h-observe-2h --soak-duration 7200 --soak-birds 12
"<候选.app>/Contents/MacOS/Birding" --soak-desktop /absolute/new/m6h-soak-8h --soak-duration 28800 --soak-birds 12
```

主会已提供离线入口 `--verify-soak-smoke <folder> [--verify-soak-output <report.json>]`，位于NSApplication创建前。`SoakVerification.inspectCompletedSmoke(at:)` 是独立离线检查源码，不会启动应用或推进引擎；对真实30秒报告检查目录隔离、生产调度、真实CPU/RSS、事件全量计数、自然状态早于清理、零资源、flush和窗口释放。首次调用16/16通过，结果为 `.build/m6h-smoke-initial/verification.json`。其通过仅属于smoke，不能替代长跑或独立的用户文件隔离取证。

| 项目 | 当前状态 | 后续所需证据 |
| --- | --- | --- |
| 与M7a合批构建/签名 | 第三轮Release 89.63s、strict签名通过 | 本次结果不代表M7a整阶段验收 |
| 30秒真实桌面smoke及离线检查 | 首次退出0、16/16通过 | `.build/m6h-smoke-initial`中的manifest/JSONL/summary/verification |
| 状态栏UUID名称与默认应用偏好隔离修订 | 第四轮候选真实30秒及22/22检查通过 | `.build/m6h-smoke-status-isolation`；旧16/16不覆盖新增检查 |
| 控制窗关闭、应用菜单Quit | 2026-10-25两次实际退出，分别14/14离线检查通过 | `.build/m7-soak-close-window`、`.build/m7-soak-menu-quit`；不算2h/8h |
| 外部应用终止、启动中途失败清理 | 未运行 | 需各自独立目录与收尾证据，普通Quit不替代 |
| 用户数据与草稿隔离 | 独立持久路径与源码审计通过；实际文件哈希证据有限，非全通过 | settings未变，visitors/observations变化，旧安装PID 13106同时运行，变化不可归因；需可区分写入来源的证据，不得为验证读取或改写草稿 |
| 真实2h人工观察 | 未运行 | 解锁桌面、人工起止/观察记录；锁屏和不在场时段不能计算为观察 |
| 真实8h运行 | 默认工作负载完成并通过证据审阅 | 28800.112952秒、43836事件无缺口、28资源与图层归零；未发生场景不获长期覆盖 |
| 物理多屏/热插拔 | 用户明确无外接屏，未验收 | 2026-10-25按用户指示先完成单屏；虚拟screens不替代真实设备 |
| 系统sleep/wake | 未验收，需要用户真实操作 | 实际通知、时序与恢复状态；不能用调用sleeping/waking冒充 |
| 长期泄漏/能耗 | 未验收 | RSS/CPU趋势用于定位；需补充实际工具/环境证据，不能仅据零计数定论 |

本文件记录支持能力、首次smoke实际结果与待执行项；所有既有失败、硬件缺口和未安装状态仍保留。checkpoint不代表M6h或M7a整阶段通过；30秒自动到时退出不替代关闭控制窗、菜单Quit、系统退出、真实2h观察或8h运行。

## 补充隔离窗口与拒绝覆盖检查

第二次独立30秒真实运行`.build/m6h-smoke-isolation`退出0，离线16/16再次通过。紧邻启动/结束快照`.build/m7a-delivery/user-data-narrow-smoke.json`仍显示用户visitors/observations变化，settings/species/gifts的存在性和哈希不变；旧安装版全程并行运行，因此不能用此比对独立归因文件写入者，文件哈希全不变项仍不授予通过。会话manifest记录独立五路径，代码在启动持久化前注入这些路径；不修改用户文件来取得测试通过。

复用首轮非空输出目录的启动按预期退出1，并逐文件SHA256确认既有证据完全未被覆盖；结果`.build/m6h-reject-existing.json`。这仅验证拒绝非空路径，不等价于启动中途失败的完整收尾验收。

## 状态栏隔离修正后的真实30秒复验

第四轮M7b/c候选（SHA256 `7d3b5931971cd52d0aab5aa52abeee89f4419d6190ac834e0c260d07baaffcb6`）运行`.build/m6h-smoke-status-isolation`，退出0、实际墙钟30.109228秒，新增偏好检查后的离线22/22通过。每次UUID autosaveName在整个记录生命周期保持一致；结束后隔离suite已移除，本次状态栏键无残留，默认应用域与受保护生产偏好键的进程内前后快照没有差异，cleanupSucceeded=true且errors为空。原始证据为该目录的`manifest.json`、`telemetry.jsonl`、`preference-isolation.json`、`summary.json`及`verification.json`。

本轮用于验证已修正的名称隔离与清理，没有再次通过用户文件哈希碰运气消除此前归因限制；没有证明所有用户文件无写入、退出后磁盘状态或全局defaults隔离。桌面工具仍报告锁定，此次30秒工具运行不计入2h人工观察，不构成8h或M6h/M7d整阶段验收。

## 第八轮候选8小时隔离运行已启动

完整birds4593/4593、settings2190/2190退出0后，于北京时间 **2026-10-24 22:37:40**（UTC 14:37:40）启动真实8h运行，请求28800秒、默认12鸟；PID **75532**，证据目录`.build/m7-final-soak-8h-first`。若无退出/暂停/睡眠影响，预计北京时间2026-10-25 06:37:40以后收尾；以实际summary为准，不能预先判为通过。

运行的是第八轮冻结候选的独立bundleID副本`ChirpOS M7bc Final Verification.app`，SHA256 `6afc9007ca8664a04d1969c50d06a1cf9207854f28f26dd7009b8c00c0b18796`。其38个Mach-O代码/数据分区与冻结候选一致，二进制文件哈希因应用标识及签名重签不同。默认应用域为`dev.birding.desktop.verification.6dd53dfa-7516-49d0-b836-ab17463e8b32`，controller suite为`dev.birding.desktop.soak.EE4E1A5F-0C5B-48AA-8A6C-75C33D13B769`；五个持久化路径均位于本次输出目录。已安装M6a/b继续运行，没有关闭、替换或保存其草稿。

启动后100.112936秒样本记录12只自然到场、5996次生产tick、locked=true、sleep/wake均0，RSS为171917312 bytes；只是启动进展，不能外推长期趋势。默认设置不自动放置巢台/浴盆等场景，该样本nests/nestMaterials均0；本轮不能替未发生的新内容授予长跑覆盖。锁屏时间不计为人工观察，既有睡眠策略保持原状；最终必须分别审阅墙钟、awake uptime、模拟推进、tick缺口、实际sleep/wake与CPU/RSS趋势。

收尾后读取summary、全部telemetry/events和preference-isolation，检查持续时长、完整事件、隔离及资源释放。现有`--verify-soak-smoke`明确只接受30秒，不用于此8h目录，也不改报告把8h冒充smoke。用户已安排稍后解锁、先完成其他工作；安装和2h人工观察留待实际条件满足，M6h/M7d及总目标仍未完成。

## 2026-10-25安装与退出路径补验

第八轮候选已于北京时间05:52保护设置/草稿后安装重启；实际73熟客与250条旧手册记录保留，详见[M7d记录](M7D-ACCEPTANCE.md)。此前“未安装”保留为历史轮次状态。8h首轮会话21055/PID75532仍运行，不重启它来补测其他入口。

另复制第八轮产物，使用独立bundleID `dev.birding.desktop.exitverification.25486542-fe7c-4912-aaee-ad84f6a96b20` 验收退出；strict签名通过，比较36个有文件字节的Mach-O分区完全一致（零填充分区未计入此36项，不与此前38项口径混用），元数据`.build/m7bc-delivery/exit-verifier.json`。两个会话都请求7200秒，但在完成真实生产调度及自然到场后主动提前退出，不属于2h观察。

| 入口 | 目录 | 实际时长/自然终态 | 退出与证据 |
| --- | --- | --- | --- |
| CUA点击控制窗关闭 | `.build/m7-soak-close-window` | 49.290743秒、12居民、20条事件 | `controlWindowClosed`，退出0，14/14离线检查通过 |
| CUA点击应用菜单Quit | `.build/m7-soak-menu-quit` | 134.668132秒、12居民、75条事件 | `applicationTermination`，退出0，14/14离线检查通过 |

两次事件sequence完整且逐分类与summary一致；自然终态、清理、IO排空各记录一次且顺序正确；全部28个命名资源均存在并为0，关窗后total/masks/dynamicContainers/animations均0，timer/鼠标监听停止、访客与手册flush通过、suite和本次状态栏键清理通过、默认应用域无残留变化，errors为空。单独证据`exit-verification.json`。初次离线脚本误写资源数量32，导致该检查false；按源码明确的28个资源名称逐个验证后14/14通过，首次结果保留为`exit-verification-first.json`，未修改应用报告或重跑会话来抹掉历史。

工具边界：关窗退出后立即调用CUA读取同一app，会将已退出的验收副本重新以普通模式启动（PID82622）。发现后通过其真实菜单正常关闭；设置文件仍与安装前逐字节一致，但普通实例可能参与访客/观察写入，不能把整段工具操作宣称为全用户文件无写入。菜单Quit会话PID82652按唯一bundleID重新定位，确认7200秒控制窗和12居民后退出。此后终止状态用原exec handle和进程/summary核对，避免再次触发自动重开。旧长期会话与已安装版未被误退出。两次隔离会话的报告只证明其自身命名路径及默认域检查，不扩大为普通重开实例的隔离证明。

7h18分时的只读日志快照审阅在`.build/m7-final-soak-review-progress.json`，完整离线审阅脚本`.build/review-m7-soak.py`仅解析真实JSONL和summary，不推进模拟、修改运行或自动授予整体通过。待8h自然收尾后再生成最终结果。

## 8小时最终收尾与单屏限制（2026-10-25）

原PID75532/会话21055于06:37:40自然退出0，reason为durationReached；墙钟与awake均28800.112952秒。完整43836事件与summary一致，序列无缺口；自然12居民、4run/4lease在清理及IO drain后28命名资源全部归零，图层、窗口、timer、鼠标监听释放，持久化与偏好隔离成功，errors为空。独立9项运行与11项完成检查通过。RSS峰值171.671875 MiB，第2–7小时中位170.89–171.39 MiB，第8小时143.53 MiB，未见持续失控增长；不等同无泄漏或系统能耗结论。

本轮已知锁屏26445.430174秒，sleep/wake及暂停均0；不是2h人工观察或真实系统睡眠验收。默认负载没有场景注入，巢台/浴盆/赠礼等缺少实际发生证据，不能由8h补授覆盖。完整报告、图表和来源身份见[M7d最终记录](M7D-ACCEPTANCE.md)。以上较早“运行中”段落保留为历史状态。

用户确认没有外接屏，双屏/热插拔记无设备未验收。单屏准备时完成最新草稿保护、诊断重启和Finder拖动，但独立长跑副本的透明窗口干扰日常落稳；其退出后诊断恢复落稳。此时Mac已重新锁定，单屏窗口移动/关闭/全屏与菜单栏暂停恢复仍未完成，未以隔离handler或锁屏诊断替代。M6h/M7d整体仍待这些项目及2h人工观察。
