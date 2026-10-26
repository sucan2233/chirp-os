# Pro 客户端更新与 GitHub 发布

本分支提供独立的Pro更新通道，目标仓库为`sucan2233/chirp-os`。不用Apple Developer付费账号也可以制作安装包和验证更新来源；Apple公证与本项目的更新签名是两回事。

## 客户端如何更新

开启更新的Pro应用启动后延迟15秒检查，然后每小时检查；也可从菜单点击“检查更新…”。客户端读取自维护仓库Releases，只接受非草稿、非预发布的`pro-vX.Y.Z`，按当前CPU架构选择更高版本。原作者的普通版与历史`vX.Y.Z`不会作为Pro更新。

客户端取得ZIP与独立`.sig`，先用安装包内置公钥验证Ed25519签名，再下载、检查大小及SHA-256、审核ZIP路径和解压体积、校验包标识、版本、CPU架构与更新公钥。签名覆盖版本、文件名、文件大小、ZIP哈希，不能仅替换GitHub上的哈希来伪造更新。

验证成功后显示提示和菜单红点。用户点击“安装并重启”才会启动替换：后台助手等待旧进程退出，再交换应用目录、启动新版并等待健康确认；启动失败则恢复旧版。设置与观鸟记录保留在应用包外，不随安装包替换。Pro更新缓存独立放在`~/Library/Application Support/Birding/ProUpdates`。

普通本地测试包默认关闭更新；发布模式显式启用更新。两者仍沿用已有测试版的bundle identifier和偏好域，Pro名称、更新来源和是否开启更新单独控制。

此前提供的Pro 0.6.0测试包没有开启更新，不能靠服务器发布让它自行升级。需要先手动安装一次包含更新公钥的新版；以后才能走此通道。没有Apple公证时，首次打开网络下载的应用可能需要用户在macOS“隐私与安全”中确认；本项目不会清除隔离标记或关闭Gatekeeper。后续更新也可能触发系统重新确认；新版90秒内没有完成启动确认时会回滚。各系统的实际启动与升级提示仍需真机验证。

## 首次配置：一个更新私钥

公钥提交在`config/pro-update-public-key.txt`，私钥仅保存在被Git忽略的`.local/pro-update-private-key`。私钥文件权限为0600，不应上传仓库或粘贴到聊天。保留离线备份；丢失或更换密钥会使已安装客户端拒绝新签名，需要另行设计迁移或手动安装。

更新签名密钥与 Git SSH 密钥独立：`ssh-ed25519 AAAA…` 用于 Git 连接认证，其 SSH 私钥不能填入更新 Secret。更新脚本要求 base64 编码的原始 32 字节 Ed25519 私钥，并校验它是否匹配仓库公钥。GitHub 保存 Secret 后不回显内容；保存成功不代表密钥匹配，必须以发布签名步骤及下载后的公钥验签结果为准。

本轮已生成本机密钥并提交对应公钥；你需要备份`.local/pro-update-private-key`并将同一私钥配置到GitHub Secret。新仓库首次生成密钥的命令如下；已有密钥不要重复生成：

```sh
mkdir -p .local config
swift scripts/pro-update-sign.swift init .local/pro-update-private-key config/pro-update-public-key.txt
```

GitHub仓库进入 **Settings → Secrets and variables → Actions → New repository secret**，添加：

| 名称 | 内容 |
| --- | --- |
| `CHIRPOS_UPDATE_PRIVATE_KEY` | 私钥文件中的base64原始Ed25519私钥，整行保存，不加引号，不再做一次base64编码 |

这里不需要Apple证书Secrets。GitHub Actions在运行时临时写入私钥，使用后清除；不得在日志中输出私钥。内置`GITHUB_TOKEN`用于上传Release资产，无需在客户端内置GitHub令牌。

## 发布一个版本

1. 在`main`完成代码与统一验证。修改`scripts/pro-version.txt`，例如`0.8.0`；为该版本编写`docs/releases/pro-v0.8.0.md`。
2. Git提交并推送主线，然后建立与版本一致的标签：

   ```sh
   git tag -a pro-v0.8.0 -m 'release(Pro): 发布0.8.0百鸟动作与独立更新版'
   git push origin main
   git push origin pro-v0.8.0
   ```

3. 打开仓库Actions，选择Pro发布工作流，点击Run workflow并填写已存在的标签`pro-v0.8.0`。
4. 流水线检查版本、标签和发布说明，执行测试，生成应用、ZIP、DMG、签名和校验文件，先上传到草稿Release，再确认GitHub返回的ZIP SHA-256与本地一致，最后公开Release。
5. 用户第一次下载DMG/ZIP安装。已有开启更新的客户端会在下次检查时获得较高版本；同版本不会重复更新。

首次发布只是建立更新源，完整远程升级验收需要至少两个实际版本。不能把0.8.0检测不到比自己更新的版本当作更新失败，也不能把离线替换验证当作远程端到端升级通过。

后续例如从0.8.0到0.8.1：提高版本、补发布说明、提交、推送标签、运行同一工作流。不要覆盖已经公开的版本资产；修复应发更高版本。

首次云端尝试 `pro-v0.8.0` 在 Swift 编译阶段失败，未进入签名或创建 Release；修复访客送礼曲线的类型推断超时后，以 `pro-v0.8.1` 重试，保留原标签。发布流水线改用 `swift test -c release` 运行完整核心测试，避免调试模式下行为仿真的额外耗时。发布脚本测试使用固定的隔离夹具版本，不依赖当前产品版本。

`pro-v0.8.2` 的完整云端日志确认使用 Xcode 16.4 / Swift 6.1.2；本机为 Xcode 27.1。旧编译器在测试夹具和原生验收中的复杂表达式出现推断超时、CGFloat 运算歧义和可选整数推断错误，仍未进入签名或创建 Release。`pro-v0.8.3` 集中拆分这些表达式，并将 Pro 工作流的 `DEVELOPER_DIR` 固定为 `/Applications/Xcode_26.3.app/Contents/Developer`（GitHub macOS 15 arm64 镜像列出的版本），目录不可用时立即失败。后续调整工具链时应先核对 runner 镜像清单，不能仅凭本地测试通过认定云端兼容。

0.8.3 修复后的独立工作区已统一验证：完整 Release 编译通过，核心测试 1102 项、0 失败（66.852 秒），Pro 发布检查 30 项、普通发布检查 11 项及鸟种数据一致性检查通过。云端发布及下载后验签另以实际运行结果记录。

0.8.3 云端运行确认已使用 Xcode 26.3 / Swift 6.2.4，其余已报编译错误消除，仍在 `CourtshipTestSupport.swift` 的左右方向位置数组三元表达式发生类型推断超时，未进入签名。0.8.4 将默认间隔和两个坐标逐个明确为 CGFloat，以显式分支替代数组三元表达式。修复后本地 Release 编译及 1102 项核心测试通过（0 失败，66.700 秒），30 项 Pro 发布检查和鸟种数据一致性检查通过。

0.8.4 云端在修复求偶夹具后暴露 `SharedBehaviorExport.swift` 的携叶帧数组长拼接超时，仍未进入签名。0.8.5 将该文件的携叶、捕虫、筑巢帧序列逐段追加，避免多层泛型运算符推断，并通过编译耗时诊断检查剩余表达式。诊断发现的互相理羽、追逐候选位置以及求偶设置排版验收表达式也已拆分。最终应用 Release 编译通过，未再报告超过 100ms 的表达式；1102 项核心测试 0 失败（74.482 秒），30 项发布检查和鸟种数据一致性检查通过；22 个场景在 30/60/120Hz 重放通过，生成 JSON 与已跟踪基线一致。

本地复查核心测试应使用完整 Xcode：

```sh
python3 scripts/test-species-parity.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c release
python3 scripts/test-pro-release.py
```

仅安装或选中 Command Line Tools 时可能报 `no such module 'XCTest'`；上述环境变量只影响这次命令，无需修改系统默认开发目录。

## 本地构建与发布材料

```sh
# 普通测试包：更新关闭
bash scripts/package-pro-macos.sh

# 开发阶段验证更新包（允许尚未提交的实现，不用于公开发行）
bash scripts/package-pro-macos.sh --release

# 正式发布材料：要求干净工作区及已存在、指向HEAD的版本标签
# 此命令只准备材料，不会自动上传或安装
bash scripts/release-pro-macos.sh
```

发布ZIP用于客户端自动下载和替换，DMG用于用户手动安装。ZIP与其`.sig`必须同时发布，文件名须保留生成规则`ChirpOS-Pro-X.Y.Z-macOS-arm64.zip`（或实际构建架构）。本轮macOS优先，Windows的更新与发布仍按原实现单独处理。

`scripts/release-macos.sh`和原`release.yml`保留普通上游版协议，Pro应使用独立入口。无需修改上游仓库，也不会把Pro指向原作者Release。

## 本轮验证与尚未完成的外部步骤

本轮实现完成后统一验证：

| 项目 | 结果 |
| --- | --- |
| Release构建及独立签名打包 | 通过，Pro 0.8.0，arm64 |
| 核心测试 | 1102/1102，0失败 |
| Pro发布脚本离线检查 | 30/30 |
| 普通版发布兼容检查 | 11/11 |
| 原生更新UI | 20/20 |
| 真实签名ZIP、临时应用暂存、交换与回滚 | 9/9 |
| DMG/ZIP内容、签名、SHA-256、工作流YAML与Shell语法 | 通过 |
| 鸟种数据一致性 | 通过 |

[验证汇总](evidence/pro-updates-20261026/validation.json)、[原生更新UI](evidence/pro-updates-20261026/update-ui-report.json)、[真实包暂存与替换](evidence/pro-updates-20261026/staging-report.json)、[安装包校验值](evidence/pro-updates-20261026/containers-report.json)。没有把临时副本的目录交换标成真实桌面退出、重启和系统许可全部通过。

审阅中将助手等待从10秒调整为120秒并检查进程存活，避免Pro重新解压较慢时误取消；助手会从签名ZIP重新创建候选包，不信任先前暂存目录。验证入口解析临时目录的符号链接，生产目标仍保持严格路径限制。

GitHub Secret配置、首次公开Release以及真实“旧客户端→下载→退出→启动新版”的现场验证需要实际发布环境；没有执行这些步骤时不得标记完成。

## 官方资料

- GitHub Release资产API：<https://docs.github.com/en/rest/releases/assets>（`digest`字段）。
- GitHub Actions Secrets：<https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions>。
- Apple关于未识别开发者应用的打开流程：<https://support.apple.com/en-us/102445>。
- Sparkle文档中的EdDSA更新签名说明：<https://sparkle-project.org/documentation/>。本项目复用自己的更新器，并未集成Sparkle。
