---
allowed-tools: Bash, Read, Write, LS
---

# Issue Analyze

分析 issue 以识别并行工作流，实现最大效率。

## 用法
```
/pm:issue-analyze <issue_number>
```

## 快速检查

1. **查找本地任务文件：**
   - 首先检查 `.claude/epics/*/$ARGUMENTS.md` 是否存在（新命名约定）
   - 如果未找到，搜索 frontmatter 中包含 `github:.*issues/$ARGUMENTS` 的文件（旧命名）
   - 如果未找到："❌ 没有 issue #$ARGUMENTS 的本地任务。运行：/pm:import first"

2. **检查是否已有分析：**
   ```bash
   test -f .claude/epics/*/$ARGUMENTS-analysis.md && echo "⚠️ 分析已存在。覆盖？(yes/no)"
   ```

## 说明

### 1. 读取 Issue 上下文

从 GitHub 获取 issue 详情：
```bash
gh issue view $ARGUMENTS --json title,body,labels
```

读取本地任务文件以了解：
- 技术需求
- 验收标准
- 依赖
- 工作量估算

### 2. 识别并行工作流

分析 issue 以识别可以并行运行的独立工作：

**常见模式：**
- **数据库层**：Schema、migrations、models
- **服务层**：业务逻辑、数据访问
- **API 层**：Endpoints、validation、middleware
- **UI 层**：Components、pages、styles
- **测试层**：单元测试、集成测试
- **文档**：API docs、README 更新

**关键问题：**
- 将创建/修改哪些文件？
- 哪些更改可以独立进行？
- 更改之间有什么依赖关系？
- 哪里可能发生冲突？

### 3. 创建分析文件

获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

创建 `.claude/epics/{epic_name}/$ARGUMENTS-analysis.md`：

```markdown
---
issue: $ARGUMENTS
title: {issue_title}
analyzed: {current_datetime}
estimated_hours: {total_hours}
parallelization_factor: {1.0-5.0}
---

# Parallel Work Analysis: Issue #$ARGUMENTS

## Overview
{Brief description of what needs to be done}

## Parallel Streams

### Stream A: {Stream Name}
**Scope**: {What this stream handles}
**Files**:
- {file_pattern_1}
- {file_pattern_2}
**Agent Type**: {backend|frontend|fullstack|database}-specialist
**Can Start**: immediately
**Estimated Hours**: {hours}
**Dependencies**: none

### Stream B: {Stream Name}
**Scope**: {What this stream handles}
**Files**:
- {file_pattern_1}
- {file_pattern_2}
**Agent Type**: {agent_type}
**Can Start**: immediately
**Estimated Hours**: {hours}
**Dependencies**: none

### Stream C: {Stream Name}
**Scope**: {What this stream handles}
**Files**:
- {file_pattern_1}
**Agent Type**: {agent_type}
**Can Start**: after Stream A completes
**Estimated Hours**: {hours}
**Dependencies**: Stream A

## Coordination Points

### Shared Files
{List any files multiple streams need to modify}:
- `src/types/index.ts` - Streams A & B (coordinate type updates)
- Project configuration files (package.json, pom.xml, Cargo.toml, etc.) - Stream B (add dependencies)
- Build configuration files (build.gradle, CMakeLists.txt, etc.) - Stream C (build system changes)

### Sequential Requirements
{List what must happen in order}:
1. Database schema before API endpoints
2. API types before UI components
3. Core logic before tests

## Conflict Risk Assessment
- **Low Risk**: Streams work on different directories
- **Medium Risk**: Some shared type files, manageable with coordination
- **High Risk**: Multiple streams modifying same core files

## Parallelization Strategy

**Recommended Approach**: {sequential|parallel|hybrid}

{If parallel}: Launch Streams A, B simultaneously. Start C when A completes.
{If sequential}: Complete Stream A, then B, then C.
{If hybrid}: Start A & B together, C depends on A, D depends on B & C.

## Expected Timeline

With parallel execution:
- Wall time: {max_stream_hours} hours
- Total work: {sum_all_hours} hours
- Efficiency gain: {percentage}%

Without parallel execution:
- Wall time: {sum_all_hours} hours

## Notes
{Any special considerations, warnings, or recommendations}
```

### 4. 验证分析

确保：
- 所有主要工作都被工作流覆盖
- 文件模式不会不必要地重叠
- 依赖关系合理
- Agent 类型与工作类型匹配
- 时间估算合理

### 5. 输出

```
✅ Issue #$ARGUMENTS 分析完成

识别了 {count} 个并行工作流：
  Stream A：{name}（{hours}h）
  Stream B：{name}（{hours}h）
  Stream C：{name}（{hours}h）

并行化潜力：{factor}x 加速
  顺序时间：{total}h
  并行时间：{reduced}h

有冲突风险的文件：
  {list shared files if any}

下一步：使用 /pm:issue-start $ARGUMENTS 开始工作
```

## 重要说明

- 分析仅存在于本地——不同步到 GitHub
- 关注实际的并行化，而非理论最大值
- 分配工作流时考虑 agent 专长
- 在估算中考虑协调开销
- 优先清晰分离而非最大并行化