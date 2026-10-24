# M7b/c 珠颈斑鸠运材与整理验收

状态（2026-10-25）：**M7b/c阶段验收通过，已安装并重启**。基线`906d7e9`（M7a已验收提交）。第八轮候选巢台专项1116/1116、完整birds4593/4593与settings2190/2190通过，以下保留每轮失败和修正证据。M7b与M7c合批实现，全部代码、素材、夹具完成后由主会统一构建和验证；运输与整理分别证明。累计完成167张新增鸟体姿态和16张道具；2026-10-25已完成实际设置/草稿保护、安装重启及持久化核对，见[M7d记录](M7D-ACCEPTANCE.md)。2h人工观察、8h运行及物理硬件验收不包含在本阶段通过结论中。

## 冻结素材与接口

仅`spottedDove`新增8鸟体帧。53旧斑鸠帧保持完整前缀，新增索引53–60，总61帧；公共34帧及其他45鸟旧像素/索引必须保持。每帧48×48逻辑、原64×64像素，脚锚`(29,39)`，独立`body/feet/headNeck/bill`四层；枝条单独绘制，不烘焙到鸟身。颈斑随颈面映射，躯干、折翼、尾姿独立变化。M7a既有绘制和五个喙锚不重画。

| 阶段/帧 | 右向真实喙尖 | 左向镜像喙尖 |
| --- | --- | --- |
| M7b `carryLook` | `(40,19)` | `(8,19)` |
| M7b `carryLower` | `(40,31)` | `(8,31)` |
| M7b `carryGrip` | `(40,39)` | `(8,39)` |
| M7b `carryPlace` | `(40,39)` | `(8,39)` |
| M7c `nestPlace` | `(40,26)` | `(8,26)` |
| M7c `nestAdjust0` | `(40,39)` | `(8,39)` |
| M7c `nestAdjust1` | `(41,39)` | `(7,39)` |
| M7c `nestSettle` | `(40,39)` | `(8,39)` |

`NestArtGeometry.pose(species:frame:)`提供上述8个独立姿态；`billAnchor(species:frame:)`还覆盖`fly0…7/land0…2/glide0…2/bank0…2/bound/stand`共19张真实复用帧。复用锚读取原通用绘制的头部、喙、躯干与外层飞行变换，不能手抄估值；普通stand右向`(40.5,17.5)`。`NestPoseAnchors.anchor(species:frame:)`转接`PoseClip.nestBeakAnchor`及`beakAnchor`。旧`carryBeakAnchor`资格不扩展，斑鸠不会因此获得麻雀leafCarry或小树枝访问资格。

道具预算恰6张，全部独立worldScale，不随carrier.relativeScale改变：

| 文件 | 画布/接触合同 |
| --- | --- |
| `twigToken.png` | 16×16，真实横向长16；grip`(3,12)`、surface`(8,12)`，含边框的真实polygon底部y12 |
| `nestPlatform.png` | 144×48，contactAnchor`(72,24)`、contactY24，材料支撑点`(60,24)/(72,24)/(84,24)` |
| `nestMaterialTray.png` | 32×16，contactAnchor`(16,12)`、contactY12，库存材料支撑点`(8,12)/(16,12)/(24,12)` |
| `nestOverlay1/2/3.png` | 各144×48；空状态0复用底图，1–3为完整、稀疏浅盘覆盖层，承载面始终y24 |

材料盘与巢台中心横距120逻辑点（乘worldScale），左优先、右备选，整组同屏且依托合法宿主。盘底图不带库存枝条；待整理材料也不烘焙进overlay。覆盖层只表示已经原子整理提交的进度，三根实际材料仍满足唯一状态与数量守恒。本阶段通过后累计167张新增鸟体帧/16张道具，素材预算剩0/0；整个M6/M7目标仍有安装与真实长期/硬件验收未完成。

## twig变换与接触

`TwigGeometry.logicalSize/grip/surface/polygon`是绘制和几何唯一来源。polygon含边框，以填充定义，不增加越界的居中描边；左右对称轮廓使右向原图夹点x3与左向对应夹点x13都是真实枝体位置，夹持前后不改变已放置轮廓。

`transformedPolygon(position:anchor:worldScale:facingRight:rotation:)`、`bounds(...)`、`sweptBounds(...rotationRange:)`使用原图anchor作为position所指世界点；先镜像相对anchor的x，再旋转。`canvasBounds/sweptCanvasBounds`另提供完整透明画布包络。旋转区间通过各顶点正弦/余弦的内部极值求边界，不仅比较区间两端，也不靠离散抽样决定生产包络。拾取/放下rotation=0，运输是否转枝以执行器冻结值为准，不能凭空增加旋转。

设W=worldScale、B=worldScale×斑鸠relativeScale、P为材料surface世界点，接触时：右向脚`(P.x−5W−11B,P.y)`，左向脚`(P.x+5W+11B,P.y)`。`TwigGeometry.gripPoint(surfacePoint:worldScale:facingRight:)`提供真实夹点。喙和脚参考点同时经`PoseClip.Anchor.world`镜像。巢台的单鸟槽不等于强行固定同一个落脚x；按选中材料/朝向求脚位，y承载面不变。

带枝包络必须覆盖四carry帧、19复用帧、两朝向及实际角度区间；翼、尾与枝条只允许真实喙部夹持区相交。`ScenePropRenderState.rect`的twig分支须使用同源polygon边界，渲染纹理仍按16×16原画布与anchor定位，不能把纹理压缩到较矮的墨迹包络。真实生产CALayer与全路线安全另验。

## clip、素材检查与导出

- `PoseClip.nestMaterialPickup(species:)`：`carryLook .4 / carryLower .3 / carryGrip .2 / carryLook .3`，共1.2s，0.7s进入原子拾取。
- `PoseClip.nestMaterialPlace(species:)`：落稳后`carryPlace .4 / carryLook .3`，共0.7s；使用真实地面接触，不复用灰喜鹊空中释放。
- `PoseClip.nestBuild(species:)`：`nestPlace .3 / (nestAdjust0 .3 + nestAdjust1 .3)×2 / nestSettle .4 / nestPlace .3`，共2.2s；1.9s压实结束、抬身前由执行器原子提交。
- 三个clip固定脚锚、单次播放、currentEngineState恢复；safe exit、库存与进度不由clip计时替代。
- `NestArt.image()/trayImage()/overlayImage(progress:)/twigImage()`；progress0及越界值返回nil，不产生第七张道具。
- `NestArtVerification.run(into:folder:)`输出`nest-art/report.json`、左右四层联系表、六张接触预览和六道具/四进度联系图。仅验素材与接触几何，不能冒充运输/整理native验收。

共享图集在斑鸠旧53帧后追加carry4再build4；metadata新增`nestMaterialPickup/nestMaterialPlace/nestBuild`与`nestBeakAnchors`（8新帧+19复用帧，共27项）。共享道具manifest新增六图的尺寸、接触点、真实polygon与进度元数据；原叶片、昆虫、浴盆等合同保留。

GIF沿用13鸟×三缩放×双向=78个旧文件名、每份100帧、loop0。只为斑鸠增加带独立twig的运材源姿态循环和整理进度源姿态循环，原求偶双角色panel保留。0.25s fly/glide只是源图示意，不能当成实际运输路线、真实库存消耗或完成证据；0.5×可读性须审真实连续图层。

## 统一验收结果

| 检查 | 必须保留的证据与边界 | 本批结果 |
| --- | --- | --- |
| Release/严格签名 | 整批全部实现后统一候选构建 | 第八轮73.44秒、strict通过 |
| 核心/回放 | 当批模拟版本、全量核心、30/60/120Hz完整报告、旧20报告与M7a比较及明确剔字段范围 | v18；66报告跨率一致，旧20完整报告无剔字段一致；核心轮次见下 |
| 素材/导出/parity | 46鸟旧像素/索引保持、恰8新鸟帧+6道具、四层/27喙锚、78 GIF/7800帧/loop0及旧名字 | 第四轮旧像素/索引、parity与GIF通过；art347/347通过；第六轮完整巢台专项通过 |
| M7b独立运输 | 真实材料盘取枝→携带→落稳放下→空喙恢复→离开落稳；放下仅增加待整理，不提前增长进度 | 0.5×/1×双向80项通过；2×及后续自动/中断组受阻 |
| M7c独立整理 | 有已送达材料才启动；独立run两轮调整/压实后原子消费一根；三次进度0→3且安全离开，第三次无额外第四条记录 | 0.5×/1×双向100项通过；2×及后续三轮完整/自动/中断组受阻 |
| 取消/守恒 | 可用+附着+待整理+已整理+耗损=3；原子拾取/放下/整理提交前后取消、重复tick、宿主/对象失效、暂停/睡眠/退出 | 核心全量992及修正后定向46通过；第六轮巢台专项1116/1116通过 |
| 原生/视觉 | 三缩放双向实际鸟/枝/CALayer、接触不跳变、枝不穿翼尾、遮挡、真实连续时戳与进度可辨 | 三缩放双向原生数值检查通过；已查看运材/整理关键图层及三根完成进度，详见末节；长期人工观感待验 |
| 设置/观察 | 隔离中英控件、缺鸟/缺材/无空间拒绝、默认及旧设置保护、preview来源与自然唯一完成 | 第八轮独立完整settings2190/2190（巢材85、筑巢53）通过；自动/preview完成及来源隔离原生检查通过 |
| 压力/清理 | 24/64居民实际运输与整理，取消、900s自然到期、退休有界及对象/预约/图层零最终残留 | 核心压力/生命周期及第六轮完整原生中断/图层清理通过 |
| 性能 | 同机冻结基线三轮两版本三场景18次、metrics/cleanup及p50/p95/p99；不能替代实际专项工作负载 | 增量18、累计18、长场景复测6均通过完整性；详见下表 |
| 安装/真实长期 | 2026-10-25安装重启并验证数据保留；长期与硬件按独立证据 | 安装通过；真实长期与硬件待验 |

运输放下后取消仍保留待整理材料，但运输不记完成；整理提交后取消保留进度，但该整理run不记完成。拾取后取消不返库存，未送达材料回收记耗损；到期/清除整体取消并安全恢复。无配对、蛋、幼鸟、繁殖失败或必须照料叙事，不扩其他45鸟。以下保留真实轮次、失败/修正和路径；阶段通过不替代安装和长期验收。

## 首轮统一验证与修正记录

首次Release构建因`NestVisitSchedule.maximumPlannedDuration`跨行加号空白语法错误停止；修正后第二轮Release104.56秒、strict签名通过。首个`swift test`调用使用系统默认Command Line Tools，因缺XCTest未执行测试；按项目文档为单次测试指定完整Xcode后，第二次调用发现新`NestMaterialTests`缺`BehaviorRunID(rawValue:)`参数标签，修正后第三次调用实际完成全量992测试：391.537秒、2条失败、0 unexpected，两条均属`NestAdmissionTests.testRealLegacyRunsAndNestVisitsAreBusyInBothDirections`。赠礼组合夹具额外推进9秒使灰喜鹊进入周期hop，无法申请真实赠礼授权；移除该额外推进，保留真实授权、真实run和双向busy断言，补停稳前提检查。原始日志依次为`.build/m7bc-tests-initial.log`、`m7bc-tests-second.log`、`m7bc-tests-third.log`。

首次巢台原生专项`.build/m7bc-nest-initial`：素材339/347通过，四个0.5×/1×运材场景合计56/60通过，随后2×被真实指针`{628.5625,634.4140625}`挡住安全走廊而停止。无完整专项通过结论；分组报告、连续图层图、GIF及时间戳保留。初始候选SHA256为`aed024b129d68eccac7d54df647d475f467303f3153884a8649df0e90386aa97`，汇总`.build/m7bc-delivery/validation-summary-initial.json`。

素材失败包括七个低头姿态颈斑黑底被五个白点覆盖，真实黑底内部像素为0；修正映射黑底并将五点落在独立原生像素，检查加强为黑底存在和五个精确颜色。twig的解析斜边与关闭抗锯齿后的像素填充存在差异，改为描摹既有56像素墨迹边界的整数阶梯polygon；仍严格比较全部256个像素，不放宽几何检查。旧鸟帧、喙/脚锚和行为时序不改。

四组原生运材均实际完成，接触前后root像素差异为0；失败来自连续性断言将1/120秒采样间隔当作1/60秒引擎推进。改用真实`engine.time`增量和生产速度上界，保留原容差，拆出anchor/layer/pickup/delivery/continuous子checks及首次异常诊断。真实指针安全规则未改。

全部修正收拢后第三轮Release101.15秒、strict签名通过。重新导出共享素材后，46鸟旧像素/索引逐一保留，恰追加斑鸠8帧；parity通过。22夹具×30/60/120Hz共66份完整报告一致，旧20份完整报告与M7a一致，未剔字段。78个GIF/7800帧/loop0、全部旧文件名保留。定向核心与原生复验结果继续追加，不将上述结果解释为M7b/c或长期验收已完成。

第四次核心调用为`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter Nest`，共46方法（含名称匹配的6个旧nested/version用例），196.277秒、1条失败；赠礼互斥夹具已通过。唯一失败是`NestPoseTests`独立polygon字面量仍为修正前斜边，更新为已验明56原生墨迹像素的整数边界，保留独立顶点与旋转包络断言。第五次定向`NestPoseTests`2/2通过，0.227秒。第六次调用最终全量992/992通过、0 failures、0 unexpected，用时380.776秒（suite墙钟380.832秒），日志`.build/m7bc-tests-full-sixth.log`。这是独立完整全绿轮次，以上失败与修正历史全部保留。

首轮增量性能运行与第五次测试的短暂编译重叠，全部记录保留在`.build/m7bc-performance-overlapped-test-build`，明确排除最终性能结论；待测试进程结束后另跑正式三轮对照。

## 同机性能实际结果

正式增量18次在测试进程退出后执行；M5n累计18次对候选显式传入`--stress-content disabled`，关闭浴盆、叶片携带、捕虫、礼物、求偶和筑巢。两套候选与基线均18/18通过压力完整性，cleanup全一致。以下单位毫秒，单机加速核心，不是桌面长跑或能耗结论。

| 对照/场景 | 基线median p50 | 候选median p50 | 变化 | 基线最差p95/p99 | 候选最差p95/p99 |
| --- | ---: | ---: | ---: | --- | --- |
| M7a增量/ordinary | 0.019500 | 0.019458 | -0.2154% | 0.034583/0.073625 | 0.031083/0.039375 |
| M7a增量/crowded | 0.049458 | 0.049583 | +0.2527% | 0.073000/0.087583 | 0.083042/0.096083 |
| M7a增量/long | 0.011792 | 0.013333 | +13.0682% | 0.022125/0.027916 | 0.022708/0.029625 |
| M5n累计关闭新内容/ordinary | 0.018834 | 0.019417 | +3.0955% | 0.030667/0.036375 | 0.031167/0.040500 |
| M5n累计关闭新内容/crowded | 0.049750 | 0.049583 | -0.3357% | 0.077500/0.137958 | 0.073750/0.088708 |
| M5n累计关闭新内容/long | 0.011583 | 0.012250 | +5.7584% | 0.021875/0.027041 | 0.023292/0.031875 |
| M7a长场景独立复测/long | 0.013625 | 0.013583 | -0.3083% | 0.022708/0.028958 | 0.023000/0.032750 |

增量长场景首轮+13.0682%，独立三轮复测−0.3083%，升幅未复现；两组metrics与cleanup完全一致，保留两轮，不选取有利样本冒充唯一结果，未据此修改生产性能代码。累计M5n三类均未超过10%排查阈值。M5n ordinary/crowded除eventDigest外其余metrics一致，摘要不足以定位所有事件时间差，不能声称完整事件等价。long确切复现旧`sideHop` run183、sequence396、time734.1s、automatic/targetInvalid一次失败；候选无该失败，后续自然事件序列分岔，不能声称工作量逐事件相同。原始报告及所有重复样本见`.build/m7bc-performance`、`.build/m7-final-m5n-performance`、`.build/m7bc-long-performance-recheck`。

桌面工具于本轮再次明确报告Mac锁定；原生专项、完整birds/settings、最终安装及真实桌面长期项目继续等待实际桌面条件，不以离屏图片或核心模拟替代。

## 第二轮原生复验

用户回复后立即运行第三轮构建候选（SHA256 `672e1035fd347d28b997eef8cd9b2a607ea0aa902ed192544485eccf41975fac`）。素材346/347，唯一剩余失败为`carryPlace-MappedSpottedCollarSurvivesRaster`，继续修正真实素材。运材0.5×/1×双向四场景80/80通过；拆分的连续性、锚点与拾取/放下检查均通过，接触root像素差异为0。随后2×仍因真实指针`{628.5625,634.4140625}`无完整安全走廊中止，尚未运行运材settings及筑巢native/settings。CUA同时报告Mac锁定，不把80项局部结果当作完整专项通过。证据保存在`.build/m7bc-nest-second`及`.build/m7bc-delivery/validation-summary-second.json`。

第二轮后集中修正：`carryPlace`的头部角度由0.82改为1.04弧度，使侧颈黑底能容纳五个独立白点；喙尖仍为(40,39)，脚锚和其他姿态不变。新增`--verify-nest-art <folder>`，只运行素材/接触几何并明确输出source-art-only范围，不替代运输、整理、设置或真实桌面验收。同时修正M6h状态栏autosaveName的隔离报告，详见`M6H-ACCEPTANCE.md`。全部源码完成后启动第四轮Release与第七次核心调用（Nest定向）；第七次核心46/46通过、0 failures、183.549秒，日志`.build/m7bc-tests-nest-seventh.log`。第四轮Release99.38秒、严格签名通过。源素材347/347通过，主会查看修正后的右向四层联系图；独立素材检查不替代原生图层路线。46鸟旧像素和索引仍完全保留；parity、78 GIF/7800帧/loop0、66份跨率完整报告及旧20份不剔字段回放对比通过。证据分别在`.build/m7bc-art-fourth`、`.build/m7bc-replays-fourth`、`.build/m7bc-pose-previews-fourth`与`.build/m7bc-revision-fourth`。

第四轮候选冻结于`.build/m7bc-revision-fourth/ChirpOS Dev M7bc fourth candidate.app`，SHA256 `7d3b5931971cd52d0aab5aa52abeee89f4419d6190ac834e0c260d07baaffcb6`。此前候选与失败证据保持独立，第四轮尚未运行完整巢台/鸟/settings原生验收，未安装。正式性能对照属于第三轮候选；第四轮仅调整放枝头角、素材单独入口与隔离长跑状态栏报告，没有将此前性能测量冒称第四轮实测。

第四轮另以真实30秒smoke验证状态栏隔离修正，退出0、离线22/22通过，见`M6H-ACCEPTANCE.md`；不计入2h/8h。

## 完整设置独立验收

第四轮编译产物在独立应用标识的验收副本中执行完整`--verify-settings`，2188/2188通过，包括巢材设置85项与筑巢设置51项。副本只改CFBundleIdentifier及对应ad-hoc签名；38个Mach-O代码/数据分区逐项相同，元数据`.build/m7bc-revision-fourth/settings-verification-bundle.json`。独立应用域避免完整设置测试操作`ChirpOS.Main`时影响已安装版的状态栏偏好；该结果不证明安装身份或用户草稿已验收。

完整结果`.build/m7bc-settings-first/report.json`，主会查看中英巢台controls与英文筑巢journal截图；保存/取消、迁移、旧草稿保留、拒绝原因和来源计数检查均通过。此前`--verify-nest`遇到运材2×guard会停止后续分组；现在调整专项入口为各组独立执行并汇总异常，任一异常仍导致整体FAIL和退出1，所有真实指针guard保留。当时第五轮统一构建及专项待收取，实际结果见后续记录；不将分组继续执行解释为跳过失败。

## 第三轮巢台专项与报告完整性

第五轮Release73.94秒、严格签名通过。第三轮专项`.build/m7bc-nest-third`实际执行663项检查无false，但运材和整理各在2×遭遇真实pointer `{628.5625,634.4140625}`走廊guard异常，根报告`passed=false`、errors含两组，进程退出1。已执行素材347、运材80、运材设置85、整理100、整理设置51。0.5×/1×双向整理均经真实运输准备后独立run完成，原生锚点与连续性检查通过；主会查看1×右向的抬头、调整、压实root图层。

本轮发现旧分组defer报告仅根据已执行checks生成passed，throw时可能误显true；根报告虽正确FAIL，但单独子报告仍有歧义。现统一增加`completed`与`checksPassed`，只有组执行到底且检查全通过才允许`passed=true`。历史第三轮报告原样保留，不回写成新的报告语义。该项只修正证据报告，不放松断言或执行安全检查。

第六轮Release77.48秒、严格签名通过；第四轮专项`.build/m7bc-nest-fourth`验证了新报告语义：663项已执行checks均通过，运材/整理native两组各`completed=false`且`passed=false`，两settings组`completed=true`且`passed=true`，根报告保留两条2×pointer错误、整体FAIL、退出1。2×及其后的自动、完整三材料、中断等原生场景仍未执行；不是“663/663完整专项通过”。

最新候选冻结于`.build/m7bc-delivery/ChirpOS Dev M7bc sixth candidate.app`，SHA256 `d27e100b002b38d19b7e0b52718d4f30012baec3e94595cf45ac11ae597f73fc`，源码哈希与元数据`.build/m7bc-delivery/sixth-candidate.json`。第四轮以后只改验收分组汇总和报告完成标志，生产行为/素材/设置/长跑逻辑未再修改；此前完整核心、导出、回放、settings与smoke结论保持其各自轮次，未冒称第六轮全部重新测量。

本批以实现checkpoint进行中文本地提交，不授予M7b/c整阶段通过，不推送、不安装。后续必须完成巢台三缩放全部原生、完整birds、当前安装版草稿保护及更新重启，并按M6h/M7d记录真实2h/8h及硬件证据。该checkpoint时桌面工具持续报告Mac锁定、尚待用户答复。此后用户安排稍后解锁、先完成其他工作；最新原生补验结果见下节。

## 锁屏期间独立场景补验

用户明确安排稍后解锁、先完成其他工作。原生夹具现将每个缩放/朝向、自动机会、三材料完整流程与中断清理作为独立case，异常记入`caseErrors`后继续其他case；所有case结束后仍对任一异常抛错并使总验收FAIL，真实pointerguard不变。

第七轮Release75.30秒、严格签名通过；第五轮专项`.build/m7bc-nest-fifth`读到pointer已变为`{539.58984375,981.98046875}`，2×双向路线已可安全执行。素材347、运材164、运材settings85、整理settings51均通过；整理428项中4项失败，整体1075项/4 false/无caseErrors，退出1。失败仅为宿主失效场景之后复用同一夹具的准备运输`ThreeStableMaterialsAndConservation`断言。

源码核对：`BehaviorEngine`将实际离场累计到`departureCount`，重新安装fixture birds不重置该生命周期计数；旧断言错误要求每次journey的历史arrival/departure计数始终为0。修正为每次启动前记录基线，逐tick及终态必须与基线一致；材料身份、三根守恒及居民对象身份检查全部保留，另输出`populationBefore/After`和独立无人口变动断言。没有重置生产计数以使测试通过。第八轮Release73.44秒、严格签名通过。

第六轮巢台专项`.build/m7bc-nest-sixth/report.json`完整执行1116项，全部通过、errors为空、退出0；素材347、运材native171、运材settings85、整理native460、整理settings53。两native组均`completed=true`、`checksPassed=true`、`passed=true`且`caseErrors`为空。三缩放双向路线、自动机会、三材料完整流程、第三次提交后无第四记录、点击/取消/宿主失效/睡眠命令/退出命令及清理全部执行。此前四个误报场景的到达/离开基线与结束值均为`0/1`，材料守恒和居民身份检查通过；历史离场没有被清零。

主会查看了本轮0.5×/1×左向及2×双向运材夹持root图层、2×双向整理压实，以及第三根整理后progress=3的实际图层。最后一张证据为`nest-build-native-670923D7-518D-4A73-9665-B51213AB0956/nestBuildNativeThree-3-build-journey/0113-actual-layer.png`，三个材料ID分别为1/2/3且均为arranged。这里只记录已查看的关键图层，不宣称逐帧人工看过所有GIF。这些隔离生产handler/CALayer检查不替代真实系统sleep/wake、硬件或人工长时间观察。


## 第八轮候选完整回归与阶段结论

冻结候选`.build/m7bc-delivery/ChirpOS Dev M7bc eighth candidate.app`，二进制SHA256 `9ba89b807c9d9af693316f8059170b6facbedb290f5d1456e46f50b10e680310`，元数据`.build/m7bc-delivery/eighth-candidate.json`。完整回归使用独立应用标识副本`ChirpOS M7bc Final Verification.app`，仅改CFBundleIdentifier与ad-hoc签名，38个Mach-O代码/数据分区与候选一致，strict签名通过。

串行完整`--verify-birds`与`--verify-settings`均退出0：`.build/m7bc-birds-first/report.json`为4593/4593，`.build/m7bc-settings-second/report.json`为2190/2190。与第六轮巢台1116/1116合并，M7b/c阶段通过，素材预算纳入最终167/16。第七/八轮只修改验收case隔离、人口基线断言及证据；生产行为/素材/core未改。992核心、后续46定向、素材导出/跨率回放和性能结论保持上述各自轮次，不冒称在第八轮二进制重新测量。

用户安排稍后解锁、先做其他工作；未替换或退出安装版，更新前仍须保护当时最新保存设置与未保存草稿。全量回归退出后已启动独立8小时默认工作负载，目录`.build/m7-final-soak-8h-first`；启动不等于通过，最终时长、sleep/lock、RSS/CPU及清理须收尾后审阅。默认运行不自动放置巢台/浴盆等场景，不为未发生行为补授长期覆盖。2h人工观察、物理多屏/热插拔、真实sleep/wake仍待执行，M6h/M7d和总目标未完成。

2026-10-25补充：安装、草稿保护与重启已完成，详见[M7d记录](M7D-ACCEPTANCE.md)；上述未安装描述保留为各历史轮次状态。8h运行尚待收尾，未授予M6h/M7d通过。

## V03阶段审计补验（2026-10-25）

审计发现原1116项矩阵没有完整覆盖理巢离巢/落稳时的取消。本轮仅扩展验收代码，补齐8阶段理巢和6阶段运材×14原因×运行/暂停、8阶段理巢暂停恢复，原生7546/7546通过；核心47项首次有2条错误暂停换位预期，修正后失败方法1/1定向通过，其他46方法沿用该轮通过记录，不合并为一次全绿。Release89.16秒、strict签名通过。完整失败历史、矩阵核对与候选身份见[M7d记录](M7D-ACCEPTANCE.md#v03阶段覆盖审计与补验2026-10-25)。生产行为及已安装的第八轮候选未改。
