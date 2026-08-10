# 安全与恢复

## 变更前

- 关闭 Mod Organizer、SkyrimSE、Skyrim Launcher。
- 确认 `ModsPath`、`ProfilePath` 是目标实例，不是另一个 profile。
- 先运行盘点和预览，不直接编辑 live 文件。
- 检查新名称冲突、非法字符和当前条目存在性。

## 应用范围

应用脚本只允许：

- 改目标 MOD 文件夹名；
- 改 `ProfilePath/modlist.txt` 中对应的名称。

应用脚本必须只读并校验 `plugins.txt`、`loadorder.txt`，不能把它们作为写入目标。排序和 `+`/`-` 状态保持原样。

不允许：

- 删除 MOD 文件夹或覆盖已有目标文件夹；
- 修改 ESP/ESM/ESL/BSA/BA2；
- 重新生成排序；
- 自动启用或禁用条目；
- 把整个 Skyrim 安装目录提交到 GitHub。

## 备份内容

一次应用至少备份：

- 改名前的每个目标文件夹；
- `modlist.txt`；
- `plugins.txt` 和 `loadorder.txt` 的基线副本；
- 预览表和实际 rename map；
- 文件数量、大小；需要严格验证时再计算 SHA-256。

备份应放在仓库外的本地路径，不要提交到 GitHub。

## 回滚原则

回滚优先是可恢复的移动和复制：

1. 将当前新文件夹移入备份目录中的 quarantine；
2. 从备份恢复旧名称文件夹；
3. 恢复 `modlist.txt`；
4. 默认不恢复 `plugins.txt` / `loadorder.txt`，避免覆盖备份之后用户做的其他合法改动。

应用失败时脚本会尝试自动回滚，并保留备份路径供人工处理。
