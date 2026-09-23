# MOD 标签与重命名工作流

[![validate](https://github.com/Hyper357/TES5-mo2-mod-label-renaming/actions/workflows/validate.yml/badge.svg)](https://github.com/Hyper357/TES5-mo2-mod-label-renaming/actions/workflows/validate.yml)

一个面向 Skyrim Special Edition / Anniversary Edition、Mod Organizer 2（MO2）的可复用 MOD 整理流程。

这个项目不是 MOD 列表、整合包或游戏文件备份。它提供一套可以交给其他 AI、协作者或自己重复使用的工作方法：

```text
读取 MO2 实际条目
        ↓
建立作者/系列登记表
        ↓
核对 Nexus 页面与功能
        ↓
人工或 AI 生成重命名预览
        ↓
用户审阅并明确批准
        ↓
备份、改文件夹名、改 modlist.txt
        ↓
验证内容、启用状态、排序和其他配置未改变
```

## 适用场景

- 下载了一批新 MOD，只想处理这一批，不想重新整理整个列表。
- 需要统一中文名、官方英文名和分类标签。
- 需要让同作者、同品牌或同系列 MOD 在 MO2 左侧排序时自然聚在一起。
- 需要让另一个 AI 按明确的安全流程执行，而不是凭感觉批量改名。
- 需要在应用前审阅 CSV 预览，并保留可回滚备份。

## 核心命名格式

当前规范 **2.0**。

```text
[母体作者] 中文功能名 - 变体/层级 (by 补丁作者) — Official English Title — 【分类·标签】 【技术·标签】
```

示例：

```text
[4thUnknown] 伊斯拉米尔护甲 - 基础本体 — Ysmir Armor SE — 【服装·护甲】 【本体·ESP】
[4thUnknown] 伊斯拉米尔护甲 - SPID独立分发补丁 (by Leo) — SPID - Ysmir Armor — 【系统·分发】 【补丁·SPID】
```

规则重点：

- **中括号前缀永远属于原作者母体**（`[4thUnknown]`）。补丁/材质作者后置为 `(by Leo)`，不得占据前缀。前缀同时承担"同作者条目在 MO2 左栏聚成一簇"的职责。
- **禁用密集点号 `·` 作为名称主体分隔符**，改用带空格的短横线 ` - `。点号只允许出现在标签内部（`【服装·护甲】`）。
- **标签之间留一个半角空格**：`【服装·护甲】 【体型·3BA】`，不要写 `【服装·护甲】【体型·3BA】`。
- 中段统一 ` — `（em dash 两侧半角空格），工具脚本按它切分英文标题。
- 作者名、正式品牌名和系列品牌保留原文，不随意音译。
- 官方英文标题保留，功能性中文放在前面。
- `Overhaul` → `大修`，`Rework/Remade` → `重制`，`Fix` → `修复`，`Patch` → `补丁`，`Replacer` → `替换`。
- `SKSE`、`SPID`、`OAR`、`MCO`、`3BA`、`CBBE`、`SMP`、`AE`、`NG`、`PBR` 等缩写保留。
- 同作者不自动等于同系列；只有 Nexus 标题、说明、合集、依赖或作者声明能够证明时才建立系列。
- 标签必须嵌入名称末尾，不能只写在外部表格里，否则 MO2 内无法直接筛选和审阅。
- **存量 1.x 名称不为格式而重命名**，只在因其它原因触碰该条时顺带升级。

完整标准见 [`docs/naming-standard.md`](docs/naming-standard.md)。

> **排序与空 Mod 垫片不在本流程的默认范围。** 那是一项显式启用的扩展，见
> [`docs/sorting-and-spacers.md`](docs/sorting-and-spacers.md)。默认流程不改排序、不改启用状态、不动
> `plugins.txt` / `loadorder.txt`。

## 快速开始

要求：Windows、PowerShell 7（推荐）、MO2 portable 或 instance profile。Nexus API 只用于可选的元数据缓存，不是运行本地盘点的必要条件。

### 1. 读取实际 MO2 条目

```powershell
pwsh -File .\scripts\Get-MO2ModInventory.ps1 `
  -ModsPath 'E:\SkyrimAE\mo2\mods' `
  -ProfilePath 'E:\SkyrimAE\mo2\profiles\Default' `
  -OutputPath '.\work\inventory.csv'
```

这个步骤只读 `modlist.txt`、实际 MOD 文件夹和 `meta.ini`，不会把 `Data` 目录当作 MO2 的真实 MOD 视图。

### 2. 建立作者/系列登记表

无 Nexus API key 时仍可生成登记表，之后由人或 AI 打开 Nexus 页面补充作者、官方标题和摘要：

```powershell
pwsh -File .\scripts\Build-AuthorSeriesRegistry.ps1 `
  -InventoryPath '.\work\inventory.csv' `
  -OutputPath '.\work\author-series-registry.csv'
```

如果有 Nexus API key，可以显式传入，或使用环境变量 `NEXUS_API_KEY`。不要把 key 写进脚本或提交到 Git：

```powershell
$env:NEXUS_API_KEY = '只在当前终端临时设置'
pwsh -File .\scripts\Build-AuthorSeriesRegistry.ps1 `
  -InventoryPath '.\work\inventory.csv' `
  -OutputPath '.\work\author-series-registry.csv' `
  -CachePath '.\work\nexus-cache.csv'
```

### 3. 标签统计与初稿（可选，批量场景推荐）

先扫现有名称的真实标签用法，作为词库冻结依据；再从 inventory + registry 自动生成 rename map 初稿（已命名条目不动，未命名条目给出英文名、系列/作者候选，中文功能名留空待人工填写）：

```powershell
pwsh -File .\scripts\Get-TagStatistics.ps1 `
  -ProfilePath 'E:\SkyrimAE\mo2\profiles\Default' `
  -OutputPath '.\work\tag-statistics.csv'

pwsh -File .\scripts\New-RenameMapDraft.ps1 `
  -InventoryPath '.\work\inventory.csv' `
  -RegistryPath '.\work\author-series-registry.csv' `
  -OutputPath '.\work\rename-map-draft.csv'
```

### 4. 准备重命名表

复制 `examples/rename-map.csv`（或从初稿中挑选本批次行），为当前批次填写：

| 字段 | 是否必需 | 说明 |
|---|---:|---|
| `OldName` | 是 | `modlist.txt` 和实际文件夹中的当前名称（必须与现有名称完全一致，含标签） |
| `NewName` | 是 | 最终写入文件夹和 `modlist.txt` 的完整名称 |
| `Reason` | 否 | 页面核对后的功能/系列判断 |
| `Confidence` | 否 | `高`、`中`、`低` |
| `SourceUrl` | 否 | Nexus 页面或其他一手来源 |
| `ReviewNote` | 否 | 给审阅者或下一个 AI 的备注 |

这一步是翻译和判断的主要位置。不要让脚本猜测中文名，也不要把未核实的标题直接当作最终名称。

### 5. 生成预览

```powershell
pwsh -File .\scripts\New-RenamePreview.ps1 `
  -MapPath '.\work\rename-map.csv' `
  -ModsPath 'E:\SkyrimAE\mo2\mods' `
  -ProfilePath 'E:\SkyrimAE\mo2\profiles\Default' `
  -OutputPath '.\work\rename-preview.csv'
```

只有所有目标文件夹、`modlist.txt` 条目、名称冲突、Windows 文件名检查都通过，且 OldName 未同时出现在其他 profile 的 `modlist.txt` 中，预览才会标记为 `ReadyToApply=True`。所有 CSV 导出为带 BOM 的 UTF-8，可直接用 Excel 打开审阅。

### 6. 审阅后应用

应用前必须关闭 MO2、SkyrimSE、Skyrim Launcher。应用脚本只处理预览中通过校验的目标：

```powershell
pwsh -File .\scripts\Apply-RenameMap.ps1 `
  -PreviewPath '.\work\rename-preview.csv' `
  -ModsPath 'E:\SkyrimAE\mo2\mods' `
  -ProfilePath 'E:\SkyrimAE\mo2\profiles\Default'
```

脚本会备份 `modlist.txt`、`plugins.txt`、`loadorder.txt`、预览表、rename map 和每个目标文件夹的 manifest（文件数、总大小），然后改文件夹名并精确替换 `modlist.txt` 条目。默认不复制 MOD 文件内容（改名不改内容，manifest 足够回滚和验收）；需要内容级备份时传 `-CopyFolders`。它不会安装、删除、启用、禁用或排序 MOD。

### 7. 验收

```powershell
pwsh -File .\scripts\Verify-RenameMap.ps1 `
  -PreviewPath '.\work\rename-preview.csv' `
  -BackupPath 'E:\SkyrimAE\mod-label-renaming-backups\rename_YYYYMMDD_HHMMSS' `
  -ModsPath 'E:\SkyrimAE\mo2\mods' `
  -ProfilePath 'E:\SkyrimAE\mo2\profiles\Default' `
  -HashFiles
```

如果需要恢复名称，使用应用生成的备份：

```powershell
pwsh -File .\scripts\Restore-RenameBackup.ps1 `
  -BackupPath 'E:\SkyrimAE\mod-label-renaming-backups\rename_YYYYMMDD_HHMMSS' `
  -ModsPath 'E:\SkyrimAE\mo2\mods' `
  -ProfilePath 'E:\SkyrimAE\mo2\profiles\Default'
```

## 给其他 AI 的入口

让另一个 AI 使用本项目时，直接要求它先阅读：

1. [`AGENTS.md`](AGENTS.md)
2. [`docs/ai-runbook.md`](docs/ai-runbook.md)
3. [`docs/naming-standard.md`](docs/naming-standard.md)
4. [`docs/safety-and-recovery.md`](docs/safety-and-recovery.md)
5. [`docs/sorting-and-spacers.md`](docs/sorting-and-spacers.md) —— **仅当本次要动排序时才需要**

然后提供：

- MO2 `mods` 路径
- MO2 profile 路径
- 本次要处理的范围，例如某个分隔区、顶部 N 条或明确的 MOD 名称
- 是否允许访问 Nexus 页面
- 是否只生成预览，或已经明确批准应用
- **是否要顺带整理排序**（默认不要；这一项必须显式说明）

推荐委托语句：

> 按本仓库的 MOD 标签与重命名流程处理这批 MOD。先只读盘点实际 MO2 条目，核对 Nexus 页面，生成带 OldName/NewName/Reason/Confidence/SourceUrl 的预览 CSV，等待我审阅。未明确批准前不要改文件夹、modlist、插件或排序。

## 工程结构

```text
.
├── AGENTS.md
├── README.md
├── CONTRIBUTING.md
├── LICENSE
├── config/
│   ├── naming-rules.json
│   └── tag-vocabulary.json
├── docs/
│   ├── ai-runbook.md
│   ├── HANDOFF-PI.md
│   ├── naming-standard.md
│   ├── safety-and-recovery.md
│   ├── sorting-and-spacers.md
│   └── workflow.md
├── examples/
│   └── rename-map.csv
├── fixtures/
│   └── mo2/...
├── scripts/
│   ├── Get-MO2ModInventory.ps1
│   ├── Build-AuthorSeriesRegistry.ps1
│   ├── Get-TagStatistics.ps1
│   ├── New-RenameMapDraft.ps1
│   ├── New-RenamePreview.ps1
│   ├── Apply-RenameMap.ps1
│   ├── Verify-RenameMap.ps1
│   ├── Restore-RenameBackup.ps1
│   └── Test-Project.ps1
└── .github/workflows/validate.yml
```

## 设计边界

- 本项目只负责 MOD 名称、标签、登记表、预览、备份和验证。
- 不直接编辑 ESP/ESM/ESL/BSA/BA2；不处理翻译字符串内容。
- 不自动改变 `plugins.txt`、`loadorder.txt` 或 MO2 左侧排序。
- 不上传当前用户的 MOD 文件、游戏文件、Nexus key、浏览器缓存、完整报告或备份。
- 需要翻译或建立系列关系时，必须保留来源和置信度，不能把推测写成已核实事实。

## License

MIT，详见 [`LICENSE`](LICENSE)。

