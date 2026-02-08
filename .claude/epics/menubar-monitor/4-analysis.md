---
issue: 4
title: "FSEvents 实时文件监控"
analyzed: 2026-02-08T04:40:08Z
estimated_hours: 5
parallelization_factor: 2.0
---

# Parallel Work Analysis: Issue #4

## Overview
实现 FileWatcher 服务，使用 macOS FSEvents API 监控项目目录中的 `.claude/prds/` 和 `.claude/epics/` 变更。核心功能包括：FSEvents 流管理、500ms debounce、增量解析、5 分钟全量重扫兜底，以及与 AppState 的集成。

## 依赖前置
- Issue #5（ProjectScanner）尚未完成，FileWatcher 需要 ProjectScanner 提供项目路径列表和 `rescan()` 能力
- **策略**：定义 FileWatcher 需要的 ProjectScanner 接口协议，先实现 FileWatcher 核心逻辑，集成点使用协议抽象

## Parallel Streams

### Stream A: FSEvents 核心引擎
**Scope**: FileWatcher 核心类——FSEvents 流创建/启动/停止、路径注册/注销、事件回调分发
**Files**:
- `PIQ/Services/FileWatcher.swift`
**Agent Type**: general-purpose
**Can Start**: immediately
**Estimated Hours**: 3
**Dependencies**: none

关键实现点：
- `FSEventStreamCreate` + `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes`
- 路径动态增删（stop → recreate stream → start）
- 事件回调通过 `@MainActor` 分发到 AppState
- 500ms debounce：`DispatchWorkItem` cancel/reschedule 模式
- 5 分钟 `Timer` 全量重扫兜底
- `Sendable` 合规（Swift 6 strict concurrency）

### Stream B: 单元测试
**Scope**: FileWatcher 的可测试性设计和测试用例
**Files**:
- `PIQTests/FileWatcherTests.swift`
**Agent Type**: general-purpose
**Can Start**: after Stream A completes
**Estimated Hours**: 2
**Dependencies**: Stream A

测试覆盖：
- 路径注册/注销
- debounce 行为（多事件合并）
- 事件过滤（只处理 .md 文件）
- 增量解析触发逻辑
- 全量重扫定时器
- 错误处理（无效路径、权限不足）

## Coordination Points

### Shared Files
- `PIQ/App/AppState.swift` — Stream A 需要扩展 AppState 添加 FileWatcher 集成点
- `PIQ.xcodeproj/project.pbxproj` — 两个 stream 都需要注册新文件

### Sequential Requirements
1. Stream A 完成 FileWatcher 核心实现
2. Stream B 编写测试（依赖 Stream A 的接口定义）
3. 最后统一更新 pbxproj 和 AppState 集成

### 与 Issue #5 的接口契约
FileWatcher 需要以下能力（由 ProjectScanner 或协议提供）：
```swift
protocol ProjectScannerProtocol {
    func scanProject(at url: URL) async -> Project?
    func rescanAll() async -> [Project]
}
```
FileWatcher 通过此协议触发增量/全量解析，不直接依赖具体实现。

## Conflict Risk Assessment
- **Low Risk**: FileWatcher 是全新文件，不与现有代码冲突
- **Medium Risk**: AppState 扩展需要与后续 issue 协调
- **注意**: 需确保 FSEvents C API 的 Swift 6 concurrency 安全包装

## Parallelization Strategy

**Recommended Approach**: sequential（Stream A → Stream B）

由于 Stream B（测试）强依赖 Stream A（实现），实际执行为顺序。但 Stream A 内部的 FSEvents 引擎和 debounce 逻辑可以视为子任务并行设计。

## Expected Timeline

With sequential execution:
- Wall time: 5 hours
- Total work: 5 hours

实际上由于 #5 未完成，建议：
1. 先完成 #5（ProjectScanner）
2. 再实现 #4（FileWatcher），此时可以直接集成而非使用协议抽象

## Notes
- FSEvents C API 需要 `import CoreServices`
- `FSEventStreamCreate` 的回调是 C function pointer，需要 `@convention(c)` 桥接
- Swift 6 strict concurrency 下，FSEvents 回调需要通过 `DispatchQueue.main.async` 或 `@MainActor` 安全分发
- debounce 实现建议用 `Task.sleep` + actor 隔离，而非 `DispatchWorkItem`，更符合 Swift 6 风格
- 考虑使用 `AsyncStream` 包装 FSEvents 回调，提供更现代的 API
