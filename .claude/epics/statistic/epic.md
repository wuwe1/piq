---
name: statistic
status: done
created: 2026-02-08T14:43:37Z
updated: 2026-02-09T03:39:16Z
progress: 100%
task_count: 2
tasks_done: 2
prd: .claude/prds/statistic.md
github: https://github.com/wuwe1/piq/issues/13
---

# Epic: statistic

## 概述

为 PIQ menubar 添加统计面板，包含项目进度总览、7 天 task 完成趋势图（Swift Charts）和活动历史时间线。数据全部来自已有的 `ActivityStore` 和 `Project` 模型，无需新增持久化层。通过 MenuBarView 的视图切换在项目列表和统计面板之间导航。

## 架构决策

- **Swift Charts**：使用 macOS 14+ 内置的 Charts framework 绘制趋势图，零第三方依赖
- **视图切换而非新窗口**：统计面板在现有 MenuBarExtra window 内通过 `@State var showStats` 切换显示，保持单窗口体验
- **ActivityStore 扩展**：仅需添加 `tasksCompletedPerDay(lastDays:)` 一个新方法，其余数据直接从现有 API 和 Project 模型计算
- **内联计算**：统计数据量小（< 1000 events），直接在视图中计算，不需要后台线程或缓存

## 技术方法

### 新增文件（2 个）

#### 1. `PIQ/Views/StatsView.swift` — 统计面板主视图
三个 Section 纵向排列在 ScrollView 中：

**Summary Section（进度总览）**
- 全局统计行：总 task 数 / 已完成 / 完成率
- 每个项目一行：名称 + ProgressBarView + 百分比
- Epic 状态分布：三个 badge（backlog / in-progress / done）

**Trend Section（时间趋势）**
- Swift Charts `BarMark` 显示最近 7 天每日完成 task 数
- X 轴：日期（weekday 缩写），Y 轴：数量
- 下方文字显示平均 task 耗时（`activityStore.averageTaskDuration()`）

**Activity Section（活动时间线）**
- `activityStore.recentEvents(limit: 20)` 倒序显示
- 每行：相对时间 + 类型图标（doc.text / list.bullet / checklist）+ 名称 + StatusBadge（old → new）
- 空状态："No activity yet"

#### 2. `PIQ/Views/ActivityRowView.swift` — 单条活动事件行
- 接收 `ActivityEvent` 参数
- 显示相对时间（RelativeDateTimeFormatter）
- 类型图标区分 PRD / Epic / Task
- 状态变更 badge

### 修改文件（2 个）

#### `PIQ/Views/MenuBarView.swift`
- 添加 `@State private var showStats = false`
- header 添加统计按钮（`chart.bar` 图标），点击切换 `showStats`
- content 区域根据 `showStats` 显示 `projectList` 或 `StatsView`

#### `PIQ/Services/ActivityStore.swift`
- 添加 `tasksCompletedPerDay(lastDays:) -> [(date: Date, count: Int)]` 方法
  - 按日分组 `.done` 事件，返回最近 N 天每天的完成数（包含 0 的天）

### 不需要修改
- `PIQ.xcodeproj/project.pbxproj` — 需注册 2 个新文件
- 数据模型不变，ActivityEvent / Project 已够用

## 实施策略

两个任务按顺序执行：
1. Task 1：ActivityStore 扩展 + StatsView + ActivityRowView 创建
2. Task 2：MenuBarView 集成（视图切换 + 统计按钮）

可以合并为单任务，因为总工作量 < 3 小时。但拆分为 2 个保持 commit 清晰。

风险缓解：
- Swift Charts 不可用 → 用简单的 HStack + Rectangle 手绘柱状图
- ActivityStore 无数据 → 空状态友好提示
- 360x500 空间不够 → ScrollView 可滚动

## 任务分解预览

## 已创建的任务

- [ ] #14 - StatsView、ActivityRowView 与 ActivityStore 扩展 (parallel: false)
- [ ] #15 - MenuBarView 统计入口集成 (parallel: false, depends: #14)

总任务数：2
并行任务数：0
顺序任务数：2
估计总工作量：2.5-3.5 小时

## 依赖项

- `ActivityStore`（已实现）— recentEvents、averageTaskDuration、tasksCompleted
- `ActivityEvent` 模型（已实现）— 事件数据结构
- `ProgressBarView`（已实现）— 复用进度条组件
- `StatusBadge`（已实现）— 复用状态 badge 组件
- Swift Charts framework（系统自带）
- `AppState.setupActivityStore()` — 需确认在应用启动时调用

## 成功标准（技术）

- StatsView 渲染 < 100ms
- Swift Charts 趋势图正确显示 7 天数据
- 活动时间线与 ActivityStore 数据一致
- 项目列表 ↔ 统计面板切换流畅
- 构建零错误零警告（Swift 6 strict concurrency）

## 估计工作量

- 总任务数：2
- 涉及文件：4-5 个
- 规模：M（约 2-3 小时）
- 关键路径：Task 1 → Task 2（线性）
