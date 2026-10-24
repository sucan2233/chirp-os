# M6a sideHop 失效诊断

2026-10-24。主会话已统一编译并完成全量测试：`SideHopDiagnosisTests` **15/15通过**，全量 **724/724通过、0失败**，包含新增2项局部证据测试及收紧的历史复现断言；日志 `.build/m6ab-tests-complete.log`。复现入口证据 `.build/m6a-sidehop-183.json` 精确命中历史事件。三组完整压力均通过，metrics、cleanup与M5n完全一致，long两摘要也保持一致，证据 `.build/behavior-stress.lKM5rN/`、`.build/m6ab-stress-comparison.json`。本子会话仅核对已有证据和更新文档，**没有自行编译、运行测试或原生检查**。侧跳直接退出原因已确认，上游鸟 23 的完整路线和所有权历史尚未被当前 JSON 记录，不能凭一次安全分类断言所有规划都正确。

## 历史证据与问题界定

已读取主规格 `BEHAVIOR-CONTENT-SPEC.md`、逐鸟矩阵、引擎设计第 34 节、`.build/m5n-stress-comparison.json`、`.build/behavior-stress.iCy1bv/long.json`，以及 SideHop、Stress、Runtime、LandingReservation、Bird 运动和世界更新实现。

历史失败唯一标识如下：seed **73**，12 鸟、2 屏、自主模式，run **183**，参与鸟 **27**，事件 **396**，模拟时间 **734.099999999661**，`sideHop / automatic / failed / targetInvalid`。M5n 比对文件记录该工作负载与 M5m 的 metrics、cleanup 完全相等。历史完整报告的 `eventDigest=ac9ebe59dd382b9a`、`stateDigest=338604c7a3e9e17c`；本次主会话完整long压力复验的两摘要与之相同。

历史 `passed=true` 只证明既有完整性、零超时、收尾规则通过；其中 `failedRuns` 允许因目标安全变化而增加，不能据此证明这次退出合法，也不能因存在一次 failed 就认定是 bug。代码仍发出原有 `failed / targetInvalid`，不改为 completed，不改变观察记录规则。

## run 183 实跑归因与可证范围

主会话结果 `expectedSideHopReproduced=true`，仍是同一 seed73/run183/bird27/event396/t734.1。主因 `birdIntrusion / safetyExit / executionValidation`，冲突鸟为 **23**。这是执行器实际走廊检查触发，不是 motion 异常被伴随几何覆盖：预期/实际 motionRevision 都为 **2**，鸟 27 仍 `flying`、`isSideHopping=true`、`needsDestination=false`，原始/当前宿主都为 ID110/PID701、矩形 `(105,100,2200,70)`，尺度都为 `0.9694896625527707`。本次 JSON 没有伴随安全问题字段。

从已保存矩形直接计算（只读 JSON 数值运算，未执行引擎）：

| 量 | 实际值（点） | 含义 |
| --- | --- | --- |
| 侧跳连续走廊 | `(256.884800,50.556027,138.637022,58.169380)` | 原起点、目标及当前脚位的连续包络 |
| 鸟23冲突包络 | `(196.353757,36.456382,67.676993,61.111994)` | 鸟体落点包络与渲染 bounds 的并集，再外扩8点 |
| 交集 | `(256.884800,50.556027,7.145950,47.012349)` | 面积约335.947889；不是零面积相切 |
| 去掉最后8点外扩的鸟23包络右界 | `256.030750` | 距侧跳走廊左界尚有 **0.854050** 点 |
| 侧跳目标预约左界（含8点余量） | `331.291421` | 距鸟23冲突包络右界尚有 **67.260671** 点 |
| 鸟27实际脚位 / 目标脚位 | `(292.431375,93.607081)` / `(367.406621,100)` | 还在短跳途中，没有误报已落稳 |

**直接结论：这是动态安全余量侵入导致的合法侧跳中止。** 去掉8点余量后仍有间隙，当前证据没有显示鸟体实际相撞；侵入发生在整段走廊靠原起点的一侧，远离目标预约。目标预约不是全路径空域租约，不能据此认定预约失效或两个 run 获得相同落点。整份报告最终 activeRuns、leases、reservations、ecologyMemories 都为0，且完整性通过；没有显示该次事件导致唯一终态或最终清理错误。

此结论只涵盖 SideHop 的本地退出保护。当前 JSON 没有鸟23的物种、state、facing、position、hostID/PID/fraction、motionRevision、runtime owner/kind、flightVelocity 或 plannedFlightFootprint，也没有准入时刻/前一安全 tick 的鸟23快照。因此不能确认它究竟是先有普通飞行、后新选路线，还是另一个已拥有鸟的执行器，也不能证明其具体目的地或某一次选路调用。

几何能提供一个**条件推断**：若按普通飞行且无姿态偏移来解释，`height=48×scale+20` 与 `width=58×scale+18` 都得到 `scale=0.8564998803758456`，与标准麻雀尺度一致，脚位约为 `(229.192253或231.192253,79.859877)`（左右方向有2点差异）。该值不是已观测的鸟23状态，更不能把几何反推的物种当成身份记录。

## 路线与预约为何允许这种情况

源码链路如下：

1. `SideHopPlan.safetyIssue` 检查其他鸟**当前位置包络**、普通到达的**目标脚点包络**、Runtime 的**落点预约**，以及其他 `LedgeTraversalExecution` 的**连续走廊**。它没有检查其他普通飞行的完整 `Bird.plannedFlightFootprint`。
2. `SideHopExecution.landingReservations` 只提供 `plan.destination`，没有起点到终点的 span/headroom。Runtime 管理的是落点预约间的互斥，不锁定整段侧跳空域。
3. `BehaviorEngine.plan(for:)` 传给 `DestinationPlanner` 的 `reserved` 也只有 `runtime.landingReservations[].footprint`。Planner 用它裁剪合法**终点区间**；其他鸟当前 host/fraction 也只贡献预测**脚点**，没有把完整已执行飞行或侧跳扫掠区当成全局空域约束。
4. 已开始的 `Bird.tick` 沿自己的路线前进，不会因后出现一个 SideHop 自动停车或重规划。引擎固定步先 Runtime 验证、再积分鸟运动；下一次验证可以发现进入保护余量的动态鸟，并按既有安全恢复契约中止侧跳。

所以“目标预约有效”和“另一只鸟之后途经走廊”可以同时成立。只看已保存事实，**未发现预约所有权或恢复 bug**；源码确实存在“已知普通飞行完整航路不参与 SideHop 准入”的预测覆盖差异。`FlightSceneEnvelope.isClear` 和 `AllopreeningPlan` 已读取普通鸟 plannedFlightFootprint，可作为增强方案的实现参考，但不能据此替当前 SideHop 擅自引入全局避碰承诺。引擎设计第19.2节的社交移动说明也明确没有全桌面全局避碰系统。

## 最小局部证据与待决增强方案

独立测试新增的以下两项，以及已有历史复现用例收紧后的鸟23侵入、executionValidation阶段、motionRevision均为2且无伴随证据的断言，均已由主会话统一验证通过，见 `.build/m6ab-tests-complete.log`：

- `testRecordedRun183GeometryShowsMarginIntrusionWithoutDestinationSlotOverlap` 固化实跑两矩形和目标脚点，使用实际 Geometry 计算交集，保留8点余量侵入、去余量仍相隔0.854050、目标预约相隔67.260671的证据。它不伪称恢复了鸟23路线。
- `testExistingUnleasedFlightDocumentsDynamicSafetyExitWithDistinctLandingSlots` 只用两只鸟：先为无行为 owner 的鸟安装实际直线飞行，起点距待跳鸟200点、目标在另一侧400点，随后用真实 `.sideHop(.preview)` 启动。当前位置和两落点相离，但既有飞行包络与跳跃走廊相交；不再写 position，只通过30/60/120Hz调用引擎固定步推进，要求动态侵入产生同类 safetyExit、motionRevision不变、释放单次run/租约/预约且不回传旧脚位。短 urgent 直线段只是缩短测试时间，**不是鸟23实际航路的复刻**。

两项分别证明实跑的保护边界，以及当前代码确实能在没有预约冲突时接受一个随后会遭遇动态飞行的跳跃。这是当前行为契约的特征测试；若主会话决定增强预测准入，应将第二项改为拒绝启动的回归要求，不能同时保留矛盾预期。

若需要继续严格回答“鸟23当时究竟由谁选了哪条路线”，建议先补一轮**只读诊断**，不修改共享引擎：在 SideHop 的准入和失败样本中记录冲突鸟的 ID/species/state/position/velocity、host+fraction、motionRevision、owner run/kind、plannedFlightFootprint；每个活动 hop 仅保存准入和最近一次安全快照，终态输出后释放，不保存无界历史。然后由主会话重跑575秒，区分路线在 hop 前已存在，还是在 hop 后改变。当前本轮只改测试/文档，没有擅自实施该诊断扩展。

若产品要求**避免可预见的既定路线让行失败**，建议主会话决定以下方案后再改行为：

1. 最小局部增强：SideHop 准入对已 flying 的其他鸟读取 `plannedFlightFootprint`，复用8点安全余量检查；不可取得包络时保守拒绝。仍保留动态取消。缺点是完整航路 AABB 较保守，可能多拒绝；还要明确是否将此共享几何检查同步用于 EdgePeek。
2. 只有补证确认“hop之后的新路线进入应保护区域”、并要求双向路径互斥时，再另行授权共享引擎/Planner：把活动 ledge traversal 的完整空间保护提供给**路线可行性验证**，不能仅把额外矩形塞进终点区间裁剪就声称路径已避让。必须有新普通路线、已飞行鸟、跨越原起点和两个先后启动顺序的回归。
3. 任一行为增强都会改变接受率、后续随机消费和旧事件摘要，应由主会话明确语义版本/夹具更新策略；本次诊断不偷改M5n基线，也不把targetInvalid改成成功。

目前不建议为消除这一个 failed 指标直接改共享规划器。现有证据足以确认本地动态安全退出；对上游的可预测性增强及鸟23具体路线还需要上述补证和产品边界决策。

## 证据捕获与分类

`BehaviorRuntime.validate` 先检查目标预约合法性及预约间冲突，再调用执行器验证。失败时先 detach run/ownership，再调用 execution.cancel，最后发出 terminal event。`BehaviorEngine.updateWorld` 又会在 Runtime 验证前先调用 Bird.updateHost，后者可能已经取消无效运动。

因此只在终态观察器里查询 Runtime、或者取消后查询鸟的运动，都可能错失原因。本实现采取以下路径：

1. SideHop 沿既有几何判定顺序返回第一条具体 `SafetyIssue`；`isSafe` 仍判断同一结果。没有新增随机调用，也没有改变候选集合、探测距离、遍历顺序、运动积分或调度时钟。
2. 执行器在自身失败处锁存 `SideHopDiagnostic`。`cause` 始终是实际触发的 guard，`classification` 只由该主因决定；伴随几何问题另存到可选 `accompanyingSafety`，包含独立原因、冲突对象和矩形，不覆盖主因。Runtime 提前判定预约失败时，在 cancel 中、实际取消鸟运动之前补捕获。锁存后不再覆盖。
3. Runtime 对双方预约都加 8 点余量，可能在 SideHop 未加余量的走廊仍清晰时提前发现冲突；cancel 的补捕获显式检查这条真实 Runtime 预约规则，避免把余量重叠归成 unknown。
4. Stress 观察器仅保留活动 SideHop 执行器引用，在终态读取锁存证据后移除。失败样本仍最多 32 条，超限累计计数和 omittedSamples。没有全事件录制或无界历史。

证据包含原因、捕获阶段、模拟时间、鸟 ID/状态/实际脚位、取消前是否仍在侧跳、目标请求状态、预期/实际 motionRevision、原始/当前宿主矩形、宿主 ID/PID、起终 fraction、目标脚点、尺度、连续走廊，以及冲突鸟/表面/run ID 和冲突矩形。异常的非有限可选几何输出为 nil，避免诊断本身破坏 JSON 编码。旧 M5n 样本缺失 `sideHop` 字段时读取为 nil。

| 分类 | 原因 | 能证明什么 |
| --- | --- | --- |
| `safetyExit` | 宿主缺失/复用/变形、尺度/显示布局变化、走廊出屏、落点失效、遮挡、其他鸟进入、普通到达目标占用、预约/走廊冲突 | 当前几何或资源安全条件不成立；退出本身符合该安全保护 |
| `invariantViolation` | Runtime 已接受但运动未能启动；前置状态成立但宿主跟踪被拒绝 | 执行契约存在不一致，必须按 bug 调查 |
| `unresolved` | 实际触发 motionRevision/状态 guard、无法归因 | 即使同时存在鸟侵入等几何问题，运动异常仍是主因，不能声明安全退出 |

`safetyExit` 描述保护条件，并不自动证明所有上游规划正确。例如另一只鸟的普通路线若错误进入已保护区域，侧跳退出可以是安全的，但仍应调查规划器为何允许侵入。需结合冲突对象、几何与资源证据区分外界环境变化和预约/恢复 bug。

Review 修正：原 `invalid` 优先采纳 `plan.safetyIssue` 会把实际 motion guard 误覆盖为安全退出，已改为主因/伴随证据分别保存。宿主元数据更新若已取消运动并改变 motionRevision，且 Runtime 的预约预验证仍通过，后续触发的主因也是 `motionRevisionChanged / unresolved`；宿主尺寸/尺度变化仅作为伴随证据，不能据此替代运动主因。该修正及另外新增的两项证据测试均已包含在主会话15/15诊断、724/724全量通过的最终验证中。

## 两层复现

历史 workload 的 warmup 固定为 160×60 tick；`engine.time` 每个固定步都增加，即使暂停。目标在 active 约 574.1 秒。新 `BehaviorStress.m5nSideHopConfiguration` 保留同一 seed、鸟数、屏数、160 秒 warmup、全部 active 命令/随机消费、0.1 秒世界采样及正常 drain，只将 active 截短为 **575 秒**。主会话实跑已确认该截短工作负载精确复现，不声称已证明绝对最短输入。

主会话完成统一构建后，在项目根目录运行：

```sh
dist/ChirpOS.app/Contents/MacOS/Birding \
  --stress-behavior .build/m6a-sidehop-183.json \
  --stress-sidehop-case m5n-183
```

等价的显式 workload：

```sh
dist/ChirpOS.app/Contents/MacOS/Birding \
  --stress-behavior .build/m6a-sidehop-explicit.json \
  --stress-seconds 575 --stress-birds 12 --stress-displays 2 \
  --stress-seed 73 --stress-mode autonomous
```

case 入口必须命中上述**全部事件身份**并包含诊断证据，才将 envelope 的 `expectedSideHopReproduced` 写为 true；未命中时仍保存报告，CLI 退出 1。可以追加 `--stress-seconds 3600` 重放完整历史负载，其他鸟数/屏数/seed/mode 的组合会被明确拒绝。普通显式 workload 入口仍沿用原来的完整性通过规则。

第二层是 `SideHopDiagnosisTests` 的单鸟/双鸟局部复现：真实 `.sideHop(.preview)` 启动、实际 tick 推进、真实世界更新引入遮挡/入侵、通过 Runtime 释放并检查终态；这些局部场景用于隔离安全条件，**不是对 run 183 根因的预设**。启动契约、运动替换和状态异常的故障注入明确标注，用于证明诊断不会把内部不一致或并发异常归成安全退出。

统一测试命令（主会话已完成全量验证，以下保留为局部复验入口）：

```sh
swift test --filter SideHopDiagnosisTests
swift test --filter SideHopTests
swift test --filter BehaviorStressTests
```

主会话应沿用项目既定完整验证流程；这些命令不代替全部套件。新增测试覆盖：

- 连续拱形走廊与细遮挡刚好接触、深入 `0.001×scale` 的真实边界；0.5×/1×/2×、左右方向、负坐标屏。
- 外来鸟在连续走廊边界相切及深入 0.001 点，暂停/未暂停下立即安全释放；区分实体入侵与远处普通飞行的未来落点冲突。
- Runtime 提前发现目标落点遮挡，以及仅双方预约余量重叠的分支，均在取消前留下具体证据。
- 宿主删除、PID 复用、尺寸/尺度/显示器/工作区变化，经过真实 Bird.updateHost 和 Runtime 验证。
- 30/60/120Hz 安全完成时事件一致且没有失败诊断。
- 未授权的运动替换保留 `unresolved`，不取消新的运动；启动契约故障保留 `invariantViolation`。
- 运动版本异常/运动状态异常各自与鸟侵入同时发生时，主因仍分别是 `motionRevisionChanged` / `motionStateChanged`，分类为 `unresolved`；鸟侵入证据仅进入 `accompanyingSafety`，取消回调不能覆盖主因；新字段 JSON 往返及缺失字段兼容。
- 失败样本离开 256 条事件环后仍存在；32 条诊断上限；JSON 往返、旧样本兼容；有/无诊断的事件 digest 与计数一致。
- 真实 seed 73 截短 workload 必须命中 run183/bird27/event396/t734.1，并提供非 unattributed 的证据及最终零资源残留。

## 主会话验收与未决项

1. 主会话最终统一验证：诊断15/15、全量724/724通过，均为0失败；覆盖新增2项证据测试与收紧的历史断言。日志 `.build/m6ab-tests-complete.log`。这不是对全部原生或长期桌面验收的声明。
2. case 入口已实跑，直接失效主因确认是鸟23进入8点安全余量。其完整路线和owner未被当前JSON记录；补证和可选预测增强方案见上文。当前切片没有修改 BehaviorEngine、Runtime、Bird 或共享事件类型。
3. 主会话已完成三组完整压力：ordinary（600秒、24鸟、2屏）、crowded（600秒、64鸟、4屏）、long（3600秒、12鸟、2屏、自主模式），全部通过；各组metrics、cleanup与M5n完全一致。完整long的eventDigest仍为`ac9ebe59dd382b9a`、stateDigest仍为`338604c7a3e9e17c`。新证据 `.build/behavior-stress.lKM5rN/`，对比结果 `.build/m6ab-stress-comparison.json`，M5n基线 `.build/behavior-stress.iCy1bv/`。新增诊断仅是输出；上述一致性来自相同完整负载比较，没有用575秒截短负载替代3600秒摘要。
4. `expectedSideHopReproduced=true` 只确认历史事件被复现和捕获，仍须审阅分类。不得把 CLI PASS 宣称为“根因已确认”“已修复”或“零行为失败”。

本切片写范围只有 `Behavior/SideHop.swift`、`Behavior/BehaviorStress.swift`、`Birding/BehaviorStressCLI.swift`、独立 `SideHopDiagnosisTests.swift` 与本文；没有提交。共享工作区其他素材、配置、姿态实现的并发改动保持原状。后续全 M6/M7 授权不改变本切片职责范围。
