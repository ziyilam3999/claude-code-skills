---
name: mailbox
description: >
  Cross-session messaging between Claude Code agents. Use when the user says
  "/mailbox", "send a message to [agent]", "check mailbox", "check for messages",
  or wants to exchange information between Claude Code sessions. Supports
  subcommands: send, check, status, handoff. Each session gets an auto-generated
  agent name on first use for routing. Works across local CLI and Dispatch (cloud)
  sessions.
---

# Mailbox

Exchange messages between Claude Code sessions via a shared git-backed mailbox.

## How It Works

Claude Code sessions cannot communicate directly. This skill uses a shared git
repository as a bulletin board. One session writes a message, the other pulls and
reads it. Works across local CLI terminals AND Dispatch (cloud) sessions.

## Execution Flow

On every `/mailbox` invocation, check which mode to use:

1. **If you have a MAILBOX CACHE memorized** from a previous `/mailbox` call in this conversation → use the **Warm Path** (skip to Subcommands directly)
2. **Otherwise** → run **Cold Start** first, then proceed to Subcommands

---

## Cold Start

**Runs once per conversation** — on the very first `/mailbox` invocation. All subsequent invocations use the Warm Path.

### Step 1: Discover Mailbox Repo

Determine the mailbox repo path (`MAILBOX_REPO`):

1. If env var `MAILBOX_REPO` is set, use it
2. Else if `~/.mailbox-repo` file exists, read its contents (an absolute path)
3. Else if `mailbox/inbox/` exists in the current project root, use the current project root
4. Else: **auto-bootstrap** a new mailbox repo:
   ```bash
   mkdir -p ~/claude-code-mailbox/mailbox/inbox ~/claude-code-mailbox/mailbox/archive
   cd ~/claude-code-mailbox && git init
   echo ".ai-workspace/sessions/" > .gitignore
   git add -A && git commit -m "chore: initialize mailbox"
   echo "$(cd ~/claude-code-mailbox && pwd)" > ~/.mailbox-repo
   ```
   Set `MAILBOX_REPO` to `~/claude-code-mailbox` and continue. Print: "Created new mailbox at ~/claude-code-mailbox"

All paths below are relative to `{MAILBOX_REPO}`.

### Step 2: Detect Default Branch

```bash
cd {MAILBOX_REPO}
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}' || echo "main")
```

### Step 3: Resolve Agent Name

Resolve the agent name using session-scoped identity.

#### 3a: Read session ID

Session IDs are delivered to each session privately via the `SessionStart`
hook (`inject-session-id.sh`), which injects a line of the form
`MAILBOX_SESSION_ID={id}` into that session's additionalContext at boot.
This is the authoritative source — it cannot be overwritten by other
terminals running in the same project directory.

Priority order:

1. **If a `MAILBOX_SESSION_ID=...` line appeared in this session's SessionStart context, use that value.** It is authoritative and session-private.
2. Else if you already memorized a session ID earlier in this conversation, use it.
3. Else (legacy fallback — SessionStart hook did not run, e.g. older Claude Code, or Windows terminal that skipped the hook): list files in `.ai-workspace/sessions/` of the **current project root** and pick the most recently modified filename as the session ID. **Warn the user**: "⚠ SessionStart hook did not deliver MAILBOX_SESSION_ID; falling back to most-recent sessions/ file. If you have multiple terminals open in the same project, identities may collide — restart terminals to pick up the hook."
4. Else set session ID to `"default"`.

Do not re-read any shared singleton file like `.current-session-id`. That
path was removed because it was a last-writer-wins collision point between
terminals sharing a project directory.

#### 3b: Read agent registry

Read `{MAILBOX_REPO}/.ai-workspace/.mailbox-agents.json`.
- If it exists, parse it as JSON: `{ "<session-id>": "<agent-name>", ... }`
- If it does not exist, start with an empty registry `{}`
- **Important:** Always read/write the registry from `{MAILBOX_REPO}`, never from the current project root (unless CWD *is* the mailbox repo). If `.ai-workspace/.mailbox-agents.json` exists in CWD but CWD ≠ MAILBOX_REPO, ignore it — it is stale.

#### 3c: Resolve name

**Important:** Only use the sources listed below to determine the agent name. Do NOT use project memory, auto-memory files, or context from prior conversations. Agent names are session-scoped and must come from: (1) the user, initial prompt, or project CLAUDE.md saying "Your name is X" or "Your mailbox name is X", (2) the registry entry for THIS session ID, or (3) fresh generation.

**Never save agent names to memory.** Do not write your own or any other agent's name to Claude Code memory files (auto-memory, project memory, MEMORY.md, etc.). Names are session-scoped and will mislead future sessions. The registry is the only persistence mechanism for agent names.

1. If the user, initial prompt, or project CLAUDE.md says "Your name is X" or "Your mailbox name is X", use X
   -- read the existing registry JSON, set ONLY the key `"<session-id>"` to `"X"`, write back the complete registry (preserving all other entries)
2. If the session ID is `"default"` (hook did not fire): **skip the registry lookup**.
   Generate a new name (step 5 below) and write it to the registry under key `"default"`.
   This prevents multiple hookless sessions from sharing a name.
3. If the registry has an entry for the current session ID, use that name
4. If a name was already generated earlier in this conversation, use it, write to registry
5. Otherwise, generate a new name using `{adjective}-{name}` format:
   - Adjectives: happy, clever, brave, calm, eager, gentle, kind, lucky, swift, wise
   - Names: alice, bob, charlie, dave, emma, frank, grace, henry, iris, jack
   - Pick randomly (e.g., `happy-alice`, `clever-bob`)
   - Before writing, check if this name already exists as a value in the registry under a different session ID. If so, generate a different name (try up to 3 times).
   - Read the existing registry, add the new entry keyed by session ID, write back the full registry (preserving all other entries)
6. Print: `Agent name: {name}. Run /rename {name} to label this terminal tab.`

**Safety check:** When writing to the registry, ONLY write/update the key matching YOUR memorized session ID. Never modify entries for other session IDs.

#### Registry maintenance

When writing to the registry, if it has more than 20 entries, keep only the 20 most recent
(by position in the JSON object -- newer entries are appended at the end).

Names are **persisted per-session** in the registry. This means:
- The name survives `/compact` and `--continue`/`--resume` (same session ID).
- Different sessions on the same project get **independent names**.
- To change your name, say "Your name is X".

### Step 4: Memorize Cache

After completing steps 1-3, memorize the following as your **MAILBOX CACHE**:

```
MAILBOX CACHE:
  repo: {MAILBOX_REPO}
  session_id: {session ID}
  agent_name: {resolved name}
  default_branch: {DEFAULT_BRANCH}
  known_agents: {}
```

This cache persists for the rest of the conversation. All subsequent `/mailbox` calls use it directly.

Now proceed to the relevant Subcommand below.

---

## Warm Path

**Used for all `/mailbox` invocations after the first.** You already have a MAILBOX CACHE memorized.

Use the cached `repo`, `session_id`, `agent_name`, and `default_branch` directly — no discovery, no registry reads, no branch detection.

For transport mode: check `known_agents` in the cache (see Transport Mode Detection below). If the agent is cached and `checked_at` < 30 min ago, use the cached mode. Otherwise run transport detection once and update the cache.

Proceed directly to the relevant Subcommand.

---

## Reserved Aliases

- **`all`**: Messages addressed to `all` are read by every agent.
- **`dispatch`**: Messages addressed to `dispatch` are read by Dispatch (cloud) sessions. When checking messages, Dispatch sessions should match `to:` against their own name, `all`, AND `dispatch`.

When sending to a Dispatch (cloud) session, address the message `to: dispatch`.

## Remote Trigger Integration

Remote triggers (scheduled agents via `RemoteTrigger` API) get a new session ID on
every run, which breaks registry-based name persistence. To give a trigger a stable
mailbox name, include this directive in the trigger's `prompt` field:

    Your mailbox name is {name}. [rest of prompt]

This is handled by priority rule #1 in name resolution. The name is written to the
registry on each run (keyed by that run's session ID), keeping the registry current.

When creating triggers via `RemoteTrigger create`, always include this directive:

```json
{
  "prompt": "Your mailbox name is swift-grace. Check mailbox and process bug reports.",
  "cronExpression": "0 8 * * *"
}
```

## Transport Mode Detection

Determines whether to use **local mode** (skip git push/pull) or **git mode** (full push/pull).

**Caching:** After detecting transport mode for any agent, update `known_agents` in the MAILBOX CACHE:
```
known_agents:
  {agent-name}: { transport: local|git, checked_at: {current timestamp} }
```
On subsequent calls, if the agent is in `known_agents` and `checked_at` < 30 min ago, use the cached transport mode without re-running detection.

### For send / handoff operations

Determine transport mode for the **recipient**:

1. If the recipient is `dispatch` or `all`: use **git mode** (stop here)
2. Reverse-lookup: scan `{MAILBOX_REPO}/.ai-workspace/.mailbox-agents.json` for
   entries whose **value** matches the recipient name. Collect the session ID(s).
3. For each matching session ID, check if the file
   `{MAILBOX_REPO}/.ai-workspace/sessions/{session-id}` exists AND was modified
   within the last `MAILBOX_SESSION_TTL` minutes (env var, default `120`):
   ```
   TTL=${MAILBOX_SESSION_TTL:-120}
   find {MAILBOX_REPO}/.ai-workspace/sessions/ -name "{session-id}" -mmin -"$TTL" 2>/dev/null
   ```
4. If at least one matching session file is recent: use **local mode**
5. Otherwise: use **git mode** (recipient may be remote or offline)

### For check operations

**Pull decision:**
1. Run a lightweight remote check:
   ```
   cd {MAILBOX_REPO}
   git fetch origin "$DEFAULT_BRANCH" 2>/dev/null
   BEHIND=$(git rev-list "HEAD..origin/$DEFAULT_BRANCH" --count 2>/dev/null || echo "1")
   ```
2. If BEHIND > 0 or the fetch failed → **git mode** (pull needed).
   If BEHIND = 0 → **local mode** (skip pull).

**Push decision (after processing):**
3. For each processed message, determine transport mode for the **sender** (`from:` field):
   - Check `known_agents` cache first (if cached and < 30 min old, use it)
   - Otherwise, run the same reverse-lookup + session-file-age check as send operations, then cache the result
4. If any sender is remote (git mode) or unknown → **git mode** (push needed).
   If all senders are local, or no messages → **local mode** (skip push).

### Fallback

If any detection step fails (command errors, missing files, parse failures),
default to **git mode**. It is always safe to *attempt* push/pull; if push
fails (e.g., archived remote, network error), warn and continue — the message
is committed locally. It is never safe to skip when uncertain.

### Cache Invalidation

| Cached Value | When to Invalidate |
|-------------|-------------------|
| `repo`, `session_id`, `agent_name`, `default_branch` | Never — constant within a conversation |
| `known_agents[X].transport` | Re-check if `checked_at` > 30 min ago |
| `known_agents[X].transport` | Re-check if git push/pull fails for that agent |
| Entire MAILBOX CACHE | Clear on unexpected git error; re-run Cold Start |

Safety property: falling back to Cold Start is always correct. The cache is purely an optimization.

### Push Failure Recovery

After any `git push` failure in git mode:
1. Do NOT fail the send/check operation — the message/archive is committed locally
2. Warn the user: "⚠ Push failed — message committed locally but Dispatch sessions may not see it"
3. Log in run data with issue: "git push failed: {error summary}"

## Subcommands

All subcommands below assume the MAILBOX CACHE is populated (either by Cold Start or from a previous invocation). Use cached `repo`, `agent_name`, and `default_branch` directly.

### `/mailbox send` or `/mailbox send to <agent-name>`

Write and deliver a message.

1. Determine recipient:
   - If user specified `to <name>`: use that name
   - If user said "send to X": use X
   - Otherwise: ask "Who should this be addressed to?"
2. Determine message content:
   - If user provided content inline: use it
   - Otherwise: compose using the checklist below

   **Compose checklist — mentally simulate: "The receiver has zero context from my
   conversation. What do they need to understand and act without asking follow-ups?"**

   Include every applicable item:

   | Category | Include |
   |----------|---------|
   | **Identity** | What project/repo, what branch, what PR (URL if exists) |
   | **Action done** | What you completed — concrete results, not just "I looked into it" |
   | **Evidence** | Metrics, test results, audit scores, error messages — paste actual values |
   | **Decisions** | Design choices made and *why*, alternatives rejected |
   | **Artifacts** | URLs (PRs, deploys, previews), file paths changed, commands to run |
   | **Current state** | What is working now, what is not, any blockers |
   | **Ask / Next step** | Exactly what you need from the receiver, or what they should do next |

   **Anti-patterns (from KB F7, F11, F13):**
   - "I made some improvements" → say *what* improvements with *what* effect
   - "There were a few issues" → list each issue with its resolution
   - "See the PR" → include key changes inline; receiver may not have repo access yet
   - "As discussed" / "as mentioned" → never reference prior conversation; inline all context
   - Vague status without counts → use mechanical clarity: "3/5 tests pass", "PASS", "12 files"
   - Sending a status without metrics when metrics exist in your conversation
3. Run Transport Mode Detection for the recipient (check `known_agents` cache first).
4. Write message file to `{repo}/mailbox/inbox/`:

   **Filename:** `{YYYY-MM-DDTHHMM}-{from}-to-{to}-{subject-slug}.md`

   **Format:**
   ```markdown
   ---
   from: {agent_name}
   from_project: {current project directory name}
   to: {recipient-name}
   to_project: {recipient project, if known, else "unknown"}
   subject: {brief subject line}
   timestamp: {ISO-8601}
   status: unread
   # --- optional reply/threading fields (all default-omitted) ---
   reply_expected: false          # true if you expect a reply
   reply_sla_seconds: null        # defaults by priority when reply_expected=true: blocker=600, normal=1500, fyi=null
   reply_to: {filename-of-prior-mail}  # when this mail is itself a reply
   thread_id: {slug}              # groups related mails; defaults to subject-slug on thread start
   priority: normal               # blocker | normal | fyi
   auto_schedule_wakeup: false    # see Phase 3.2 in plan; requires reply_expected=true + non-null SLA
   ---

   {message body -- use the compose checklist above; receiver has zero context}
   ```

   **Send-time validation** (reject before writing the file):
   - `reply_expected: false` AND non-null `reply_sla_seconds` → reject: `reply_sla_seconds only valid when reply_expected: true`.
   - `priority: fyi` AND `reply_expected: true` → reject: `fyi priority cannot require a reply`.
   - `auto_schedule_wakeup: true` AND `reply_expected: false` → reject: `auto_schedule_wakeup requires reply_expected: true`.
   - `auto_schedule_wakeup: true` AND null `reply_sla_seconds` (after priority-default resolution) → reject: `auto_schedule_wakeup requires a non-null reply_sla_seconds`.
   - `priority` not in `{blocker, normal, fyi}` → reject: `priority must be one of: blocker, normal, fyi`.

   **SLA defaults** (applied only when `reply_expected: true` and `reply_sla_seconds` is null): `blocker=600`, `normal=1500`, `fyi=null`. Source: swift-henry's 2026-04-13 comm-schedule protocol lock.

5. Git operations — **batch into a single command**:

   **Git mode:**
   ```bash
   cd {repo} && git checkout {default_branch} && git pull --rebase && git add mailbox/inbox/{filename} && git commit -m "mailbox: {from} -> {to}: {subject}" && git push 2>&1 || echo "⚠ Push failed — message committed locally but Dispatch sessions may not see it."
   ```

   **Local mode:**
   ```bash
   cd {repo} && git checkout {default_branch} && git add mailbox/inbox/{filename} && git commit -m "mailbox: {from} -> {to}: {subject}"
   ```

6. **Auto-schedule wake-up (if `auto_schedule_wakeup: true`):** run the procedure in "Wait-for-reply infrastructure" below, passing the message's `subject-slug`, `to:` (as `expected_sender`), effective `reply_sla_seconds`, and a default `max_retries = 2`.
7. Print:
   ```
   Message sent to {to} ({mode}). Tell that session to run /mailbox check.
   Retract via /mailbox retract {subject-slug} until recipient archives it.
   ```
   where `{mode}` is `local` or `git` and `{subject-slug}` is the canonical slug used in the filename. If auto-wakeup was scheduled, append:
   ```
   Auto-wakeup scheduled for {fire_at_iso} (cron {cron_id}).
   Note: cron fires only when Claude is idle. If Claude exits before fire time, the wake-up is lost — run /mailbox check --resume-wait {subject-slug} manually on next startup.
   ```

### `/mailbox check`

Read and archive incoming messages.

1. Run Transport Mode Detection for check (pull decision):

   **Git mode (upstream has changes):**
   ```bash
   cd {repo} && git checkout {default_branch} && git pull --rebase
   ```

   **Local mode (no upstream changes):**
   ```bash
   cd {repo} && git checkout {default_branch}
   ```

2. List all files in `{repo}/mailbox/inbox/`
3. For each `.md` file, read the frontmatter:
   - If `to:` matches this agent's name OR `to: all`: this message is for us
   - If this is a Dispatch session: also match `to: dispatch`
   - Skip messages where `to:` doesn't match
4. For each matching message:
   a. Print the subject, sender, timestamp, and body
   b. If the message has a `type: handoff` field, also print all `handoff:` fields (repo, branch, pr, task_status, what_done, what_left, files_changed, resume_plan)
   c. Update `status: unread` to `status: read` in the file
   d. **Archive (REQUIRED):** `git mv mailbox/inbox/{file} mailbox/archive/{file}`
   e. **Append read receipt** to `{repo}/.ai-workspace/read-receipts.jsonl` (gitignored) via atomic append (open O_APPEND on POSIX, or temp-file-rotation on Windows if append is unsafe):
      ```json
      {"timestamp": "{ISO-8601-now}", "reader": "{agent_name}", "sender": "{from}", "filename": "{file}", "subject": "{subject}"}
      ```
      Rotation: if `read-receipts.jsonl` has > 1000 lines after append, trim to the newest 500 lines.
5. Run Transport Mode Detection for each sender (`from:` field) — check `known_agents` cache first, run detection only for unknown/stale senders. This determines the push decision.
6. Git operations — **batch into a single command**:
   ```bash
   cd {repo} && git add mailbox/ && git commit -m "mailbox: {agent_name} read {N} message(s)"
   ```
   **Git mode only** (any sender is remote or unknown):
   ```bash
   git push 2>&1 || echo "⚠ Push failed — archive committed locally but remote sync failed."
   ```
7. **Verify archive:** Confirm no processed messages remain in `mailbox/inbox/` for this agent. If any do, run `git mv` now, then `git add mailbox/ && git commit -m "mailbox: archive missed files"`. Only run `git push` if in git mode.
8. **Pending-replies GC:** for every file in `{repo}/.ai-workspace/pending-replies/*.json`, compute `sent_at + (max_retries + 1 + 3) * sla_seconds + 3600s`. If that timestamp is in the past, delete the watcher file (and `CronDelete(cron_id)` if `cron_id != null`, ignoring errors). The `+3` term bounds worst-case extension from early-fire absorptions (budget=3).
9. If no messages found: print `No new messages for {agent_name}.`

### `/mailbox status`

Show agent identity, unread count, polling mechanics, and co-located agents.

1. Count files in `{repo}/mailbox/inbox/` where `to:` matches this agent's name (and `dispatch`/`all` if applicable).
2. **Cron introspection (Polling mechanics):**
   a. Run `ToolSearch select:CronCreate,CronList,CronDelete` first — without this, `CronList` raises `InputValidationError`.
   b. Call `CronList`. Parse each line: `{id} — {schedule} ({mode}) [{persistence}]: {prompt}`.
   c. Filter to lines whose prompt substring-contains the literal token `/mailbox check` (not just `/mailbox`).
   d. For each match print:
      ```
      Polling mechanics:
        Cron: {id} — {schedule} [{persistence}]
        Mode: {recurring|one-shot}
        Prompt: {prompt}
      ```
   e. If zero matches: `⚠ No scheduled /mailbox check cron detected. Replies to this agent may have unbounded latency.`
   f. On `InputValidationError`: `⚠ Cron introspection unavailable ({error}). Ensure ToolSearch has loaded CronList.` Then continue — do not abort `/mailbox status`.
3. **Co-location probe:** enumerate every entry in `{repo}/.ai-workspace/.mailbox-agents.json`. For each `(session-id, agent-name)` pair where `agent-name != self`, check whether `{repo}/.ai-workspace/sessions/{session-id}` was modified within the last `MAILBOX_SESSION_TTL` minutes (env var, default `120`). Collect the set of co-located agent names (dedupe — multiple session IDs may map to the same name). If registry is missing or malformed, emit `⚠ Co-location probe unavailable (registry missing/malformed)` and continue.
   - If the co-located set is non-empty, print:
     ```
     Co-located with: {agent1}, {agent2}
       ⚠ Shared failure domain — heartbeats between co-located agents NOT recommended.
     ```
4. **Read-receipt cursor counter:** per-agent cursor file `{repo}/.ai-workspace/read-receipts-cursor/{agent_name}.txt` stores a single integer = last-seen line number in `read-receipts.jsonl`.
   a. Read cursor (default `0` if file absent).
   b. Count current total lines in `{repo}/.ai-workspace/read-receipts.jsonl` (0 if file absent).
   c. **Rotation guard:** if cursor > current line count, reset cursor to `0` and read from line 1 (rotation trim happened since last status call).
   d. Read lines `cursor+1 .. EOF` and count entries where `sender == {agent_name}`. Call that `N`.
   e. Write the new EOF line number to the cursor file via atomic temp-then-rename.
5. Print:
   ```
   Agent: {agent_name}
   Project: {current project}
   Mailbox repo: {repo}
   Unread: {count} message(s)
   Recent read receipts: {N} of your mails were read since last status check.
   ```

### `/mailbox retract <slug>`

Withdraw a mail you sent, as long as the recipient has not yet archived it. The retraction is best-effort: if the recipient pulls and archives before your retract reaches their branch, the mail is already delivered and cannot be un-sent.

1. **Resolve slug → file (double-anchored):**
   a. Glob `{repo}/mailbox/inbox/*-to-*-{slug}.md` as a candidate pool.
   b. For each candidate, read frontmatter and compute the canonical subject-slug by slugifying the `subject:` field with the same slugifier `/mailbox send` uses (lowercase, non-alnum → `-`, collapse runs).
   c. Retain only candidates whose canonical subject-slug is **exactly equal** to the provided `{slug}` — not a suffix match. This prevents `foo` from matching a mail with subject-slug `bar-foo`.
   d. If the glob returned zero candidates, scan all `{repo}/mailbox/inbox/*.md` frontmatter and apply the same exact-equality filter.
   e. Multiple matches → abort, print disambiguation listing (filename + timestamp + from → to).
   f. Zero matches → abort: `No inbox mail from {agent_name} with subject-slug {slug}.`
2. Verify frontmatter `from:` equals `{agent_name}`. Else refuse: `Cannot retract: {filename} was sent by {from}, not you.`
3. Verify file path is under `mailbox/inbox/` not `mailbox/archive/`. Else refuse: `Cannot retract: {filename} is already archived.`
4. **Race-close (pre-commit fetch):** determine recipient transport mode from the mail's `to:` field. If git mode:
   ```bash
   cd {repo} && git fetch origin {default_branch}
   ```
   Then check whether the file still exists at `inbox/{file}` on `origin/{default_branch}`:
   ```bash
   git cat-file -e origin/{default_branch}:mailbox/inbox/{file} 2>/dev/null
   ```
   If it does NOT exist on origin (recipient already archived), abort: `⚠ Retract lost the race — {to} already pulled and archived {filename}. Send a correction mail instead.`
   If local mode, skip the fetch.
5. **Snapshot rollback target:** `PRE_RETRACT=$(git rev-parse HEAD)`.
6. `git rm mailbox/inbox/{file}`.
7. Append a JSONL record to `{repo}/.ai-workspace/retractions.log` (gitignored). Fields: `{timestamp, agent, filename, to, subject, outcome}`. Rotate: if line count > 1000, trim to the newest 500 lines.
8. Commit: `git commit -m "mailbox: {agent_name} retracted {filename}"` and record `RETRACT_COMMIT=$(git rev-parse HEAD)`.
9. **Git mode only — push, with non-destructive rollback on failure:**
   ```bash
   git push 2>&1
   ```
   If push fails:
   a. `git pull --rebase`.
   b. Inspect result. Three sub-cases:
      - **(i) Clean rebase, file still absent on new HEAD and no recipient archive commit landed** (just stale remote): the rebase left the retract commit correctly layered on top of the latest remote — retry `git push`. If push fails again, re-enter step 9's failure path (up to 3 total attempts with `git pull --rebase` between each). After 3 failed attempts, abort and instruct the user to resolve manually. **Do NOT revert** — a clean rebase means the retract is still valid; `git revert {RETRACT_COMMIT}` would forward-recreate `inbox/{file}` and push it, defeating the entire retraction command.
      - **(ii) Rebase pulled in a recipient archive commit** (file moved to `archive/{file}` on origin): the recipient already saw it. Retraction is moot. **Do NOT revert** — the revert would be empty against the merged tree. Leave `RETRACT_COMMIT` in local history as a no-op on merge. Update the retractions.log entry's `outcome` to `"lost-race-recipient-archived"`. Print:
        ```
        ⚠ Retract lost the race: recipient {to} archived {filename} at {archive-commit-sha}.
        The retract commit on your local branch is now meaningless. Leaving it in place
        (recipient's archive takes precedence on merge). Send a correction mail instead.
        ```
      - **(iii) Rebase conflict unrelated to a recipient archive:** abort, leave the working tree in the conflict state, instruct the user to resolve manually.
   c. **Never `git reset --hard`** — it discards unrelated local commits.
10. On happy path and sub-case (i), print:
    ```
    Retracted. Recipient will never see it ({mode}).
    ```
    Sub-case (ii) prints the lost-race banner in step 9(b)(ii) instead.

### `/mailbox sent`

List mail you have sent (newest first, capped at 100).

1. Enumerate `{repo}/mailbox/inbox/*.md` and `{repo}/mailbox/archive/*.md`. Filenames begin with an ISO timestamp, so sort descending by filename — chronological without parsing frontmatter.
2. Walk the sorted list; for each file:
   a. Read frontmatter. On parse failure, skip the file and continue.
   b. If `from:` != `{agent_name}`, skip.
   c. If the file is under `inbox/`, format as `[unread]`. If under `archive/`, lookup archive time via `git log -1 --format=%cI -- mailbox/archive/{file}` and format as `[read at {archive-commit-time}]`.
   d. Print:
      ```
      [unread] {timestamp} → {to}: {subject}  ({filename})
      [read at {archive-commit-time}] {timestamp} → {to}: {subject}  ({filename})
      ```
   e. Stop after 100 printed lines. If the list was truncated, append `(older entries omitted — 100-item cap)`.
3. If zero matches: `No mail sent by {agent_name}.`

### `/mailbox thread <thread_id>`

Reconstruct and print an entire threaded conversation in chronological order.

1. Enumerate `{repo}/mailbox/inbox/*.md` + `{repo}/mailbox/archive/*.md`.
2. For each file, read frontmatter. On parse failure, skip silently. Keep files whose `thread_id:` equals `{thread_id}`.
3. Sort the kept files by frontmatter `timestamp:` ascending.
4. Build a `reply_to` chain map: for each mail, its parent is the mail whose filename equals its `reply_to:` field (if any). Compute indent depth = chain length from root.
5. For each mail, print:
   ```
   {indent}{timestamp} {from} → {to} [{priority}]: {subject}
   {indent}  ({filename})
   {indent}  {body-first-line-or-80-chars}
   ```
   where `{indent}` is two spaces per depth level.
6. If zero matches: `No mail found in thread {thread_id}.`

### Wait-for-reply infrastructure

Shared procedure used by `auto_schedule_wakeup: true` at send time, by `/mailbox wait-for-reply`, and by the re-arm path in `/mailbox check --resume-wait`. Watcher files live at `{repo}/.ai-workspace/pending-replies/{slug}.json` (gitignored). One file per slug; filename IS the canonical slug.

**Schema:**
```json
{
  "slug": "example-slug",
  "waiter_agent": "forge-plan",
  "expected_sender": "swift-henry",
  "sent_at": "2026-04-13T12:45:00+08:00",
  "max_retries": 2,
  "retries_used": 0,
  "early_fire_absorptions": 0,
  "sla_seconds": 1500,
  "cron_id": "20e3f83e",
  "scheduling_mode": "cron-pinned"
}
```
`cron_id` MAY be `null` iff `scheduling_mode == "passive-year-boundary"`.

**Step 0 — Precondition:** `ToolSearch select:CronCreate,CronList,CronDelete` loaded. Else abort: `⚠ Cannot schedule wake-up: cron tools not loaded.`

**Step 1 — Compute `fire_at`:**
- Base: `fire_at = now + sla_seconds + 95`. The 95 s pad is **load-bearing** — the probe has observed one-shot jobs firing up to 90 s early; the pad guarantees that even an early fire lands past the true SLA deadline.
- Hint (non-load-bearing): round `fire_at` forward to the next minute whose minute field is neither `00` nor `30`. If that next minute also hits `00`/`30`, add one more minute. This reduces jitter observed on boundary minutes; correctness does not depend on it.

**Step 2 — Year-boundary check (passive fallback):**
- If `fire_at.year != now.year`, the cron 5-field expression cannot pin a year. Fall back to passive mode:
  - Do NOT call `CronCreate`.
  - Write the watcher file with `scheduling_mode: "passive-year-boundary"`, `cron_id: null`.
  - Print: `⚠ auto_schedule_wakeup cannot cross a year boundary with the current cron-expression mechanism. Reply watcher is passive — /mailbox check --resume-wait {slug} will still detect the reply on manual invocation, but no wake-up will fire.`
  - Skip steps 3–4.

**Step 3 — Two-phase write (cron first, watcher second):**
a. Call `CronCreate(cron="{M} {H} {DoM} {Mon} *", prompt="/mailbox check --resume-wait {slug}", recurring=false)`. Do NOT pass `durable: true` — the Phase 1 probe showed it is silently downgraded to session-only. Capture returned `cron_id`.
b. Only after `cron_id` is known, write `{repo}/.ai-workspace/pending-replies/{slug}.json` via atomic temp-then-rename (`{slug}.json.tmp` → `{slug}.json`) with the schema above.
c. If (a) fails: do not touch the pending-replies directory. Surface the error and abort.
d. If (b) fails after (a) succeeded: call `CronDelete(cron_id)` to remove the orphaned cron. If `CronDelete` also fails, log both errors and rely on `/mailbox check --resume-wait` step 1's "missing watcher → stale fire, warn and return" path to absorb the orphan on fire.

**Step 4 — Return** `cron_id` and `fire_at` to the caller.

### `/mailbox check --resume-wait <slug>`

Variant of `/mailbox check` invoked by the scheduled cron (or manually) to process a pending reply.

1. Read `{repo}/.ai-workspace/pending-replies/{slug}.json`. Missing → stale fire: `⚠ No pending-reply watcher for {slug} (already resolved or GC'd).` Return.
2. Run `/mailbox check` normally (pull, archive, commit). Collect the list of mails processed in this check.
3. **Reply detection — ALL three conditions required** for a processed mail to count as a reply to this watcher:
   - Mail's `from:` equals watcher's `expected_sender`, AND
   - Mail's `reply_to:` equals `{slug}` OR mail's `thread_id:` equals `{slug}`, AND
   - Mail's `timestamp:` is strictly after watcher's `sent_at`.
4. **Reply found:** delete the watcher file; call `CronDelete(cron_id)` if `cron_id != null` (no-op if already fired); print `Reply to {slug} received.` Done.
5. **No reply found — branch on timing:**
   - **(a) Early fire** (`now < sent_at + sla_seconds`): check `early_fire_absorptions`.
     - If `>= 3`: budget exhausted, fall through to path (b) below (charges a retry).
     - Otherwise: increment `early_fire_absorptions`; compute `remaining = (sent_at + sla_seconds) - now`; set `fire_at = now + max(remaining + 95, 120)`; apply step 1's `:00/:30` avoidance; re-issue `CronCreate` (recurring=false); update the watcher's `cron_id` and `early_fire_absorptions` via the two-phase write (cron first, then watcher update). On `CronCreate` failure, leave watcher as-is, surface error, and let the next `/mailbox check` GC path handle it. Log `early-fire absorbed ({early_fire_absorptions}/3)`. Return.
   - **(b) SLA elapsed** (`now >= sent_at + sla_seconds`): increment `retries_used`. If `retries_used >= max_retries`, delete watcher file and print `⚠ No reply to {slug} after {max_retries} attempts over ~{max_retries * sla_seconds}s. Escalating to human.` Else compute `fire_at = now + sla_seconds` (apply step 1 pad + rounding), re-issue `CronCreate`, update watcher via two-phase write.
6. Commit any archives normally per `/mailbox check` step 6.

**Garbage collection (runs on every `/mailbox check`, not just `--resume-wait`):** delete any watcher file whose `sent_at + (max_retries + 1 + 3) * sla_seconds + 3600s` is in the past. The `+3` term bounds the worst-case extension from early-fire absorptions (budget of 3). Passive-year-boundary watchers are GC'd by the same rule.

### `/mailbox wait-for-reply <slug> [--max-retries N] [--interval-seconds S]`

For agents who forgot `auto_schedule_wakeup: true` at send time, or want to add a watcher to a mail already sent.

1. Resolve `{slug}` to a file using the same double-anchored resolver as `/mailbox retract` (glob candidate pool + frontmatter exact-equality on canonical subject-slug). Search both `inbox/` and `archive/`. If zero / multiple, abort with disambiguation.
2. From the resolved mail's frontmatter: set `expected_sender = to:`, `sent_at = timestamp:`.
3. Parse CLI flags:
   - `--max-retries N`: clamp to `[1, 10]`. Default `2`.
   - `--interval-seconds S`: default to the effective `reply_sla_seconds` of the resolved mail (after priority-default resolution), or `1500` if the mail has none.
4. **Compute first `fire_at = now + interval_seconds`** — NOT `sent_at + interval_seconds`. The user may be invoking `wait-for-reply` late (past `sent_at + interval`); `sent_at`-based computation could produce a past timestamp, and past-timestamp one-shot semantics are undefined. `now + interval_seconds` guarantees a future fire time.
5. Run the "Wait-for-reply infrastructure" procedure from Step 1 onward with `sla_seconds = interval_seconds`, `max_retries = N`. The same 95 s pad + `:00/:30` avoidance + year-boundary fallback apply.
6. Print: `Watcher armed for {slug}. Wake-up at {fire_at_iso} (cron {cron_id}). Max retries: {N}.` Or the passive-mode banner from Step 2 of the infrastructure procedure.

### `/mailbox handoff to <agent-name>`

Write a structured handoff message for session-to-session work transfer.

1. Determine recipient (same as `/mailbox send`)
2. Compose a handoff message with structured fields:

   ```markdown
   ---
   from: {agent_name}
   from_project: {current project directory name}
   to: {recipient-name}
   to_project: {recipient project, if known, else "unknown"}
   subject: {brief description of handoff}
   type: handoff
   timestamp: {ISO-8601}
   status: unread
   handoff:
     repo: {repository name being worked on}
     branch: {current branch name}
     pr: {PR URL if one exists, else "none"}
     task_status: {completed | blocked | partial}
     what_done:
       - {completed item 1}
       - {completed item 2}
     what_left:
       - {remaining item 1}
       - {remaining item 2}
     files_changed:
       - {path/to/file1}
       - {path/to/file2}
     resume_plan: {path to plan file, if any, else "none"}
   ---

   {detailed prose context -- everything the receiving agent needs to continue the work}
   ```

3. Run Transport Mode Detection for the recipient (check `known_agents` cache first) and git operations (same as `/mailbox send` step 5)
4. Print: `Handoff sent to {to} ({mode}). They can run /mailbox check to pick up the work.`
   where `{mode}` is `local` or `git`.

## Important Rules

- Messages must be **self-contained**. The receiver has zero context from the sender's conversation. Include everything needed to understand and act on the message.
- Never read messages addressed to other agents (different `to:` field).
- **Git mode:** Always git push after send/check so remote sessions see changes. **Local mode:** Skip push — local sessions share the filesystem and see committed changes immediately.
- If the mailbox repo has uncommitted changes unrelated to mailbox, only stage mailbox files.
- If git push fails in git mode (e.g., needs pull first), run `git pull --rebase` then retry push.
- **Never persist agent names to memory.** Do not save your own or others' mailbox agent names to Claude Code memory files. Names are session-scoped — the registry is the sole persistence mechanism. Memory entries will become stale and mislead future sessions.

## Protocol Safety Rules

These rules prevent agents from reasoning about their own infrastructure from memory instead of querying it — the root cause of the 2026-04-13 T1320/T1430/T1445 retraction incident.

1. **One-shot crons only for wait-for-reply.** Every `CronCreate` used to wake a waiting agent must use `recurring: false` with a pinned future minute/hour/DoM/month. Never use `*/5` or any recurring pattern — recurring crons burn retry budget against the same deadline.
2. **Bounded retries.** After `max_retries` one-shot fires with no reply, escalate to a human. Never re-arm indefinitely.
3. **No heartbeats between co-located agents.** Agents sharing the same filesystem share a failure domain — a heartbeat between them proves nothing about the network and only adds noise.
4. **Verify polling before expecting a reply.** Before sending mail that expects a reply, run `/mailbox status` and confirm a `/mailbox check` cron is listed under Polling mechanics. If none exists, the reply latency is unbounded.
5. **Probe tools before claiming their behavior.** Before asserting anything about your own tools (cron semantics, tool-search behavior, scheduling windows), run `ToolSearch` to load the schema and invoke the tool itself. Do not reason from memorized schemas or prior-conversation state — tool surfaces change, and memory goes stale.

## Run Data Recording

After the mailbox operation completes (or errors out), persist run data. This section always runs.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"mailbox","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "success|no-action|error",
  "project": "{current working directory name}",
  "trigger": "/mailbox {subcommand}",
  "metrics": {
    "messagesSent": 0,
    "messagesRead": 0,
    "agentsRegistered": 0,
    "subcommandsUsed": ["{subcommand1}", "{subcommand2}"],
    "transportMode": "local|git",
    "executionPath": "cold|warm"
  },
  "issues": [],
  "summary": "{one-line: e.g., 'sent 1 message to brave-alice (git mode, warm)'}"
}
```

**Outcome values:**
- `success` — mailbox operation completed (message sent, messages read, status shown, handoff delivered)
- `no-action` — no messages to process or no action taken (e.g., `/mailbox check` with empty inbox)
- `error` — skill could not complete (mailbox repo not found, git failure, etc.)

Keep last 20 runs (older runs are permanently discarded). Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {agent} | {messagesSent}s/{messagesRead}r/{agentsRegistered}reg | {executionPath} | {summary}
```

Do not fail the skill if recording fails — log a warning and continue.
