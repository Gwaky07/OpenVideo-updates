# OpenVideo 更新源发布规则

本仓库向已安装的 OpenVideo 提供公开产品代码更新。所有电脑、开发者和开发 Agent 必须先阅读本文件；主仓库 `Gwaky07/OpenVideo` 的发布脚本是发行入口。

- 先同步两个仓库的 `main`。源码工作树必须干净，源码 `HEAD` 与 `origin/main` 相同后才能构建。禁止使用旧电脑未同步的包。
- 侧栏清单的 `commit`、`headCommit` 必须相同，且均为 Git 自动生成的 40 位小写 SHA。禁止 `--short`、手写短提交号或放宽客户端校验。
- 清单、ZIP 内 `openvideo-sidebar-package.json` 的版本及提交必须一致，包内 `config/product-update.json` 的版本也必须一致。SHA-256 和字节数只能从最终 ZIP 自动计算。
- 在主仓库使用 `Build-OpenVideoSidebarUpdate.ps1` 和 `Publish-OpenVideoSidebarUpdate.ps1`，或使用 `Ship-OpenVideoColleagueUpdate.ps1`。发布使用 `Submit-OpenVideoUpdateFeed.ps1` 创建 PR 并等待必需检查。开发者需要可访问本仓库的 `gh` 登录；自动发布使用有适当权限的 `OPENVIDEO_UPDATES_TOKEN`。密钥不得进入 Git。
- 禁止直接推送或强推 `main`；所有修改通过 PR，必需检查名称为 `更新清单与包校验`。禁止管理员绕过。检查失败不得合并、宣称发布成功或让用户重试坏包。
- `latest-sidebar.json` 是当前侧栏更新入口；历史 Release 标签中的清单只作历史记录。修改规则不能覆盖现有线上清单或重新上传现有包。
- 本仓库不保存主产品源码、模型权重、运行时、用户配置、项目、授权或真实素材。`scripts/` 仅保存公开发行校验工具，由主仓库受控同步，不得复制完整源码树。
- 发布校验必须在本地和 CI 都执行。公网包的 URL、SHA-256、bytes 以及包内身份必须通过；只有合并到 `main` 后才算更新源发布完成。
- 新侧栏清单使用无前导零的稳定版本号，必须严格高于基线版本，包内 `identity_revision=2` 且配置的两个提交号与清单一致；历史兼容只适用于基线清单原样保留。门禁运行基线受信任脚本，不执行候选 PR 脚本。
- 新建或修改 Markdown 正文使用中文；代码、命令、路径、字段名和必要专有名词可保留原文。
