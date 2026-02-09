# PIQ

macOS menubar app that monitors `.claude/` project directories in real time.

Built for developers using [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with the PM workflow — track PRDs, Epics, and Tasks without leaving your editor.

## Features

- **Auto-discovery** — Configure scan roots (e.g. `~/Developer`), PIQ finds all projects with `.claude/` directories
- **Real-time monitoring** — FSEvents watches for file changes, UI updates within seconds
- **Status at a glance** — See PRD/Epic/Task counts and status badges per project
- **Activity feed** — Track status changes across all projects with relative timestamps
- **Statistics** — Task completion charts, average duration, daily throughput
- **Consistency checks** — Warns when epic `tasks_done` doesn't match actual task file counts
- **Git worktree support** — Detects and displays active worktrees per project
- **Notifications** — macOS notifications for task completions, epic milestones, and new PRDs
- **Quick actions** — Open files, copy paths, jump to GitHub Issues

## Screenshots

```
┌─────────────────────────────────────┐
│  👀 PIQ                  2 projects │
├─────────────────────────────────────┤
│  📂 my-project                      │
│  PRDs  1 done        Tasks  6/8     │
│  Epics 1 in-progress                │
│  ████████████░░░░ 75%               │
│                                     │
│  📂 another-project                 │
│  PRDs  1 backlog     Tasks  —       │
│  Epics 0                            │
├─────────────────────────────────────┤
│  ↻ Refresh              ⚙ Settings │
└─────────────────────────────────────┘
```

## Install

Download the latest DMG from [Releases](https://github.com/wuwe1/piq/releases), open it, and drag PIQ to Applications.

Signed with Developer ID and notarized by Apple — opens without Gatekeeper warnings.

### Requirements

- macOS 15.0 (Sequoia) or later

## How it works

PIQ reads YAML frontmatter from markdown files in `.claude/` directories:

```
your-project/
└── .claude/
    ├── prds/
    │   └── feature-name.md        # type: prd, status: backlog|in-progress|done
    └── epics/
        └── feature-name/
            ├── epic.md            # type: epic, task_count, tasks_done
            ├── 001.md             # type: task, status: open|in-progress|done
            └── 002.md
```

Configure a scan root in Settings, and PIQ automatically discovers and monitors all projects underneath.

## Build from source

```bash
git clone https://github.com/wuwe1/piq.git
cd piq
xcodebuild build -project PIQ.xcodeproj -scheme PIQ -configuration Debug
```

Run tests:

```bash
xcodebuild test -project PIQ.xcodeproj -scheme PIQ -destination 'platform=macOS'
```

## Tech stack

- Swift 6 with strict concurrency
- SwiftUI (`MenuBarExtra` with `.window` style)
- FSEvents for file watching
- Custom frontmatter parser (zero dependencies)
- JSON persistence for config and activity history

## License

MIT
