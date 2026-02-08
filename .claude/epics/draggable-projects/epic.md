---
name: draggable-projects
status: backlog
created: 2026-02-08T12:00:25Z
updated: 2026-02-08T12:03:36Z
progress: 0%
task_count: 1
tasks_done: 0
prd: .claude/prds/draggable-projects.md
github: https://github.com/wuwe1/piq/issues/11
---

# Epic: draggable-projects

## 概述

为 PIQ menubar 项目列表添加拖拽排序功能。在 `ProjectConfig` 中新增 `projectOrder` 字段持久化顺序，在 `MenuBarView` 的 `ForEach` 上添加 `onMove` 支持，`rescanAll()` 后按保存的顺序排列项目。

## 架构决策

- **SwiftUI 原生 `onMove`**：使用 `ForEach` + `onMove` modifier，这是 SwiftUI 内置的列表重排方案，无需手写拖拽逻辑。需要将 `ScrollView` + `LazyVStack` 替换为 `List` 以获得原生 `onMove` 支持，或使用 `draggable`/`dropDestination` API 在自定义布局中实现
- **路径字符串排序键**：使用 `rootPath.path(percentEncoded: false)` 作为排序键，与 `expandedProjectPaths` 保持一致的 key 策略
- **就地排序**：`reorderProjects()` 在 `projects` 数组上直接排序，不创建新数组，保持引用稳定

## 技术方法

### 数据模型变更
- `ProjectConfig.swift`：添加 `var projectOrder: [String] = []` 字段
- 更新自定义 `init(from:)` 和 `encode(to:)` 处理新字段
- `CodingKeys` 枚举添加 `projectOrder` case

### 状态管理
- `AppState.swift`：添加 `moveProjects(from:to:)` 方法处理拖拽回调
- `AppState.swift`：添加 `reorderProjects()` 方法，在 `rescanAll()` 末尾调用
- `reorderProjects()` 逻辑：根据 `projectConfig.projectOrder` 排序，未知项目追加末尾

### UI 变更
- `MenuBarView.swift`：在 `ForEach` 上添加拖拽支持
- 方案 A（优先）：使用 `List` + `onMove`，自定义 `listStyle` 匹配当前外观
- 方案 B（备选）：保持 `ScrollView` + `LazyVStack`，使用 `.draggable` + `.dropDestination` 手动实现

## 实施策略

单任务实现，按文件逐个修改：
1. `ProjectConfig.swift` — 添加 `projectOrder` 字段 + Codable 更新
2. `AppState.swift` — 添加 `moveProjects` + `reorderProjects` 方法
3. `MenuBarView.swift` — 添加 `onMove` 或拖拽支持
4. 手动测试：拖拽排序 → 刷新 → 重启，验证持久化

风险缓解：
- `MenuBarExtra(.window)` 中 `List` 的 `onMove` 可能不工作 → 备选方案 B
- `projectOrder` 为空时静默跳过排序，不影响现有行为

## 任务分解预览

## 已创建的任务

- [ ] #12 - 实现项目拖拽排序与顺序持久化 (parallel: false)

总任务数：1
并行任务数：0
顺序任务数：1
估计总工作量：1-2 小时

## 依赖项

- menubar-monitor epic 已完成（基础架构就绪）
- `ProjectConfig` 的自定义 Codable 需同步更新

## 成功标准（技术）

- 拖拽操作流畅，无 UI 卡顿
- `projects.json` 中正确保存 `projectOrder` 数组
- `rescanAll()` 后顺序保持不变
- 新项目追加到列表末尾
- `projectOrder` 为空时回退到扫描顺序
- 不破坏现有展开状态、快捷操作、上下文菜单

## 估计工作量

- 总任务数：1
- 涉及文件：3-4 个
- 规模：S（约 1-2 小时）
