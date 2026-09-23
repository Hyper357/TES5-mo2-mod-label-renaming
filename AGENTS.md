# Instructions for AI agents

This repository packages the reusable “MOD 标签与重命名” workflow. It is not the user's Skyrim installation.

Before acting:

1. Read `README.md`, `docs/ai-runbook.md`, `docs/naming-standard.md`, and `docs/safety-and-recovery.md`.
2. Treat the user's supplied `ModsPath` and `ProfilePath` as the only live scope.
3. Read the active `modlist.txt` and actual MOD folders before asserting installed, enabled, ordered, localized, or translated state.
4. Use Nexus pages or other primary sources for official title, author, summary, and series claims. Record `SourceUrl` and `Confidence` in the review map.
5. Generate a preview and wait for explicit approval before applying changes.

Safety rules:

- Never upload `mo2/mods`, `Data`, downloads, overwrite, save files, browser profiles, API keys, or backups to this repository.
- Never edit ESP/ESM/ESL/BSA/BA2 files.
- **Default: never change `plugins.txt`, `loadorder.txt`, enablement, or MO2 left-pane sorting as part of a rename operation.**
  The sorting + empty-mod-spacer extension documented in `docs/sorting-and-spacers.md` is **opt-in only**:
  do not apply it, and do not mix it into a rename batch, unless the user has explicitly asked for sorting
  in that same request. If a request is ambiguous about whether sorting is wanted, ask — do not assume.
- Never use a guessed series relationship as a confirmed fact.
- Close MO2 and Skyrim processes before applying a rename map.
- Back up `modlist.txt` and a per-folder manifest (file count, total size) before changing them; copy folder contents only when `-CopyFolders` is requested.
- **Never let a generated script or template hardcode an absolute install path.** Derive every path from
  the caller-supplied root, or a sandboxed test run will silently write into the user's real install.
See `docs/safety-and-recovery.md` → "路径隔离" for the incident that established this rule.

The normal sequence is:

```text
inventory → registry → page review → rename map → preview → user approval → apply → verify
```
