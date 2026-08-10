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
- Never change `plugins.txt`, `loadorder.txt`, enablement, or sorting as part of a rename operation.
- Never use a guessed series relationship as a confirmed fact.
- Close MO2 and Skyrim processes before applying a rename map.
- Back up the target folders and `modlist.txt` before changing them.

The normal sequence is:

```text
inventory → registry → page review → rename map → preview → user approval → apply → verify
```
