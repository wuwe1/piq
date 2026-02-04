---
allowed-tools: Bash, Read, Write, LS, Task
---

# Epic Start

启动并行 agent 在共享 worktree 中处理 epic 任务。

## 用法
```
/pm:epic-start <epic_name>
```

## 快速检查

1. **验证 epic 存在：**
   ```bash
   test -f .claude/epics/$ARGUMENTS/epic.md || echo "❌ 未找到 Epic。运行：/pm:prd-parse $ARGUMENTS"
   ```

2. **检查 GitHub 同步：**
   查找 epic frontmatter 中的 `github:` 字段。
   如果缺失："❌ Epic 未同步。请先运行：/pm:epic-sync $ARGUMENTS"

3. **检查 worktree：**
   ```bash
   git worktree list | grep "epic-$ARGUMENTS"
   ```

## 说明

### 1. 创建或进入 Worktree

遵循 `/rules/worktree-operations.md`：

```bash
# 如果 worktree 不存在，创建它
if ! git worktree list | grep -q "epic-$ARGUMENTS"; then
  git checkout main
  git pull origin main
  git worktree add ../epic-$ARGUMENTS -b epic/$ARGUMENTS
  echo "✅ 已创建 worktree：../epic-$ARGUMENTS"
else
  echo "✅ 使用现有 worktree：../epic-$ARGUMENTS"
fi
```

### 2. 识别就绪的 Issues

读取 `.claude/epics/$ARGUMENTS/` 中的所有任务文件：
- 解析 frontmatter 中的 `status`、`depends_on`、`parallel` 字段
- 如需要检查 GitHub issue 状态
- 构建依赖图

分类 issues：
- **Ready**：没有未满足的依赖，未开始
- **Blocked**：有未满足的依赖
- **In Progress**：已在处理中
- **Complete**：已完成

### 3. 分析就绪的 Issues

对于每个没有分析的就绪 issue：
```bash
# 检查分析
if ! test -f .claude/epics/$ARGUMENTS/{issue}-analysis.md; then
  echo "正在分析 issue #{issue}..."
  # 运行分析（内联或通过 Task 工具）
fi
```

### 4. 启动并行 Agents

对于每个有分析的就绪 issue：

```markdown
## 开始 Issue #{issue}：{title}

正在读取分析...
发现 {count} 个并行工作流：
  - Stream A：{description}（Agent-{id}）
  - Stream B：{description}（Agent-{id}）

在 worktree ../epic-$ARGUMENTS/ 中启动 agents
```

使用 Task 工具启动每个工作流：
```yaml
Task:
  description: "Issue #{issue} Stream {X}"
  subagent_type: "{agent_type}"
  prompt: |
    Working in worktree: ../epic-$ARGUMENTS/
    Issue: #{issue} - {title}
    Stream: {stream_name}

    Your scope:
    - Files: {file_patterns}
    - Work: {stream_description}

    Read full requirements from:
    - .claude/epics/$ARGUMENTS/{task_file}
    - .claude/epics/$ARGUMENTS/{issue}-analysis.md

    Follow coordination rules in /rules/agent-coordination.md

    Commit frequently with message format:
    "Issue #{issue}: {specific change}"

    Update progress in:
    .claude/epics/$ARGUMENTS/updates/{issue}/stream-{X}.md
```

### 5. 跟踪活跃的 Agents

创建/更新 `.claude/epics/$ARGUMENTS/execution-status.md`：

```markdown
---
started: {datetime}
worktree: ../epic-$ARGUMENTS
branch: epic/$ARGUMENTS
---

# 执行状态

## 活跃的 Agents
- Agent-1：Issue #1234 Stream A（数据库）- 开始于 {time}
- Agent-2：Issue #1234 Stream B（API）- 开始于 {time}
- Agent-3：Issue #1235 Stream A（UI）- 开始于 {time}

## 排队的 Issues
- Issue #1236 - 等待 #1234
- Issue #1237 - 等待 #1235

## 已完成
- {暂无}
```

### 6. 监控和协调

设置监控：
```bash
echo "
Agents 启动成功！

监控进度：
  /pm:epic-status $ARGUMENTS

查看 worktree 更改：
  cd ../epic-$ARGUMENTS && git status

停止所有 agents：
  /pm:epic-stop $ARGUMENTS

完成后合并：
  /pm:epic-merge $ARGUMENTS
"
```

### 7. 处理依赖

当 agents 完成工作流时：
- 检查是否有任何被阻塞的 issues 现在已就绪
- 为新就绪的工作启动新 agents
- 更新 execution-status.md

## 输出格式

```
🚀 Epic 执行已开始：$ARGUMENTS

Worktree：../epic-$ARGUMENTS
分支：epic/$ARGUMENTS

在 {issue_count} 个 issues 上启动 {total} 个 agents：

Issue #1234：数据库 Schema
  ├─ Stream A：Schema 创建（Agent-1）✓ 已启动
  └─ Stream B：Migrations（Agent-2）✓ 已启动

Issue #1235：API Endpoints
  ├─ Stream A：用户 endpoints（Agent-3）✓ 已启动
  ├─ Stream B：帖子 endpoints（Agent-4）✓ 已启动
  └─ Stream C：测试（Agent-5）⏸ 等待 A 和 B

被阻塞的 Issues（2）：
  - #1236：UI 组件（依赖 #1234）
  - #1237：集成（依赖 #1235、#1236）

使用 /pm:epic-status $ARGUMENTS 监控
```

## 错误处理

如果 agent 启动失败：
```
❌ 启动 Agent-{id} 失败
  Issue：#{issue}
  Stream：{stream}
  错误：{reason}

继续其他 agents？(yes/no)
```

如果 worktree 创建失败：
```
❌ 无法创建 worktree
  {git error message}

尝试：git worktree prune
或：使用 git worktree list 检查现有 worktrees
```

## 重要说明

- 遵循 `/rules/worktree-operations.md` 进行 git 操作
- 遵循 `/rules/agent-coordination.md` 进行并行工作
- Agents 在同一 worktree 中工作（不是单独的）
- 最大并行 agents 数量应合理（例如 5-10）
- 如果启动多个 agents，请监控系统资源
