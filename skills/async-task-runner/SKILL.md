name: async-task-runner
description: Use when work must run in a fresh tmux context outside the current turn—launch it with skills/async-task-runner/scripts/async-task, harvest the final message for autonomous runs, and snapshot the tmux pane on demand when you or the human need a quick peek.
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
2. **Agree oversight + cadence** with the human partner: confirm whether they plan to attach (interactive) or expect status pings only (autonomous), and settle on concrete check-in times. If you promise to “monitor,” set a reminder (plan item) and actually re-check via `capture`/`logs` at the agreed interval.
3. **Draft the prompt** in a scratch file (e.g. `/tmp/prompt-db-vacuum.txt`) with:
   - Objective, definition of done, runtime expectations.
   - Whether human approval is required mid-run.
   - Explicit deliverables for the final response (don’t mention `stdout.final`; just describe the result—this helper captures the last message automatically).
4. **Capture touchpoints**: note what humans should monitor (e.g. “Ping me when index rebuild hits 50%”).
5. **State the autonomy level explicitly**:
   - If this run is autonomous, say so in the prompt (e.g. “You will run autonomously; the human will not answer. Make decisions yourself.”) and remind the subagent to follow the `autonomous-subagent` discipline.
   - If it’s interactive, emphasise how/when the human may step in.
6. **Start the session** (from the repo root unless you intentionally change `--cwd`):
   ```bash
   ~/.codex/superpowers/skills/async-task-runner/scripts/async-task start db-vacuum \
     --prompt-file /tmp/prompt-db-vacuum.txt \
     --human-note "Check status at halfway mark; attach only if stderr spikes."
   ```
   - Add `--cwd /path/to/worktree` when the task must run elsewhere.
   - Add `--interactive` when you need the Codex TUI inside tmux (logs still capture output).
7. **Immediately report** back in the main conversation:
   - Session name (e.g. `db-vacuum`)
   - Run directory
   - Success criteria / definition of done
   - Monitoring plan (`status`, `logs stdout`, expected checkpoints) and who owns updates

### After Launch – Assign Responsibilities

| Lane | Who watches | What they do | When complete |
| ---- | ----------- | ------------ | -------------- |
| **Interactive** (human steering) | Human partner attaches via `tmux attach -t <session>` | Drive the subagent directly; parent can run `capture <session>` (default 10 lines) if a quick peek is needed | Human signals completion, parent cleans up on request |
| **Autonomous** (no oversight) | Parent agent | Periodically run `~/.codex/superpowers/skills/async-task-runner/scripts/async-task status <session>` and `logs` for snapshots; notify human on milestones | Parent reports final result from `stdout.final` + exit code |

Tip: interactive sessions should run `/status` once before closing to copy the Session ID (needed for `restart --resume-id <ID>` if Codex must be re-authenticated).
**Artifacts to expect**
- Autonomous lane → `stdout.final` (final reply) + optional stderr tail. Use pane capture only when debugging, and remind the subagent it must treat silence as confirmation to proceed.
- Interactive lane → live tmux only. Capture snippets via `capture <session>` if you need to quote or inspect progress.

## Monitoring & Touchpoints

- `status` – quick heartbeat (dir, note, exit code).
- `stdout.final` – authoritative final message for autonomous runs; it is captured automatically, so just instruct the subagent on what to output (don’t mention `stdout.final` explicitly).
- `logs … stderr` – tail of stderr for spotting runtime errors without opening the pane.
- `capture <session> [--lines N]` – snapshot the tmux pane (recommend 10 lines to start) when you need to peek. Use repeatedly to scroll further back (increase `--lines` if necessary).
- `capture <session> [--lines N]` – snapshot the tmux pane (recommend 10 lines to start) when you need to peek. Use repeatedly to scroll further back (increase `--lines` if necessary).
- `say <session> "message"` – inject a follow-up message into an interactive subagent (uses tmux send-keys). Only available for interactive sessions.
- `restart <session> --resume-id <ID>` – kill/recreate the tmux session and run `codex resume <ID> --yolo`. Copy the session ID from `/status` inside the pane before exiting so you have it ready.
- Humans can always attach to the tmux session directly for interactive steering.
- Keep snapshots short by default (10 lines) to preserve parent context; only increase when debugging.
- If you say you’ll “monitor” an autonomous run, schedule the check (update your plan) and use `logs`/`capture` at that time. Ask the human before polling aggressively to avoid needless context churn.
- Need to re-auth or unstick Codex? Run `/status` in the pane, copy the Session ID, then `restart <session> --resume-id <ID>` immediately after killing the old session.
- **No `tail -f`.** If someone needs live output, they should attach via tmux themselves.

## Completion & Cleanup

1. `~/.codex/superpowers/skills/async-task-runner/scripts/async-task status <session>` → ensure it reads `[stopped]`, capture exit code + finished timestamp.
2. Summarize results back to the human using the data under `.async-tasks/<session>/`—lead with `stdout.final` for autonomous runs; for interactive runs cite your own summary or provide a captured snippet.
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
| Tail stderr or stdout snapshot | `~/.codex/superpowers/skills/async-task-runner/scripts/async-task logs <session> [stderr|stdout] [--lines N]` |
| Capture live pane (interactive peek) | `~/.codex/superpowers/skills/async-task-runner/scripts/async-task capture <session> [--lines N] [--output file]` |
| Send follow-up message (interactive) | `~/.codex/superpowers/skills/async-task-runner/scripts/async-task say <session> "message"` |
| Restart Codex TUI in same tmux | `~/.codex/superpowers/skills/async-task-runner/scripts/async-task restart <session> --resume-id <ID>` |
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
4. At halfway mark, run `.../scripts/async-task capture issue42-vacuum --lines 20` (or have the human attach) to summarize latest progress and request approval.
5. When `status` reports `[stopped] exit:0`, read `stdout.final`, deliver the summary, then `kill --clear`.

## Red Flags – Stop and Re-evaluate

- Session name reused or unclear.
- Prompt lacks explicit success criteria or deliverable location.
- No human-note despite needing approval/checkpoints.
- You haven’t told the human how to monitor or when you’ll report back.
- Logs show silence for longer than expected—use `logs` to inspect and escalate promptly.
