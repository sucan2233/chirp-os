# M7a 珠颈斑鸠求偶展示验收记录

状态（2026-10-24）：本批**阶段通过，已本地提交`906d7e9`，尚未安装**。基线为`ce8b390`；第三轮Release及严格签名、第二轮定向求偶、第三轮完整birds、第四轮定向核心、第二轮完整settings及18/18性能对照均通过，候选已冻结。累计159鸟体帧/10道具，剩8/6。首轮952 tests的失败历史保留，不称全量核心单次全绿。最初仅完成素材与静态源码核对时的“未验证”状态作为历史保留；硬件与真实长跑仍未验收。用户安装版仍为M6a/b。

## 本批素材与几何合同

仅珠颈斑鸠`spottedDove`追加五张独立绘制帧；旧48帧作为完整前缀，新增索引48–52，总53帧。其余45种鸟图集、家燕/白眉捕虫及灰喜鹊赠叶素材保持既有路径；首轮导出对照已确认46鸟旧像素不变、恰增斑鸠5帧。本批无新道具；阶段通过后累计159鸟体帧/10道具，剩8/6。

逻辑画布48×48，斑鸠原生64×64；固定脚锚`(29,39)`。独立语义层为`body/feet/headNeck/bill`，完整绘制按此顺序叠加。躯干、折翼和尾姿各帧独立变化；前倾时颈面连接肩胸与转动头部，黑色颈斑及五个白点通过同一颈面映射。脚部沿用原stand绘制几何，头颈不进入脚平面；不是旧stand/idle改名或整体平移鸟图。

| 帧 | 右向真实喙尖（48逻辑） | 左向`x→48−x` | 素材作用 |
| --- | --- | --- | --- |
| `courtRaise` | `(39.5,13)` | `(8.5,13)` | 抬胸、伸颈、上提喙尖 |
| `courtBow0` | `(41,24)` | `(7,24)` | 身体与头颈共同前倾 |
| `courtBow1` | `(41.5,30)` | `(6.5,30)` | 深鞠躬、躯干压低、尾部抬起 |
| `courtBowRecover` | `(40,19)` | `(8,19)` | 头胸回升、保持展示后的独立恢复姿态 |
| `courtObserve` | `(38.5,16)` | `(9.5,16)` | 观看者转头，改变头宽、眼位和颈斑投影 |
| 复用`stand` | `(40.5,17.5)` | `(7.5,17.5)` | 由原通用绘制的头、喙几何同源求解 |

喙尖由头部旋转矩阵和实际喙多边形求解；表中不是另行估计的吸附点。左右世界坐标使用`PoseClip.Anchor.world`，喙与脚参考点同时镜像。完整转身画布并集宽58×有效鸟缩放，双方并集间留12个**桌面点**；12不随worldScale缩放，准入由core的`CourtshipGeometry`负责。

## 接口、时序与导出

- `CourtshipArtGeometry.pose(species:frame:)`、`billAnchor(species:frame:)`提供新五帧几何及五帧+stand喙锚；其他物种返回nil。
- 内部`CourtshipPoseAnchors.anchor(species:frame:)->PoseClip.Anchor?`接入`PoseClip.beakAnchor`；旧增强姿态继续走原锚点路径。
- `DetailedBirdArt.courtshipImage(_:species:part:)`与`courtshipBillAnchor(_:species:)`由`make/poseImage/poseBillAnchor`分发。`BirdArt.courtshipNames`来自共享profile五帧清单，末尾追加到斑鸠图集。
- `PoseClip.courtship(species:role:)->PoseClip?`接受`.initiator/.observer`，仅斑鸠可用；双方均要求完整五帧+stand，固定脚、单次播放、恢复引擎当前状态。
- `CourtshipArtVerification.run(into:folder:)`写入`courtship-art/report.json`、左右原生源图/四层联系表和六张双鸟缩放预览。`--verify-courtship`另接平台实际双鸟与设置验收；完整birds和M6内容入口也接素材检查。

两个角色采样同一run age：朝向0.4s→抬身0.5s→两轮各1s鞠躬→观察0.5s→恢复0.6s，共4s（执行器硬上限6s）。每轮鞠躬为`courtBow0 .35 / courtBow1 .40 / courtBowRecover .25`。观看者只在2.9–3.4s使用`courtObserve`，其余阶段stand；发起者在观察/恢复阶段保持`courtBowRecover`，结束释放后由引擎恢复。所有五张专用帧均会被两角色合计实际采样。

共享manifest新增`courtshipInitiator/courtshipObserver`两个clip，仅斑鸠新增`courtshipBeakAnchors`（五帧+stand），通用`beakAnchors`追加五帧。parity保留旧34公共帧及所有旧可选前缀的严格期望，检查斑鸠53帧、真实喙锚、角色序列/时长和仅斑鸠授权。

GIF仍为13鸟×三缩放×双向=78份，旧文件名保留，每份100帧、loop=0；斑鸠现有六份增加相向双角色panel，与生产clip同源。预览尾部0.35s站立间隔仅用于展示循环，不是生产阶段。联系表与静态pair预览不能替代实际连续CALayer/时间戳审查，尤其0.5×下颈部斑点和观看者转头是否可辨。

## 统一验收状态

主会已接Engine/Runtime/scheduler，平台已接原生与设置入口；接线完成不等于运行验收。模拟源码当前为v17，文件格式仍为1；以下只记录已取得的实际结果，修复尚待补验不计通过。

| 检查 | 必须保留的证据/范围 | 本批结果 |
| --- | --- | --- |
| Release / 严格签名 | 全部代码实现后统一构建与候选签名 | 第二轮66.92s、第三轮89.63s Release均通过，严格签名均通过 |
| 核心 | 双角色4s、完整五帧、准入/随机流、任一方中断、取消/暂停/恢复、24/64工作负载与零残留 | 首轮952 tests、7 failures（1 unexpected）、191.731s保留；定向核心第二、三轮各32 tests/1 failure，第四轮32/32通过、9.922s；不称全量单次全绿 |
| 素材 / 图集 | 五独立姿态、四层重建、斑点连续、脚位、描边边界；46鸟旧像素/索引逐帧对照、恰增斑鸠5帧、道具不变 | 首轮art 50/55，5项颜色空间误判修复后，第二轮定向求偶250/250全通过。46鸟旧像素不变、恰增5帧对照通过 |
| 导出 / parity | 共享图集/metadata/support、旧78文件名、78 GIF/7800帧/loop0 | 已确认78 GIF、7800帧、loop=0检查通过；其余项目按实际报告记录 |
| 完整birds / 原生 | 0.5×/1×/2×双向两角色真实图层、脚位不滑、遮挡/点击、中断与自然完成 | 首轮旧FoodTray因userInput退出；第二轮spottedDove 2×因live pointer无安全走廊退出；第三轮3615/3615全通过。定向求偶native首轮98/98通过，第二轮定向求偶合计250/250通过 |
| 设置 / journal | 中英控件、支持物种、社交总开关、明确拒绝、preview来源、唯一自然记录；隔离控制器不改用户设置 | 定向求偶settings首轮97/97通过，第二轮定向求偶合计250/250通过；完整settings首轮2051/2052，唯一旧起飞准备预览因userInput失败；第二轮2052/2052 PASS |
| 回放 / 历史兼容 | v17当前全部夹具30/60/120Hz完整报告，旧19份与基线比较并明确是否剔字段 | 60份跨率完整报告通过；旧19份报告与M6g完整一致 |
| 视觉 | 源联系表、真实连续PNG/GIF和原始时间戳；小尺寸辨识边界如实记录 | 已实际查看0.5× forward、1× forward、2× mirror连续原生图及中英controls；不据此扩称所有方向/缩放均已逐图视觉验收 |
| 性能 | 冻结基线同机三轮两版本三场景18次，metrics/cleanup与p50/p95/p99；范围为加速核心工作负载 | 18/18全通过；ordinary/crowded/long medianP50相对M6g分别为−0.6410%/+1.1013%/+5.4462%，metrics与cleanup均一致；不覆盖原生渲染或长期堆内存测量 |
| 安装 / 硬件 / 长跑 | 未安装；物理多屏/热插拔、真实sleep/wake、2h/8h与长期内存/能耗 | 未验收 |

初始历史：素材owner交付时仅做静态源码核对，未自行构建、测试、导出、运行原生或提交；其后由主会统一执行，实际结果更新于本表。M6g最新独立补验275/275通过记录保留在[M6G-ACCEPTANCE.md](M6G-ACCEPTANCE.md)，不因M7a草稿更改历史状态；M6h真实长跑与硬件界限按其独立证据验收。M7a不引入雌雄、配对/繁殖成功、叫声或飞行求偶，也不提前实施M7b/M7c。

## 主会统一验证命令（原始计划）

以下保留统一验收开始前的命令计划；不能据此推断每个入口当前均未执行或均已通过，真实结果按轮次记录。主会可沿用自己的冻结候选路径和日志命名，运行native前应保证真实桌面/指针安全走廊可用，且所有鼠标键保持释放。

```sh
CHIRPOS_DEVELOPMENT_BUILD=1 CHIRPOS_APP_PATH="$PWD/.build/m7a-delivery/ChirpOS Dev.app" bash scripts/build.sh
codesign --verify --deep --strict --verbose=2 ".build/m7a-delivery/ChirpOS Dev.app"
swift test
".build/m7a-delivery/ChirpOS Dev.app/Contents/MacOS/Birding" --verify-courtship .build/m7a-courtship-initial
".build/m7a-delivery/ChirpOS Dev.app/Contents/MacOS/Birding" --verify-birds .build/m7a-birds-initial
".build/m7a-delivery/ChirpOS Dev.app/Contents/MacOS/Birding" --verify-settings .build/m7a-settings-initial
".build/m7a-delivery/ChirpOS Dev.app/Contents/MacOS/Birding" --export-shared shared
".build/m7a-delivery/ChirpOS Dev.app/Contents/MacOS/Birding" --export-pose-previews .build/m7a-delivery/pose-previews
python3 scripts/test-species-parity.py
```

`swift test --filter Courtship`可作为故障定位或定向复验入口，不能替代全量结果。图集历史像素/索引、GIF解码、完整跨率/旧报告及同机性能对照均由主会既有验收流程执行；后续把真实结果、路径、轮次和失败修复逐项追加于本表，不把未执行项或修复待补验项记为通过。


## 统一验证开始后的实际记录

首轮Release的BirdingCore编译通过，平台`CourtshipSettingsVerification.swift:142`复杂布尔表达式触发Swift类型检查超时。主会拆为visible/accessibility/enabled独立值；同时清理未使用name、多余try和scope末尾defer三个警告。第二轮Release成功（66.92s），开发包严格签名检查通过，日志`.build/m7a-build-initial.log`及`.build/m7a-build-second.log`。随后开始全量核心、完整birds与导出；尚未得出本批通过结论。

首轮全量核心共952 tests，7 failures（1 unexpected），耗时191.731s；全部失败集中于`CourtshipAdmissionTests.testLegacyFoodTrayFixedPerchAndRealAuthorizedGiftAreBusyInBothDirections`。该夹具已修，尚待补验，原始失败不改记为通过。

首轮`--verify-courtship`合计245/250：native 98/98、settings 97/97全部通过；art 50/55，5项为颜色空间误判，检查已修待补验。定向通过不能替代完整birds尚未覆盖到的M7a入口。

首轮完整settings为2051/2052，唯一失败是`passiveMotionSavedEnabledPreview-en-takeoffPreparation`，证据为`.build/m7a-settings-initial/report.json`及`passive-motion-settings-34169025-C75D-491D-BD7A-E5CE059DFF65/preview-en-takeoffPreparation.json`。该截图配套JSON的实际提示为`Release the mouse button and try again.`，对应生产`.userInput`拒绝。旧夹具虽先`syncWorld(buttonsDown:false)`，真实按钮handler仍会再次`syncWorld()`并读取`NSEvent.pressedMouseButtons`；因此不是英文期望文案或保存状态改变。

首轮完整birds在旧FoodTray夹具`treeSparrow-scale-2.0`生产放置拒绝后退出，尚未执行M7a。日志为`.build/m7a-birds-initial.log`，详细证据为`.build/m7a-birds-initial/food-tray-598A5BF6-1743-465A-84E3-2CB385F2EE01/food-tray-evidence.json`。事件显示：1×第三次访问在模拟时间35.4333s因`userInput`取消，随后2×放置同样因`userInput`拒绝，发生在几何检查之前，不能归因为`noSpace`。报告还记录该次访问的完整流程、扣一份食物、返回原脚位三项失败，与中途取消一致。对照`ce8b390`，两处旧夹具及其相关生产准入和平台输入同步路径未变，未发现M7a导致这些失败的证据。主会将在同一安全指针位置、所有鼠标键释放后统一补跑；2×食盘几何及完整birds后续覆盖仍待确认。

首轮导出对照确认46鸟旧像素不变、恰增斑鸠5帧；78份GIF共7800帧且loop=0检查通过。60份跨率完整报告通过，旧19份报告与M6g完整一致。上述结果分别保留其实际验收范围，不补写尚未完成的性能、安装、硬件或长跑结论。该次记录时第三轮构建及定向tests仍在运行，未纳入当时结果；后续结果按轮次追加如下。

### 后续统一补验记录

第三轮Release成功，耗时89.63s，严格签名检查通过。第二轮`--verify-courtship`为250/250全通过，首轮art颜色空间误判的修复已完成补验；首轮245/250历史保留。

完整birds第二轮在`spottedDove` 2×夹具因live pointer找不到安全走廊而退出；第三轮3615/3615全通过。前两轮退出仍保留为真实历史，不将其记为通过，也未为补验放宽生产规则。

定向核心第二轮32 tests、1 failure，失败位于第185行：夹具错误预期未被拾取的available叶片应被删除。第三轮仍为32 tests、1 failure，失败位于第201行：remove后的正常0.2s淡出尚未等待完成。主会补充retired断言，并`advance(.25)`等待淡出后，第四轮32/32通过，耗时9.922s。以上为夹具预期与等待时序修正，无生产规则放宽；首轮全量952 tests、7 failures（1 unexpected）、191.731s结果继续保留，定向补验通过不等于全量核心单次全绿。

视觉方面已实际查看0.5× forward、1× forward、2× mirror连续原生图及中英controls；该记录仅覆盖已查看的画面，不扩大为全部六组逐图视觉结论。该次记录时完整settings第二轮仍在运行，未纳入当时结果；未安装及硬件/长跑限制维持不变。

完整settings第二轮2052/2052 PASS，日志`.build/m7a-settings-second.log`，报告`.build/m7a-settings-second/report.json`。首轮2051/2052及userInput证据继续保留。该次记录时性能尚在运行，未计入当时结果；最终结果追加如下。

### 最终性能与冻结候选

最终性能同机三轮、两版本、三场景共18/18全通过，报告为`.build/m7a-performance/summary.json`。相对M6g，ordinary/crowded/long的medianP50变化分别为−0.6410%、+1.1013%、+5.4462%；三场景metrics与cleanup均一致。报告范围明确为加速核心工作负载，不包含原生渲染性能或长期堆内存测量，不能替代真实长跑验收。

M7a据以上实际结果记为阶段通过，累计159鸟体帧/10道具，剩8/6。冻结候选为`.build/m7a-delivery/ChirpOS Dev M7a candidate.app`，SHA-256为`ce7e23f099134f974cc92fb4129d4d2f0e6ad850170ac51b1bc978a13e342020`；同目录验收汇总为`.build/m7a-delivery/validation-summary.json`。阶段通过保留所有首轮失败及定向补验历史，不改称全量核心单次全绿。

候选尚未安装；物理多屏/热插拔、真实sleep/wake、2h/8h长跑与长期内存/能耗仍未验收，M6h独立长跑范围维持原有边界。
