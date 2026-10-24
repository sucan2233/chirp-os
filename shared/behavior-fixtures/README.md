# 行为输入格式与共享场景 v1

这些 JSON 是引擎输入，采用 Quartz 桌面坐标（向右为 x 正方向，向下为 y 正方向）。它们不依赖 AppKit、窗口标题、桌面截图或用户配置，供 macOS 与后续 Windows 核心运行同一场景。

- `version`：文件格式版本；未知版本拒绝，不能忽略无法理解的事件。
- `simulationVersion`：M6d 当前为12，单scheduler场景模式、日常13%预留区间及共享租约改变模拟语义。旧生产录制版本1–11明确拒绝；请在相应旧提交重放或重新录制，不能直接改版本标签。14份仓库手写夹具保留原输入与独立断言，仅迁移版本；新增第15份浴盆夹具。v11曾完成42次与M6a/b完整报告对照；v12不承诺旧摘要不变，不从当前实现反向生成expected。
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

`clearLeaf` 无 payload，仅清除落叶及待释放落叶，保留已放置食盘和食盘待放置；`clearProps` 同时清除食盘、食盘待放置并取消访客；两者均完整录制和重放。`cancelAmbient` 取消待放置。`pause(true)` 冻结待放置倒计时、对象寿命及访问阶段；继续后从剩余时间推进。`settings.foodTrayEnabled` 默认 true，关闭后取消待放置并移除食盘。quiet 不新增自动访问，允许已启动访问完成及手动预览。

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

# 手写场景：观察/警觉、完整落叶返程、双鸟招呼、暂停中点击迁移、侧跳、起飞准备、熟客再次到访、安静节奏与手动群飞、边缘探头来回与暂停、双鸟追逐与暂停
dist/ChirpOS.app/Contents/MacOS/Birding --replay-behavior shared/behavior-fixtures/v1/leaf.json
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
