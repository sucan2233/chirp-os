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

## 0.8.5 云端发布状态（2026-10-26）

运行 `40318109342`（源码 `0e7741b`，标签 `pro-v0.8.5`）已通过完整云端编译及核心测试，随后在签名步骤报告 `Invalid base64 key/signature file ... (expected 32 bytes)`；未创建 Release 或上传资产。仓库 Secret 的格式不符合更新签名协议。随后浏览器设置页仅列出名为 `GITHUB` 的仓库 Secret，未列出目标名称；仍需用户将 `.local/pro-update-private-key` 的原始整行内容填入 `CHIRPOS_UPDATE_PRIVATE_KEY`。不得使用 SSH 私钥，也不要再次编码或添加引号。该本机文件已通过公钥配对检查，但不能据此认定 GitHub Secret 正确。

工作流增加编译前的密钥格式与公钥配对检查（更新后 31 项离线发布检查通过），错误配置会在耗时编译前停止；检查使用临时 0600 文件，不输出密钥内容，退出时删除。修正 Secret 后可对同一未发布标签再次手动运行最新主线工作流，避免覆盖已有发布资产；历史失败记录保留。下载后的独立验签和真实远程升级仍需在首次发布成功后验收。

运行 `40320442787` 已验证 Secret 配对成功、云端核心测试 1102/1102（183.775 秒）及 ZIP/DMG/Ed25519 全部通过。随后在创建草稿 Release 的 API 请求返回 `403 Resource not accessible by integration`，日志显示 `GITHUB_TOKEN` 已有 `Contents: write`；没有创建草稿或上传资产。

GitHub Release API 对显式 `target_commitish` 所指提交与默认分支之间的工作流差异执行额外权限检查，即使标签已经存在。旧发布命令将源码提交重复传入 `--target`；现移除此参数，沿用 `--verify-tag` 及本地/远端标签 SHA 校验，由已存在标签确定发布源码。无需新增个人令牌或扩大权限。参考官方 Releases API 的创建说明：<https://docs.github.com/en/rest/releases/releases#create-a-release>。

签名打包成功后，流水线先保存 `pro-vX.Y.Z-源码SHA-verified-assets` Actions artifact（7 天），再创建 Release；仅包含公开安装包、独立签名和构建说明，不含私钥。发布端失败时可下载已验证材料恢复，避免丢失整轮构建。安装包来源仍是指定标签，主线后续概率系统变更不会进入 0.8.5。

运行 `40323236452` 已通过密钥检查、完整核心测试、签名打包和 artifact 归档。移除重复 `target_commitish` 后，草稿创建及六资产上传成功；随后校验草稿时请求 `/releases/tags/pro-v0.8.5` 返回 404。该接口只查询已公开 Release，不能用于发布前的草稿校验；这次不再是编译、密钥或权限失败。官方说明见同页的 [Get a release by tag name](https://docs.github.com/en/rest/releases/releases#get-a-release-by-tag-name) 与 [Get a release](https://docs.github.com/en/rest/releases/releases#get-a-release)。

GitHub CLI 自身的 [草稿查询实现](https://github.com/cli/cli/blob/trunk/pkg/cmd/release/shared/fetch.go) 也专门处理此差异：先通过 GraphQL 按待发布标签取得草稿 ID，再走 REST 按 ID 读取完整资产。这解释了 `gh release upload` 已成功而后续直接调用 tags REST 接口仍失败；单纯重试 404 或继续扩大权限不能修复接口用错。

发布逻辑改为 `scripts/publish-pro-release.py`：保留创建响应中的 Release ID，按 `/releases/{id}` 核对草稿、六资产集合、大小及 SHA-256，之后仍按同一个 ID 公开并复查。普通发布拒绝任何已存在 Release；恢复模式只接受唯一未公开草稿，要求资产全部已上传且与原构建逐字节匹配，不覆盖文件、不删除草稿、不改标签。缺失 digest 最多等待六次，真实 hash 或资产集合不匹配立即停止。正常发布工作流在切换到旧标签前保存当前发布脚本，确保旧产品标签也能使用修复后的发布协议。

恢复运行 `40328974512` 成功取得草稿 ID `424241975`，但六资产清单不匹配。2026-10-26 在 GitHub 实际展开资产确认，上传的中文文件名 `安装说明.txt` 被服务端改成 `default.txt`，其 SHA-256 与原说明文件一致；其他五个文件名称正常。GitHub [资产上传说明](https://docs.github.com/en/rest/releases/assets#upload-a-release-asset) 明确指出特殊字符文件名可能被改写。发布附件现统一采用 ASCII 名称 `INSTALL.txt`，文件内容继续为中文，DMG 内仍保留中文说明名。

旧产品标签和既存 artifact 保持不变：发布器接受本地 `INSTALL.txt` 或旧 `安装说明.txt` 中唯一一个，旧名称仅在上传前拷贝为 `INSTALL.txt`。恢复已上传的 `default.txt` 时，先按原构建的六文件完整大小与摘要验证，再按资产 ID 将该说明附件改名为 `INSTALL.txt`，重新读取草稿全量核验后才公开。仅允许这一明确的历史兼容规则；资产缺失、额外文件、重复说明、摘要变化或错误状态均停止。不重新签名、构建或上传安装包。失败信息同步到 Actions annotation，便于通过公开 API 读取具体原因。

**首次发布已完成。** 修复提交 `cb1d388` 推送后，恢复运行 [`40333809147`](https://github.com/sucan2233/chirp-os/actions/runs/40333809147) 全部成功；[`pro-v0.8.5`](https://github.com/sucan2233/chirp-os/releases/tag/pro-v0.8.5) 于 **2026-10-26 21:48:53（Asia/Shanghai）**公开。源码仍为原标签 `0e7741b`，不包含主线后续概率 V2。六附件已匿名重新下载，逐份核对 GitHub 大小/摘要，并确认与原始 artifact 内容一致；公开 ZIP 的 Ed25519、公钥、SHA-256、包路径及 DMG 校验通过。

客户端生产选择器读取真实公开 Releases，验证旧版本 `0.8.0` 能发现 `0.8.5`，当前版本 `0.8.5` 不重复更新，真实签名与归档检查通过。同一云端安装包此前在隔离应用副本上通过暂存、原子替换、回滚及篡改拒绝 9 项检查；27 组离线发布协议回归、34 项签名/发布检查通过。见[发布验收汇总](evidence/pro-release-085-20261026/validation.json)及[隔离替换报告](evidence/pro-release-085-20261026/staging-report.json)。实际桌面退出/重新启动及 Gatekeeper 交互仍未验收，未替换用户当前安装版。

### 已构建成功、仅发布失败时恢复

1. 打开 Actions 的 **Recover ChirpOS Pro macOS release**，从 `main` 运行，填写原标签及成功归档产物的运行 ID；本次为 `pro-v0.8.5`、`40323236452`。
2. 恢复流程核对原工作流、仓库、源码祖先关系和测试/打包/归档步骤成功状态，下载该标签与源码 SHA 唯一对应、尚未过期的 artifact。
3. 核对构建说明、标签 SHA、签名公钥、ZIP 独立签名、SHA256SUMS 和 DMG；按 Release ID 复查已有草稿的六资产后公开。不重新编译、不需要再次使用更新私钥。
4. 下载公开文件再次验签，并核对客户端能选中此版本。恢复 workflow 成功不等于实际桌面退出、重启和 Gatekeeper 已验收。

不要直接重跑旧 workflow 或删除正确草稿；旧定义仍有原来的接口错误，普通完整发布也会拒绝已存在草稿。artifact 过期、来源不匹配或资产不完整时先排查，不强行覆盖公开版本。离线协议回归入口为 `python3 scripts/test-pro-publish.py`，覆盖草稿 ID、恢复、漂移标签、错误资产及 digest 等待行为。

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

发布ZIP用于客户端自动下载和替换，DMG用于用户手动安装。ZIP与其`.sig`必须同时发布，文件名须保留生成规则`ChirpOS-Pro-X.Y.Z-macOS-arm64.zip`（或实际构建架构）。当前维护范围仅为 macOS / ChirpOS Pro。

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

GitHub Secret 配对与首次公开 Release 已完成，并通过真实公开包下载验签；真实“旧客户端→下载→退出→启动新版”的桌面现场验证仍保留未验收。

## 官方资料

- GitHub Release资产API：<https://docs.github.com/en/rest/releases/assets>（`digest`字段）。
- GitHub Actions Secrets：<https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions>。
- Apple关于未识别开发者应用的打开流程：<https://support.apple.com/en-us/102445>。
- Sparkle文档中的EdDSA更新签名说明：<https://sparkle-project.org/documentation/>。本项目复用自己的更新器，并未集成Sparkle。
