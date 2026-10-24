# M6f.2 验收记录（阶段验收通过、未安装）

记录日期：2026-10-24。**状态：M6f.2阶段验收通过，随本阶段记录本地提交、未安装。** Release/严格签名、完整birds3322项、settings1820项、54回放、素材导出、六组native视觉及性能18/18通过。核心证据为第三轮完整876项中其余875项通过，加第四轮白眉16项定向补验全部通过；没有单次876项全绿记录。依赖M6f.1提交 `13e4733`，历史证据见 [M6f.1验收](M6F1-ACCEPTANCE.md)。累计已验证150张新增鸟体/10张道具、剩17/6张，仍为46鸟；本批只新增3张鸟体，不新增道具。下一阶段M6g，M6/M7整体仍未完成；用户安装版仍为M6a/b。

## 行为与录制范围

复用已有白眉姬鹟居民，从合法普通窗口顶部或地面栖点出击，不补鸟、不传送、不增加固定小栖木资格。出击半径80–220逻辑点、拦截段不超过3s、run不超过25s；预约原落脚点，成功或错过均尝试返回，原点失效从实际脚位寻找安全落点。沿用连续真实喙接触、独立昆虫与合喙0.18s/恢复0.30s，捕获且最终落稳才completed与入册；错过或取消不计成功。两鸟共用原8%机会、单虫和单run，不增加时钟。

模拟版本v15，拒绝旧生产录制1–14；第18份手写夹具`flycatcher-insect-catch.json`覆盖出击、暂停、真实返回及取消后独立虫继续。18夹具在30/60/120Hz的54份完整报告一致，旧17报告不剔除字段与M6f.1完全一致；历史生产录制须用对应版本重放，不直接改版本标签。

## 素材与锚点合同

| 项目 | 素材与锚点合同 |
| --- | --- |
| 物种与帧 | `yellowRumpedFlycatcher` 的catchOpen/catchClose/catchRecover三张独立姿态；白眉图集为旧34+3=37帧，不加入十二鸟基础poseSpecies。 |
| 画布与图层 | 48×48逻辑坐标，保持现有分辨率、脚参考锚(29,39)，body/feet/headNeck/bill四语义层；空中脚收起，参考锚不表示脚实际触地。 |
| 外观 | 成年雄鸟黑背黄腹、白眉白翼斑及黄腰；短扇尾、圆翼，与家燕叉尾/尖翼/锈喉独立。Open上举展翼前探，Close下拍合喙，Recover半收翼回正。 |
| 新帧喙锚 | 由实际填充上喙尖顶点和头部旋转同源计算，非口腔空白中心；左右按x→48−x，世界尺度/旋转由现有Anchor.world应用。 |
| 复用帧喙锚 | fly0…7、land0…2、glide0…2、bank0…2、bound、stand，共19帧；旧头部8/7/15与旧喙长4继续供绘制和锚计算共同读取，TransportArtGeometry保持原变换。stand/land右(40.5,19)、左(7.5,19)。 |
| 保持范围 | 保护46鸟所有旧像素/索引及M6f.1家燕新包；不改昆虫四帧、16×16/中心(8,8)/半径3/worldScale/12fps合同。 |

以下数值用于审阅，运行入口读取实际绘制几何，不使用表中舍入值。

| 帧 | 右向(x,y) | 左向(x,y) |
| --- | --- | --- |
| catchOpen | (43.212447948,18.448751458) | (4.787552052,18.448751458) |
| catchClose | (42.546661078,21.023346855) | (5.453338922,21.023346855) |
| catchRecover | (41.413995467,20.699680047) | (6.586004533,20.699680047) |

API保持 `CatchPoseAnchors.anchor(species:frame:) -> PoseClip.Anchor?`，支持两鸟各22个帧名；`DetailedBirdArt.catchImage(_:species:part:)`、`catchBillAnchor(_:species:)`沿现有make/poseImage/poseBillAnchor接入。CatchArtGeometry提供独立物种几何及共有常量；Profile/Definitions/PoseClip与出击、返回、落稳判定由主会/core接入，本切片未修改这些文件。

## 导出与静态审查

- BirdArt.poseExportSpecies为原12鸟与catch物种的有序并集，保留12鸟原顺序后追加白眉；metadata仅生成实际可用clip，GIF基础轨道使用compactMap，不为白眉索取未制作的十帧基础姿态。
- 已导出78份循环GIF：旧72份文件名保留，新增白眉0.5×/1×/2×双向六份，共7800帧、loop=0检查通过；白眉仅catch展示轨道。SharedArt保持schema，追加白眉metadata及图集三帧；不新增道具。
- M6ContentVerification提供白眉catch联系表及六张双向/缩放静态预览；InsectCatchArtVerification提供两鸟四语义层与上喙实际alpha检查，白眉独立source左右联系表。十九复用锚、两鸟六姿态独立性、白眉37帧及catch-only metadata相关原生检查随完整birds首轮通过。
- FeedingArtVerification保留旧34/allopreening及全部preCatch前缀/顺序/去重断言，仅扩充明确的白眉catch尾段；parity精确校验37帧、空基础poseFrames与22个catch/transport喙锚，首轮通过。
- 静态源码对照13e4733：移除新白眉分支并还原同值常量后，DetailedBirdArt旧绘制操作保持；家燕三姿态原始参数及昆虫几何源码保持。该结论不是逐像素或原生验收通过。
- 白眉翼轮廓含最大0.5逻辑单位描边界限为x8…40.5、y7.5…38.1；喙最前端约x43.213，头颈连接最大y28.624低于脚平面39。完整birds首轮通过；主会已查看白眉catch联系表及0.5×右向连续四帧，Euclid已逐组审阅六组native，具体结果与观感边界见下表。

## 统一验收记录

| 检查 | 必需证据 | 本批结果 |
| --- | --- | --- |
| Release / 严格签名 | 全部实现后统一构建 | 首轮PASS：Release 79.40s，`.build/m6f2-build-initial.log`；严格签名通过，`.build/m6f2-signature-initial.log` |
| 核心测试 | 出击/真实接触/返回落稳、失败恢复、暂停/取消、原点失效及零残留；两鸟既有契约回归 | 第三轮完整876项中其余875项通过（142.466s），`.build/m6f2-tests-third.log`；修正新增边界断言后第四轮白眉16项全部通过、0失败，wall 6.981s，`.build/m6f2-tests-fourth-targeted.log`。两轮合并覆盖，不是单次876全绿 |
| 完整birds原生 | 两鸟行为及素材原生检查 | 首轮3322项全部PASS：`.build/m6f2-birds-initial/report.json` |
| 设置与观察 | 白眉独立预览、中英controls/journal、来源及唯一成功计数 | 首轮1820项全部PASS：`.build/m6f2-settings-initial/report.json`；主会已查看中英controls及英文journal正常，截图目录`insect-catch-settings-EAC7E15E-A2E1-46E9-B11E-87CB05D391F3` |
| 回放 | 18夹具×30/60/120Hz完整报告及旧行为回归 | 54份跨率回放通过：`.build/m6f2-replays.log`；旧17份报告不剔除字段完全一致：`.build/m6f2-delivery/legacy-replay-comparison.json` |
| 压力 / 性能 | 实际负载与同机对照 | 第四轮24/64居民各实际完成2次捕获、1次取消，暂停与清理回归通过。性能18/18 PASS，全部metrics/cleanup一致；p50 ordinary +1.973684%、crowded −0.669912%、long −1.891235%，均低于10%阈值：`.build/m6f2-performance/summary.json` |
| 像素与索引 | 对13e4733保护46鸟全部旧帧及家燕catch包；白眉仅追加3帧，道具不变 | PASS：46鸟旧像素/索引不变，恰新增3张鸟体：`.build/m6f2-delivery/legacy-pixel-comparison.json` |
| 导出 / parity / GIF | 37帧白眉图集、catch-only metadata/22锚、78GIF/7800帧/loop=0及旧72份回归 | PASS：`.build/m6f2-export-initial.log`、`.build/m6f2-parity-initial.log`；78GIF/7800帧/loop=0及旧72文件名保留：`.build/m6f2-delivery/gif-validation.json` |
| 视觉 | 实际联系表及0.5×/1×/2×双向源图、生产连续图层、真实接触与恢复 | 主会已查看白眉catch联系表及0.5×右向连续四帧；Euclid逐组审阅六组native，均返回原脚位completed、观察交付时perched，95项专项检查全true。虫速137.78–234.89pt/s、提前1.198–1.539s、60Hz虫宽比例0.072–0.489；0.5×虫点可追踪但四帧细节难辨，深色背景通过不替代杂乱桌面观感 |
| 安装与硬件边界 | 未安装；物理多屏/热插拔、真实睡眠唤醒、2h/8h及长期内存/能耗另列 | 未验收 |

## 核心测试失败与修正历史

- 首轮：测试代码hostID可选值未解包导致编译失败，Pascal已用XCTUnwrap修正；该轮不能记作断言失败或测试通过。
- 第二轮：876项、513次断言失败、144.169s。`Tests:132`的ground检查将额外2pt hit padding当作画布范围，产生510次失败；`Scheduling:59`跨draws完整报告比较产生3次失败，共涉及两方法。Lorentz只读解析两侧报告确认仅`schedulerRemaining`不同，实际idle帧也完全一致；先前idle帧不同的猜测不作为结论。
- 第二轮修正：ground检查实际render rect/landingFootprint；同draws跨Hz仍完整比较，跨draws仅归一化`schedulerRemaining`。Hooke只读复审通过，生产代码未改。
- 第三轮：完整876项、1244次断言失败、142.466s，全部仅新增`Tests:141`的严格`landing.contains(render.rect)`，其余875测试通过；实际render和landing各自严格屏内检查及Scheduling修正均通过。Pascal用同夹具x=1870.6、scale=0.4022709261691359复现render.maxX与landing.maxX差2.2737367544323206e−13，即1ULP；这是同夹具复现值，不声称是失败tick实际值。
- 第四轮：仅将上述新增相互包含断言改为逐边≤4ULP，保留两项严格屏内断言，生产代码未改。`swift test --filter FlycatcherInsectCatch` exit 0，16项0失败，wall 6.981s，覆盖修正的1项与其余白眉回归。复用第三轮其余875项通过证据，不重跑无关测试，也不将两轮数量相加为单次测试总数。

性能为同机加速核心对照，不是原生渲染、长期堆内存或能耗测量；实际捕获另由专项测试与native覆盖。0.5×虫点可追踪但四帧细节难辨，已审深色背景不替代杂乱桌面。物理多屏/热插拔、真实睡眠唤醒、2h/8h及长期内存/能耗仍未验收。

运行结果由主会提供，素材owner读取第四轮日志与已有证据后更新文档，本轮未修改源码、运行验证、安装或提交。保留前三轮失败历史；本批阶段验收通过不代表整个M6/M7目标完成。
