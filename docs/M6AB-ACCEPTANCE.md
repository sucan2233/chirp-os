# M6a / M6b 验收记录

日期：2026-10-24。范围为统一物种配置、可选姿态契约、侧跳失败诊断，以及麻雀、珠颈斑鸠、家燕、夜鹭的40张新增姿态。本记录不代表M6c–M7d已交付；全量工作继续按[实施进度](IMPLEMENTATION-PROGRESS.md)推进。

## 已取得的证据

| 检查 | 实际结果 | 本地证据 |
| --- | --- | --- |
| 全量核心测试 | 726项、0失败；包括晚期缺帧与初始缺帧两项补充回归 | `.build/m6ab-tests-final-accepted.log` |
| 四鸟素材及原生图层 | 637项通过；含40帧独立性、逻辑喙锚、固定脚趾、三档比例双向镜像、命中、名字、逐阶段点击和生命周期 | `.build/m6ab-content/report.json`及同目录图片 |
| 旧图集兼容 | 46种鸟全部既有帧逐像素不变，包含既有专用帧；公共34帧及索引保留 | `.build/m6-delivery/legacy-pixel-comparison.json` |
| 物种与参数 | 46种鸟、公共34帧、46组飞行参数一致；支持审计与图集一致 | `scripts/test-species-parity.py` |
| 旧回放 | 14份夹具各以30/60/120Hz重放，42/42通过，未更新旧expected | `.build/m6ab-replays/summary.json` |
| 压力回归 | ordinary/crowded/long均通过，metrics与cleanup逐项等于M5n；long仍包含历史sideHop失败 | `.build/behavior-stress.lKM5rN/`、`.build/m6ab-stress-comparison.json` |
| 历史侧跳复现 | 精确命中run183、鸟27、事件396、模拟时间734.1；取消前捕获bird23进入走廊 | `.build/m6a-sidehop-183.json`；具体归因见[诊断记录](m6a-sidehop-diagnosis.md) |
| 参考动画 | 四鸟×三档比例×左右方向，共24份循环GIF；表现采样不增加生产时钟 | `.build/m6-delivery/pose-loops/` |
| 完整鸟类原生检查 | 1253项通过，包含本批637项及既有访问、图层、遮挡、点击等回归 | `.build/m6ab-birds-accepted/report.json` |
| 设置页完整复验 | 1471项通过，覆盖中英文本、保存、取消、开关与持久化 | `.build/m6ab-settings-accepted/report.json` |
| 休息缺帧补充回归 | 21项PoseClip测试通过；其中两项覆盖36组晚期缺帧、暂停恢复及初始缺帧场景 | `.build/m6ab-pose-tests-accepted.log` |
| 地面/更新/发布脚本 | 24/17/11项通过 | `.build/m6ab-ground/`、`.build/m6ab-updates/`、`.build/m6ab-release-tests.log` |
| 桌面集成/数量与屏外进入 | 13/12项通过 | `.build/desktop-check.TOOZ5O/report.json`、`.build/population-check.vhU3M3/report.json` |

主会话已查看四鸟完整姿态联系表：观察/警觉保持物种轮廓，休息有缩身与回头藏喙，起飞有屈腿和蹬伸抬翼。动画参考导出中的标签改为固定深色，以免深色系统主题下在浅背景上不可读。静态图层和显式模拟步验收不能替代真实桌面持续使用。

## 统一验证中发现的问题

- 本机默认Command Line Tools不包含XCTest；测试命令使用仓库既有说明中的`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，不改系统选择。
- 新原生验收的持久化成员名及跨行数组拼接修正；诊断Auditor保留单参数回调入口，兼容原有函数引用。
- 未增强鸟种的回退测试中，大斑啄木鸟会按真实规则优先侧边落点，起飞准备拒绝；测试使用120点高的顶部窗口，产品准入不变。
- 旧飞行测试未注入随机轨道，第二次全量运行出现两条黑鸢速度跳变断言。改为四角、中点和固定种子内部轨道样本，保留原速度阈值，定向复验通过；旧失败未记录随机参数，不能声称已修复生产速度问题。
- 旧食盘原生夹具仅按屏幕42%/78%选择高度，未计入弧线、鸟体及鼠标保护区；改为完整走廊布局，并记录实际鼠标与准入几何，生产安全条件不变。
- 设置页新增同源支持名单后，旧精确文案断言同步更新。首次完整设置检查1471项，仅两条同伴理羽文案断言失败。
- 独立审查发现休息尾段可选帧失效会使旧周期hop重新进入，暂停期间也可能跳变。现于启动时冻结运动及增强画面选择：初始缺帧整轮使用旧表现；已进入增强的run缺帧只退回旧画面，保留增强hop至统一释放。补帧不改变运动所有权。新增测试已定向通过，独立静态复审未发现遗留问题。
- 固定栖木旧原生夹具会在全部候选均未满足100点指针净空时继续选择最远者，导致31条同源失败。扩大夹具候选高度并统一净空检查后，完整鸟类原生1253项通过；未放宽生产准入。

## 已安装应用与剩余验收边界

已将通过验收的开发包安装并重启到`/Users/sucan/Applications/ChirpOS Dev.app`，旧包保留于`.build/m6-delivery/ChirpOS Dev before M6ab.app`。严格签名验证通过。安装前后设置文件字节相同，SHA256为`4e0442697301b354569eecb5c3075acb942a6e857777a7f1daf1cd5ffd2e22de`。

通过原生UI读取确认`hoverDelay=0.2`和`pointerFollowEnabled=true`仍在；真实交互页四鸟说明可完整显示，点击“预览留意鼠标”返回已启动提示。这证明真实居民入口可用，不声称已逐鸟观察完整动画。随后工具检测到用户切换到“体型与动作”页面，停止继续操作设置，保留用户当前草稿，不再次保存或重置。

本批核心、素材、原生隔离验收和安装冒烟已完成。完整真实桌面的逐鸟长期观感继续纳入M6h/M7d；2小时观察、8小时浸泡、物理多屏热插拔及睡眠唤醒均未完成，不以加速模拟代替。
