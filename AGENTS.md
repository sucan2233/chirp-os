# 仓库开发约定

本文件适用于整个仓库；分支、打包和发布约定见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 维护范围

- 本分支仅开发、测试、打包和发布 macOS / ChirpOS Pro。
- `platforms/windows/` 及旧 Windows 构建脚本仅保留作历史参考，不再同步功能、修复、编译或验收，不作为 macOS 交付前置条件。
- 吸收上游更新时，不重新引入 Windows CI、.NET 依赖或双平台一致性要求。历史文档中的 Windows 待办不属于当前任务。
- `shared/` 继续保存 macOS 导出的目录、素材及回放夹具；保持资源镜像与 macOS 定义一致，不据此要求维护 Windows 消费者。

## 开发、验收与提交

- Git 提交必须使用中文并遵循 Conventional Commits，例如 `feat(概率): 增加系统默认权重`。
- 代码开发全部实现后，再统一编译、验证和验收；检查范围应与改动对应，记录实际结果，不以编译成功替代功能验收。
- 保留用户已有配置、观鸟数据、Pro 身份及本地测试通道。测试使用隔离配置，不直接覆盖用户安装版。
- 开发分支使用 `codex/<任务名>`；不重置或强推覆盖维护主线。提交不等于授权推送、安装或公开发布。
- macOS 核心检查入口为 `scripts/test.sh`，资源检查入口保留历史文件名 `scripts/test-species-parity.py`，只检查 macOS 与导出资源的契约。
- Pro 本地打包使用 `scripts/package-pro-macos.sh`，发布使用 `scripts/release-pro-macos.sh` / `release-pro.yml`；普通版发布入口不用于 Pro。
