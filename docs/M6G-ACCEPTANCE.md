# M6g 验收记录（阶段验收通过、未安装）

记录日期：2026-10-24。基线M6f.2提交`3bad0e7`，历史证据见[M6f.2验收](M6F2-ACCEPTANCE.md)。**状态：阶段验收通过、未安装。第五轮Release/严格签名、核心定向49/49、完整settings1955/1955、57跨率回放、旧18完整报告、素材及18次性能对照通过；冻结候选第六轮赠礼验收275/275通过，关闭2×双向及点击落稳遗留项。未宣称单次920核心全绿或真实长期验收。** 本批灰喜鹊4张新增姿态已通过像素及art验证，累计已验证154鸟体帧/10道具、剩13/6，仍为46鸟；历史失败与各次补验范围保留。用户安装版仍M6a/b，整个M6/M7未完成。

以下素材合同、API及“统一验收待填”表保留为首轮前的冻结记录，其中“未运行”描述当时状态；当前实际结果与失败历史追加于文末，不以首轮部分通过改写正式进度。

## 素材与几何合同

| 项目 | 实现合同，待统一验证 |
| --- | --- |
| 物种与帧 | `azureWingedMagpie`新增独立carryLook/carryLower/carryGrip/carryPlace；原44帧不动，新图集48帧；叶片复用现有leafToken。 |
| 画布与层 | 48×48逻辑坐标、现有物种像素密度、脚参考锚(29,39)，body/feet/headNeck/bill四语义层；黑帽浅颊、青翼长尾独立绘制，不套麻雀姿态。 |
| 拾取 | Look/Lower/Grip保持原脚部几何，独立改变头颈、肩翼和长尾；Grip真实上喙尖右(40,39)/左(8,39)，头颈不穿脚平面。 |
| 空中释放 | Place上举翼、收脚、打开下喙，上喙尖右(42,23)/左(6,23)；脚参考锚仍(29,39)，不表示实际脚触地。 |
| 喙锚 | carry4＋fly0…7/land0…2/glide0…2/bank0…2/bound/stand，共23帧，均由绘制几何同源生成。原公共头部7.5/7/15仅提取为同值常量，保留原变换顺序；stand/land右(40.5,19)/左(7.5,19)。 |
| 叶片 | 16×16、grip(3,12)、surface(10,12)，真实轮廓底边12；独立worldScale，不继承灰喜鹊relativeScale，不烘焙进鸟图。鸟叶并集覆盖实际采样的全部23帧、双朝向及旋转；连续旋转范围应覆盖中间极值。 |
| 接收点 | metadata采用`resolvedFixedPerch.foot`。只读核对core的`GiftReceiverGeometry.anchor(on:)`直接返回该点；FixedPerchArt按真实alpha裁剪得到railY，显示rect的`minY + railY × ratio`正好等于perch.foot.y，水平中心对应perch.foot.x。不另猜原始图片尺寸或偏移，本切片未修改栖木绘制或布局；待统一验证三缩放下同源接入。 |
| 资格 | visitorGift仅灰喜鹊；leafCarry仍仅麻雀，灰喜鹊不新增fixedPerchVisit资格。授权账本、额度、路线、释放后落叶和寿命由core/platform负责。 |

## 冻结API与导出

- `PoseClip.carryBeakAnchor(species:frame:) -> Anchor?`、`CarryPoseAnchors.anchor(species:frame:)`覆盖两种携带绘制源，灰喜鹊共23帧；`CarryArtGeometry.pose`与`transportBillAnchor`提供同源几何，`magpieReleaseBeak`为(42,23)。
- `DetailedBirdArt.carryImage(_:species:part:)`、`carryBillAnchor`、`transportBillAnchor`沿现有make/poseImage/poseBillAnchor接入；原麻雀绘制分支保留。
- `PoseClip.visitorGiftPickup(species:)`：Look .4s/Lower .3s/Grip .2s/Look .3s，总1.2s，原子拾取时刻由执行器在.7s提交。
- `PoseClip.visitorGiftRelease(species:)`：仅空中Place .3s，不追加地面Look。鸟的真实飞行与独立叶片受控落下由执行器继续管理。
- metadata追加visitorGiftPickup/visitorGiftRelease、4新帧喙锚与23个transportBeakAnchors；leafToken元数据追加120s礼物寿命、接收点和禁止承载鸟落栖说明，无新道具文件。
- 灰喜鹊已在原基础姿态名单，预期仍78份GIF/7800帧/loop0，全部旧文件名保持；只在灰喜鹊原有双向0.5×/1×/2×循环内追加拾取/飞行/释放展示轨道，叶片独立绘制。
- `VisitorGiftArtVerification.run(into:folder:)`由M6ContentVerification调用，提供双向四语义层联系表、六份鸟叶组合静态预览、23喙锚/镜像/实际alpha、拾取脚位/释放收脚、边界及鸟叶包围范围证据；真实原生旅程与授权检查另由平台/core接入。相关历史完整帧前缀检查及parity已更新期望，均未运行。

## 统一验收待填

核心接线已实现，尚待本表中的统一验证：赠礼只使用现有熟客、现成叶片和已保存接收枝；同一个ScenePropID从预约、拾取、附着、释放到展示，普通麻雀的独立leafCarry资格保持不变。接收区域独立于鸟落脚预约，并在run结束后按物件剩余寿命继续参与避让。接收锚保存身份、屏幕身份或slot修订发生变化会使旧申请失效。

授权结果通过显式外部输入进入引擎，完整绑定request、档案命名空间、熟客、鸟、物种、来源、叶片及接收slot/revision。引擎不读墙钟或账本；平台的5秒时限包含排队与锁等待。同一引擎的迟到/重复结果保留录制输入但不能复活申请；旧引擎回调不能交给新引擎。释放在实际Bird.tick之后先纯预检，再消费token并同步提交，失败和取消不退款。

模拟v16拒绝真实v15录制；旧18份手写夹具仅迁移版本，第19份`visitor-gift.json`明确提供初始熟客档案及授权输入。报告增加授权绑定、注册/消费状态、独立接收预约及下落实体状态；无赠礼状态时新增可选字段保持缺省，旧完整报告比较不剔字段。该兼容性要求尚未运行验证。

| 检查 | 需要的真实证据 | 本批结果 |
| --- | --- | --- |
| Release / 严格签名 | 整批完整实现后统一构建 | 未运行 |
| 核心 / 授权 / 负载 | 拾取真实现成叶片、配额原子性、迟到token、取消/暂停/重启与零残留 | 未运行 |
| 完整birds / 礼物原生 | 真实拾取、携带、空中释放、叶片到达perch.foot与完整生命周期 | 未运行 |
| 设置 / 观察 | 中英控件、默认关闭、真实来源与唯一成功计数 | 未运行 |
| 回放 / 兼容 | 当批模拟版本、完整跨率报告、旧18报告回归，不能从当前结果反推expected | 未运行 |
| 素材 / parity / GIF | 46鸟全部旧像素/索引不变、恰增灰喜鹊4帧、道具不变、78循环GIF | 未运行 |
| 视觉 / 几何 | 新四姿态、双向三缩放、真实鸟叶并集与接收轨迹，不以源图替代生产图层 | 未运行 |
| 性能 | 同机冻结基线对照、metrics/cleanup及实际礼物工作负载 | 未运行 |
| 安装 / 硬件 / 长跑 | 当前未安装；物理多屏/热插拔、真实sleep/wake、2h/8h与长期内存/能耗 | 未验收 |

素材owner未构建、测试、导出、原生运行或提交；上述均为源码合同及静态阅读结果，不是本批验收通过。后续按主会真实证据填入结果，保留失败与修正历史，不将整个M6/M7标为完成。

## 构建失败历史与第三轮结果

全部实现后由主会统一构建，前两轮失败保留，不并入第三轮成功记录。

| 轮次 | 实际结果及问题 | 证据 |
| --- | --- | --- |
| 第一轮 | 编译失败。`BehaviorEngine.swift`数组拼接的换行及运算符空格触发语法错误；`GiftLedger.swift`第38/46行的`Darwin.flock`被解析为同名结构体，触发无参调用及类型错误。后者保留`import Darwin`并改为现有存储代码使用的`flock(...)`调用，未改锁语义。 | `.build/m6g-build-initial.log` |
| 第二轮 | 编译失败。`PosePreviewExport.swift`数组拼接换行触发语法及后续参数类型错误；`GiftVerification.swift`第418行表达式过于复杂，编译器无法在合理时间内完成类型检查。 | `.build/m6g-build-second.log` |
| 第三轮 | Release构建通过，日志耗时64.42s；严格签名检查通过。构建成功不等于功能验收通过，也不表示已安装。 | `.build/m6g-build-third.log`、`.build/m6g-signature.log` |

## 首轮统一验证实际结果

此处保留首轮结果；记录该轮时下一轮尚未运行，失败修订即使已落盘也不能计为复验通过。后续实际复验结果另见文末，不覆盖首轮失败历史。

| 检查 | 首轮实际结果 | 证据 |
| --- | --- | --- |
| 全量XCTest | 执行920个测试，79项失败记录（其中5项unexpected），集中于6个测试方法；总耗时186.593s。不是79个方法失败，也不是整套通过。 | `.build/m6g-tests-initial.log` |
| 完整birds | 共3437项，3433通过、4失败。 | `.build/m6g-birds-initial/report.json`、`.build/m6g-birds-initial.log` |
| 完整settings | 共1955项，1954通过、1失败。 | `.build/m6g-settings-initial/report.json`、`.build/m6g-settings-initial.log` |
| 跨率回放 | 19份场景在30/60/120Hz共57次通过，完整报告跨率一致。 | `.build/m6g-replays.log`、`.build/m6g-replays/` |
| 旧18份完整报告 | 与基线`3bad0e7`逐份一致，`ignoredNewFields=[]`，没有剔除新增字段。 | `.build/m6g-delivery/legacy-replay-comparison.json` |
| 旧像素与索引 | 46鸟旧像素与索引全部不变；仅灰喜鹊由44帧增为48帧，恰增4帧。 | `.build/m6g-delivery/legacy-pixel-comparison.json` |
| 共享参数parity | 46鸟日程、34个公共帧名及46鸟飞行配置匹配，通过。 | `.build/m6g-parity.log` |
| GIF导出 | 78份、7800帧，全部loop=0；旧78个文件名保持。该结果只证明导出和解码合同，不替代真实礼物旅程验收。 | `.build/m6g-delivery/gif-validation.json`、`.build/m6g-export-previews.log` |

核心失败的6个方法如下，保留完整名称以供下一轮逐项对照；本记录不预判它们属于生产问题还是夹具问题：

- `LeafCarryPoseTests.testEveryTransportFrameHasAFinitePreciseSparrowBillWithoutGrantingOtherSpecies`
- `VisitorGiftAdmissionTests.testGiftAndLegacyFoodTrayOrFixedPerchRunsAreBusyInBothDirections`
- `VisitorGiftAdmissionTests.testOrdinaryPlacedLeafIsReusedWithoutCopyAndFeatureControlsEightVersusSixHundredSeconds`
- `VisitorGiftExecutionTests.testEachPhaseInterruptReclaimsUnreleasedLeafButKeepsReleasedGiftWithoutCompletion`
- `VisitorGiftSchedulingTests.testActualAutomaticGiftConsumesOneSharedOpportunityAndItsOwnRandomStreamAcrossCallbackRates`
- `VisitorGiftSettingsTests.testLegacySettingsDefaultGiftsOffWithoutChangingAnyExistingPreference`

birds的4项失败为`giftNative-1.0-left-RealPlacementAndNativePreviewStart`、`giftNative-2.0-left-RealPlacementAndNativePreviewStart`、`giftNative-2.0-right-RealPlacementAndNativePreviewStart`及`giftNativeInterrupt-click`。它们集中在`.build/m6g-birds-initial/gift-native-7546D3BE-D246-4CF9-87A9-72153EC0E8A8/report.json`，该子报告为48/52通过，不能称全部礼物native通过。

settings唯一失败为旧设置期望检查`visitorGiftSettingsMissingKeyDefaultsOffPreservesExistingValues`；礼物settings子报告为105/106通过，路径`.build/m6g-settings-initial/visitor-gift-settings-E201191E-41BE-4A57-8375-96F5D92ADD44/report.json`。修订与下一轮实际结果应另行追加，不覆盖本轮失败。

## 持久化与真实自动礼物专项证据

持久化专项**29/29通过**，计数来自首轮settings总报告中的`giftLedger`5项、`giftNamespace`5项、`giftBridge`17项、`giftRecording`2项。这29项是1955项settings检查的子集，不能重复加入总数；覆盖真实双进程bootstrap与额度竞争、稳定身份及旧快照保护、未来/损坏文件保护、录制身份边界、5秒排队和主队列交付过期、取消竞争及消费不退款。

| 原始证据目录（均位于`.build/m6g-settings-initial/`） | 实际核对结果 |
| --- | --- |
| `gift-ledger-bootstrap-D5D48E49-28EC-4825-BAC3-60CC8C96B210/` | 两个真实worker PID为52741、52742，均采用磁盘namespace `700`，无错误；各自结果保存在`worker-0.json.result.json`与`worker-1.json.result.json`。 |
| `gift-ledger-contest-AD371F11-8FDB-4FC9-B828-DCF897B6CD71/` | PID52743、52744竞争同一身份，恰一个token，另一个`alreadyGranted`；`gifts.json`仅一条grant。两个进程使用独立访客文件锁，共享账本锁，覆盖账本本身的跨进程互斥。 |
| `gift-ledger-global-5EB79B68-C01C-4452-80F6-9FB0D313782E/` | PID52745、52746分别使用namespace `73`、`74`，恰一个token，另一个`globalCooldown`；`gifts.json`仅一条grant，24小时限制跨namespace生效。 |

bridge专项中，`giftBridgeFiveSecondsIncludesQueueAndDeliversOnce`、`giftBridgeMainQueueExpiryRetainsCommittedQuotaAndReturnsOnlyTimeout`及`giftBridgeCommitDeadlineRaceRetainsQuotaWithoutToken`均为true。取消修复相关的`giftBridgeCancelledTransactionCannotClearReplacementOrDeliverTwice`、`giftBridgeCompletedClaimReleasesPendingBeforeCallbackDelivery`、`giftBridgeConcurrentFinishCancelImmediatelyAdmitsReplacementExactlyOnce`也均为true；最后一项汇总32轮真实提交后的完成/取消竞争，不能误记为另外32个报告检查。

真实自动ledger→送达→自然计数链路**5/5通过**，对应上述gift-native子报告中的以下检查；它们是52项子报告及3437项birds总报告的子集，独立于29项持久化settings检查：

- `giftNativeAutomaticRealBootstrapProviderAndObserver`
- `giftNativeAutomaticGrantBindsPersistedVisitorExactlyOnce`
- `giftNativeAutomaticDurableGrantToVisibleDeliveryAndNaturalCount`
- `giftNativeAutomaticRealDropWithinPointEightSeconds`
- `giftNativeAutomaticCleanupKeepsConsumedLedgerAndUniqueCount`

该链路使用真实bootstrap、平台provider/observer和持久账本，不以手工注入token替代自动授权。消费证据位于`.build/m6g-birds-initial/gift-native-7546D3BE-D246-4CF9-87A9-72153EC0E8A8/automatic-durable-322FF853-5792-46C9-8A66-1FB42B35762D/gifts.json`。这5项通过不覆盖仍失败的其他缩放/朝向启动和点击中断检查。

**以上为首轮记录时的状态：整批未通过、未安装，下一轮当时未运行。** 尚不能据此推进M6g正式完成状态，也不补写未取得的性能、硬件或长跑验收结论。首轮日志及报告保留原样。

## 后续构建与第二轮定向复验（2026-10-24）

| 检查 | 实际结果 | 证据 |
| --- | --- | --- |
| 第四轮构建 | 编译失败，唯一问题为native验证`GiftVerification.swift`第340行跨模块访问internal `hostPID`。改为通过public `hostID`、当前surface存在性及真实foot位置检查落稳，不为验证放宽生产字段可见性。 | `.build/m6g-build-fourth.log` |
| 第五轮构建与签名 | Release构建66.89s通过；严格签名通过。 | `.build/m6g-build-fifth.log`、`.build/m6g-signature-final.log` |
| 核心第二轮定向 | `VisitorGift\|GiftLedger\|LeafCarryPose`范围49/49通过，0失败、0unexpected，33.079s；覆盖首轮6个失败方法对应的修订检查，并包含24/64居民实际礼物压力场景。不是第二次全量920项通过。 | `.build/m6g-tests-second.log` |
| 回放复验 | 19份场景×30/60/120Hz，共57次退出成功且完整报告跨率一致。 | `.build/m6g-replays-second.log`、`.build/m6g-replays/summary.json` |
| 历史报告复验 | 旧18份报告与`3bad0e7`仍全部一致，`ignoredNewFields=[]`，没有剔字段。 | `.build/m6g-legacy-replays-second.log`、`.build/m6g-delivery/legacy-replay-comparison.json` |
| native第二轮 | 部分通过、整轮未通过：0.5×/1×双向四条journey共36/36通过；进入2×前找不到避开live pointer的完整走廊，明确报错退出，未绕过生产准入。2×及新增点击落稳尚未执行。 | `.build/m6g-gift-second.log`、`.build/m6g-gift-second/gift-native-61C549E0-1F5F-4F55-824F-8A4F7434C6CA/report.json` |
| 完整settings第二轮 | 1955/1955通过，报告`passed=true`；首轮唯一失败已复验通过，保留首轮失败记录。 | `.build/m6g-settings-second/report.json` |
| 同机性能 | 三轮、两版本、三场景共18/18通过，三组metrics/cleanup全部一致；详细数值与范围见下节。 | `.build/m6g-performance.log`、`.build/m6g-performance/summary.json` |

核心6项对照中，5个失败方法在第二轮以原名通过；原`LeafCarryPoseTests.testEveryTransportFrameHasAFinitePreciseSparrowBillWithoutGrantingOtherSpecies`修订后更名为`testEveryTransportFrameHasAFinitePreciseSparrowBillWithoutExpandingLeafCarryEligibility`，也已通过。24/64压力分别为`testTwentyFourResidentsCompleteTwoGiftsAndOneAttachedCancellation`和`testSixtyFourResidentsCompleteTwoGiftsAndOneAttachedCancellation`，两者均通过；这些均包含在49项内，不另加计数。

native第二轮日志要求将鼠标移向屏幕边缘以获得完整安全走廊。主会已通过CUA确认Mac锁定，当前无法移动真实指针，并已异步请用户解锁；这是待解除的运行环境阻塞，不能把36/36部分检查写成整轮native PASS。首轮1×左向启动已在本轮旅程通过，2×两方向及点击中断/新增点击落稳仍不能宣称复验关闭。完整settings第二轮已1955/1955通过，证据为`.build/m6g-settings-second/report.json`；首轮1954/1955记录继续保留。settings通过不替代上述native旅程与点击验收。

## 性能完成、素材计数与checkpoint边界

M6f.2→M6g同机性能18/18通过。active advance单位为毫秒，medianP50取各版本三轮p50中位数，最差p95/p99取M6g三轮最差值：

| 场景 | M6f.2 medianP50 | M6g medianP50 | 变化 | M6g最差p95 / p99 |
| --- | --- | --- | --- | --- |
| ordinary | 0.019375 | 0.019834 | +2.369032% | 0.034458 / 0.046292 |
| crowded | 0.049083 | 0.050667 | +3.227187% | 0.077916 / 0.098958 |
| long | 0.012875 | 0.013500 | +4.854369% | 0.022959 / 0.034584 |

三组`metricsUnchanged`及`cleanupUnchanged`全部为true，增幅均低于10%排查阈值。证据`.build/m6g-performance/summary.json`。这是既有工作负载的同机加速核心模拟对照，不是实际墙钟长跑、原生渲染或长期堆内存/能耗验收；相同metrics不能替代礼物专项工作负载证据。

灰喜鹊四帧已通过旧46鸟像素/索引对照和art检查，第二轮`.build/m6g-gift-second/visitor-gift-art/report.json`为63/63通过。累计新增素材正式更新为154鸟体帧/10道具，剩13鸟体帧/6道具；阶段原生验收仍待完成。素材、核心定向与性能通过不抹去首轮920测试的79项失败历史，也不构成单次920全绿。

已保存未安装候选`.build/m6g-delivery/ChirpOS Dev M6g candidate.app`。M6g状态为“已实现，核心定向复验/settings/回放/素材/性能通过，整批原生未通过待解锁”。M6h隔离真实墙钟长跑与M7a可继续独立实施；本记录不宣称两者已实现或验收。本地checkpoint提交只保存当前工作，不表示M6g阶段完成；用户安装版仍为M6a/b，所有旧失败记录保留。


## 冻结候选原生补验完成（2026-10-24）

第三、四、五轮均在完成0.5×/1×双向36项后，由真实鼠标安全走廊guard退出；没有绕过准入或修改候选。用户解锁并把鼠标留在屏幕边缘后，第六轮退出码0，`.build/m6g-gift-sixth/report.json`为275/275全通过：art63、native77、settings106、持久化29。

native77覆盖三个缩放双向六旅程、点击中断后的真实completed及合法落脚、禁用/宿主失效/暂停、授权拒绝与迟到结果、独立控制器和自动provider→账本→送达→唯一自然来源记录。首轮三个旅程启动及点击失败均已被本轮对应检查关闭。第六轮未重新运行完整birds3437或核心920；不能把定向补验写成单次全量全绿。

已逐图审查2×双向实际root CALayer下降联系图：叶片从喙部分离，鸟转身时叶片不随之翻转，独立连续下降到接收树枝rail；两方向均未见悬空落点或瞬移。证据为`.build/m6g-delivery/giftNative-2.0-right-descent.png`、`giftNative-2.0-left-descent.png`，原始连续帧/GIF和模拟时戳位于第六轮gift-native子目录。

本轮使用原冻结候选，二进制SHA256仍为`5ab47835c68e7e86b9704fd335c7aceb86da99dceea41e1e55869e5fdf421b2f`。M6g阶段验收通过，未安装；M6h/M7开发继续。实际2h观察、8h浸泡、物理多屏/热插拔及真实睡眠仍未验收。
