# Worktree 操作

Git worktree 通过允许同一仓库拥有多个工作目录来实现并行开发。

## 创建 Worktree

始终从干净的 main 分支创建 worktree：
```bash
# 确保 main 是最新的
git checkout main
git pull origin main

# 为 epic 创建 worktree
git worktree add ../epic-{name} -b epic/{name}
```

Worktree 将作为同级目录创建以保持清晰的隔离。

## 在 Worktree 中工作

### Agent 提交
- Agent 直接提交到 worktree
- 使用小型、集中的提交
- 提交消息格式：`Issue #{number}: {description}`
- 示例：`Issue #1234: Add user authentication schema`

### 文件操作
```bash
# 工作目录是 worktree
cd ../epic-{name}

# 正常的 git 操作有效
git add {files}
git commit -m "Issue #{number}: {change}"

# 查看 worktree 状态
git status
```

## 同一 Worktree 中的并行工作

如果多个 agent 处理不同的文件，它们可以在同一 worktree 中工作：
```bash
# Agent A 处理 API
git add src/api/*
git commit -m "Issue #1234: Add user endpoints"

# Agent B 处理 UI（没有冲突！）
git add src/ui/*
git commit -m "Issue #1235: Add dashboard component"
```

## 合并 Worktree

当 epic 完成时，合并回 main：
```bash
# 从主仓库（不是 worktree）
cd {main-repo}
git checkout main
git pull origin main

# 合并 epic 分支
git merge epic/{name}

# 如果成功，清理
git worktree remove ../epic-{name}
git branch -d epic/{name}
```

## 处理冲突

如果发生合并冲突：
```bash
# 冲突将被显示
git status

# 人工解决冲突
# 然后继续合并
git add {resolved-files}
git commit
```

## Worktree 管理

### 列出活动的 Worktree
```bash
git worktree list
```

### 删除过时的 Worktree
```bash
# 如果 worktree 目录已被删除
git worktree prune

# 强制删除 worktree
git worktree remove --force ../epic-{name}
```

### 检查 Worktree 状态
```bash
# 从主仓库
cd ../epic-{name} && git status && cd -
```

## 最佳实践

1. **每个 epic 一个 worktree** - 不是每个 issue
2. **创建前清理** - 始终从更新的 main 开始
3. **频繁提交** - 小提交更容易合并
4. **合并后删除** - 不要留下过时的 worktree
5. **使用描述性分支** - `epic/feature-name` 而不是 `feature`

## 常见问题

### Worktree 已存在
```bash
# 首先删除旧的 worktree
git worktree remove ../epic-{name}
# 然后创建新的
```

### 分支已存在
```bash
# 删除旧分支
git branch -D epic/{name}
# 或使用现有分支
git worktree add ../epic-{name} epic/{name}
```

### 无法删除 Worktree
```bash
# 强制删除
git worktree remove --force ../epic-{name}
# 清理引用
git worktree prune
```