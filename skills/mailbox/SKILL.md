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

## Discover Mailbox Repo

Before any mailbox operation, determine the mailbox repo path (`MAILBOX_REPO`).

**Important:** Always re-run this discovery on each `/mailbox` invocation. Do NOT cache or memorize the mailbox repo path from a previous call -- the configuration may have changed.

1. If env var `MAILBOX_REPO` is set, use it
2. Else if `~/.mailbox-repo` file exists, read its contents (an absolute path)
3. Else if `mailbox/inbox/` exists in the current project root, use the current project root
4. Else: **auto-bootstrap** a new mailbox repo:
   ```bash
   mkdir -p ~/claude-code-mailbox/mailbox/inbox ~/claude-code-mailbox/mailbox/archive
   cd ~/claude-code-mailbox && git init
   echo ".ai-workspace/.current-session-id" > .gitignore
   echo ".ai-workspace/sessions/" >> .gitignore
   git add -A && git commit -m "chore: initialize mailbox"
   echo "$(cd ~/claude-code-mailbox && pwd)" > ~/.mailbox-repo
   ```
   Set `MAILBOX_REPO` to `~/claude-code-mailbox` and continue. Print: "Created new mailbox at ~/claude-code-mailbox"

All paths below are relative to `{MAILBOX_REPO}`.

## Setup: Agent Name

On every `/mailbox` invocation, resolve the agent name using session-scoped identity:

### Step 1: Read session ID

1. If you already memorized a session ID earlier in this conversation, use it (skip to Step 2).
2. Otherwise, read `.ai-workspace/.current-session-id` from the **current project root** (not the mailbox repo).
   - The PreToolUse hook fires synchronously for THIS session, so the file is accurate right now.
   - Memorize this value: "My session ID is {id}" -- use it for ALL subsequent `/mailbox` calls in this conversation.
   - If the file does not exist, set session ID to `"default"`.
3. **Validate:** Check that `.ai-workspace/sessions/{session-id}` exists as a file in the current project root. If not, the ID may be stale (written by a different session) -- re-read `.current-session-id` and update your memorized value. If validation still fails, proceed with the current ID (the hook may not have created per-session files yet).

### Step 2: Read agent registry

Read `{MAILBOX_REPO}/.ai-workspace/.mailbox-agents.json`.
- If it exists, parse it as JSON: `{ "<session-id>": "<agent-name>", ... }`
- If it does not exist, start with an empty registry `{}`
- **Important:** Always read/write the registry from `{MAILBOX_REPO}`, never from the current project root (unless CWD *is* the mailbox repo). If `.ai-workspace/.mailbox-agents.json` exists in CWD but CWD ≠ MAILBOX_REPO, ignore it — it is stale.

### Step 3: Resolve name

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
7. Remember this name for the rest of the conversation

**Safety check:** When writing to the registry, ONLY write/update the key matching YOUR memorized session ID. Never modify entries for other session IDs.

### Registry maintenance

When writing to the registry, if it has more than 20 entries, keep only the 20 most recent
(by position in the JSON object -- newer entries are appended at the end).

Names are **persisted per-session** in the registry. This means:
- The name survives `/compact` and `--continue`/`--resume` (same session ID).
- Different sessions on the same project get **independent names**.
- To change your name, say "Your name is X".

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

Before each send/check/handoff operation, determine whether to use **local mode**
(skip git push/pull) or **git mode** (full push/pull cycle).

### For send / handoff operations

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

1. Run a lightweight remote check:
   ```
   cd {MAILBOX_REPO}
   DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}' || echo "main")
   git fetch origin "$DEFAULT_BRANCH" 2>/dev/null
   BEHIND=$(git rev-list "HEAD..origin/$DEFAULT_BRANCH" --count 2>/dev/null || echo "1")
   ```
2. **Pull step:** If BEHIND > 0 or the fetch failed → **git mode** (pull needed).
   If BEHIND = 0 → **local mode** (skip pull).
3. **Push step (after processing):** If any processed message's `from:` agent does NOT
   map to a recent local session (same reverse-lookup as send) → **git mode** (push needed).
   If all messages were from local agents, or no messages → **local mode** (skip push).

### Fallback

If any detection step fails (command errors, missing files, parse failures),
default to **git mode**. It is always safe to push/pull; it is never safe to
skip when uncertain.

## Subcommands

### `/mailbox send` or `/mailbox send to <agent-name>`

Write and deliver a message.

1. Resolve agent name (setup above)
2. Determine recipient:
   - If user specified `to <name>`: use that name
   - If user said "send to X": use X
   - Otherwise: ask "Who should this be addressed to?"
3. Determine message content:
   - If user provided content inline: use it
   - Otherwise: compose based on conversation context (what has been done, current state, what the receiver needs to know)
4. Write message file to `{MAILBOX_REPO}/mailbox/inbox/`:

   **Filename:** `{YYYY-MM-DDTHHMM}-{from}-to-{to}-{subject-slug}.md`

   **Format:**
   ```markdown
   ---
   from: {agent-name}
   from_project: {current project directory name}
   to: {recipient-name}
   to_project: {recipient project, if known, else "unknown"}
   subject: {brief subject line}
   timestamp: {ISO-8601}
   status: unread
   ---

   {message body -- self-contained, includes all context the receiver needs}
   ```

5. Run Transport Mode Detection (send). Then git operations in the mailbox repo:

   **Git mode:**
   ```
   cd {MAILBOX_REPO}
   DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
   git checkout "$DEFAULT_BRANCH"
   git pull --rebase
   git add mailbox/inbox/{filename}
   git commit -m "mailbox: {from} -> {to}: {subject}"
   git push
   ```

   **Local mode:**
   ```
   cd {MAILBOX_REPO}
   DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
   git checkout "$DEFAULT_BRANCH"
   git add mailbox/inbox/{filename}
   git commit -m "mailbox: {from} -> {to}: {subject}"
   ```

6. Print: `Message sent to {to} ({mode}). Tell that session to run /mailbox check.`
   where `{mode}` is `local` or `git`.

### `/mailbox check`

Read and archive incoming messages.

1. Resolve agent name (setup above)
2. Run Transport Mode Detection (check). Then ensure mailbox repo is on the default branch:

   **Git mode (upstream has changes):**
   ```
   cd {MAILBOX_REPO}
   DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
   git checkout "$DEFAULT_BRANCH"
   git pull --rebase
   ```

   **Local mode (no upstream changes):**
   ```
   cd {MAILBOX_REPO}
   DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
   git checkout "$DEFAULT_BRANCH"
   ```

3. List all files in `{MAILBOX_REPO}/mailbox/inbox/`
4. For each `.md` file, read the frontmatter:
   - If `to:` matches this agent's name OR `to: all`: this message is for us
   - If this is a Dispatch session: also match `to: dispatch`
   - Skip messages where `to:` doesn't match
5. For each matching message:
   a. Print the subject, sender, timestamp, and body
   b. If the message has a `type: handoff` field, also print all `handoff:` fields (repo, branch, pr, task_status, what_done, what_left, files_changed, resume_plan)
   c. Update `status: unread` to `status: read` in the file
   d. **Archive (REQUIRED):** `git mv mailbox/inbox/{file} mailbox/archive/{file}`
6. Git operations (always commit locally; push only in git mode):
   ```
   cd {MAILBOX_REPO}
   git add mailbox/
   git commit -m "mailbox: {agent-name} read {N} message(s)"
   ```
   **Git mode only** (any processed message was from a non-local agent):
   ```
   git push
   ```
7. **Verify archive:** Confirm no processed messages remain in `mailbox/inbox/` for this agent. If any do, run `git mv` now, then `git add mailbox/ && git commit -m "mailbox: archive missed files"`. Only run `git push` if in git mode.
8. If no messages found: print `No new messages for {agent-name}.`

### `/mailbox status`

Show agent identity and unread count.

1. Resolve agent name (setup above)
2. Count files in `{MAILBOX_REPO}/mailbox/inbox/` where `to:` matches this agent's name (and `dispatch`/`all` if applicable)
3. Print:
   ```
   Agent: {name}
   Project: {current project}
   Mailbox repo: {MAILBOX_REPO}
   Unread: {count} message(s)
   ```

### `/mailbox handoff to <agent-name>`

Write a structured handoff message for session-to-session work transfer.

1. Resolve agent name (setup above)
2. Determine recipient (same as `/mailbox send`)
3. Compose a handoff message with structured fields:

   ```markdown
   ---
   from: {agent-name}
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

4. Run Transport Mode Detection (send) and git operations (same as `/mailbox send` step 5)
5. Print: `Handoff sent to {to} ({mode}). They can run /mailbox check to pick up the work.`
   where `{mode}` is `local` or `git`.

## Important Rules

- Messages must be **self-contained**. The receiver has zero context from the sender's conversation. Include everything needed to understand and act on the message.
- Never read messages addressed to other agents (different `to:` field).
- **Git mode:** Always git push after send/check so remote sessions see changes. **Local mode:** Skip push — local sessions share the filesystem and see committed changes immediately.
- If the mailbox repo has uncommitted changes unrelated to mailbox, only stage mailbox files.
- If git push fails in git mode (e.g., needs pull first), run `git pull --rebase` then retry push.
- **Never persist agent names to memory.** Do not save your own or others' mailbox agent names to Claude Code memory files. Names are session-scoped — the registry is the sole persistence mechanism. Memory entries will become stale and mislead future sessions.

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
    "transportMode": "local|git"
  },
  "issues": [],
  "summary": "{one-line: e.g., 'sent 1 message to brave-alice (git mode)'}"
}
```

**Outcome values:**
- `success` — mailbox operation completed (message sent, messages read, status shown, handoff delivered)
- `no-action` — no messages to process or no action taken (e.g., `/mailbox check` with empty inbox)
- `error` — skill could not complete (mailbox repo not found, git failure, etc.)

Keep last 20 runs. Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {agent} | {messagesSent}s/{messagesRead}r/{agentsRegistered}reg | {summary}
```

Do not fail the skill if recording fails — log a warning and continue.
