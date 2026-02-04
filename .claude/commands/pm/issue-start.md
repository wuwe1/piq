---
allowed-tools: Bash, Read, Write, LS, Task
---

# Issue Start

基于工作流分析，使用并行 agents 开始处理 GitHub issue。

## 用法
```
/pm:issue-start <issue_number>
```

## 快速检查

1. **获取 issue 详情：**
   ```bash
   gh issue view $ARGUMENTS --json state,title,labels,body
   ```
   如果失败："❌ 无法访问 issue #$ARGUMENTS。检查编号或运行：gh auth login"

2. **查找本地任务文件：**
   - 首先检查 `.claude/epics/*/$ARGUMENTS.md` 是否存在（新命名）
   - 如果未找到，搜索 frontmatter 中包含 `github:.*issues/$ARGUMENTS` 的文件（旧命名）
   - 如果未找到："❌ 没有 issue #$ARGUMENTS 的本地任务。此 issue 可能是在 PM 系统外创建的。"

3. **检查分析：**
   ```bash
   test -f .claude/epics/*/$ARGUMENTS-analysis.md || echo "❌ 未找到 issue #$ARGUMENTS 的分析

   运行：/pm:issue-analyze $ARGUMENTS first
   或：/pm:issue-start $ARGUMENTS --analyze 同时执行"
   ```
   如果没有分析且没有 --analyze 标志，停止执行。

## 说明

### 1. 确保 Worktree 存在

检查 epic worktree 是否存在：
```bash
# 从任务文件中找到 epic 名称
epic_name={extracted_from_path}

# 检查 worktree
if ! git worktree list | grep -q "epic-$epic_name"; then
  echo "❌ epic 没有 worktree。运行：/pm:epic-start $epic_name"
  exit 1
fi
```

### 2. 读取分析

读取 `.claude/epics/{epic_name}/$ARGUMENTS-analysis.md`：
- 解析并行工作流
- 识别哪些可以立即开始
- 记录工作流之间的依赖关系

### 3. 设置进度跟踪

获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

创建工作区结构：
```bash
mkdir -p .claude/epics/{epic_name}/updates/$ARGUMENTS
```

用当前日期时间更新任务文件 frontmatter 的 `updated` 字段。

### 4. 启动并行 Agents

对于每个可以立即开始的工作流：

创建 `.claude/epics/{epic_name}/updates/$ARGUMENTS/stream-{X}.md`：
```markdown
---
issue: $ARGUMENTS
stream: {stream_name}
agent: {agent_type}
started: {current_datetime}
status: in_progress
---

# Stream {X}: {stream_name}

## Scope
{stream_description}

## Files
{file_patterns}

## Progress
- Starting implementation
```

使用 Task 工具启动 agent：
```yaml
Task:
  description: "Issue #$ARGUMENTS Stream {X}"
  subagent_type: "{agent_type}"
  prompt: |
    You are working on Issue #$ARGUMENTS in the epic worktree.
    
    Worktree location: ../epic-{epic_name}/
    Your stream: {stream_name}
    
    Your scope:
    - Files to modify: {file_patterns}
    - Work to complete: {stream_description}
    
    Requirements:
    1. Read full task from: .claude/epics/{epic_name}/{task_file}
    2. Work ONLY in your assigned files
    3. Commit frequently with format: "Issue #$ARGUMENTS: {specific change}"
    4. Update progress in: .claude/epics/{epic_name}/updates/$ARGUMENTS/stream-{X}.md
    5. Follow coordination rules in /rules/agent-coordination.md
    
    If you need to modify files outside your scope:
    - Check if another stream owns them
    - Wait if necessary
    - Update your progress file with coordination notes
    
    Complete your stream's work and mark as completed when done.
```

### 5. GitHub 指派

```bash
# 指派给自己并标记为进行中
gh issue edit $ARGUMENTS --add-assignee @me --add-label "in-progress"
```

### 6. 输出

```
✅ 已在 issue #$ARGUMENTS 上开始并行工作

Epic：{epic_name}
Worktree：../epic-{epic_name}/

启动 {count} 个并行 agents：
  Stream A：{name}（Agent-1）✓ 已启动
  Stream B：{name}（Agent-2）✓ 已启动
  Stream C：{name} - 等待中（依赖 A）

进度跟踪：
  .claude/epics/{epic_name}/updates/$ARGUMENTS/

使用 /pm:epic-status {epic_name} 监控
同步更新：/pm:issue-sync $ARGUMENTS
```

## 错误处理

如果任何步骤失败，清楚报告：
- "❌ {失败的内容}：{如何修复}"
- 继续可能的操作
- 绝不留下部分状态

## 重要说明

遵循 `/rules/datetime.md` 处理时间戳。
保持简单——相信 GitHub 和文件系统能正常工作。