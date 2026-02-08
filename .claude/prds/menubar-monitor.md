---
name: menubar-monitor
description: macOS menubar app for real-time PM project status monitoring
status: done
created: 2026-02-07T15:49:38Z
updated: 2026-02-08T11:48:09Z
---

# PIQ - Project Intelligence & Quality Monitor

## 概述

一个原生 macOS menubar 应用，通过监控 `.claude/` 目录下的文件变化，实时追踪基于 PM（Claude Code PM）约定的项目管理状态。消除手动运行 `/pm:status`、`/pm:epic-list`、`/pm:next` 等命令的需求，将项目状态一目了然地呈现在菜单栏中。

## 问题

当前使用 PM 系统管理项目时，开发者需要：
1. 频繁手动运行 `/pm:status`、`/pm:standup` 等命令查看项目全貌
2. 需要进入 Claude Code 会话才能获取状态信息
3. 无法感知文件变化（如 Teams 中其他 agent 的并行工作）带来的状态更新
4. 跨多个项目时需要在不同目录间切换查看

## 目标用户

使用 PM（Claude Code PM）系统管理项目的开发者，特别是：
- 同时管理多个项目的开发者
- 使用 Claude Code Agent Teams 并行开发的团队
- 需要随时掌握项目进度的项目管理者

## 技术栈

- **语言**: Swift 6
- **UI 框架**: SwiftUI（MenuBarExtra `.window` 模式）
- **最低支持**: macOS 14 (Sonoma)
- **文件监控**: FSEvents / `DispatchSource.makeFileSystemObjectSource`
- **数据解析**: 自定义 YAML frontmatter 解析器（不引入第三方依赖）
- **数据持久化**: JSON 文件（项目配置 + 活动历史）
- **构建工具**: Xcode / Swift Package Manager
- **图标风格**: 像素风（Pixel Art）
- **分发**: 直接构建或 Homebrew Cask

## Frontmatter 规范

所有 frontmatter 字段使用严格的枚举值和一致的命名，便于 FSEvent 监听器实时解析。每个文件通过 `type` 字段标识类型，通过 `status` 字段标识状态。

### PRD Frontmatter

```yaml
---
type: prd                              # 固定值，标识文件类型
name: feature-name                     # kebab-case，同文件名
description: "一行中文简述"              # 双引号包裹
status: backlog | in-progress | done   # 三态枚举
created: 2026-02-07T12:00:00Z         # ISO 8601 UTC
---
```

### Epic Frontmatter

```yaml
---
type: epic                             # 固定值
name: feature-name                     # 同 PRD name
status: backlog | in-progress | done   # 三态枚举
created: 2026-02-07T12:00:00Z         # ISO 8601 UTC
prd: .claude/prds/feature-name.md     # PRD 相对路径
github: ""                             # sync 后填充 Issue URL
task_count: 0                          # 任务总数（decompose 后更新）
tasks_done: 0                          # 已完成任务数
---
```

### Task Frontmatter

```yaml
---
type: task                             # 固定值
name: "任务标题中文"                     # 双引号包裹
status: open | in-progress | done      # 三态枚举
created: 2026-02-07T12:00:00Z         # ISO 8601 UTC
github: ""                             # sync 后填充 Issue URL
---
```

### FSEvent 监控要点

- **监听路径**: `.claude/prds/` 和 `.claude/epics/` 的文件创建/修改事件
- **解析策略**: 检测到文件变更时，读取 frontmatter 的 `type` 字段区分文件类型，然后读取 `status` 字段
- **进度计算**: Epic 的 `task_count` 和 `tasks_done` 字段可直接算百分比（`tasks_done / task_count * 100`）
- **一致性校验**: PIQ 同时扫描 epic 目录下的 task 文件统计实际完成数，与 `tasks_done` 比对；不一致时在 UI 上标记警告（说明工作中的 agent 可能出了问题）
- **状态枚举**: 所有文件统一使用 `backlog/open → in-progress → done` 三态流转
- **type 字段**: 每个文件都有 `type` 字段（`prd` / `epic` / `task`），便于分类

### 状态枚举汇总

| type | 初始状态 | 进行中 | 完成 |
|------|---------|--------|------|
| prd  | backlog | in-progress | done |
| epic | backlog | in-progress | done |
| task | open    | in-progress | done |

## 核心功能

### F1: 项目管理

**自动发现（主要方式）**
- 用户在设置中配置一个或多个扫描根目录（如 `~/Developer`）
- PIQ 定期扫描根目录下所有子目录，发现含 `.claude/prds/` 或 `.claude/epics/` 的项目
- 新项目出现时自动纳入监控，无需手动操作
- 项目目录被删除时自动从列表中移除（或标记为不可用）
- 扫描频率：启动时全量扫描 + FSEvents 监控根目录变化

**手动添加（补充方式）**
- 设置中点击 "+" 按钮，通过系统文件选择器添加不在扫描根目录下的项目
- 支持拖拽文件夹到 menubar 图标添加
- 添加时自动校验是否包含 `.claude/` 结构，不包含则提示
- 手动添加的项目不受自动扫描的增删影响

**项目列表管理**
- 自动发现 + 手动添加的项目统一展示
- 可临时隐藏/取消隐藏项目（不删除，只是不显示）
- 项目列表持久化存储到 `~/.piq/projects.json`
- menubar 下拉菜单中按项目分组展示

**Worktree 识别**
- 同一 git 仓库的 worktree 识别为同一项目的子目录
- 层级展示：主仓库为父节点，worktree 为子节点
- 通过 `git worktree list` 自动发现关联的 worktree

### F2: 实时文件监控

**FSEvents 监控**
- 监控每个项目（含 worktree）的 `.claude/prds/`、`.claude/epics/` 目录
- 文件创建、修改、删除事件触发状态刷新
- 防抖处理（debounce 500ms），避免频繁刷新
- 低资源占用，不影响系统性能

**解析引擎**
- 自定义 frontmatter 解析器：解析 `---` 之间的 `key: value` 行，不依赖第三方 YAML 库
- 通过 `type` 字段判断文件类型（prd / epic / task）
- 通过 `status` 字段获取当前状态
- Epic 进度通过 `tasks_done / task_count` 直接计算
- 一致性校验：扫描 task 文件实际状态，与 epic 的 `tasks_done` 比对，不一致时标记警告
- 支持增量解析（仅重新解析变化的文件）

### F3: 状态面板

**Menubar 图标**（像素风）
- 默认图标：项目状态正常时显示静态像素图标
- 状态指示：有活跃 in-progress 项目时显示像素动画或彩色点
- 数字徽章（可选）：显示当前 in-progress task 数量

**下拉面板（MenuBarExtra `.window` 模式）**

```
┌─────────────────────────────────────┐
│  PIQ - Project Monitor              │
├─────────────────────────────────────┤
│  📂 project-alpha                 ▼ │
│  ┌─────────────────────────────────┐│
│  │ PRDs     2 in-progress / 5     ││
│  │ Epics    1 in-progress / 3     ││
│  │ Tasks    3 open / 8 done       ││
│  │ Progress ████████░░ 6/8        ││
│  └─────────────────────────────────┘│
│    └─ 🌿 worktree: epic-auth       │
│                                     │
│  📂 project-beta                  ▼ │
│  ┌─────────────────────────────────┐│
│  │ PRDs     1 backlog / 2         ││
│  │ Epics    0 in-progress         ││
│  │ Tasks    — (no epics)          ││
│  │ Progress idle                  ││
│  └─────────────────────────────────┘│
├─────────────────────────────────────┤
│  Recent Activity                    │
│  • 5m ago  Task #42 → in-progress  │
│  • 1h ago  Epic auth  4/6 done     │
│  • 3h ago  PRD payments created    │
├─────────────────────────────────────┤
│  ⚙️ Settings    📋 Copy Status      │
└─────────────────────────────────────┘
```

**展开详情视图**

点击项目名称展开：
- **PRD 列表**: 名称 + 状态标签（backlog / in-progress / done）
- **Epic 列表**: 名称 + 进度条 + `tasks_done/task_count` + 状态
- **Task 列表**: 编号 + 名称 + 状态
- **一致性警告**: 如果 epic 的 `tasks_done` 与实际 task 文件统计不一致，显示 ⚠️ 标记
- **GitHub 链接**: 已同步的 Epic/Task 显示 GitHub Issue 链接

### F4: 快捷操作

**文件操作**
- 点击 PRD/Epic/Task 名称 → 在默认编辑器中打开对应 `.md` 文件
- 右键菜单 → "在 Finder 中显示"
- 右键菜单 → "复制文件路径"

**命令复制**
- 点击 Epic → 复制 `/pm:epic-show {name}` 命令到剪贴板
- 点击 Task → 复制 `/pm:issue-start {number}` 命令
- 点击项目 → 复制 `cd {path}` 命令

**GitHub 跳转**
- 如果 frontmatter 中 `github` 字段非空 → 点击直接在浏览器中打开 GitHub Issue
- 显示 GitHub 同步状态（`github` 字段是否已填充）

**终端集成**
- 点击项目 → 在默认终端中打开项目目录
- 快捷按钮 → 打开 Claude Code 到该项目

### F5: 活动历史与统计

**活动时间线**
- 检测 status 字段变更，生成事件记录（对比内存中的旧状态快照）
- 事件格式：`{timestamp, project, itemType, itemName, oldStatus, newStatus}`
- 持久化到磁盘：`~/.piq/activity.json`（按日期分文件或单文件滚动）
- App 重启后保留历史，可回溯查看

**用时统计**
- 基于活动历史计算：每个 task 从 `open → in-progress` 到 `in-progress → done` 的耗时
- Epic 总耗时：从第一个 task 开始到所有 task 完成
- 项目级统计：活跃天数、平均 task 完成时间、吞吐量趋势
- 在设置或详情视图中展示简单的统计面板

### F6: 通知系统

**状态变更通知**（通过 macOS UserNotifications）
- Epic 进度达到里程碑（25%、50%、75%、100%，基于 `tasks_done/task_count`）
- Task 状态变更（open → in-progress → done）
- 新 PRD 创建（检测到新的 `type: prd` 文件）
- Epic 完成（`status` 变为 `done`）
- 一致性异常（epic `tasks_done` 与实际不符）

**通知配置**
- 全局开关：启用/禁用通知
- 按项目配置：哪些项目发送通知
- 按事件类型配置：哪些事件触发通知
- 免打扰模式：特定时间段静默

### F7: 设置

**通用设置**
- 开机自启动（Login Items）
- menubar 图标样式选择
- 刷新间隔（文件轮询备选方案）
- 语言切换（中/英）

**项目设置**
- 扫描根目录管理（添加/移除自动发现的根目录）
- 手动添加的项目管理
- 项目隐藏/显示切换
- 每个项目的监控范围配置

**通知设置**
- 通知偏好配置（如 F6 所述）

**数据管理**
- 活动历史存储路径配置
- 历史数据保留天数
- 导出活动历史（JSON / CSV）

## 数据模型

### 状态枚举

```swift
/// 统一的三态流转
enum ItemStatus: String, Codable {
    case backlog        // PRD/Epic 初始态
    case open           // Task 初始态
    case inProgress = "in-progress"
    case done
}

/// 文件类型标识
enum ItemType: String, Codable {
    case prd
    case epic
    case task
}
```

### Project

```swift
struct Project: Identifiable, Codable {
    let id: UUID
    var name: String
    var path: URL                    // 项目根目录
    var isActive: Bool
    var lastScanned: Date
    var worktrees: [Worktree]       // 关联的 worktree 列表
    var prds: [PRDItem]
    var epics: [EpicItem]
}

struct Worktree: Identifiable, Codable {
    let id: UUID
    var name: String                 // worktree 名称（如 epic-auth）
    var path: URL                    // worktree 根目录
    var branch: String               // 分支名
}
```

### PRDItem

```swift
struct PRDItem: Identifiable, Codable {
    let id: String                   // frontmatter name
    var description: String
    var status: ItemStatus           // backlog → in-progress → done
    var created: Date
    var filePath: String             // 相对路径
}
```

### EpicItem

```swift
struct EpicItem: Identifiable, Codable {
    let id: String                   // frontmatter name
    var status: ItemStatus           // backlog → in-progress → done
    var prdRef: String               // PRD 相对路径
    var githubURL: String            // 空字符串 = 未同步
    var taskCount: Int               // frontmatter task_count
    var tasksDone: Int               // frontmatter tasks_done
    var actualTasksDone: Int         // PIQ 扫描 task 文件得出的实际完成数
    var tasks: [TaskItem]
    var created: Date
    var directoryPath: String        // 相对路径
}

extension EpicItem {
    /// 进度百分比
    var progressPercent: Int {
        guard taskCount > 0 else { return 0 }
        return Int(Double(tasksDone) / Double(taskCount) * 100)
    }

    /// frontmatter 与实际 task 文件是否一致
    var isConsistent: Bool {
        tasksDone == actualTasksDone
    }
}
```

### TaskItem

```swift
struct TaskItem: Identifiable, Codable {
    let id: String                   // 文件名（编号或 issue number）
    var name: String
    var status: ItemStatus           // open → in-progress → done
    var githubURL: String            // 空字符串 = 未同步
    var created: Date
    var filePath: String             // 相对路径
}
```

### ActivityEvent（活动历史）

```swift
struct ActivityEvent: Identifiable, Codable {
    let id: UUID
    var timestamp: Date
    var projectName: String
    var itemType: ItemType           // prd / epic / task
    var itemName: String
    var oldStatus: ItemStatus?       // nil = 新建事件
    var newStatus: ItemStatus
    var filePath: String
}
```

## 非功能需求

### 性能
- 启动时间 < 2 秒
- 文件变化到 UI 更新延迟 < 1 秒
- 内存占用 < 50MB（10 个项目）
- CPU 空闲时占用 < 1%

### 安全
- 仅读取本地文件系统，不发送任何数据到外部
- 使用最小权限，仅访问用户添加的项目目录
- 文件路径不暴露到日志或错误报告中

### 可靠性
- 项目目录被删除/移动时优雅降级
- frontmatter 缺少 `type` 字段或格式异常时跳过该文件，不崩溃
- 支持 `.claude/` 目录结构不完整的项目（如只有 prds 没有 epics）
- 活动历史文件损坏时自动重建（从当前文件状态重新扫描）

## 项目结构

```
piq/
├── PIQ/                              # Xcode 项目
│   ├── App/
│   │   ├── PIQApp.swift              # App 入口，MenuBarExtra(.window)
│   │   └── AppState.swift            # 全局状态管理（@Observable）
│   ├── Models/
│   │   ├── Project.swift             # 含 Worktree 定义
│   │   ├── PRDItem.swift
│   │   ├── EpicItem.swift
│   │   ├── TaskItem.swift
│   │   ├── ItemStatus.swift          # 统一枚举定义
│   │   └── ActivityEvent.swift       # 活动事件
│   ├── Services/
│   │   ├── FileWatcher.swift         # FSEvents 文件监控
│   │   ├── FrontmatterParser.swift   # 自定义 frontmatter 解析（无第三方依赖）
│   │   ├── ProjectScanner.swift      # 项目扫描、worktree 发现、一致性校验
│   │   ├── ActivityStore.swift       # 活动历史持久化和统计
│   │   └── NotificationService.swift # 通知管理
│   ├── Views/
│   │   ├── MenuBarView.swift         # 主下拉面板
│   │   ├── ProjectCardView.swift     # 单个项目卡片（含 worktree 子节点）
│   │   ├── ProjectDetailView.swift   # 项目展开详情
│   │   ├── ActivityFeedView.swift    # 最近活动时间线
│   │   ├── StatsView.swift           # 用时统计面板
│   │   └── SettingsView.swift        # 设置界面
│   ├── Utilities/
│   │   └── Extensions.swift
│   └── Resources/
│       └── Assets.xcassets           # 像素风图标资源
├── PIQTests/                         # 单元测试
│   ├── FrontmatterParserTests.swift  # 解析器测试（核心）
│   ├── ProjectScannerTests.swift
│   └── ActivityStoreTests.swift
├── Package.swift                     # SPM（无第三方依赖）
└── README.md
```

## 实现阶段

### Phase 1: 核心基础 (MVP)
- [ ] SwiftUI MenuBarExtra(.window) 应用骨架
- [ ] 设置界面：扫描根目录配置 + 手动添加项目
- [ ] 自动发现：扫描根目录下含 `.claude/` 的项目
- [ ] 自定义 FrontmatterParser：解析 `---` 之间的 key-value，基于 `type` 字段分发
- [ ] ProjectScanner：扫描 `.claude/prds/` 和 `.claude/epics/` 目录
- [ ] 项目列表持久化到 `~/.piq/projects.json`
- [ ] 基本下拉面板 UI（项目卡片 + 状态摘要）
- [ ] Epic 一致性校验（`tasks_done` vs 实际 task 文件统计）

### Phase 2: 实时监控 & 活动历史
- [ ] FSEvents 文件监控集成
- [ ] 增量解析（仅处理变化的文件）
- [ ] 防抖处理（500ms debounce）
- [ ] 状态变更检测（内存快照对比）
- [ ] ActivityStore：活动事件持久化到 `~/.piq/activity.json`
- [ ] 活动时间线 UI

### Phase 3: 多项目 & 交互
- [ ] 多项目管理（添加/移除/切换）
- [ ] Worktree 发现和层级展示
- [ ] 快捷操作（打开文件、复制命令、GitHub 跳转）
- [ ] 展开详情视图（PRD/Epic/Task 列表 + 一致性警告）
- [ ] 终端集成

### Phase 4: 统计、通知 & 打磨
- [ ] 用时统计：task 耗时、epic 耗时、项目吞吐量
- [ ] StatsView 统计面板
- [ ] macOS UserNotifications 集成
- [ ] 设置界面（通用 + 项目 + 通知 + 数据管理）
- [ ] 开机自启动（Login Items）
- [ ] 像素风图标设计和 UI 打磨
- [ ] 性能调优和边界测试

## 成功标准

1. 不打开 Claude Code 就能看到所有项目的 PRD/Epic/Task 状态
2. 文件变化后 1 秒内 menubar 状态自动更新
3. Epic 进度通过 `tasks_done/task_count` 精确展示，不一致时有警告
4. 支持同时监控 5+ 个项目（含 worktree），内存 < 50MB
5. 一键跳转到 GitHub Issue 或打开本地文件
6. 活动历史持久化，可回溯分析项目开发节奏

## 已确认的设计决策

| 决策项 | 结论 |
|-------|------|
| Worktree 处理 | 识别为同一项目，层级展示（主仓库→worktree 子节点） |
| iOS/iPadOS | 后续再考虑 |
| 图标风格 | 像素风（Pixel Art） |
| blocked/depends_on | 移除，任务协调由 Agent Teams 自行决定 |
| Frontmatter 解析 | 自己写，不引入 Yams 等第三方依赖 |
| 活动历史 | 持久化到磁盘，支持用时分析和统计 |
| task_count 校验 | 信任 frontmatter 值，同时扫描验证，不一致时 UI 标记警告 |
| UI 模式 | MenuBarExtra `.window` 模式（自定义 popover） |
| 项目管理系统名称 | PM（原 CCPM，已重构精简） |
| 项目添加方式 | 自动发现（扫描根目录）为主 + 手动添加为辅 |
| 首次启动 | 无引导流程，直接进入空状态，用户自行去设置配置 |
| 并行协作模型 | Claude Code Agent Teams（非 subagent） |
