# PI Agent 接手指令（HANDOFF）

> 本文件给接手的 AI agent（PI）——它是一份**自足的委托书**，读完即可全面接管本项目，无需额外背景对话。

## 0. 你的角色

你是本项目（**Skyrim AE MOD 标签与重命名工作流**，GitHub: `Hyper357/TES5-mo2-mod-label-renaming`，本机副本 `E:\SkyrimAE\.tools\tes5-mo2-mod-label-renaming`）的维护者和执行者。项目内容：MO2（Mod Organizer 2）左侧 MOD 的名称规范化——把文件夹名和 `modlist.txt` 条目从杂乱英文改成「中文功能名 — 官方英文名 — 【标签】」格式，全部过程可备份、可回滚、可验收。**你只负责名字和标签，不碰任何游戏内容。**

## 1. 必读文件（按此顺序）

1. `README.md`（总览与快速开始）
2. `docs/workflow.md`（阶段 0-6 完整流程，含**阶段 0.5 新安装常设计划**）
3. `docs/ai-runbook.md`（AI 执行手册：顺序、证据纪律、停止条件）
4. `docs/naming-standard.md`（命名格式、中文名判断、标签原则、系列判定、置信度）
5. `docs/safety-and-recovery.md`（备份内容、应用范围、回滚原则）
6. `config/naming-rules.json` + `config/tag-vocabulary.json`（**词库已按真实用法冻结**，含 deprecated 漂移清单——新命名不得使用 deprecated 标签）
7. `AGENTS.md`（仓库自身的安全规则，务必遵守）

## 2. 环境事实

- 系统：Windows，PowerShell **5.1**（`powershell`，不是 `pwsh`）。所有脚本用 `powershell -NoProfile -ExecutionPolicy Bypass -File ...` 运行（仓库里的 `pwsh` 示例在你机器上不存在，替换为 `powershell`）。
- MO2 实例：`E:\SkyrimAE\mo2`（portable），mods 目录 `E:\SkyrimAE\mo2\mods`，profile `E:\SkyrimAE\mo2\profiles\Default`。
- **只有一个 profile（Default）**。"结构化整理" profile 已删除（备份 zip 在 `E:\SkyrimAE\Backup\profiles_结构化整理_20260811_144159.zip`），所以跨 profile 问题已清零——但预览/应用仍带跨 profile 检测，遇到其他 profile 引用应拒绝而非绕过。
- 当前约 2216 个 MOD 条目；新安装 mod 出现在顶部 `98 新安装 MOD 测试区_separator`（禁用）**以上**的区域。
- 工作产物统一放仓库 `work\` 下（inventory.csv、registry.csv、rename-map-*.csv、rename-preview-*.csv、tag-statistics.csv、rename-map-draft*.csv）。这些 CSV 输出均为 **UTF-8 with BOM**（Excel 可直开）；`modlist.txt` 写入保持无 BOM（MO2 兼容）。

## 3. 已完成与未完成（截至 2026-08-15）

- 98 区两个批次已应用并验收通过：
  - 批量1（23 条，备份 `E:\SkyrimAE\mo2\profiles\mod-label-renaming-backups\rename_20260811_151940`）
  - 批量2（22 条，备份 `E:\SkyrimAE\mo2\profiles\mod-label-renaming-backups\rename_20260815_104654`）
- **遗留待办：OBody 家族剩余 3 条**——预览在 `work\rename-preview-obody-family.csv`（4 行，其中 OBodyWeight 已于批量1应用；剩 3 行 Ready 未应用：OBody Next Generation、OBody Next Generation - Yet Another Settings Loader、OBody NG Preset Distribution Assistant NG）。要完善它们或给用户确认后应用。
- **仓库 git 未提交**：12 个文件修改 + 2 个新脚本（`Get-TagStatistics.ps1`、`New-RenameMapDraft.ps1`）。**未经用户明确要求不要 commit/push。**

## 4. 常设计划（新装一批跑一遍）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-MO2ModInventory.ps1 `
  -ModsPath 'E:\SkyrimAE\mo2\mods' -ProfilePath 'E:\SkyrimAE\mo2\profiles\Default' `
  -OutputPath '.\work\inventory.csv'

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-AuthorSeriesRegistry.ps1 `
  -InventoryPath '.\work\inventory.csv' -OutputPath '.\work\registry.csv' -SkipNexus

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\New-RenameMapDraft.ps1 `
  -InventoryPath '.\work\inventory.csv' -RegistryPath '.\work\registry.csv' `
  -OutputPath '.\work\rename-map-draft-98.csv' -Separator '98 新安装 MOD 测试区'
```

`Status=待补中文名` 的行就是待处理对象。之后走完整链路：

1. **Nexus 核对**（见第 6 节）→ 填 `rename-map.csv`（OldName 必须与当前实际名称**逐字符一致**，含已有标签；NewName 用第 5 节格式）
2. `New-RenamePreview.ps1` 出预览（机器校验：存在性/非法字符/目标冲突/重复/`+`-`保持/跨 profile）
3. **展示给用户**：OldName→NewName、标签拆解、依据（SourceUrl）、Confidence；等用户明确批准
4. 确认无 MO2/Skyrim 进程 → `Apply-RenameMap.ps1`（自动备份：modlist/plugins/loadorder 基线 + rename-map + manifest，默认不复制文件内容；`-CopyFolders` 才全量备份）
5. `Verify-RenameMap.ps1` 验收（含 plugins/loadorder 哈希比对），向用户报告备份路径

## 5. 命名与标签要点

格式（2.0）：`[母体作者] 中文功能名 - 变体/层级 (by 补丁作者) — Official English Title — 【标签】 【标签】`

- **中括号前缀永远属于原作者母体**；补丁/材质作者后置为 `(by X)`，不占前缀。前缀同时承担"同作者条目在 MO2 左栏聚簇"的职责。
- **禁用密集点号 `·` 作为名称主体分隔符**，改用带空格的短横线 ` - `；点号只允许出现在标签内部（`【服装·护甲】`）。**标签之间留一个半角空格**（`】 【`）。1.x 的 `系列锚点·中文名` 写法已废弃。
- 中文名只翻译**功能**，品牌/作者/缩写（SKSE、SPID、KID、PBR、3BA、CBBE、HIMBO、SMP、AE、NG、VR…）保留原文。
- 官方英文标题保留；本地 mod（无 Nexus 页面）用其自述名。
- 标签必须写进名称末尾（MO2 内可搜索），从 `config/tag-vocabulary.json` 选取；**禁止** deprecated 列表中的写法（如裸 `HIMBO`、`BodySlide`、`待核`、`多版本`、`工具`、`汉化·和光` 等）。
- 系列判定：只在标题/页面说明/合集/依赖/作者声明证明时为`系列`；同作者≠同系列。作者已作为前缀时，系列下沉到标签池 `【系列·xxx】`。
- 汉化条目与其本体用相近中文名 + 同一母体前缀，排在相邻（汉化建议【汉化·人工】，注明"和光词条"用 ReviewNote 而非标签）。
- 置信度：高=官方标题/功能/系列均一手来源（Nexus 页面）；中=本地判断（modid=0、技术产出）；低=仅猜测（禁止写成事实，注明待核）。

## 6. Nexus 核对方法（重要）

- 页面直抓（webfetch）会被 Nexus 403。**用 playwright 浏览器工具**：`page.goto(url)` 后等约 1.5-2.5s，从 `meta[property="og:title"]` 取官方标题、`meta[name="description"]` 取摘要、`a[href*="users/"]` 取作者（过滤 `My profile`/`My mods`/`account_circle`）。可一轮 script 批量遍历多个 id（先对每个条目取 `meta.ini` 的 `modid`；`modid=0` 或无 meta.ini = 本地安装）。
- 若你有 houseCARL MCP：优先用 `housecarl_nexus_search` / `housecarl_nexus_mod`（无需 key），更稳。
- 每个判断写 `SourceUrl` + `Reason` + `Confidence`；页面核对失败就写"页面未核实"，**绝不编造**标题/作者/摘要。

## 7. 安全铁律（违反即事故）

1. 绝不直接写 `.esp/.esm/.esl/.bsa/.ba2`；不处理插件内容、翻译文本。
2. 不改 `plugins.txt`、`loadorder.txt`、启用状态（`+`/`-`）、排序、行序——应用脚本只改文件夹名 + `modlist.txt` 对应行，且备份这两个状态文件只读基线。
3. 应用/恢复前必须确认 MO2/Skyrim/Skyrim Launcher 进程已关闭。
4. 改动前先备份（脚本自动做）；`work\` 产物属于仓库，与用户 MOD 文件无关；**不得上传** `mo2\mods`、`Data`、存档、下载、overwrite、浏览器数据、API key 等到 GitHub。
5. 任何 rename map 变更先出预览、等用户批准；用户说"再改"、"换标签"时以用户为准。
6. 每个批次结束时报告：应用条数、备份路径、Verify 结果、低置信度条目明细。

## 8. 已知技术坑（写脚本时遵守）

- 本机只装 PowerShell 5.1（无 pwsh）。
- **`$x = if (...) { @() } else { @() }` 会把空数组变成 `$null`**（StrictMode 下 `.Count`/`.Sum` 报 PropertyNotFound）——必须先 `$x = @()` 再条件填充；`Measure-Object` 空输入后取 `.Sum` 也要先判空。已有两处修复（New-RenamePreview、Apply-RenameMap 的 manifest 段）。
- 本地变量不要用自动变量名（`$matches` 会被 `-match` 改写）。
- CSV 导出用 BOM；`modlist.txt` 写回用无 BOM UTF-8；替换 modlist 是"逐行精确匹配 `+old`/`-old`"式替换，不重排。
- 文件名校验：Windows 非法字符已被预览拦截；改名后立刻 `Verify-RenameMap.ps1` 确认文件数/大小=manifest。

## 9. 日常接管权限边界

- **允许**：跑盘点/初稿/预览/应用/验收/回滚；维护 `work\`、`config\`、`docs\`、`scripts\`；回答"这个 mod 是干嘛的/标签怎么打"类问题。
- **需请示**：修改游戏/配置目录（非 mods）、改 plugins/loadorder、删 MOD、修改仓库 git 历史、批量处理 50+ 条以上、改变命名标准或词库。
- **不做**：翻译 mod 内容、编辑插件、制作 patch、排序策略调整（除非用户明确要求并另开课题）。

## 10. 接手第一步（现在就做）

1. 按第 1 节读完文档。
2. `git status` + `git log --oneline` 确认仓库状态（有未提交改动，保持原样）。
3. 跑一遍第 4 节三行命令，确认盘点/初稿能出（这是"接管成功"的最低验证）。
4. 向用户报告：环境验证结果 + 当前待办（OBody 剩余 3 条、未提交改动）+ 你的工作计划，然后等用户指令。
