# 行为输入格式与共享场景 v1

这些 JSON 是引擎输入，采用 Quartz 桌面坐标（向右为 x 正方向，向下为 y 正方向）。它们不依赖 AppKit、窗口标题、桌面截图或用户配置，供 macOS 与后续 Windows 核心运行同一场景。

- `version`：文件格式版本；未知版本拒绝，不能忽略无法理解的事件。
- `simulationVersion`：M6f.2当前为15，新增白眉姬鹟出击返回捕虫语义。旧生产录制版本1–14明确拒绝；请在相应旧提交重放或重新录制，不能直接改版本标签。旧17份仓库手写夹具保留原输入和独立断言，仅迁移版本；新增第18份`flycatcher-insect-catch.json`。18夹具在30/60/120Hz的54份完整报告一致，旧17夹具60Hz报告不剔除字段与M6f.1完全一致；不从当前实现反向生成expected。第16份仍为`leaf-carry.json`，第17份仍为`insect-catch.json`，v13/v14历史结果见下文。
- `seed`、鸟/运行/道具/栖息地对象 ID 使用十进制字符串，避免 JavaScript 等环境丢失 64 位整数精度。
- `settings`：完整配置或合法的旧格式配置；按 BirdSettings schema 迁移。
- `initialWorld`、`fixtureBirds`：共享夹具可指定初始表面和已停稳鸟；可选 `flightOrigin` 让鸟从该坐标开始普通直达飞行，仍需 `advance` 输入才能移动和产生速度。生产录制从空引擎开始，不注入或还原任意中途的可变 Bird。
- `inputs`：严格按数组顺序处理。支持 world、settings、visitorMemory、command、advance、population、reconcileLayout、arrive、depart、route。visitorMemory 仅允许在尚无鸟注册时恢复档案，随输入一起记录，不读取重放机器上的用户档案。
- `advance.elapsed`：一次原始回调时长，保持引擎 0.05 秒截断；`repeatCount` 仅压缩相同连续回调，默认 1。不可把长暂停变成补播。
- `advance.options`：此时实际启用的数量调度、环境调度和自主选路开关。
- `world.availableFrames`：首次输入或素材变化时写入完整清单；省略时继承上一世界，显式空字典会清空。避免每帧重复记录不变素材。
- `world.displayIDs`：与 displays 顺序对应的稳定标识；省略为空。`fixedPerchArtAvailable` 表示真实栖木素材是否可用，省略为 true；生产平台必须按实际资源填写。
- `world.foodTrayArtAvailable`：真实食盘素材是否可用，省略为 true。每次 world 输入都是该能力的完整快照；省略不继承前次 false。该字段的变化参与录制去重，不能被省略素材清单的压缩逻辑吞掉。
- `world.surfaces[].habitatKind`：可选 `fixedPerch`、`foodTray` 或 `bath`；未知标签拒绝。保留 `isFixedPerch` 旧格式兼容，缺少新标签时 true 映射为 `fixedPerch`；显式新标签优先。普通窗口缺少标签。对象表面由引擎对象存储生成，录制表面标签不能凭空恢复对象、食物或预约。
- `world.localMinuteOfDay`：本地民用时钟的分钟（0–1439）；缺失或 null 表示没有时钟输入，日夜模式采用中性节奏。重放不读取机器时区或当前时间；世界更新中省略该字段会清空，不继承。
- `world` 输入的 `sampleDT`：窗口采样时长。无该字段的世界更新只校验世界，不推进窗口跟随。
- `expected`：生产录制保存终态报告和完整事件序列。重放命令逐项比较，包括鸟坐标、姿态、生态记忆、道具、租约和熟客档案，以及下述栖息地对象状态。共享手写夹具另由 XCTest 对完成行为、取消原因及零残留作独立断言，不用当前实现反向生成通过标准。

## B14 食盘命令与报告

命令均使用 `kind: "command"`，payload 位于 `command`。下列名字区分大小写；缺少必填字段、未知来源、非法坐标或非法延时均拒绝。

| command.name | 必填 payload | 行为 |
| --- | --- | --- |
| `placeFoodTray` | `point: {x, y}` | 在指定脚锚放置一个食盘；不触发访问。完整图形与鸟体空间必须落在单块工作区及物理显示器内，避开占位和高层面板；已有盘返回 busy，不能覆盖、补食或重置寿命。 |
| `placeFoodTrayAfter` | `delay: 0...10` | 延时后按当时 world.pointer 尝试放置；只调度放盘。生产入口将非有限值替换为 3 秒并截断到 0...10，磁盘 payload 必须已规范化。 |
| `cancelFoodTrayPlacement` | 无 | 取消待放置倒计时。 |
| `removeFoodTray` | 无 | 取消待放置和访客，删除盘；飞行恢复从实际脚坐标开始。 |
| `foodTrayVisit` | `source: user / preview / automatic` | 仅复用已有麻雀或珠颈斑鸠，不能新增鸟。 |

`clearLeaf` 无 payload，仅清除原动态落叶及待释放动态落叶，保留静止携带叶片、已放置食盘和食盘待放置；`clearProps` 清除全部道具、食盘/浴盆/携带叶片及相应待放置并取消访客。静止携带叶片使用下文 `removeCarryLeaf`；这些命令均完整录制和重放。`cancelAmbient` 取消待放置。`pause(true)` 冻结待放置倒计时、对象寿命及访问阶段；继续后从剩余时间推进。`settings.foodTrayEnabled` 默认 true，关闭后取消待放置并移除食盘。quiet 不新增自动访问，允许已启动访问完成及手动预览。

访问需要真实 `stand`、`fly0...fly7`、`land0...land2` 和四帧 `feedLook / feedDown0 / feedDown1 / feedLift`，缺帧不得降级为通用姿态。先观察 0.8 秒，再真实接近及着陆，进食 3.6 秒后真实返回原脚锚并落稳。全程持有食盘对象槽和两个落点预约，每次完整进食只消费一份。食盘初始三份、180 秒模拟寿命；耗尽或到期先 retiring，等待已有访问结束后删除。明确移除则立即取消访问和释放预约。

自然访问只在居民原有 departure 机会用 25% 概率尝试，同一 motionRevision 只尝试一次；使用独立 SplitMix64 流 `seed XOR 0x464F4F4454524159`，遵守 quiet、素材、冷却和环境安全门槛。放盘不创建新的随机计时器或强制离栖。

version 10 的报告增加：

- `habitats`：按对象 ID 排序的快照。每项包含十进制字符串 `id`、`kind: "foodTray"`、命名坐标 `rect`、`blockers` 矩形数组、`remainingUses`、`retiring`、`remainingLifetime`（秒）。对象独立于 run，访问完成后仍可存在。
- `hasFoodTrayPlacement`：是否有待放置倒计时。
- `habitatReservations`：运行持有的对象槽数量。原 `reservations` 继续统计落点预约；食盘访问活跃时分别为 1 和 2，完成/取消后均为 0。

安全边界：最多 32 MiB、60,000 条输入、216,000 个回调、一小时有效模拟；最多 16 个显示器、256 个表面、64 个初始鸟。不完整/超限录制不能保存为正常记录。生产输入通过命令行显式启用，仅保存在指定本地文件。

## 使用

```sh
# 开发构建，然后录制一个单独的 8 秒本机测试进程（也可不指定时长，正常退出时保存）
CHIRPOS_DEVELOPMENT_BUILD=1 ./scripts/build.sh
dist/ChirpOS.app/Contents/MacOS/Birding --record-behavior .build/live-behavior.json --record-duration 8

# 不打开原生窗口即可重放。expected 存在时，不一致会退出 1。
dist/ChirpOS.app/Contents/MacOS/Birding --replay-behavior .build/live-behavior.json --replay-hz 120 --replay-output .build/replay-report.json

# 旧动态落叶追随场景
dist/ChirpOS.app/Contents/MacOS/Birding --replay-behavior shared/behavior-fixtures/v1/leaf.json

# 第16份场景：静止叶片携带；使用已统一验证的构建，无需为文档另行构建
dist/ChirpOS.app/Contents/MacOS/Birding --replay-behavior shared/behavior-fixtures/v1/leaf-carry.json --replay-hz 120 --replay-output .build/leaf-carry-report.json

# 第17份场景：家燕捕虫、暂停/取消及真实捕获恢复（当前模拟v15）
dist/ChirpOS.app/Contents/MacOS/Birding --replay-behavior shared/behavior-fixtures/v1/insect-catch.json --replay-hz 120 --replay-output .build/insect-catch-report.json

# 第18份场景：白眉姬鹟栖点出击、暂停/返回及取消后独立虫继续（模拟v15）
dist/ChirpOS.app/Contents/MacOS/Birding --replay-behavior shared/behavior-fixtures/v1/flycatcher-insect-catch.json --replay-hz 120 --replay-output .build/flycatcher-insect-catch-report.json
```

当前 macOS 测试把同一输入序列分别拆成至多 1/30、1/60、1/120 秒的回调，比较完整报告；保留输入发生边界，不跨 world/command 合并时间。这验证回调分段稳定性，不宣称恢复录制时没有采到的鼠标轨迹。不同采样率的真实移动轨迹另由 PassiveEcologyTests 验证。Windows 解析器与原生验收尚待迁移，当前文件通过不代表跨端已经对齐。

`travel-together.json` 从两只普通飞行鸟开始，经过非零速度接续、同行与暂停后分别落到原目标；再次请求应拒绝停栖候选。独立断言检查原落点、参与者、完整完成及拒绝原因。

`allopreening.json` 从同窗相邻的家燕开始，接近、理羽、暂停继续并退回两个原位；独立断言检查完成、原落点和资源释放。

`fixed-perch.json` 从已有居民的窗口脚位出发，真实飞往保存的栖木中心并落稳；独立断言检查目标坐标、原居民 ID、完整完成、栖木快照和资源释放。

`food-tray.json` 是第 14 个共享场景：已有麻雀停稳后放盘，观察、真实接近、暂停继续、进食并返回窗口原脚锚。独立断言检查原居民 ID、原脚坐标、一次完整完成、两份余粮和零运行/预约；三种回调频率比较完整报告。`FoodTrayTests` 另对两种鸟的中间状态、到期/耗尽延迟删除、取消恢复及自动种子样本设断言。

## M6d 浴盆与场景焦点

`placeBath(point)`、`placeBathAfter(delay)`、`cancelBathPlacement`、`removeBath`及`bathVisit(source)`采用食盘相同payload形状；`clearCurrentScene`清除当前食盘或浴盆及待放置。两种对象共用一个容量，退休仍占容量，不覆盖已有场景。`world.bathArtAvailable`每次world输入独立快照，缺省true，实际平台按可绘制资源填写。

浴盆固定水线y20、单槽脚(64,20)，128×40画布；只支持麻雀和白头鹎，必需7张bath姿态及shake、stand、完整起降帧。300秒寿命、三次完整访问，安全返程落稳才扣次。取消不计成功，暂停冻结寿命/年龄/水花；暂停删除立即解开承载引用，恢复后使用已有找落点/离场路径。

唯一sceneFocus控制同一AmbientScheduler：首机会min(remaining,10)，用户输入60秒抑制优先；场景机会70%尝试浴盆，30%旧选择器；低/中/高间隔30–45/20–35/15–25秒。日常8%捕虫/4%求偶/1%礼物区间本批仍为空机会。新随机流使用固定盐，暂停不消费。

报告增加`hasBathPlacement`、`sceneFocusID`、`schedulerRemaining`、`sceneCooldownRemaining`、`userInputRemaining`；道具记录frame与anchor，使水花相位也参与回放比较。`bath.json`覆盖已有居民试水/洗澡/暂停/真实返回，独立断言不依赖生成的expected。统一验证结果在M6d验收文档记录。


## M6e 静止叶片携带（模拟版本13）

命令沿用上表的 `command` payload；本批已实现并通过统一验证。

| command.name | 必填 payload | 行为 |
| --- | --- | --- |
| `placeCarryLeaf` | `point: {x, y}` | 在合法普通窗口顶沿或地面支撑点放一枚静止叶片；不创建鸟、不启动携带。 |
| `placeCarryLeafAfter` | `delay: 0...10` | 到期读取当时world.pointer放置；暂停冻结，非法磁盘值拒绝。 |
| `cancelCarryLeafPlacement` | 无 | 只取消待放置倒计时。 |
| `removeCarryLeaf` | 无 | 清除携带叶片各状态和待放置，取消所属run；保留原动态落叶追随。 |
| `leafCarry` | `source: user / preview / automatic` | 招募已有麻雀，真实接近、拾取、短途携带及放下；缺物种/帧/空间明确拒绝。 |
| `clearCurrentScene` | 无 | 清除当前食盘/浴盆/携带叶片及相应待放置；与仅清动态叶片的clearLeaf区分。 |

`settings.leafCarryEnabled`缺省true，仅持久化开关，独立于动态落叶；关闭后取消待放置并清理携带实体。`world.leafCarryArtAvailable`每次world输入为完整快照，省略true，不继承前次false。叶片16×16，独立worldScale，柄(3,12)/支撑(10,12)，接触帧喙(40,39)，鸟脚(29,39)；左右按同源变换。一次仅一枚实体，同一ID贯穿available/attached/placed/retired。拾取前180s、附着受25s run上限约束、放下后8s且最后0.2s淡出；只有放下并恢复结束才completed和入册。

普通食盘可以与叶片共存；浴盆与可拾取叶片争用唯一sceneFocus。放下即退出叶片场景提频，恢复期间仍持有原run资源。场景机会70%尝试当前焦点，沿用独立随机流与60s用户输入抑制；忙碌不补发，不新增timer。

版本13报告增加 `carriedObjects`（状态、owner/reservedByRun、宿主身份与比例、worldScale、朝向、剩余寿命）、`hasCarryLeafPlacement`、`sceneFocusKind`，以及 `props[].mirrored`；完整报告连同已有位置/锚/旋转共同对照。`leaf-carry.json`覆盖完整携带、暂停、放下后自然到期、第二次运行暂停删除、延时放置取消与场景清理；XCTest独立断言同一实体、唯一终态及零残留。

最终证据：826核心测试通过；第二轮48完整回放见 `.build/m6e-replays-second.log` 与 `.build/m6e-replays/`。旧15报告回归见 `.build/m6e-delivery/legacy-replay-comparison.json`，比较时仅去除 `carriedObjects/hasCarryLeafPlacement/sceneFocusKind/prop.mirrored`。阶段已验证交付、随本阶段记录本地提交、未安装，详见 [M6e验收](../../docs/M6E-ACCEPTANCE.md)；不代表Windows迁移、物理多屏或真实长期桌面验收。

## M6f.1 家燕捕虫（历史模拟版本14）

| command.name | 必填 payload | 行为 |
| --- | --- | --- |
| `insectCatch` | `species: "barnSwallow"`、`source: user / preview / automatic` | 只复用已有普通飞行居民。preview可等待已有鸟自然起飞最多10s；不补鸟、传送或强制起飞。 |
| `cancelInsectCatchPreview` | 无 | 取消尚未开始的等待；已启动run由既有取消/清理入口处理。 |
| `clearInsect` | 无 | 清虫、取消捕虫run及待预览；暂停中也可清理。 |

`settings.insectCatchEnabled`默认true，仅保存开关；关闭会立即清虫并取消等待/run。`world.insectArtAvailable`是每次world输入的独立完整快照，省略true，不继承旧false；鸟帧缺失仍拒绝。`clearCurrentScene`、`clearProps`均涵盖虫与捕虫等待/run；点击取消后虫保持同一ID、沿原路线运行剩余寿命，暂停冻结虫/阶段/等待/冷却。日常固定8%机会尝试捕虫，sceneFocus模式不尝试；独立随机流、无资格即丢弃，不新增timer。

仅家燕catch三帧及19复用帧真实喙锚；虫16×16、中心(8,8)、碰撞半径3×worldScale、12fps、12s寿命、全局最多1只。整画布从屏外进入，完整可见到窗口至少0.8s，速度≤480×worldScale；contact候选1.2/2/2.8/3.6s、首段末端+0.25s，优先前侧斜入并保持鸟初速切线和原目标。连续真实喙resolver检测完整运动段，只有真实接触才移除虫；合喙0.18s/恢复0.30s并恢复原目标后才completed。错过则安全恢复后failed/missedTarget，不入册。

v14报告增加 `insect`、`lastInsectContact`、`insectMissedTargetCount`、`hasInsectCatchPreview`、`insectPreviewRemaining`、`insectPreviewSpecies`、`insectCooldownRemaining`。第17夹具保留独立断言，逐输入前缀覆盖暂停、点击取消、原虫继续、清虫、第二次真实接触及回原目标落稳；另有成功/错过的跨率分段报告和24/64居民实际工作负载。

阶段验收通过：860核心/3156原生鸟/1782设置、51完整报告、旧16份去上述7字段兼容、三轮18次性能通过。最终回放在 `.build/m6f1-replays/`，初轮保留 `.build/m6f1-replays-initial/`，旧比较在 `.build/m6f1-delivery/legacy-replay-comparison.json`。随本阶段记录本地提交、未安装；首轮失败与完整边界见 [M6f.1验收](../../docs/M6F1-ACCEPTANCE.md)。白眉姬鹟的后续交付见下节，Windows与真实长期/物理硬件验收不由这些报告替代。

## M6f.2 白眉姬鹟出击返回（当前模拟版本15）

`insectCatch`的species现支持`barnSwallow`与`yellowRumpedFlycatcher`，来源仍为user/preview/automatic，取消与清虫命令保持。白眉预览直接招募已有合法普通窗口顶部/地面停栖居民，不等待普通飞行、不补鸟，不新增固定小栖木资格；预约原脚位，出击80–220逻辑点、拦截段≤3s、run≤25s。真实捕获后合喙恢复并尝试返回原脚位，原点失效从实际脚位寻找安全落点，最终落稳才completed；错过或取消不入册。两鸟共用原8%机会、单虫及单run，既有暂停/清理规则保持，无新时钟。

第18夹具覆盖暂停、真实返回、再次出击及暂停点击取消后原虫继续，保留独立语义断言。模拟v15的54完整报告跨率一致：`.build/m6f2-replays.log`；旧17份报告不剔字段与M6f.1完全一致：`.build/m6f2-delivery/legacy-replay-comparison.json`。以上重放命令已随统一验收执行，文档收尾未重复运行。

M6f.2阶段验收通过：第三轮完整876项中其余875项通过（142.466s），第四轮`swift test --filter FlycatcherInsectCatch`的16项全通过（6.981s），覆盖修正的1项及其余白眉回归，不宣称单次876全绿。24/64居民各实际完成2次捕获与1次取消；Release/严格签名、3322原生鸟、1820设置、46鸟旧像素/索引、恰增3鸟帧无新道具、parity、78 GIF/7800帧/loop0及18次性能通过。累计150鸟体/10道具，剩17/6；随本阶段记录本地提交、未安装，用户安装版仍M6a/b。前三轮测试失败、1ULP同夹具复现与≤4ULP断言修正见[M6f.2验收](../../docs/M6F2-ACCEPTANCE.md)，生产代码未因这些修正改变。下一阶段M6g；物理多屏/热插拔、真实睡眠唤醒、2h/8h及长期内存/能耗仍未验收。
