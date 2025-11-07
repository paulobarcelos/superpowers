---
name: autonomous-subagent
description: Use when a Codex subagent must work without further human replies—detect autonomous instructions early, make decisions independently, and deliver results without stalling for clarification.
---

# Autonomous Subagent Survival Guide

## Overview
When you are told to “run autonomously,” “work without waiting,” or the parent spawns you through async-task-runner in non-interactive mode, you cannot rely on live human feedback. Your job is to keep moving, make decisions with the information you already have, and return a clear result and status report. Stalling for clarification wastes the limited context window and causes the parent to discard your work.

## How to Detect You’re Autonomous
- Prompt explicitly says “run autonomously,” “no human replies,” “work without asking questions,” etc.
- Async-task-runner metadata (`.async-tasks/<session>/meta.json`) shows `interactive: false`.
- Human note or instructions mention that the parent will only read the final message/logs.
- The session is non-interactive (spawned via `codex exec`) and the instructions warn that the human is unavailable.
If you are unsure, assume autonomy until told otherwise. You may say once, “Assuming autonomous mode; proceeding without human clarification.”

## Core Discipline
1. **No human questions.** You may not ask the user to choose between options. Instead, choose yourself and justify the choice in your output.
2. **Make explicit assumptions.** When data is missing, pick the safest, simplest assumption, record it in an “Assumptions” block, and proceed.
3. **Stay within scope.** Follow any constraints, paths, or runtimes from the original prompt. If constraints conflict, explain the conflict and pick the least risky option.
4. **Keep lightweight notes.** If the run is long, periodically append status lines to stdout/stderr (for async-task runs) so the parent can inspect progress when they peek.
5. **Finish with a report.** Always end with:
   - Summary of what you attempted and the result.
   - Remaining follow-ups / blockers.
   - Assumptions you made.
   - Where artifacts live (paths, logs, commands run).

## Handling Missing Information
When you reach an unknown:
1. Scan existing files / meta / prompt for clues (recent TODOs, acceptance criteria, etc.).
2. Select the most conservative assumption that still lets you progress (prefer “implement minimal viable behavior” over “invent a new API”).
3. Continue working. Mention the assumption in your summary so the parent can adjust next time.
4. Only halt if requirements are logically impossible (e.g., contradictory constraints). If that happens, explain why it is impossible and what data would unblock it.

## Interactions With Other Skills
- You may still use brainstorming/writing-plans/etc., but do not ask the human for approval in those steps. Treat the “human partner” references in those skills as “parent agent / future reviewer.”
- If another skill instructs you to “check with the user,” replace that step with “document the question + your best answer.”
- When running tests/linters per other skills, execute them autonomously and record the outcome in your final report.

## Signals Back to the Parent
- For async-task runs, use short log entries (e.g., “#progress – migrated schema”); no need to mention stdout.final.
- If you hit a severe blocker (missing credentials, required file absent), stop further work, write a detailed blocker report, and exit. That is better than spinning forever waiting for input.
- If time-boxed, note the timebox expiry in your summary and what’s left.

## Quick Checklist Before Finishing
- [ ] Did I avoid asking the human for decisions?
- [ ] Did I document every assumption I made?
- [ ] Did I produce a concrete deliverable or blocker report?
- [ ] Did I tell the parent where to look (files, commands, logs)?

Autonomous subagents that keep going, document assumptions, and surface blockers clearly are easy for the parent to reuse. Ones that wait for permission are simply replaced. Stay moving.
