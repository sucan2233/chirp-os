# 开发指南 / Development

行为扩展与架构规划见 [行为与互动引擎设计](BEHAVIOR-ENGINE-DESIGN.md)：包含动作储备、现有架构评估、运行时边界、迁移路线与验收标准。M0–M2 已实现，实际范围、迁移桥和验收状态见文档第 16 节；其余为后续设计。

## 项目结构 / Layout

| 目录 / Directory | 内容 / Contents |
| --- | --- |
| `platforms/macos/` | Swift / AppKit 应用与测试 / App and tests |
| `platforms/windows/` | C# / WinForms / Win32 应用与测试 / App and tests |
| `shared/` | 鸟种定义、像素图集和图标 / Species, atlases, and icon |
| `Assets/` | 文档图片与图标源图 / Documentation images and icon source |
| `scripts/` | 构建与验证脚本 / Build and verification scripts |
| `dist/` | 本地构建输出，不提交 / Local build outputs, ignored by Git |

## macOS

需要 macOS 13+ 和 Swift Command Line Tools。构建使用本机架构。
Requires macOS 13+ and Swift Command Line Tools. Builds target the host architecture.

运行 XCTest 单元测试还需要安装完整 Xcode。可通过环境变量指定测试工具链，无需修改系统的默认开发工具路径：
XCTest unit tests also require a full Xcode installation. Select its toolchain for a test run without changing the system-wide developer directory:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh
```

```bash
./scripts/build.sh
./scripts/run.sh
./scripts/test.sh
```

应用 / App: `dist/ChirpOS.app`。可用 `CHIRPOS_APP_PATH` 指定独立开发包位置，避免覆盖下载的已签名版本。 / Set `CHIRPOS_APP_PATH` to build to a separate development app path.

桌面检查需要已登录的图形会话 / Desktop checks require an unlocked graphical session:

```bash
./scripts/verify-desktop.sh
./scripts/verify-population.sh
./scripts/verify-settings.sh
.build/release/Birding --verify-birds .build/bird-check
```

macOS 行为统一从 `BirdingCore/Behavior/BehaviorEngine` 进入：平台先提交 `BehaviorWorld`，
再串行调用 `handle(EngineCommand)` 与 `advance(elapsed)`；固定时间步为 1/60 秒。
渲染与像素命中读取 `BirdRenderState` 值快照，控制器不保存行为专用计时器或参与者队列。

`BehaviorRuntime` 统一负责运动占用、显著事件互斥、超时和结束清理；
`InteractionExecutions` 包含换位、绕鼠标、鸟群过境三个实现；`DestinationPlanner` 选择落点。
新增动作先在核心实现 `BehaviorExecution`，声明参与者、暂停策略、超时与清理，再接入命令/选择规则及测试。
现有 `Bird` 暂时作为运动与姿态实现，已有路径和素材仍复用。

过境鸟使用引擎 `transient` 角色，独立于常驻，最多 5 只。
`AmbientBehavior.swift` 保留机会调度与路径规划辅助函数；
`Birding/AmbientAnimations.swift` 只适配平台输入和预览结果。
默认两类事件合计每 180–360 秒尝试一次；中频 90–180 秒、高频 45–90 秒。
设置页预览与自动事件共享校验和清理规则。

`BehaviorEngine(seed:)` 支持核心场景重放，需同时给定相同配置、初始鸟、世界输入和命令时间线。
目前单一随机流，不保证跨版本或 Swift/C# 两端轨迹一致；诊断里的 seed 不能单独重放真实桌面。
`--diagnostics <path>` 输出鸟 ID、角色、行为计数和最多 256 条生命周期事件。

`BehaviorEngineTests` 覆盖 30/60/120 Hz 重放、抢占、暂停、宿主失效、移除、预览、超时和资源释放；
`AmbientTests` 保留配置兼容、路径连续性与鼠标安全距离；
`--verify-birds` 验证真实绘制/命中与互动；`--verify-settings` 输出中英文界面截图。
完整桌面集成中的 `playsLandingState` 存在迁移前已知时序不稳定，需单独记录当次结果。

## Windows

需要 .NET 10 SDK。可在 Windows、macOS 或 Linux 上构建。
Requires .NET 10 SDK. Builds can run on Windows, macOS, or Linux.

```powershell
# Windows PowerShell
./scripts/build-windows.ps1 -Runtime win-x64
# Windows ARM64
./scripts/build-windows.ps1 -Runtime win-arm64
```

```bash
# macOS / Linux
./scripts/build-windows.sh win-arm64 win-x64
```

输出 / Outputs: `dist/windows/<runtime>/ChirpOS.exe` and `dist/releases/*.zip`.

Mac 上的 ARM64 构建还会复制到 `~/Downloads/share/ChirpOS.exe`；可用 `CHIRPOS_SHARE_DIR` 指定其他目录。
On Mac, ARM64 builds also copy to `~/Downloads/share/ChirpOS.exe`; override with `CHIRPOS_SHARE_DIR`.

核心测试 / Core tests:

```bash
dotnet run --project platforms/windows/ChirpOS.Tests -c Release
```

Windows 桌面检查 / Windows desktop checks: run `ChirpOS.exe --self-test`, or double-click `Verify-Windows.cmd` in the build directory. Results are saved to `%LOCALAPPDATA%\ChirpOS\self-test.json`.

## 美术 / Artwork

像素绘制定义位于 `platforms/macos/Sources/Birding/PixelArt.swift` 、`SpeciesArt.swift` 和 `DetailedBirdArt.swift`。修改后在 Mac 上导出共用资源，并提交 `shared/` 的变化。
Artwork is defined in `platforms/macos/Sources/Birding/PixelArt.swift` `SpeciesArt.swift` and `DetailedBirdArt.swift`. Export on Mac after editing, and commit the updated `shared/` assets.

```bash
./scripts/export-shared.sh
./scripts/preview-species.sh
```

鸟种外形、行为参考及配置兼容说明见 [Bird design](BIRD-DESIGN.md)。
See [Bird design](BIRD-DESIGN.md) for appearance, behavior references and configuration compatibility.

## 自动更新 / Automatic updates

更新流程、发布约定、安全边界和测试入口见 [自动更新说明](AUTO-UPDATE.md)。
See [Automatic updates](AUTO-UPDATE.md) for the protocol, release requirements and verification.

## 本地数据 / Local data

- macOS: `~/Library/Application Support/Birding/settings.json`
- Windows: `%LOCALAPPDATA%\ChirpOS\settings.json`; diagnostics and errors are stored alongside it.

设置与构建缓存分开存储，清理缓存不会重置偏好。
Settings are separate from build caches; removing caches does not reset preferences.

## macOS 发布 / macOS releases

正式发布统一使用以下入口，默认完成 Developer ID 签名（含时间戳和 Hardened Runtime）、Apple 公证、票据附加及 Gatekeeper 验证，全部成功后才生成发布 ZIP：
Use the release entry point for Developer ID signing, timestamping, Hardened Runtime, notarization, stapling, and Gatekeeper validation. A release ZIP is produced only after all steps succeed.

```bash
mkdir -p .local
cp scripts/macos-release.env.example .local/macos-release.env
chmod 600 .local/macos-release.env
# Fill in your own signing identity and Keychain profile name in the local file.
./scripts/release-macos.sh --check
./scripts/release-macos.sh
```

本地文件被 Git 忽略，仅存放签名身份和公证配置的名称；证书私钥、密码和 API 凭据保留在钥匙串中。每台机器单独配置。可用 `CHIRPOS_RELEASE_CONFIG` 指定其他本地文件；非空环境变量优先于文件配置。
The ignored local file stores names only. Private keys and credentials remain in Keychain. Configure each machine separately. `CHIRPOS_RELEASE_CONFIG` selects another local file; nonempty environment variables override file values.

配置缺失或预检查失败时，交互式终端会询问是否使用临时签名（默认否）。无交互环境直接失败，不会自动降级。临时测试包可显式使用 `--ad-hoc`，写入 `dist/adhoc/`，文件名带 `-adhoc`，不经过公证。正式签名或公证执行失败会直接停止。`scripts/build.sh` 是本地开发构建，不代替发布入口。
Missing or unusable credentials prompt for an ad-hoc fallback in an interactive terminal (default: no). Noninteractive runs fail closed. Explicit `--ad-hoc` creates an unnotarized test ZIP under `dist/adhoc/`, with an `-adhoc` suffix. Signing/notarization failures stop the release. `scripts/build.sh` is a development build, not the release entry point.

GitHub Actions uses repository secrets: `MACOS_SIGNING_IDENTITY`, `MACOS_NOTARY_PROFILE`, `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER_ID`. Missing credentials stop the workflow. Local Keychain settings are not automatically available to CI.

Windows release assets are always ZIP archives containing ChirpOS.exe, LICENSE.txt,
README.md, and Verify-Windows.cmd. Both shell and PowerShell builds read the version
from ChirpOS.csproj. Extract the archive before launching the executable.
