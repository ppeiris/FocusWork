# FocusWork

## Why I built this

I wanted a few hours of real work without getting pulled sideways. I tried a lot of to-do apps, focus modes, and subscriptions always **too little** or **too much**, and almost always *their* idea of how to work, not how **my** head works. I had a clear picture of the app I needed but never a free month to build it properly, and I’d **never written Swift** before.

Over **Easter weekend** I started anyway. **FocusWork** is **for me first**: layout, flow, and what ships next follow my workdays, not a generic template. **Cursor**, **Composer**, and a bit of **vibe coding** (say what I want, iterate fast, let the tooling handle scaffolding) keep me out of boilerplate and out of someone else’s “productivity” box.

I’m having a blast growing it for myself. Software can bend to how you think—not the other way around—and maybe someday you’ll tell an agent how you work and get something that fits, without an App Store deciding what “counts.” I’m sharing it **open source** in case that resonates.

---

FocusWork is an open-source **macOS** app for structured focus: **projects**, **tasks** (estimates, priorities), and a **Pomodoro-style** timer with an optional **floating** timer panel. Optional integration with an **Obsidian** vault keeps projects as plain Markdown on disk. Built with **Swift** and **SwiftUI**.

## Features

- Projects and task lists with priorities and time estimates  
- Focus timer (Pomodoro-style) and floating timer UI  
- **Obsidian vault mode:** one `project_*.md` file per project under your vault, or **local-only** storage via UserDefaults  
- Documented vault format for tools and editors—see `docs/FocusWork-Obsidian-Vault-Spec.md`

## Requirements

- **macOS 14** or later (matches the Xcode deployment target)  
- **Xcode** with Swift 5  

## Build and run

Open `FocusWork.xcodeproj` in Xcode, select the **FocusWork** scheme, and run (⌘R).

From the terminal:

```bash
xcodebuild -project FocusWork.xcodeproj -scheme FocusWork -configuration Debug -destination 'platform=macOS' build
```

## Release DMG

The script builds a Release app, ad-hoc signs it, and writes `dist/FocusWork.dmg`:

```bash
./scripts/make-dmg.sh
```

## Where data lives

| Mode | Storage |
|------|---------|
| **Obsidian vault** (optional) | User selects a vault in **Settings**. One markdown file per project under `<Vault>/FocusWork/Projects/project_*.md`. |
| **Local only** | JSON in **UserDefaults** (`focuswork.projects`, `focuswork.tasks`). |

For the vault markdown format (headers, `#fw/…` task tags, filenames), see **`docs/FocusWork-Obsidian-Vault-Spec.md`**. When the app’s on-disk format changes, update that document to match **`TaskStore.swift`** and **`FocusTask.swift`**.

## Project layout

| Path | Role |
|------|------|
| `FocusWork/FocusWorkApp.swift`, `AppDelegate.swift` | App lifecycle |
| `FocusWork/AppModel.swift` | Shared app state |
| `FocusWork/Models/` | `FocusTask`, Pomodoro settings |
| `FocusWork/Services/` | `TaskStore`, `PomodoroEngine` |
| `FocusWork/Views/` | Main window, task list, settings, floating timer |
| `FocusWork/AppKit/` | Floating panel host |
| `docs/` | Vault format spec and related notes |

## Contributing

Contributions are welcome.

- For larger features or behavior changes, open an **issue** (or discuss in an existing one) before heavy implementation.  
- Keep **pull requests** focused; follow existing **Swift / SwiftUI** style and structure in the repo.  
- If you change how vault files are written or parsed, update **`docs/FocusWork-Obsidian-Vault-Spec.md`** so it stays accurate.

After you publish the repository, add your **clone URL** and **Issues** link near the top of this file (for example right under the title) so newcomers can find them quickly.

## Security

If you discover a security vulnerability, please report it **privately** (for example through GitHub **Security advisories** on the published repository) rather than filing a public issue, so it can be addressed before wider disclosure.

## License

FocusWork is released under the **[MIT License](LICENSE)**.
