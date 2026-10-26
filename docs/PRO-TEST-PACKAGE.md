# 啾啾 Pro 本地安装测试包

当前打包以 `scripts/pro-version.txt` 为版本来源，仅维护 macOS。概率 V2 已为全部 100 种鸟预设正的相对权重；勾选“手动调整概率”后显示编辑界面，可重置为默认值，保存后生效。旧版概率迁移及备份规则见 [V2 实施记录](PROBABILITY-SYSTEM-V2-IMPLEMENTATION.md)。下文的 0.6.0 产物与验收数字是首次打包的历史记录，不代表当前包的版本或验收结果。

后续更新：本文记录最初0.6.0本地测试包。更新版通过独立发布模式启用Ed25519验证与自维护仓库更新，详见[更新发布指南](PRO-UPDATES-AND-RELEASES.md)。普通测试模式仍关闭更新。

2026-10-26。本包包含M8与E0–E5交付内容：100种鸟具有增强基础姿态和特色动作，共4867帧槽。M9继续搁置，既有真实桌面未验项和性能尾部波动见[E0–E5交付记录](E0-E5-COMPLETE-ACCEPTANCE.md)。

## 名称与安装

应用文件为`ChirpOS Pro.app`，中文显示“啾啾 Pro”，英文显示“ChirpOS Pro”。菜单栏提示、辅助功能名称、菜单标题、退出项和导出图鉴标题随之更新。

运行`bash scripts/package-pro-macos.sh`统一构建并生成：

- `dist/ChirpOS Pro.app`：应用本体。
- `dist/pro/ChirpOS-Pro-0.6.0-macOS-arm64.dmg`：打开后将应用拖入Applications。
- `dist/pro/ChirpOS-Pro-0.6.0-macOS-arm64.zip`：解压后将应用移入“应用程序”。
- 同目录`SHA256SUMS.txt`、`BUILD-INFO.txt`和`安装说明.txt`：校验值、源码提交及安装说明。

适用于macOS 13及以上Apple Silicon机器；架构由实际构建主机确定。本次保持现有内部版本0.6.0，以Pro名称和构建记录区分，未冒用上游发行版本。

安装前先退出原版或测试版，安装后从“应用程序”打开Pro，再从菜单栏鸟图标进入鸟种设置与观鸟手册。当前概率 V2 默认启用全部鸟种；手动设置为零的鸟种不参与抽样。由用户手动安装，不自动覆盖已安装应用或启动第二个桌面实例。

## 数据与更新通道

Pro作为持久可复现的构建变体：`CHIRPOS_PRO_BUILD=1`会启用本地开发通道，使用现有`dev.birding.desktop.development`标识；因此沿用已有测试版偏好和本地观鸟数据，不做存档迁移或清除。应用目录名称与内部持久化键分别处理，不应同时运行旧版和Pro以免共同写入数据。

Pro沿用开发通道停用上游更新的机制。普通上游发布脚本显式关闭Pro标记，保留其原有包名和更新协议。Windows 已停止维护，不纳入打包流程。

测试包使用本机ad-hoc签名并校验完整性，没有Apple公证。DMG提供Applications快捷方式；ZIP保留完整应用目录。打包过程不会安装应用、上传安装包或推送Git。

## 验证记录

全部实现后统一验证，结果如下：

- Release构建通过，耗时91.89秒。
- Bash语法及既有发布流程11项检查通过；正式发布入口会清除继承的Pro标记。
- 实际Pro应用原生设置检查3169/3169通过，包含中文、英文菜单与状态栏品牌名称，以及本地开发通道检查。
- 应用包及中英本地化名称正确；arm64架构、macOS 13最低版本。
- ZIP与只读挂载的DMG内应用均与构建产物逐文件一致，签名严格校验通过；DMG校验和及Applications快捷方式正确。

[验证证据](evidence/pro-package-20261026/validation.json)与[完整设置检查](evidence/pro-package-20261026/settings-report.json)已归档。本轮未改动核心行为逻辑，不重复E0–E5已完成的全量核心测试。最终打包后源码提交和安装包校验值分别写入`dist/pro/BUILD-INFO.txt`、`dist/pro/SHA256SUMS.txt`。
