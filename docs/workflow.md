# 工作流说明

## 阶段 0：确定范围

先明确本批处理对象。可以是：

- `98 新安装 MOD 区` 这样的分隔区；
- 最近下载的 N 个条目；
- 一个作者或正式系列；
- 用户明确列出的文件夹名。

不要把“整个 modlist”当成默认范围。范围不清时先输出候选，不修改。

## 阶段 0.5：新安装 MOD 常设计划（推荐）

每次往 MO2 装了新 MOD 后，重复以下循环：

```powershell
# 1. 重新盘点，取最新 modlist
pwsh -File .\scripts\Get-MO2ModInventory.ps1 `
  -ModsPath 'E:\SkyrimAE\mo2\mods' `
  -ProfilePath 'E:\SkyrimAE\mo2\profiles\Default' `
  -OutputPath '.\work\inventory.csv'

# 2. 登记表（无 Nexus key 时加 -SkipNexus）
pwsh -File .\scripts\Build-AuthorSeriesRegistry.ps1 `
  -InventoryPath '.\work\inventory.csv' `
  -OutputPath '.\work\registry.csv' -SkipNexus

# 3. 只处理 98 测试区分隔区以上的新条目
pwsh -File .\scripts\New-RenameMapDraft.ps1 `
  -InventoryPath '.\work\inventory.csv' `
  -RegistryPath '.\work\registry.csv' `
  -OutputPath '.\work\rename-map-draft-98.csv' `
  -Separator '98 新安装 MOD 测试区'
```

初稿中 `Status=待补中文名` 的行才是本次要处理的。之后照常：Nexus 页面核对 → 填 rename map → `New-RenamePreview.ps1` → 用户批准 → 关 MO2 → `Apply-RenameMap.ps1`（自动备份）→ `Verify-RenameMap.ps1`。

要点：

- 汉化条目与其本体用同一母体作者前缀和相近中文名，排在相邻位置便于辨识；
- 本地安装（modid=0/无 meta）无页面可核对，标`中`置信度并在 ReviewNote 注明依据；
- houseCARL 等工具产出的重制文件夹与本体一起改名，标注【来源·本地】。

## 阶段 1：本地事实盘点

以 `ProfilePath/modlist.txt` 的 `+`/`-` 条目作为 profile 视图，再去 `ModsPath` 找同名文件夹。记录：

- 当前名称和原始行号；
- 启用状态；
- 是否为 separator；
- 文件夹是否存在；
- `meta.ini` 中的 Nexus ID、版本和安装包名；
- 当前中文名、英文名和现有标签。

不要用手写的长文件夹名代替实际 `modlist.txt` 条目，也不要用游戏 `Data` 目录代替 MO2 视图。

## 阶段 2：作者/系列登记

登记表是事实层，不是最终改名表。Nexus API 可以补充作者、官方标题和摘要；页面核对还需要人或 AI 判断：

- 官方英文标题是否与当前名称一致；
- 当前条目是主文件、附加组件、补丁、材质、BodySlide、SPID 或翻译包；
- 作者名是否是品牌名；
- 是否存在页面明确声明的系列或产品家族；
- 中文功能名和变体是否有足够证据。

每个判断都应带 `SourceUrl`、`Reason` 和 `Confidence`。

## 阶段 3：预览与审阅

重命名表至少需要 `OldName` 和 `NewName`。预览脚本负责机器可验证的部分：

- OldName 是否在实际文件夹和 profile 中存在；
- NewName 是否有 Windows 非法字符；
- NewName 是否和已有文件夹冲突；
- 同批次是否有重复目标名；
- 原始 `+`/`-` 是否可保持；
- 文件数量和总大小基线。

AI 或人负责语义部分，用户负责最终批准。

## 阶段 4：应用

应用操作严格限制为：

1. 备份 `modlist.txt`、`plugins.txt`、`loadorder.txt`、预览表、rename map 和每个目标文件夹的 manifest（文件数、总大小）；默认不复制文件夹内容，需要内容级备份时传 `-CopyFolders`；
2. 改目标文件夹名；
3. 精确替换 `modlist.txt` 中对应名称。

不安装、不删除、不启用、不禁用、不排序，也不编辑插件二进制。

## 阶段 5：验收

验收必须分别报告：

- 文件夹是否一一对应；
- 文件内容是否与应用前一致（`-CopyFolders` 备份按逐文件对比，默认按 manifest 的文件数和总大小对比）；
- 旧名称是否清除、新名称是否出现；
- `+`/`-` 和行号是否保持；
- `plugins.txt` 和 `loadorder.txt` 是否保持；
- 其他条目是否无差异；
- 备份位置和仍不确定的语义判断。

## 阶段 6：回滚

默认按 rename map 把新文件夹改回旧名并恢复 `modlist.txt`；`-CopyFolders` 备份从 `mods\` 复制恢复。`plugins.txt` / `loadorder.txt` 默认不恢复。
