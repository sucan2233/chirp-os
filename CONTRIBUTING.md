# ChirpOS Pro 维护约定

## 分支与仓库

- `main`：本项目自主维护的主分支，保留M6、M7、上游整合、M8、E0–E5和Pro打包成果，作为后续开发与打包基线。
- `codex/<任务名>`：从`main`创建的开发分支，完成实现、统一验证并提交后再合入`main`。已有阶段分支保留为历史参考。
- `origin`：自维护仓库`sucan2233/chirp-os`，后续主线推送目标为`origin/main`。
- `upstream`：原项目`billtt/chirp-os`，`upstream/main`仅作为更新来源；评估后在独立开发分支合并所需变化。

维护主线不通过重置或强推覆盖为上游版本。吸收上游改动时保留本地行为权限、素材索引、设置、观鸟数据、Pro名称和本地测试通道。提交与本地分支调整不等于远程推送或公开发布。

## 开发与验证

Git提交使用中文Conventional Commits，例如`feat(动作): 增加物种特色姿态`、`fix(打包): 修正Pro显示名称`。

代码开发全部实现后，再统一编译、验证和验收。根据改动范围执行相关检查，记录实际结果及仍未验收的项目，不以构建成功替代功能或真实桌面验收。

## 本地打包

使用`bash scripts/package-pro-macos.sh`生成Pro测试应用、DMG、ZIP及校验信息；详细安装和数据说明见[Pro测试包](docs/PRO-TEST-PACKAGE.md)。保持工作区干净后打包，使`BUILD-INFO.txt`准确记录源码提交。

`scripts/release-macos.sh`保留上游普通版发布协议，不能用于发布本分支Pro成果。独立Pro正式版本、签名公证、远程发行和自动更新通道需另行规划。M9目前仍搁置。
