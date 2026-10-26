# 啾啾 Pro · ChirpOS Pro

本项目以 `main` 作为自主维护主分支，开发及上游更新流程见 [维护约定](CONTRIBUTING.md)。

本地 macOS Pro 测试版已包含 M8 与 E0–E5 的百鸟动作增强。运行 `bash scripts/package-pro-macos.sh` 生成 `ChirpOS Pro.app`、ZIP 和可拖放安装的 DMG；安装与数据说明见 [Pro 测试包](docs/PRO-TEST-PACKAGE.md)。下方下载链接为上游普通版历史发行包，不含本分支增强内容。

**下载 / Download**

| 平台 / Platform | 最新版本 / Latest release |
| --- | --- |
| Windows · Intel / AMD 64-bit | [下载 ZIP · v0.6.0](https://github.com/billtt/chirp-os/releases/download/v0.6.0/ChirpOS-0.6.0-win-x64.zip) |
| Windows · ARM64 / UTM | [下载 ZIP · v0.6.0](https://github.com/billtt/chirp-os/releases/download/v0.6.0/ChirpOS-0.6.0-win-arm64.zip) |
| macOS · Apple Silicon | [下载 ZIP · v0.6.0](https://github.com/billtt/chirp-os/releases/download/v0.6.0/ChirpOS-0.6.0-macOS-arm64.zip) |

[所有版本 / All releases](https://github.com/billtt/chirp-os/releases) · [简体中文](#中文) · [English](#english)

![啾啾桌面运行预览 / ChirpOS desktop preview](preview.gif)

**让你的桌面，时不时来只鸟。 / A little birdlife on your desktop.**


## 中文

啾啾是一款 macOS 和 Windows 桌面观鸟应用。像素小鸟从屏幕外飞来，在窗口顶沿歇脚、眨眼、理羽，陪你工作。它们不抢焦点，也不会挡住鼠标操作。

### 有什么好玩的

- 多种小鸟，各有鲜明外形和习性动作，详见下方[鸟种列表](#鸟种--bird-species)。
- 飞行节奏按鸟种定制：猛禽交替振翅、滑翔与长时间盘旋；鹭类缓慢深拍，小型林鸟短促振翅，燕类转弯，啄木鸟起伏飞行。
- 小鸟随窗口缓慢移动，快速拖动时可能受惊飞走；前方窗口会遮住后方停留的小鸟。
- 没有合适的窗口落点时，小鸟会在 Dock／任务栏上方的屏幕底部歇脚；支持多屏及自动隐藏。
- 鸟群随机飞入、飞出，可设置数量范围，例如 3–5、8–12 或 15–20 只。
- 自由调整每种鸟的出现概率并锁定；也可设置体长、振翅频率、飞速和停留时间。
- 鼠标停在小鸟身上约 1 秒，头顶就会显示名字；macOS 可在“鸟种设置 → 交互”中将等待时间调整为 0–10 秒，设为 0 即时显示；点击仍会穿透。
- macOS 上点击小鸟可让它飞到其他位置，避开原来的落脚区域；点击仍会穿透到下方窗口，不抢焦点。
- macOS 新增偶发动作：鼠标静止且周围空间足够时，一只小鸟可能在安全距离外绕一圈；移动或点击即可结束。另有 3–5 只同种鸟错峰掠过屏幕上部，过境鸟不占常驻数量。
- “鸟种设置 → 交互”可分别开关绕鼠标与鸟群过境，选择低／中／高频率并预览。默认低频，两种动作合计每 3–6 分钟尝试一次，条件不合适时跳过；暂停、睡眠不累积事件。
- macOS 小鸟停稳后会偶尔闭眼休息，着陆后可能整理羽毛，每只鸟的节奏有所不同；鼠标靠近或点击即可打断。在“鸟种设置 → 交互 → 停栖小动作”中开关和预览。
- macOS 开发版可在“鸟种设置 → 交互 → 固定小栖木”中放置最多 3 根栖木：点击放置后把鼠标移到目标位置，3 秒后记录，再保存并应用。支持的现有小鸟会偶尔飞来停留，也可手动预览；关闭开关保留位置。
- macOS 开发版可放置浅水浴盆，供麻雀与白头鹎偶尔试水、拍翼洗澡并甩水离开。浴盆保留最多 5 分钟或 3 次完整访问，与食盘共用一个场景位置；暂停会冻结寿命与动作，完成返程落稳后才记入观察手册。
- macOS 开发版支持独立的“放置叶片 / 清除 / 预览携带”：已有麻雀可飞来拾起静止叶片，短途携带后放下；叶片待拾取最多 180 秒，放下后显示 8 秒。暂停冻结动作与寿命，放下并恢复结束才记入观察手册；与原有动态落叶追随分别开关。
- macOS 开发版支持家燕空中捕虫：复用正在普通飞行的居民，拦截独立昆虫后合喙恢复并继续原目标。预览最多等待 10 秒自然起飞；暂停冻结动作，真实捕获并恢复后才记入观察手册。
- macOS 开发版已实现白眉姬鹟从普通窗口或地面栖点出击捕虫并尝试返回原脚位；原点失效时寻找安全落点，捕获且最终落稳才记入观察手册。本阶段验收通过，不新增固定小栖木资格。
- 夜鹭会长时间守望、伸颈、抖毛，偶尔“挤洗手液”；大斑啄木鸟会沿窗口侧边停靠、啄击。
- 合并前版本菜单中的“图鉴”以网格展示全部鸟种，顶部手动选择休息、飞行、振翅、滑翔、着陆、理羽或其他习性动作。
- 合并前 macOS 开发版的“观察手册”：行为完成后按鸟种记录首次／最近时间和次数，分别标明自动、手动与预览。支持搜索和来源筛选，数据保存在本地；发现新行为不会弹窗。
- 每小时自动检查更新，下载并校验后以气泡提醒；确认后安装并重启。忽略或稍后处理时保留红点和菜单入口。
- 支持中英文切换、暂停动画和随系统启动。

U 阶段进度（2026-10-26）：已在 `codex/upstream-v07-integration` 接入100种基础内容，合并“观鸟手册”的发现、全部鸟种、行为记录和详情；新增54种不自动取得专用生态动作资格。既有概率与锁定保持，新鸟初始0%，由用户选择分配。观鸟记录与换位分流，保留真实指针的路线安全检查。已生成独立开发候选，核心修订复验、素材和新手册检查通过；完整原生场景仍有路线受阻等保留项，未替换安装版或发布v0.7.0。详细功能、数量、失败轮次与验收边界见[U交付记录](docs/U-INTEGRATION-ACCEPTANCE.md)。下述M6/M7证据属于合并前历史。

历史开发进度（2026-10-25）：M7a珠颈斑鸠求偶已通过阶段验收。M7b/c巢材运输与简化筑巢已实现：用户放置巢台和三根材料，运输与整理分别记录，取消保留已提交进度，不自动补充材料。8张新姿态和6张新道具已导出，46鸟旧像素/索引保持，66份跨率回放及旧20份完整报告一致，78 GIF/7800帧通过。全量核心992项、修正后巢台定向46项和素材347项通过；第八轮候选巢台专项1116项、完整鸟行为4593项及设置2190项全部通过，M7b/c阶段验收通过，累计167张新姿态和16张道具。2026-10-25已保护设置与草稿并安装重启；V03补验7546项通过；8h默认工作负载已自然退出并通过事件、资源清理和偏好隔离审阅。短时单屏已完成全屏切换及关闭后恢复检查；2h人工观察门槛按用户要求取消，窗口跟随、菜单暂停及真实sleep/wake按用户确认保留未验；外接双屏/热插拔因无设备未验收。详细轮次、失败历史和性能口径见[M7b/c验收](docs/M7BC-ACCEPTANCE.md)。

当前已安装开发版保持M7b/c候选；本轮U候选另存独立路径。历史安装与数据保护证据见[M7d记录](docs/M7D-ACCEPTANCE.md)。M6h状态栏隔离修正后的真实30秒smoke及22项离线检查通过；8h默认工作负载另已完成，2h人工观察时长门槛已按用户要求取消；窗口跟随、菜单暂停及真实睡眠唤醒按用户确认保留未验，物理多屏无设备未验。M6/M7已按用户确认的验收范围完成本次交付，保留上述未验项目，详见[实施进度](docs/IMPLEMENTATION-PROGRESS.md)与[M6h记录](docs/M6H-ACCEPTANCE.md)。

### 鸟种 / Bird species

下表为原46种基线。U阶段已扩展至100种，完整候选目录见 [`shared/species.json`](shared/species.json)；新增54种清单见[扩种清单](docs/species-expansion-100.json)，验收边界见U交付记录。

The table lists the original 46 species. The U integration contains 100 species; see the U delivery record for candidate validation and remaining native checks.

| 中文 | English |
| --- | --- |
| 红耳鹎 | Red-whiskered Bulbul |
| 麻雀 | Eurasian Tree Sparrow |
| 白头鹎 | Light-vented Bulbul |
| 珠颈斑鸠 | Spotted Dove |
| 乌鸫 | Chinese Blackbird |
| 鹊鸲 | Oriental Magpie-Robin |
| 棕背伯劳 | Long-tailed Shrike |
| 夜鹭 | Black-crowned Night Heron |
| 红尾水鸲 | Plumbeous Water Redstart |
| 白鹭 | Little Egret |
| 苍鹭 | Grey Heron |
| 红隼 | Common Kestrel |
| 游隼 | Peregrine Falcon |
| 黑鸢 | Black Kite |
| 普通鵟 | Common Buzzard |
| 喜鹊 | Oriental Magpie |
| 灰喜鹊 | Azure-winged Magpie |
| 大嘴乌鸦 | Large-billed Crow |
| 戴胜 | Eurasian Hoopoe |
| 家燕 | Barn Swallow |
| 绿头鸭 | Mallard |
| 噪鹃 | Asian Koel |
| 暗绿绣眼鸟 | Swinhoe’s White-eye |
| 红嘴鸥 | Black-headed Gull |
| 中杓鹬 | Whimbrel |
| 斑鱼狗 | Pied Kingfisher |
| 丘鹬 | Eurasian Woodcock |
| 黑卷尾 | Black Drongo |
| 池鹭 | Chinese Pond Heron |
| 白眉姬鹟 | Yellow-rumped Flycatcher |
| 黄眉柳莺 | Yellow-browed Warbler |
| 大山雀 | Japanese Tit |
| 黑水鸡 | Common Moorhen |
| 大斑啄木鸟 | Great Spotted Woodpecker |
| 棕头鸦雀 | Vinous-throated Parrotbill |
| 黑翅长脚鹬 | Black-winged Stilt |
| 白骨顶 | Eurasian Coot |
| 红嘴相思鸟 | Red-billed Leiothrix |
| 黑领椋鸟 | Black-collared Starling |
| 普通翠鸟 | Common Kingfisher |
| 金眶鸻 | Little Ringed Plover |
| 黑尾蜡嘴雀 | Yellow-billed Grosbeak |
| 红胁蓝尾鸲 | Red-flanked Bluetail |
| 领角鸮 | Collared Scops Owl |
| 斑头鸺鹠 | Asian Barred Owlet |
| 纵纹腹小鸮 | Little Owl |

### 开始观鸟

**Windows：** 下载对应架构的 ZIP，解压后运行 ChirpOS.exe，无需安装 .NET。支持 Windows 10/11 x64 和 Windows 11 ARM64。

**macOS：** 下载并解压 ZIP，将 `ChirpOS.app` 拖入“应用程序”后打开。下载版适用于 macOS 13 及以上的 Apple Silicon Mac。

启动后稍等片刻，小鸟就会陆续飞入。点击 macOS 菜单栏或右键点击 Windows 系统托盘中的小鸟图标，即可调整设置或退出。Windows 图标可能位于托盘的隐藏图标区域。更新前请先退出正在运行的版本。

历史发行版会在启动时提示新增鸟种。U阶段保留旧概率与锁定值、新54种初始0%，通过设置内提示由用户分配份额；不沿用会缩放锁定值的按数量分配。体型按成年鸟代表体长进行非线性缩放（红耳鹎 1×、苍鹭 2.5×），部分配色采用雄鸟或繁殖羽；动作经过像素化简化。

macOS 版本使用 Developer ID 签名并经过 Apple 公证。Windows 版本尚未使用发布者证书签名，首次打开可能遇到系统安全提示。

### 隐私与反馈

啾啾在本机运行，仅读取窗口位置、前后顺序和用于悬停识别和偶发绕飞的鼠标位置；macOS 还监听鼠标左键按下的位置，用于让点击的小鸟换个位置，不记录点击内容。不读取窗口标题或内容，也不上传窗口信息或个人设置。自动更新会连接 GitHub 检查版本并下载官方安装包。窗口遮挡按矩形估算，透明窗口、圆角和特殊系统界面的效果可能有所不同。

遇到问题或有新点子，欢迎提交 [Issue](https://github.com/billtt/chirp-os/issues)。想自己构建或贡献代码，请看[开发指南](docs/DEVELOPMENT.md)。

## English

ChirpOS brings pixel-art birds to your macOS or Windows desktop. They fly in from offscreen, perch on window edges, blink, and preen while you work—without taking focus or intercepting mouse clicks.

### Features

- Distinctive bird species, each with its own appearance and behavior. See the [Chinese–English species list](#鸟种--bird-species).
- Species have individual flight rhythms: raptors alternate powered flight with extended soaring, herons use slow strokes, small woodland birds use short bursts, swallows weave and woodpeckers bound.
- Birds follow gently moved windows and may startle when dragged quickly. Foreground windows hide birds perched behind them.
- When window perches are unavailable, birds rest along the screen bottom above the Dock or taskbar, including multi-monitor and auto-hide layouts.
- Birds arrive and leave at random, with configurable population ranges such as 3–5, 8–12, or 15–20.
- Adjust and lock arrival probabilities, and customize size, wingbeat rate, speed, and perch duration.
- Hover over a bird for about 1 second to see its name, with clicks still passing through. On macOS, adjust the delay from 0 to 10 seconds in Bird Settings → Interaction; 0 shows names immediately.
- On macOS, click a bird to move it to another spot away from its previous perch. Clicks still pass through to the window beneath without taking focus.
- macOS development builds support up to three fixed perches in Bird settings → Interaction → Fixed perches. Click Place, move the pointer to the desired position, then Save & Apply after the three-second capture. Existing supported birds occasionally visit; manual preview is also available. Turning the feature off keeps saved positions.
- macOS development builds offer a shallow bath for Eurasian Tree Sparrows and Light-vented Bulbuls. Birds may test the water, splash, shake, and return safely. The bath lasts up to five minutes or three completed visits and shares one scene slot with the food tray. Pausing freezes its lifetime and animation; visits count only after the bird returns and lands.
- macOS development builds add separate Place leaf, Clear, and Preview carrying controls. An existing Eurasian Tree Sparrow can pick up a stationary leaf, carry it a short distance, and put it down. Leaves wait up to 180 seconds and remain visible for eight seconds after placement. Pause freezes both motion and lifetime; the journal counts a visit only after placement and recovery finish. This has its own switch, separate from following a falling leaf.
- macOS development builds let an existing Barn Swallow intercept an insect during ordinary flight, close its bill, and resume its original destination. Preview waits up to ten seconds for natural flight. Pause freezes the action; the journal counts only a real capture followed by recovery.
- macOS development builds also implement Yellow-rumped Flycatcher sorties from ordinary window or ground perches, attempting to return to the original foot position or a safe alternative. The journal counts only a capture followed by a settled landing. This stage passed acceptance and adds no fixed-perch eligibility.
- macOS encounters: a small bird may circle a stationary pointer at a safe distance when there is room; moving or clicking ends the visit. Loose flocks of 3–5 birds of one species can also pass across the upper screen without affecting resident counts.
- Bird Settings → Interaction has separate encounter switches, Low/Medium/High frequency, and previews. Low (default) attempts one of the encounters every 3–6 minutes, skipping unsuitable opportunities. Pause and sleep do not accumulate events.
- Night herons watch, stretch, shake and occasionally leave a fleeting dropping; woodpeckers cling to and peck window sides.
- In the pre-integration version, open “Field guide” for a grid of all species; choose Rest, Flight, Flapping, Gliding, Landing, Preening or Other from the fixed action bar.
- Pre-integration macOS development builds include an Observation journal: completed behaviors are grouped by species with first/last recorded dates and separate natural, manual, and preview counts. Search and filter by source; records stay local and discoveries do not trigger pop-ups.
- Hourly update checks download and verify new releases in the background. A notification opens release notes and installation confirmation; a red dot and menu entry remain if you postpone.
- Chinese and English menus, animation pause, and launch at login.

U integration status (October 26, 2026): the isolated development candidate contains 100 species and one Birding Handbook. Existing preferences and locks remain intact; new species require an explicit probability allocation. Observation clicks record visits while pointer-route safety remains active. Core corrective tests, artwork audits and the new handbook checks pass; full native scene acceptance still has blocked routes and unresolved evidence. The candidate is not installed or released as v0.7.0. See the [U delivery record](docs/U-INTEGRATION-ACCEPTANCE.md) for test rounds and limits.

Historical development status (2026-10-25): M7a Spotted Dove courtship passed stage acceptance. M7b/c nest delivery and building are implemented: a user-placed platform holds exactly three twigs, delivery and arrangement complete as separate visits, and cancellation preserves committed progress without replenishment. Eight poses and six props are exported; all 46 legacy pixel/index sets, 66 cross-rate replay reports, 20 full legacy reports, and 78 GIFs/7,800 frames passed. The full core suite passed 992 tests; after corrections, 46 nest-related tests and 347 art checks passed. The eighth candidate passed all 1,116 nest checks, 4,593 full bird checks, and 2,190 settings checks. M7b/c stage acceptance is complete, bringing the total to 167 new poses and 16 props. The development app was updated and restarted on October 25, 2026, with saved settings and the current draft checked and preserved. The expanded V03 verification passed 7,546 checks. The real eight-hour default workload ended naturally and passed event, cleanup, and preference-isolation review. Focused single-screen checks covered fullscreen transitions and recovery after closing the test window. The user waived the two-hour human-observation gate; window following, menu pause/resume, and real sleep/wake remain explicitly unverified with the user’s acceptance for this delivery. External-monitor and hot-plug checks are recorded as untested because no external display is available. See the [M7b/c evidence](docs/M7BC-ACCEPTANCE.md).

The installed development app now includes M7b/c; see the [installation evidence](docs/M7D-ACCEPTANCE.md). After the status-item isolation correction, the isolated production desktop completed a real 30-second smoke and all 22 offline checks. The separate eight-hour default-workload soak is complete. The user waived the two-hour observation gate. Window following, menu pause/resume, and real sleep/wake remain unverified with the user’s explicit acceptance; physical multi-monitor checks lack equipment. M6/M7 delivery is complete within this agreed acceptance scope, with these limitations recorded; see the [progress record](docs/IMPLEMENTATION-PROGRESS.md) and [M6h evidence](docs/M6H-ACCEPTANCE.md).

### Get started

**Windows:** Download the ZIP for your architecture, extract it, and run ChirpOS.exe. No separate .NET installation is needed. Supports Windows 10/11 x64 and Windows 11 ARM64.

**macOS:** Extract the ZIP, move `ChirpOS.app` to Applications, and open it. The download supports Apple Silicon Macs running macOS 13 or later.

Birds begin arriving shortly after launch. Use the macOS menu bar icon or right-click the Windows tray icon for settings and quit. The Windows icon may be in the hidden-icons area. Quit the running version before updating.

Existing releases prompt for new species at startup. U integration is implementing preserved probabilities and locked values, zero initial shares for the 54 additions, and explicit allocation in settings. Sizes use compressed adult-length ratios (bulbul 1×, Grey Heron 2.5×); some designs show males or breeding plumage, with stylized pixel animation.

The macOS app is Developer ID-signed and notarized by Apple. Windows builds are not publisher-signed, so a system security prompt may appear on first launch.

### Privacy & feedback

ChirpOS runs locally. It reads window geometry, stacking order and pointer position for hover identification and occasional circling. On macOS, it also observes left-click positions to move clicked birds to another spot, without recording click contents. It does not read window titles or content, and never uploads window information or personal settings. Automatic updates contact GitHub to check releases and download official packages. Occlusion uses rectangular bounds; transparent windows, rounded corners, and special system views may look different.

Report a bug or suggest an idea in [Issues](https://github.com/billtt/chirp-os/issues). For building and contributing, see the [development guide](docs/DEVELOPMENT.md).

---

[MIT License](LICENSE)
