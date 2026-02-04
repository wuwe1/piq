---
allowed-tools: Read, LS
---

# Epic Oneshot

一次性将 epic 分解为任务并同步到 GitHub。

## 用法
```
/pm:epic-oneshot <feature_name>
```

## 说明

### 1. 验证前置条件

检查 epic 是否存在且未被处理过：
```bash
# Epic 必须存在
test -f .claude/epics/$ARGUMENTS/epic.md || echo "❌ 未找到 Epic。运行：/pm:prd-parse $ARGUMENTS"

# 检查是否有现有任务
if ls .claude/epics/$ARGUMENTS/[0-9]*.md 2>/dev/null | grep -q .; then
  echo "⚠️ 任务已存在。这将创建重复项。"
  echo "删除现有任务或使用 /pm:epic-sync 代替。"
  exit 1
fi

# 检查是否已同步
if grep -q "github:" .claude/epics/$ARGUMENTS/epic.md; then
  echo "⚠️ Epic 已同步到 GitHub。"
  echo "使用 /pm:epic-sync 更新。"
  exit 1
fi
```

### 2. 执行分解

直接运行 decompose 命令：
```
运行中：/pm:epic-decompose $ARGUMENTS
```

这将：
- 读取 epic
- 创建任务文件（如适当则使用并行 agent）
- 用任务摘要更新 epic

### 3. 执行同步

紧接着进行同步：
```
运行中：/pm:epic-sync $ARGUMENTS
```

这将：
- 在 GitHub 上创建 epic issue
- 创建子 issues（如适当则使用并行 agent）
- 将任务文件重命名为 issue ID
- 创建 worktree

### 4. 输出

```
🚀 Epic Oneshot 完成：$ARGUMENTS

步骤 1：分解 ✓
  - 创建的任务数：{count}

步骤 2：GitHub 同步 ✓
  - Epic：#{number}
  - 创建的子 issues：{count}
  - Worktree：../epic-$ARGUMENTS

准备开发！
  开始工作：/pm:epic-start $ARGUMENTS
  或单个任务：/pm:issue-start {task_number}
```

## 重要说明

这只是一个便捷封装，运行：
1. `/pm:epic-decompose`
2. `/pm:epic-sync`

两个命令都处理各自的错误检查、并行执行和验证。此命令只是按顺序编排它们。

当你确信 epic 已准备好并想一步从 epic 到 GitHub issues 时使用此命令。