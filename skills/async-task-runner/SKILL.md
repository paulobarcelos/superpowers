name: async-task-runner
description: Use when Codex should run work in a fresh context outside the current turn—launch the dedicated tmux session via skills/async-task-runner/scripts/async-task, keep it steerable, and surface results without polluting the main conversation.
---

# Async Task Runner

## Overview

Spin up Codex jobs in the background while keeping them fully steerable. The helper lives at `~/.codex/superpowers/skills/async-task-runner/scripts/async-task`; it wraps tmux so every task runs in a clean context—mirroring the old Claude Task isolation—ready for human interaction or autonomous monitoring, without polluting the parent session.

## When to Use

Default to this skill whenever you need execution outside the current conversational context. Triggers include:
- Preserving the main discussion or avoiding context bias (fresh prompt / fresh instructions needed).
- Running multiple tasks in parallel.
- Keeping artifacts/logs separate for later review.
- Giving your human partner a tmux session they can enter independently.
- Offloading longer or uncertain work so the parent can continue coordinating.

Only keep work inline when you explicitly need real-time back-and-forth within the same turn and the task will finish immediately; otherwise assume async offload is the right move.

## Prepare Once

1. Ensure the helper exists: `~/.codex/superpowers/skills/async-task-runner/scripts/async-task init`
2. Confirm `/.async-tasks/` is ignored (already added in this repo’s `.gitignore`).
3. If tmux is not installed, install it before proceeding.

## Launch Checklist (GREEN)

1. **Confirm async offload**: default to using this helper; only stay inline if the task must finish immediately inside the current turn.
2. **Agree oversight** with the human partner: confirm whether they plan to attach (interactive) or expect status pings only (autonomous). Record this in your prompt/note.
3. **Draft the prompt** in a scratch file (e.g. `/tmp/prompt-db-vacuum.txt`) with:
   - Objective, definition of done, runtime expectations.
   - Whether human approval is required mid-run.
   - Explicit deliverables for `stdout.final`.
4. **Capture touchpoints**: note what humans should monitor (e.g. “Ping me when index rebuild hits 50%”).
5. **Start the session** (from the repo root unless you intentionally change `--cwd`):
   ```bash
   ~/.codex/superpowers/skills/async-task-runner/scripts/async-task start db-vacuum \
     --prompt-file /tmp/prompt-db-vacuum.txt \
     --human-note "Check status at halfway mark; attach only if stderr spikes."
   ```
   - Add `--cwd /path/to/worktree` when the task must run elsewhere.
   - Add `--interactive` when you need the Codex TUI inside tmux (logs still capture output).
6. **Immediately report** back in the main conversation:
   - Session name (e.g. `db-vacuum`)
   - Run directory
   - Success criteria / definition of done
   - Monitoring plan (`status`, `logs stdout`, expected checkpoints) and who owns updates

### After Launch – Assign Responsibilities

| Lane | Who watches | What they do | When complete |
| ---- | ----------- | ------------ | -------------- |
| **Interactive** (human steering) | Human partner attaches via `tmux attach -t <session>` | Drive the subagent directly; optionally ask parent for summaries | Human signals completion, parent cleans up on request |
| **Autonomous** (no oversight) | Parent agent | Periodically run `~/.codex/superpowers/skills/async-task-runner/scripts/async-task status <session>` and `logs` for snapshots; notify human on milestones | Parent reports final result from `stdout.final` + exit code |

## Monitoring & Touchpoints

- `~/.codex/superpowers/skills/async-task-runner/scripts/async-task status <session>` – summaries, run directory, note, exit code, timestamps.
- `~/.codex/superpowers/skills/async-task-runner/scripts/async-task logs <session> [stdout|stderr] [--lines N]` – bounded snapshots; default 60 lines.
- Humans get one-glance paths: `.async-tasks/<session>/stdout.log`, `.async-tasks/<session>/stdout.final`, `.async-tasks/<session>/stderr.log`, `.async-tasks/<session>/meta.json`.
- Interactive sessions capture `stdout.log` when the run finishes; rely on tmux for live steering.
- If the human note requires confirmation, set a reminder (plan item) and pro-actively summarize the latest log segment rather than waiting to be asked.
- **Agents must not stream logs indefinitely.** Long `tail -f` calls stall the agent. If a human insists on live streaming they can run `tail -f` themselves outside the agent workflow.

## Completion & Cleanup

1. `~/.codex/superpowers/skills/async-task-runner/scripts/async-task status <session>` → ensure it reads `[stopped]`, capture exit code + finished timestamp.
2. Summarize results back to the human using the data under `.async-tasks/<session>/`.
3. If more work is needed, either:
   - Restart with a new session name (keep artifacts isolated), **or**
   - Bring the task back inline if it now fits a quick turn.
4. When everything is harvested, archive: `~/.codex/superpowers/skills/async-task-runner/scripts/async-task kill <session> --clear`.

## Quick Reference

| Need | Command |
| ---- | ------- |
| Prep workspace once | `~/.codex/superpowers/skills/async-task-runner/scripts/async-task init` |
| Launch async job | `~/.codex/superpowers/skills/async-task-runner/scripts/async-task start <session> --prompt-file <file> [--cwd <dir>] [--human-note <text>] [--interactive]` |
| Check status | `~/.codex/superpowers/skills/async-task-runner/scripts/async-task status <session>` |
| Show recent logs | `~/.codex/superpowers/skills/async-task-runner/scripts/async-task logs <session> [stdout|stderr] [--lines N]` |
| Stop / remove | `~/.codex/superpowers/skills/async-task-runner/scripts/async-task kill <session> [--clear]` |

## Common Mistakes & Counters

| Rationalization | Countermeasure |
| --------------- | -------------- |
| “It’s only a 5-minute task, async is overkill.” | The checklist isn’t about duration alone—if you need context preserved or expect follow-up, go async. Inline runs wipe transcripts and block the turn. |
| “Humans can attach via tmux if they care.” | Assume they will. Always share the session name, run dir, and success criteria so they can jump in immediately. In autonomous runs still share `status`/`logs` paths for quick checks. |
| “I’ll remember to summarize later.” | You won’t. Write the deliverable requirement into the prompt and rely on `stdout.final` for the authoritative summary. |
| “I’ll reuse the same session name to keep things tidy.” | Names collide and overwrite logs. Pick unique, descriptive identifiers per job (e.g. `db-vacuum-2025-11-04`). |

## Example Walkthrough – DB Vacuum With Human Checkpoint

1. Write `/tmp/prompt-db-vacuum.txt` with instructions to run `VACUUM ANALYZE`, upload progress snippets at 10-minute mark, and require human approval before finalizing.
2. Launch:  
   `~/.codex/superpowers/skills/async-task-runner/scripts/async-task start issue42-vacuum --prompt-file /tmp/prompt-db-vacuum.txt --cwd .worktrees/issue-42 --human-note "Human will attach; parent only summarize if requested."`
3. Post a status message referencing session `issue42-vacuum`, run dir `.worktrees/issue-42`, definition of done, and commands `status issue42-vacuum` / `logs issue42-vacuum`.
4. At halfway mark, read `.async-tasks/issue42-vacuum/stdout.log` (or run `logs` for a snapshot), summarize the latest progress, and request the human’s approval.
5. When `status` reports `[stopped] exit:0`, read `stdout.final`, deliver the summary, then `kill --clear`.

## Red Flags – Stop and Re-evaluate

- Session name reused or unclear.
- Prompt lacks explicit success criteria or deliverable location.
- No human-note despite needing approval/checkpoints.
- You haven’t told the human how to monitor or when you’ll report back.
- Logs show silence for longer than expected—use `logs` to inspect and escalate promptly.
