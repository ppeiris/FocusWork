# FocusWork: Projects, Tasks, and Obsidian Vault Format

This document describes how **FocusWork** stores **projects** and **tasks** so that tools (including other LLM agents) can generate vault files that the app can load without manual repair.

It reflects the implementation in `FocusWork/Services/TaskStore.swift`, `FocusWork/Models/FocusTask.swift` (which also defines `FocusProject`), and related UI. Behavior may change in future app versions; when in doubt, verify against those sources.

---

## 1. Storage modes

| Mode | When it applies | Where data lives |
|------|-----------------|------------------|
| **Obsidian vault** | User picks a vault folder in Settings | Markdown under `<Vault>/FocusWork/Projects/` |
| **Local (no vault)** | No vault configured | `UserDefaults` as JSON (`focuswork.projects`, `focuswork.tasks`) |

**This spec focuses on the vault layout**, because that is what you typically generate as files on disk. The in-memory models (`FocusProject`, `FocusTask`) are the same either way.

---

## 2. Vault directory layout

Given an Obsidian vault root directory `<Vault>`:

```
<Vault>/
  FocusWork/
    Projects/
      project_<sanitized-name>.md
      project_<other>_<8-char-uuid-prefix>.md   # only if filename collision
```

- The app **creates** `FocusWork/Projects/` if missing.
- It loads **every** `*.md` file in `Projects/` whose name starts with `project_`.
- **Orphan** `project_*.md` files that no longer match any project after a save are **deleted** by the app.

**Legacy migration paths** (if present, the app migrates once and then writes per-project files):

- `<Vault>/FocusWork/Projects.md` — old multi-project markdown.
- `<Vault>/FocusWork/Tasks.md` — old flat task list.

Agents generating **new** content should use **only** the per-project `project_*.md` format below.

---

## 3. Project file naming

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

## 4. Project file structure (canonical)

Each project is one UTF-8 markdown file.

### 4.1 Header (metadata lines)

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

### 4.2 Project list ordering

Projects are sorted by `project_order` ascending; ties break by `createdAt` (in-memory; **not** stored in the vault header).

---

## 5. Tasks inside a project file

Tasks are **markdown checklist items**. The app recognizes:

1. **Canonical (recommended):** `- [ ]` or `- [x]` on the first line, then **indented** lines starting with `#fw/…` tags.
2. **Legacy single line:** checkbox + **pipe-separated** body.
3. **Minimal:** checkbox + plain title (no pipes, no `#fw` block).

### 5.1 Canonical task block (tag format)

**Shape:**

- Line 1: `- [ ] ` or `- [x] ` (trailing space optional after bracket; body on this line should be **empty** for this format).
- Following lines: each begins with **at least one** space or tab, then `#fw/<key> <value>`.

**Whitespace:** The parser requires **leading** indent on tag lines so they are treated as task metadata (not top-level content).

**Keys** (the parser stores keys **without** the leading `#`, e.g. `fw/priority`):

| Tag line | Required | Value |
|----------|----------|--------|
| `#fw/priority` | Recommended | `urgent` \| `next` \| `later` (invalid → `later`) |
| `#fw/id` | Strongly recommended | Task UUID string |
| `#fw/title` | Strongly recommended | One-line title (newlines collapsed to spaces by the app on write) |
| `#fw/est-min` | Optional | Positive integer = estimate in **minutes**; omit or invalid → no estimate |
| `#fw/work-rem-sec` | Optional | Positive integer = **paused** work countdown remaining (seconds). Omit if none. |
| `#fw/total-focus-sec` | Recommended | Non-negative integer = cumulative **focused** seconds logged |
| `#fw/completed` | Recommended | `1`, `true`, or `yes` (case-insensitive) vs `0`/other |

**Checkbox vs completed:** If the markdown checkbox is `- [x]`, the task is treated as completed regardless of `#fw/completed`. The app may still write both for consistency.

**Example (incomplete task, 30 min estimate, no paused segment):**

```markdown
- [ ] 
  #fw/priority later
  #fw/id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
  #fw/title Write the spec
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
  #fw/est-min 45
  #fw/work-rem-sec 900
  #fw/total-focus-sec 1800
  #fw/completed 0

```

### 5.2 Task order

Tasks are loaded in **file order** (top to bottom). When the app saves, it writes tasks for that project in its internal `tasks` array order for that `projectId` (the UI keeps order in sync via reorder operations).

**For agents:** Emit tasks in the desired list order.

### 5.3 Legacy pipe format (still loaded)

Single line after checkbox:

```text
- [ ] <priority> | <task-uuid> | <title> | <est_min> | <work_rem_sec> | <total_focus_sec> | <completed>
```

- **Minimum:** 3 fields: `priority | id | title`
- **Optional 4–7:** estimate minutes, work remaining seconds, total focused seconds, completed (`1`/`true`/`yes`)
- Title may use `\|` for literal pipes.
- If the body contains `|`, the parser uses **pipe mode** for that line only (no multi-line `#fw` block).

### 5.4 Title-only line

```markdown
- [ ] Just a title without pipes
```

→ Task with that title, default priority `later`, **new** UUID generated if not using tag format (pipe/tag formats preserve IDs).

---

## 6. Semantic field reference (`FocusTask`)

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
| `createdAt` | `Date` | **Not** stored in vault markdown; on load from vault, defaults to “now” in the initializer path used for parsed tasks. |

---

## 7. UUID generation checklist

- Use **standard UUID strings** (RFC 4122 style) for `project_id` and each `fw/id`.
- Prefer **lowercase** hex with hyphens; the app uses `UUID(uuidString:)`.
- **Never** duplicate a task `id` inside the same project file if you want two distinct tasks.
- Reusing the same `project_id` across two different `project_*.md` files would create inconsistent state; use **one file per project** with a **unique** `project_id`.

---

## 8. What the app does when it saves

- Rewrites each `project_*.md` from in-memory state (normalized project order, sanitized filenames, tag format for tasks).
- Removes stray `project_*.md` files that are no longer in the project list.
- Continues to store **selected project** and **active task** IDs in `UserDefaults` (`focuswork.selectedProjectId`, `focuswork.activeTaskId`) even in vault mode.

Agents should assume **the next app save may reformat** files (whitespace, tag lines, optional comment).

---

## 9. Full minimal example file

```markdown
# FocusWork Project
project_name: Sample Project
project_id: 11111111-2222-3333-4444-555555555555
project_color: green
project_order: 0

<!-- Optional: human-readable hint only -->
<!-- Tasks: - [ ] / - [x] then indented #fw/... lines -->

- [ ] 
  #fw/priority later
  #fw/id aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
  #fw/title First task
  #fw/est-min 25
  #fw/total-focus-sec 0
  #fw/completed 0

- [x] 
  #fw/priority next
  #fw/id bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
  #fw/title Done task
  #fw/est-min 15
  #fw/total-focus-sec 900
  #fw/completed 1

```

---

## 10. LLM agent checklist (quick)

1. Create `<Vault>/FocusWork/Projects/` if needed.
2. For each project, write **one** `project_<sanitized_name>.md`.
3. Include `project_name`, `project_id` (UUID), and optionally `project_color`, `project_order`.
4. Append tasks as `- [ ] ` / `- [x] ` with **indented** `#fw/priority`, `#fw/id`, `#fw/title`, `#fw/total-focus-sec`, `#fw/completed`; add `#fw/est-min` / `#fw/work-rem-sec` when needed.
5. Use **valid UUIDs**; keep task order = desired list order.
6. UTF-8 encoding; avoid raw newlines inside `#fw/title` (collapse to spaces).
7. Do not duplicate `project_id` across files.

---

## 11. Related app concepts (not all in vault text)

- **Active task** and **Pomodoro** state are mostly runtime; vault persists task fields that affect countdown (`estimatedMinutes`, `savedWorkRemainingSeconds`, `totalFocusedSeconds`, `isCompleted`).
- **Task list UI order** for a project is tied to the `tasks` array order for that `projectId` when saving; keep file order consistent with that expectation.

---

*Generated to match FocusWork codebase behavior; verify against `TaskStore` if upgrading the app.*
