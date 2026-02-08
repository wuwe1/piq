---
name: draggable-projects
description: "项目卡片支持拖拽排序，自定义项目列表顺序"
status: backlog
created: 2026-02-08T11:59:14Z
---

# PRD: draggable-projects

## 执行摘要

为 PIQ menubar 的项目列表添加拖拽排序功能，让用户可以通过拖拽项目卡片来自定义展示顺序。排序结果持久化到配置文件，在重新扫描和应用重启后保持不变。

## 问题陈述

当前项目列表的顺序由扫描结果决定（文件系统枚举顺序），用户无法控制。当监控多个项目时，用户希望把最重要/最常用的项目放在列表顶部，减少查找时间。

## 用户故事

### 作为 PIQ 用户，我希望：

1. **拖拽排序** — 长按并拖动项目卡片到目标位置，松手后卡片就位
   - 验收标准：拖拽过程中有视觉反馈（卡片半透明 + 插入指示线）
   - 验收标准：松手后卡片立即就位，无闪烁

2. **顺序持久化** — 我自定义的顺序在刷新/重启后保持不变
   - 验收标准：关闭并重新打开 popover，顺序不变
   - 验收标准：点击 Refresh 按钮触发 rescanAll() 后，顺序不变
   - 验收标准：退出并重启 PIQ，顺序不变

3. **新项目处理** — 新发现的项目自动追加到列表末尾
   - 验收标准：添加新 scan root 后发现的项目出现在列表底部
   - 验收标准：已删除的项目从排序列表中自动清除

## 需求

### 功能需求

1. **拖拽交互**
   - 在 `projectList` 的 `ForEach` 上启用 `.draggable` 和 `.dropDestination`（或 `onMove`）
   - 拖拽时显示半透明预览
   - 目标位置显示插入指示线
   - 支持在 ScrollView 内拖拽滚动

2. **排序持久化**
   - 在 `ProjectConfig` 中添加 `projectOrder: [String]` 字段（存储 rootPath 字符串列表）
   - `rescanAll()` 后根据 `projectOrder` 对 `projects` 数组重新排序
   - 新发现的项目（不在 `projectOrder` 中的）追加到末尾
   - 已删除的项目（路径不再存在的）从 `projectOrder` 中自动清除

3. **排序逻辑**
   - `AppState` 中添加 `reorderProjects()` 方法
   - `rescanAll()` 末尾调用 `reorderProjects()`
   - 拖拽完成后立即调用 `saveProjectConfig()` 持久化

### 非功能需求

- **性能**：拖拽操作无卡顿，排序为 O(n) 操作
- **兼容性**：macOS 14+ (Sonoma)，与现有 MenuBarExtra window 模式兼容
- **数据安全**：`projectOrder` 为空或损坏时，回退到默认扫描顺序

## 技术方案

### 方案：SwiftUI `onMove` + ForEach Binding

```swift
// MenuBarView.swift - projectList
ForEach(appState.projects) { project in
    ProjectCardView(project: project)
}
.onMove { source, destination in
    appState.moveProjects(from: source, to: destination)
}

// AppState.swift
func moveProjects(from source: IndexSet, to destination: Int) {
    projects.move(fromOffsets: source, toOffset: destination)
    projectConfig.projectOrder = projects.map { $0.rootPath.path(percentEncoded: false) }
    saveProjectConfig()
}
```

### 数据模型变更

```swift
// ProjectConfig.swift
struct ProjectConfig: Codable, Sendable {
    var scanRoots: [URL]
    var manualProjects: [ProjectEntry]
    var discoveredProjects: [ProjectEntry]
    var projectOrder: [String]  // 新增：rootPath 字符串列表
}
```

### 排序逻辑

```swift
// AppState.swift
func reorderProjects() {
    let order = projectConfig.projectOrder
    guard !order.isEmpty else { return }

    let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    projects.sort { a, b in
        let aIndex = orderMap[a.rootPath.path(percentEncoded: false)] ?? Int.max
        let bIndex = orderMap[b.rootPath.path(percentEncoded: false)] ?? Int.max
        return aIndex < bIndex
    }
}
```

## 成功标准

- 拖拽排序操作流畅，无视觉卡顿
- 排序在 rescanAll()、popover 重开、应用重启后保持
- 新项目自动追加到末尾
- 不影响现有功能（展开状态、快捷操作、上下文菜单）

## 约束与假设

- 假设项目数量 < 50，无需虚拟化列表
- 依赖 SwiftUI 原生拖拽 API，不使用 AppKit 拖拽
- `projectOrder` 存储在现有 `~/.piq/projects.json` 中

## 范围之外

- 项目分组/文件夹功能
- 按名称/进度等自动排序选项
- 跨多个 scan root 的拖拽合并
- 键盘快捷键排序（上/下箭头）

## 依赖项

- 依赖 menubar-monitor epic 已完成的基础架构
- `ProjectConfig` 的 Codable 自定义编解码需同步更新
- `AppState.rescanAll()` 需在末尾追加排序调用

## 估计工作量

- 规模：S
- 任务数：1（单任务即可完成）
- 涉及文件：4 个（ProjectConfig.swift, AppState.swift, MenuBarView.swift, ProjectStore.swift）
