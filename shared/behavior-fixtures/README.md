# 行为输入格式与共享场景 v1

这些 JSON 是引擎输入，采用 Quartz 桌面坐标（向右为 x 正方向，向下为 y 正方向）。它们不依赖 AppKit、窗口标题、桌面截图或用户配置，供 macOS 与后续 Windows 核心运行同一场景。

- `version`：文件格式版本；未知版本拒绝，不能忽略无法理解的事件。
- `simulationVersion`：当前为 2，加入侧跳与自主起飞准备后更新。版本 1 的录制明确拒绝；需要在对应旧提交重放或重新录制，不能直接修改版本标签假装迁移。模拟语义版本。改变随机算法、调度或固定步契约时需明确迁移，不能让旧期望静默漂移。
- `seed`、鸟/运行/道具 ID 使用十进制字符串，避免 JavaScript 等环境丢失 64 位整数精度。
- `settings`：完整配置或合法的旧格式配置；按 BirdSettings schema 迁移。
- `initialWorld`、`fixtureBirds`：共享夹具可指定初始表面和已停稳鸟。生产录制从空引擎开始，不注入或还原任意中途的可变 Bird。
- `inputs`：严格按数组顺序处理。支持 world、settings、command、advance、population、reconcileLayout、arrive、depart、route。
- `advance.elapsed`：一次原始回调时长，保持引擎 0.05 秒截断；`repeatCount` 仅压缩相同连续回调，默认 1。不可把长暂停变成补播。
- `advance.options`：此时实际启用的数量调度、环境调度和自主选路开关。
- `world.availableFrames`：首次输入或素材变化时写入完整清单；省略时继承上一世界，显式空字典会清空。避免每帧重复记录不变素材。
- `world.sampleDT`：窗口采样时长。无该字段的世界更新只校验世界，不推进窗口跟随。
- `expected`：生产录制保存终态报告和完整事件序列。重放命令逐项比较，包括鸟坐标、姿态、生态记忆、道具和租约。共享手写夹具另由 XCTest 对完成行为、取消原因及零残留作独立断言，不用当前实现反向生成通过标准。

安全边界：最多 32 MiB、60,000 条输入、216,000 个回调、一小时有效模拟；最多 16 个显示器、256 个表面、64 个初始鸟。不完整/超限录制不能保存为正常记录。生产输入通过命令行显式启用，仅保存在指定本地文件。

## 使用

```sh
# 开发构建，然后录制一个单独的 8 秒本机测试进程（也可不指定时长，正常退出时保存）
CHIRPOS_DEVELOPMENT_BUILD=1 ./scripts/build.sh
dist/ChirpOS.app/Contents/MacOS/Birding --record-behavior .build/live-behavior.json --record-duration 8

# 不打开原生窗口即可重放。expected 存在时，不一致会退出 1。
dist/ChirpOS.app/Contents/MacOS/Birding --replay-behavior .build/live-behavior.json --replay-hz 120 --replay-output .build/replay-report.json

# 手写场景：观察/警觉、完整落叶返程、双鸟招呼、暂停中点击迁移、侧跳、起飞准备
dist/ChirpOS.app/Contents/MacOS/Birding --replay-behavior shared/behavior-fixtures/v1/leaf.json
```

当前 macOS 测试把同一输入序列分别拆成至多 1/30、1/60、1/120 秒的回调，比较完整报告；保留输入发生边界，不跨 world/command 合并时间。这验证回调分段稳定性，不宣称恢复录制时没有采到的鼠标轨迹。不同采样率的真实移动轨迹另由 PassiveEcologyTests 验证。Windows 解析器与原生验收尚待迁移，当前文件通过不代表跨端已经对齐。
