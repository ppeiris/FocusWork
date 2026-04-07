# FocusWork: Projects, Tasks, and Obsidian Vault Format

This document describes how **FocusWork** stores **projects** and **tasks** so that tools (including other LLM agents) can generate vault files that the app can load without manual repair.

It reflects the implementation in `FocusWork/Services/TaskStore.swift`, `FocusWork/Services/FocusWorkLocalDatabase.swift`, `FocusWork/Models/FocusTask.swift` (which also defines `FocusProject`), and related UI. Behavior may change in future app versions; when in doubt, verify against those sources.

---

## 1. Storage modes

| Mode | When it applies | Where data lives |
|------|-----------------|------------------|
| **Obsidian vault** | User picks a vault folder in Settings | Markdown under `<Vault>/FocusWork/Projects/` (see §3). Vault **path** is stored in the app’s local database (§2), not in the vault itself. |
| **Local (no vault)** | No vault configured | `UserDefaults` as JSON (`focuswork.projects`, `focuswork.tasks`) |

**This spec focuses on the vault layout**, because that is what you typically generate as files on disk. The in-memory models (`FocusProject`, `FocusTask`) are the same either way.

**Other app state (not in vault files):** Selected project ID, active task ID, task list order per project, and Pomodoro UI settings still use `UserDefaults` (and in-memory structures) even when a vault is configured.

---

## 2. App local database (macOS)

The app keeps a **small JSON file** under the user’s Application Support directory so each install (and each **bundle identifier**) has its own vault binding. This replaces the older practice of storing only the vault path in `UserDefaults` (`focuswork.obsidian.vaultPath`); on first launch, that key is **migrated** into the file and removed.

**Paths:**

- **Container:** `~/Library/Application Support/<bundle-id>/FocusWork/`
- **File:** `LocalDatabase.json`

**Bundle identifier:** Release builds use `com.focuswork.FocusWork`; Debug builds use `com.focuswork.FocusWork.debug`, so **development and production data stay separate**.

**Payload (versioned):** `schemaVersion`, `vaults[]`, `activeVaultId`. Each vault record includes:

| Field | Meaning |
|-------|---------|
| `vaultRootPath` | Absolute path to the Obsidian vault root (the folder you open in Obsidian). |
| `projectsFolderRelativePath` | Default `FocusWork/Projects` — path segments from vault root to the folder containing `project_*.md`. |

The UI currently links **one** vault per install; the JSON shape allows multiple records later.

---

## 3. Vault directory layout

Given an Obsidian vault root directory `<Vault>`:

```
<Vault>/
  FocusWork/
    Projects/
      project_<sanitized-name>.md
      project_<other>_<8-char-uuid-prefix>.md   # only if filename collision
```

- The app **creates** `FocusWork/Projects/` if missing (unless `projectsFolderRelativePath` in the local database is customized—default matches the layout above).
- It loads **every** `*.md` file in `Projects/` whose name starts with `project_`.
- **Orphan** `project_*.md` files that no longer match any project after a save are **deleted** by the app.

**Legacy migration paths** (if present, the app migrates once and then writes per-project files):

- `<Vault>/FocusWork/Projects.md` — old multi-project markdown.
- `<Vault>/FocusWork/Tasks.md` — old flat task list.

Agents generating **new** content should use **only** the per-project `project_*.md` format below.

---

## 4. Project file naming

- **Pattern:** `project_<sanitizedProjectName>.md`
- **Sanitization** (must match app behavior):
  1. Trim whitespace.
  2. Replace spaces with `_`.
  3. Keep only alphanumeric, `_`, and `-`; map every other character to `_`.
  4. Trim leading/trailing `_`; if empty, use `project`.

**Examples:**

| Display name   | Typical filename        |
|----------------|-------------------------|
| `My Project`   | `project_My_Project.md` |
| `Nadia!!`      | `project_Nadia__.md`    (non-alphanumerics → `_`) |

**Collisions:** If two projects sanitize to the same base name, the app uses:

`project_<base>_<first 8 chars of project UUID>.md`

To avoid collisions when hand-authoring, give projects distinct sanitized names or reuse the exact filename the app would emit once you know the UUID.

---

## 5. Project file structure (canonical)

Each project is one UTF-8 markdown file.

### 5.1 Header (metadata lines)

After an optional title line, the app reads **key: value** lines at the top (trimmed). Unknown lines are skipped until task checkboxes start.

| Line prefix        | Required | Meaning |
|--------------------|----------|---------|
| `project_name:`    | Strongly recommended | Human-readable project name. Pipe characters `\|` in the name must be escaped as `\|` (same as legacy encoding). |
| `project_id:`      | Strongly recommended | `UUID` string (e.g. `550E8400-E29B-41D4-A716-446655440000`). If missing, a **new** UUID is assigned at load and tasks are bound to it. |
| `project_color:`   | Optional | One of: `gray`, `blue`, `green`, `orange`, `pink`. Invalid or missing → `gray`. |
| `project_order:`   | Optional | Integer sort order (lower = earlier in the project list). |

**Recommended opening block:**

```markdown
# FocusWork Project
project_name: My Project Name
project_id: 12345678-1234-1234-1234-123456789abc
project_color: blue
project_order: 0

```

The app also writes an HTML comment describing task format; it is **ignored** on parse. You may omit it or include a similar hint.

### 5.2 Project list ordering

Projects are sorted by `project_order` ascending; ties break by `createdAt` (in-memory; **not** stored in the vault header).

---

## 6. Tasks inside a project file

Tasks are **markdown checklist items**. The app recognizes:

1. **Canonical (recommended):** `- [ ]` or `- [x]` on the first line, then **indented** lines starting with `#fw/…` tags, optionally followed by a **fenced notes block** (§6.1).
2. **Legacy single line:** checkbox + **pipe-separated** body.
3. **Minimal:** checkbox + plain title (no pipes, no `#fw` block).

### 6.1 Canonical task block (tag format)

**Shape:**

- Line 1: `- [ ] ` or `- [x] ` (trailing space optional after bracket; body on this line should be **empty** for this format).
- Following lines: each begins with **at least one** space or tab, then `#fw/<key> <value>`.
- **Optional — multi-line notes:** Immediately after the `#fw/…` lines for that task, a **fenced code block**: opening line = optional indent + *N* grave accents (N ≥ 3) + literal suffix `fw-task-note` (no space before the suffix); closing line = same indent + *N* grave accents only. If the note body contains long runs of grave accents, use a larger N. Each body line is typically written with a two-space indent; the app strips that when loading.

**Whitespace:** The parser requires **leading** indent on tag lines so they are treated as task metadata (not top-level content).

**Keys** (the parser stores keys **without** the leading `#`, e.g. `fw/priority`):

| Tag line | Required | Value |
|----------|----------|--------|
| `#fw/priority` | Recommended | `urgent` \| `next` \| `later` (invalid → `later`) |
| `#fw/id` | Strongly recommended | Task UUID string |
| `#fw/title` | Strongly recommended | One-line title (newlines collapsed to spaces by the app on write) |
| `#fw/created-at` | Recommended | **ISO 8601** instant when the task was added (e.g. `2026-04-07T15:30:45.000Z` or without fractional seconds). Omit on hand-edited vaults → app uses **import time** for that load until the file is saved again, then the written value is kept. |
| `#fw/est-min` | Optional | Positive integer = estimate in **minutes**; omit or invalid → no estimate |
| `#fw/work-rem-sec` | Optional | Positive integer = **paused** work countdown remaining (seconds). Omit if none. |
| `#fw/total-focus-sec` | Recommended | Non-negative integer = cumulative **focused** seconds logged |
| `#fw/completed` | Recommended | `1`, `true`, or `yes` (case-insensitive) vs `0`/other |
| `#fw/notes` | Optional | **Single-line** notes with escapes: `\n` = newline, `\\` = backslash, `\r` = carriage return. If a **fenced** notes block follows the tags, its content **replaces** whatever was in `#fw/notes` after parse. |

**Checkbox vs completed:** If the markdown checkbox is `- [x]`, the task is treated as completed regardless of `#fw/completed`. The app may still write both for consistency.

**Notes and UI:** Task notes are shown in the main task list editor only; they are **not** shown in the floating timer panel.

**Example (incomplete task, 30 min estimate, no paused segment):**

```markdown
- [ ] 
  #fw/priority later
  #fw/id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
  #fw/title Write the spec
  #fw/created-at 2026-04-07T10:00:00.000Z
  #fw/est-min 30
  #fw/total-focus-sec 0
  #fw/completed 0

```

**Example (completed, with logged time):**

```markdown
- [x] 
  #fw/priority next
  #fw/id bbbbbbbb-cccc-dddd-eeee-ffffffffffff
  #fw/title Ship release
  #fw/created-at 2026-04-06T18:20:00Z
  #fw/est-min 120
  #fw/total-focus-sec 7320
  #fw/completed 1

```

**Example (paused mid-session — 900 seconds left on the work timer):**

```markdown
- [ ] 
  #fw/priority urgent
  #fw/id cccccccc-dddd-eeee-ffff-000000000000
  #fw/title Deep work block
  #fw/created-at 2026-04-07T08:15:30.000Z
  #fw/est-min 45
  #fw/work-rem-sec 900
  #fw/total-focus-sec 1800
  #fw/completed 0

```

**Example (task with multi-line notes — fence length may be longer if the note contains backticks):** The opening fence is two spaces, then *N* backticks (N ≥ 3), then `fw-task-note` with no space; the closing line is two spaces plus *N* backticks only.

````text
- [ ] 
  #fw/priority later
  #fw/id dddddddd-eeee-ffff-0000-111111111111
  #fw/title Task with context
  #fw/created-at 2026-04-05T12:00:00Z
  #fw/total-focus-sec 0
  #fw/completed 0
  ```fw-task-note
  Line one of notes
  Line two
  ```
````

### 6.2 Task order

Tasks are loaded in **file order** (top to bottom). When the app saves, it writes tasks in **list order** for that project (the same order as the main UI, derived from internal ordering and `tasksOrderedInProject`). **For agents:** Emit tasks in the desired list order.

### 6.3 Legacy pipe format (still loaded)

Single line after checkbox:

```text
- [ ] <priority> | <task-uuid> | <title> | <est_min> | <work_rem_sec> | <total_focus_sec> | <completed>
```

- **Minimum:** 3 fields: `priority | id | title`
- **Optional 4–7:** estimate minutes, work remaining seconds, total focused seconds, completed (`1`/`true`/`yes`)
- Title may use `\|` for literal pipes.
- If the body contains `|`, the parser uses **pipe mode** for that line only (no multi-line `#fw` block). **Notes** are not represented in pipe format (`notes` loads as empty).

### 6.4 Title-only line

```markdown
- [ ] Just a title without pipes
```

→ Task with that title, default priority `later`, **new** UUID generated if not using tag format (pipe/tag formats preserve IDs). **Notes** empty.

---

## 7. Semantic field reference (`FocusTask`)

| Field | Type | Vault / notes |
|-------|------|----------------|
| `id` | `UUID` | Must be stable across edits if you want updates to target the same task. |
| `title` | `String` | |
| `priority` | `urgent` / `next` / `later` | |
| `projectId` | `UUID?` | Set from the **project file’s** `project_id` when parsing that file. |
| `estimatedMinutes` | `Int?` | Minutes; only positive values count. |
| `savedWorkRemainingSeconds` | `Int?` | Seconds remaining on **work** segment when paused; `nil` = not resuming a saved segment. |
| `totalFocusedSeconds` | `Int` | Cumulative logged focus time. |
| `isCompleted` | `Bool` | |
| `notes` | `String` | Multi-line free text. In vault: fenced `fw-task-note` block after `#fw` tags, and/or optional escaped `#fw/notes` line. Not shown in the floating timer. |
| `createdAt` | `Date` | Vault: `#fw/created-at` as **ISO 8601** (UTC recommended). The main task list shows **added** and a localized date next to the time stats. If the tag is **missing**, the app uses the **time of parse** for that session; the next **save** writes a stable `#fw/created-at` line. JSON / `UserDefaults` mode stores `createdAt` in encoded task JSON. |

---

## 8. UUID generation checklist

- Use **standard UUID strings** (RFC 4122 style) for `project_id` and each `fw/id`.
- Prefer **lowercase** hex with hyphens; the app uses `UUID(uuidString:)`.
- **Never** duplicate a task `id` inside the same project file if you want two distinct tasks.
- Reusing the same `project_id` across two different `project_*.md` files would create inconsistent state; use **one file per project** with a **unique** `project_id`.

---

## 9. What the app does when it saves

- Rewrites each `project_*.md` from in-memory state (normalized project order, sanitized filenames, tag format for tasks), including `#fw/created-at` for each task when saving.
- Writes **non-empty** `notes` as a fenced `fw-task-note` block after the `#fw` lines; opening/closing fence length is chosen so typical note text containing backticks does not break the block.
- Removes stray `project_*.md` files that are no longer in the project list.
- Continues to store **selected project** and **active task** IDs in `UserDefaults` (`focuswork.selectedProjectId`, `focuswork.activeTaskId`) even in vault mode.
- **Vault root path** is persisted in `LocalDatabase.json` (§2), not in `UserDefaults`.

Agents should assume **the next app save may reformat** files (whitespace, tag lines, optional comment, notes fence).

---

## 10. Full minimal example file

```markdown
# FocusWork Project
project_name: Sample Project
project_id: 11111111-2222-3333-4444-555555555555
project_color: green
project_order: 0

<!-- Optional: human-readable hint only -->
<!-- Tasks: checkbox + indented #fw lines; optional fenced fw-task-note block for multi-line notes -->

- [ ] 
  #fw/priority later
  #fw/id aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
  #fw/title First task
  #fw/created-at 2026-04-07T09:00:00.000Z
  #fw/est-min 25
  #fw/total-focus-sec 0
  #fw/completed 0

- [x] 
  #fw/priority next
  #fw/id bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
  #fw/title Done task
  #fw/created-at 2026-04-01T14:00:00Z
  #fw/est-min 15
  #fw/total-focus-sec 900
  #fw/completed 1

```

---

## 11. LLM agent checklist (quick)

1. Create `<Vault>/FocusWork/Projects/` if needed (or the path configured in the app’s vault record—default is this layout).
2. For each project, write **one** `project_<sanitized_name>.md`.
3. Include `project_name`, `project_id` (UUID), and optionally `project_color`, `project_order`.
4. Append tasks as `- [ ] ` / `- [x] ` with **indented** `#fw/priority`, `#fw/id`, `#fw/title`, `#fw/created-at` (ISO 8601), `#fw/total-focus-sec`, `#fw/completed`; add `#fw/est-min` / `#fw/work-rem-sec` when needed.
5. For **multi-line notes**, after the task’s `#fw` lines add an opening line (indented) of *N* backticks (N ≥ 3) + `fw-task-note`, then note lines, then a closing line of *N* backticks only (same N). Alternatively use one `#fw/notes` line with `\n` / `\\` escapes.
6. Use **valid UUIDs**; keep task order = desired list order.
7. UTF-8 encoding; avoid raw newlines inside `#fw/title` (collapse to spaces).
8. Do not duplicate `project_id` across files.

---

## 12. Related app concepts (not all in vault text)

- **Active task** and **Pomodoro** state are mostly runtime; vault persists task fields that affect countdown (`estimatedMinutes`, `savedWorkRemainingSeconds`, `totalFocusedSeconds`, `isCompleted`), **`createdAt`** (`#fw/created-at`), plus **notes** body text.
- **Task list UI order** for a project is kept consistent with saved markdown order via the app’s internal ordering when writing.
- **Floating timer** intentionally does **not** display task `notes` (title and timing only).

---

*Generated to match FocusWork codebase behavior; verify against `TaskStore` and `FocusWorkLocalDatabase` if upgrading the app.*
