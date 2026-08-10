# Contributing

感谢参与。这个项目的重点是可审阅、安全和可重复，而不是一次性改出一份漂亮的 MOD 列表。

## 提交新命名规则

- 说明规则解决的实际问题。
- 给出至少两个 OldName → NewName 示例。
- 说明官方来源、作者/系列判断和置信度。
- 不把单个作者自动当成系列。
- 不改变默认的“不排序、不启用、不禁用”边界。

## 修改脚本

```powershell
pwsh -File .\scripts\Test-Project.ps1
```

脚本必须继续支持参数化的 `ModsPath` 和 `ProfilePath`，不能重新写死某个用户的盘符。涉及 live MO2 的行为必须有备份、冲突检查、回滚和验收路径。
