---
name: menubar-monitor
status: done
created: 2026-02-07T16:44:24Z
updated: 2026-02-08T11:48:09Z
progress: 100%
task_count: 8
tasks_done: 8
prd: .claude/prds/menubar-monitor.md
github: https://github.com/wuwe1/piq/issues/1
---

# Epic: menubar-monitor

## 概述

使用 Swift 6 + SwiftUI 构建一个原生 macOS menubar 应用（PIQ），通过 FSEvents 监控本地 `.claude/` 目录的文件变化，实时解析 frontmatter 中的 `type`/`status`/`task_count`/`tasks_done` 字段，在菜单栏中展示多个项目的 PRD、Epic、Task 状态和进度，并持久化活动历史用于用时分析。

## 架构决策

- **MenuBarExtra `.window` 模式**：使用 SwiftUI 原生 MenuBarExtra 的 window 模式，获得完全自定义的 popover UI（进度条、展开列表、活动时间线），而非受限的 `.menu` 模式
- **自定义 frontmatter 解析器**：我们的 frontmatter 格式简单固定（`key: value` 行），自己写解析器避免引入 Yams 等第三方依赖，减少包体积和维护负担
- **FSEvents 而非轮询**：macOS 原生文件系统事件 API，延迟低（< 1s）且几乎零 CPU 占用，比定时轮询高效
- **JSON 持久化**：项目配置存储到 `~/.piq/projects.json`，活动历史存储到 `~/.piq/activity.json`，使用 Swift Codable 直接序列化，无需数据库
- **@Observable 状态管理**：使用 Swift 5.9+ 的 @Observable macro 管理全局状态（AppState），驱动 SwiftUI 视图自动更新
- **零第三方依赖**：整个项目不引入任何 SPM 包，全部用标准库和系统框架实现

## 技术方法

### 数据层
- **FrontmatterParser**：逐行解析 `---` 之间的内容，支持 string、int、bool、array 值类型；通过 `type` 字段分发到 PRDItem / EpicItem / TaskItem
- **ProjectScanner**：扫描项目 `.claude/prds/*.md` 和 `.claude/epics/*/epic.md` + `*.md`（task 文件）；调用 `git worktree list` 发现关联 worktree
- **一致性校验**：对每个 epic，扫描其目录下所有 `type: task` 文件统计 `status == done` 的数量，与 epic frontmatter 的 `tasks_done` 对比
- **ActivityStore**：维护内存中的状态快照，文件变更时对比新旧 status 生成 ActivityEvent，追加写入 `~/.piq/activity.json`

### UI 层
- **PIQApp**：MenuBarExtra(.window) 入口，像素风图标
- **MenuBarView**：主面板，包含项目列表、活动时间线、设置入口
- **ProjectCardView**：单个项目摘要卡片（PRD/Epic/Task 统计 + 进度条），含 worktree 子节点
- **ProjectDetailView**：展开后显示 PRD 列表、Epic 列表（含进度）、Task 列表、一致性警告
- **ActivityFeedView**：最近活动事件的时间线
- **StatsView**：用时统计面板（task 耗时、epic 耗时、吞吐量）
- **SettingsView**：扫描根目录管理、手动项目管理、通知配置、数据管理

### 系统集成
- **FSEvents / FileWatcher**：使用 `DispatchSource.makeFileSystemObjectSource` 或 FSEvents C API 监控目录变化，500ms debounce
- **UserNotifications**：状态变更时推送系统通知（里程碑、完成、异常）
- **NSWorkspace / Process**：打开文件（默认编辑器）、打开终端、打开浏览器（GitHub 链接）
- **Login Items**：ServiceManagement 框架实现开机自启
- **NSPasteboard**：复制命令到剪贴板

## 实施策略

PRD 定义了 4 个 Phase，我们将其映射为 8 个技术任务，按依赖顺序排列：

1. **Xcode 项目 + App 骨架**（Phase 1 基础）
2. **数据模型 + Frontmatter 解析器**（Phase 1 核心，其他一切的基础）
3. **ProjectScanner + 项目发现**（Phase 1，依赖解析器）
4. **状态面板 UI**（Phase 1，依赖 Scanner 提供数据）
5. **FSEvents 实时监控**（Phase 2，依赖 Scanner）
6. **活动历史 + 统计**（Phase 2，依赖 FSEvents 产生事件）
7. **快捷操作 + 终端集成**（Phase 3，依赖 UI）
8. **通知 + 设置 + 打磨**（Phase 4，依赖以上全部）

风险缓解：
- frontmatter 格式不规范 → 解析器容错设计，跳过无法解析的文件
- FSEvents 丢事件 → 定时全量重扫（每 5 分钟）作为兜底
- 大量文件变更 → debounce + 增量解析，避免 UI 卡顿

## 任务分解预览

- [ ] Task 1: Xcode 项目初始化与 MenuBarExtra 骨架
- [ ] Task 2: 数据模型与自定义 Frontmatter 解析器
- [ ] Task 3: ProjectScanner、项目发现与一致性校验
- [ ] Task 4: 状态面板 UI（项目卡片 + 详情 + 活动时间线）
- [ ] Task 5: FSEvents 实时文件监控
- [ ] Task 6: 活动历史持久化与用时统计
- [ ] Task 7: 快捷操作与终端集成
- [ ] Task 8: 通知系统、设置界面与最终打磨

## 依赖项

- **外部依赖**: 无（零第三方库）
- **系统框架**: SwiftUI, Foundation, AppKit, UserNotifications, ServiceManagement
- **工具**: Xcode 16+, Swift 6, macOS 14+ SDK
- **数据约定**: PM 系统的 frontmatter 规范（`type`/`status`/`task_count`/`tasks_done` 字段）

## 成功标准（技术）

- 自定义解析器能正确解析所有三种 frontmatter 类型（prd/epic/task），覆盖异常格式
- FSEvents 延迟 < 1 秒，debounce 后 UI 平滑刷新
- 10 个项目同时监控时内存 < 50MB，CPU 空闲 < 1%
- 活动历史持久化后 App 重启可完整恢复
- 一致性校验能检测 `tasks_done` 与实际不符并在 UI 标记

## 估计工作量

- **总任务数**: 8 个
- **核心路径**: Task 1 → 2 → 3 → 4 → 5（线性依赖）
- **可并行**: Task 6 可与 Task 5 并行；Task 7 可与 Task 6 并行
- **关键路径**: 前 5 个任务构成 MVP

## 已创建的任务

- [x] #2 - Xcode 项目初始化与 MenuBarExtra 骨架 (parallel: false)
- [x] #3 - 数据模型与自定义 Frontmatter 解析器 (parallel: false, depends: #2)
- [x] #5 - ProjectScanner、项目发现与一致性校验 (parallel: false, depends: #3)
- [x] #7 - 状态面板 UI (parallel: false, depends: #5)
- [x] #4 - FSEvents 实时文件监控 (parallel: true, depends: #5)
- [x] #6 - 活动历史持久化与用时统计 (parallel: true, depends: #4)
- [x] #8 - 快捷操作与终端集成 (parallel: true, depends: #7)
- [x] #9 - 通知系统、设置界面与最终打磨 (parallel: false, depends: #7,#4,#6,#8)

总任务数：8
并行任务数：3（#4, #6, #8）
顺序任务数：5（#2, #3, #5, #7, #9）
估计总工作量：37-51 小时

### 依赖关系图

```
#2 → #3 → #5 ─┬→ #7 ─┬→ #8 ─┐
               │      │      │
               └→ #4 → #6 ──┼→ #9
                             │
                      #8 ────┘
```
