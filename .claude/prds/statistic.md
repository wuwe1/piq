---
name: statistic
description: "统计面板：项目进度总览、时间趋势图、活动历史时间线"
status: done
created: 2026-02-08T14:40:57Z
---

# PRD: statistic

## 执行摘要

为 PIQ menubar 添加统计面板，在现有项目列表的基础上提供三个维度的数据可视化：项目进度总览（完成率饼图/柱图）、时间维度统计（每日/每周 task 完成数趋势）、活动历史时间线（最近状态变更事件流）。数据源基于已有的 ActivityStore 和 Project 模型，无需新增持久化层。

## 问题陈述

PIQ 当前只展示项目的实时快照（PRD/Epic/Task 数量和进度条），缺少历史维度和全局视角。用户无法回答：
- "这周我完成了多少 task？"
- "哪个 epic 耗时最久？"
- "最近有哪些状态变更？"

这些信息对于复盘效率、发现瓶颈、汇报进度至关重要。

## 用户故事

### 1. 进度总览
作为 PIQ 用户，我希望在一个面板中看到所有项目的全局进度。
- 验收标准：显示 task 总数 / 已完成数 / 完成率
- 验收标准：每个项目的进度可视化（柱状或环形图）
- 验收标准：Epic 状态分布（backlog / in-progress / done 计数）

### 2. 时间趋势
作为 PIQ 用户，我希望看到 task 完成的时间趋势。
- 验收标准：最近 7 天每天完成 task 数的柱状图
- 验收标准：平均 task 耗时（从 open 到 done）
- 验收标准：数据来自 ActivityStore 的历史事件

### 3. 活动时间线
作为 PIQ 用户，我希望看到最近的状态变更事件。
- 验收标准：按时间倒序显示最近 20 条活动事件
- 验收标准：每条事件显示：时间（相对）、项目类型图标、名称、状态变更（old → new）
- 验收标准：可区分 PRD / Epic / Task 三种事件类型

### 4. 导航集成
作为 PIQ 用户，我希望从主面板快速切换到统计面板。
- 验收标准：header 区域有统计图标按钮，点击切换到统计视图
- 验收标准：统计视图有返回按钮回到项目列表
- 验收标准：切换流畅，无闪烁

## 需求

### 功能需求

1. **统计视图入口**
   - MenuBarView header 添加统计按钮（chart.bar 图标）
   - 点击切换 content 区域为 StatsView
   - StatsView 内包含三个区域：Summary / Trend / Activity

2. **Summary 区域（进度总览）**
   - 全局统计：总 task 数、已完成数、完成率百分比
   - 每个项目一行：项目名 + 进度条 + 完成率
   - Epic 状态分布：backlog / in-progress / done 三个计数

3. **Trend 区域（时间趋势）**
   - 最近 7 天每日完成 task 数的简易柱状图
   - 使用 SwiftUI Shape 或 Chart 绘制（macOS 14+ 支持 Swift Charts）
   - 平均 task 耗时显示

4. **Activity 区域（活动时间线）**
   - 调用 `activityStore.recentEvents(limit: 20)`
   - 每条事件：相对时间 + 类型图标 + 名称 + 状态变更 badge
   - 空状态提示："No activity yet"

### 非功能需求

- **性能**：统计计算在主线程，数据量小（< 1000 events）无需异步
- **兼容性**：macOS 14+，Swift Charts framework
- **零依赖**：使用系统 Charts framework，不引入第三方图表库

## 技术方案

### 数据源（已有，无需新建）
- `AppState.projects` → 进度总览数据
- `AppState.activityStore.recentEvents()` → 活动时间线
- `AppState.activityStore.tasksCompleted(inLastDays:)` → 趋势数据
- `AppState.activityStore.averageTaskDuration()` → 平均耗时

### 新增视图
- `StatsView.swift` — 统计面板主视图，包含三个 Section
- `ActivityRowView.swift` — 单条活动事件行视图

### 修改视图
- `MenuBarView.swift` — 添加 `@State var showStats` 切换，header 添加统计按钮

### ActivityStore 可能需要的新方法
- `tasksCompletedPerDay(lastDays: Int) -> [(Date, Int)]` — 每日完成数，用于趋势图
- `epicStatusDistribution(projects:) -> (backlog: Int, inProgress: Int, done: Int)` — 静态方法即可

## 成功标准

- 统计面板在 < 100ms 内渲染完成
- 趋势图准确反映 ActivityStore 中的历史数据
- 活动时间线与实际文件变更一致
- 切换项目列表 ↔ 统计面板流畅无闪烁

## 约束与假设

- 假设 ActivityStore 已有足够的历史数据（至少运行过几次 rescanAll）
- Swift Charts 在 macOS 14+ 可用
- 统计面板在 MenuBarExtra window（360x500）内展示，空间有限
- 无需支持自定义时间范围（固定 7 天）

## 范围之外

- 导出统计报告（PDF/CSV）— 已有 Settings 中的导出功能
- 自定义时间范围选择器
- 跨项目对比分析
- 实时动画更新（每次 rescan 后刷新即可）

## 依赖项

- `ActivityStore`（已实现）— 提供历史事件数据
- `ActivityEvent` 模型（已实现）— 事件数据结构
- Swift Charts framework（系统自带，macOS 14+）
- `AppState.setupActivityStore()` 需要在应用启动时调用（检查是否已调用）

## 估计工作量

- 规模：M
- 任务数：2（StatsView 实现 + MenuBarView 集成）
- 涉及文件：4-5 个（新建 StatsView、ActivityRowView，修改 MenuBarView、可能扩展 ActivityStore）
