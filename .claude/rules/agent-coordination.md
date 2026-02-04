# Agent Coordination

在同一个 epic worktree 中多个 agent 并行工作的规则。

## 并行执行原则

1. **文件级并行** - 处理不同文件的 agent 永远不会冲突
2. **显式协调** - 当需要同一文件时，显式协调
3. **快速失败** - 立即暴露冲突，不要试图"聪明地"解决
4. **人工解决** - 冲突由人工解决，而不是 agent

## 工作流分配

每个 agent 从 issue 分析中分配一个工作流：
```yaml
# 来自 {issue}-analysis.md
Stream A: 数据库层
  Files: src/db/*, migrations/*
  Agent: backend-specialist

Stream B: API 层
  Files: src/api/*
  Agent: api-specialist
```

Agent 应该只修改其分配模式中的文件。

## 文件访问协调

### 修改前检查
修改共享文件前：
```bash
# 检查文件是否正在被修改
git status {file}

# 如果被另一个 agent 修改，等待
if [[ $(git status --porcelain {file}) ]]; then
  echo "等待 {file} 可用..."
  sleep 30
  # 重试
fi
```

### 原子提交
使提交原子化且集中：
```bash
# 好 - 单一目的的提交
git add src/api/users.ts src/api/users.test.ts
git commit -m "Issue #1234: Add user CRUD endpoints"

# 坏 - 混合关注点
git add src/api/* src/db/* src/ui/*
git commit -m "Issue #1234: Multiple changes"
```

## Agent 之间的通信

### 通过提交
Agent 通过提交看到彼此的工作：
```bash
# Agent 检查其他人做了什么
git log --oneline -10

# Agent 拉取最新更改
git pull origin epic/{name}
```

### 通过进度文件
每个工作流维护进度：
```markdown
# .claude/epics/{epic}/updates/{issue}/stream-A.md
---
stream: 数据库层
agent: backend-specialist
started: {datetime}
status: in_progress
---

## 已完成
- 创建了用户表架构
- 添加了迁移文件

## 正在进行
- 添加索引

## 被阻塞
- 无
```

### 通过分析文件
分析文件是契约：
```yaml
# Agent 读取这个以了解边界
Stream A:
  Files: src/db/*  # Agent A 只触碰这些
Stream B:
  Files: src/api/* # Agent B 只触碰这些
```

## 处理冲突

### 冲突检测
```bash
# 如果提交因冲突而失败
git commit -m "Issue #1234: Update"
# Error: conflicts exist

# Agent 应该报告并等待
echo "❌ 在 {files} 中检测到冲突"
echo "需要人工干预"
```

### 冲突解决
始终推迟给人工：
1. Agent 检测到冲突
2. Agent 报告问题
3. Agent 暂停工作
4. 人工解决
5. Agent 继续

永远不要尝试自动合并解决。

## 同步点

### 自然同步点
- 每次提交后
- 开始新文件前
- 切换工作流时
- 每工作 30 分钟

### 显式同步
```bash
# 拉取最新更改
git pull --rebase origin epic/{name}

# 如果有冲突，停止并报告
if [[ $? -ne 0 ]]; then
  echo "❌ 同步失败 - 需要人工帮助"
  exit 1
fi
```

## Agent 通信协议

### 状态更新
Agent 应该定期更新其状态：
```bash
# 每个重要步骤更新进度文件
echo "✅ 已完成：数据库架构" >> stream-A.md
git add stream-A.md
git commit -m "Progress: Stream A - schema complete"
```

### 协调请求
当 agent 需要协调时：
```markdown
# 在 stream-A.md 中
## 需要协调
- 需要更新 src/types/index.ts
- 将在 Stream B 提交后修改
- 预计：10 分钟
```

## 并行提交策略

### 不可能有冲突
当处理完全不同的文件时：
```bash
# 这些可以同时发生
Agent-A: git commit -m "Issue #1234: Update database"
Agent-B: git commit -m "Issue #1235: Update UI"
Agent-C: git commit -m "Issue #1236: Add tests"
```

### 需要时顺序执行
当触碰共享资源时：
```bash
# Agent A 首先提交
git add src/types/index.ts
git commit -m "Issue #1234: Update type definitions"

# Agent B 等待，然后继续
# （在 A 提交之后）
git pull
git add src/api/users.ts
git commit -m "Issue #1235: Use new types"
```

## 最佳实践

1. **尽早且频繁提交** - 较小的提交 = 较少的冲突
2. **保持在自己的领域** - 只修改分配的文件
3. **沟通更改** - 更新进度文件
4. **频繁拉取** - 与其他 agent 保持同步
5. **大声失败** - 立即报告问题
6. **永远不要强制** - 永远不使用 `--force` 标志

## 常见模式

### 开始工作
```bash
1. cd ../epic-{name}
2. git pull
3. 检查 {issue}-analysis.md 获取分配
4. 用 "started" 更新 stream-{X}.md
5. 开始处理分配的文件
```

### 工作期间
```bash
1. 对分配的文件进行更改
2. 使用清晰的消息提交
3. 更新进度文件
4. 检查其他人的新提交
5. 继续或根据需要协调
```

### 完成工作
```bash
1. 工作流的最终提交
2. 用 "completed" 更新 stream-{X}.md
3. 检查其他工作流是否需要帮助
4. 报告完成
```
