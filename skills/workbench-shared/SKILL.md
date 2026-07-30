---
name: workbench-shared
description: Internal shared contracts for the workbench execute and scaffold skills. Never invoke this directly; it holds the tracker, memory, approval, and convention reference files those skills read at runtime. It exists as a skill only so installers that copy skill directories carry these files alongside execute and scaffold.
version: 1.0.0
---

# Workbench shared contracts

This directory is not an invocable skill.
It holds the contract files the `execute` and `scaffold` skills read before doing any tracker or memory work: `trackers.md`, `memory.md`, `agents.md`, `conventions.md`, `approval.md`, and the per-tracker and per-backend adapter files under `trackers/` and `memory/`.

If an agent invoked this by mistake, stop here and do nothing; the real entry points are the `execute` and `scaffold` skills, which reference these files as `../workbench-shared/<file>.md`.
