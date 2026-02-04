---
allowed-tools: Bash, Read, Write, LS
---

# Issue Close

将 issue 标记为完成并在 GitHub 上关闭。

## 用法
```
/pm:issue-close <issue_number> [completion_notes]
```

## 说明

### 1. 查找本地任务文件

首先检查 `.claude/epics/*/$ARGUMENTS.md` 是否存在（新命名）。
如果未找到，搜索 frontmatter 中包含 `github:.*issues/$ARGUMENTS` 的任务文件（旧命名）。
如果未找到："❌ 没有 issue #$ARGUMENTS 的本地任务"

### 2. 更新本地状态

获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

更新任务文件 frontmatter：
```yaml
status: closed
updated: {current_datetime}
```

### 3. 更新进度文件

如果进度文件存在于 `.claude/epics/{epic}/updates/$ARGUMENTS/progress.md`：
- 设置完成度：100%
- 添加带时间戳的完成说明
- 用当前日期时间更新 last_sync

### 4. 在 GitHub 上关闭

添加完成评论并关闭：
```bash
# 添加最终评论
echo "✅ Task completed

$ARGUMENTS

---
Closed at: {timestamp}" | gh issue comment $ARGUMENTS --body-file -

# 关闭 issue
gh issue close $ARGUMENTS
```

### 5. 在 GitHub 上更新 Epic 任务列表

在 epic issue 中勾选任务复选框：

```bash
# 从本地任务文件路径获取 epic 名称
epic_name={extract_from_path}

# 从 epic.md 获取 epic issue 编号
epic_issue=$(grep 'github:' .claude/epics/$epic_name/epic.md | grep -oE '[0-9]+$')

if [ ! -z "$epic_issue" ]; then
  # 获取当前 epic 正文
  gh issue view $epic_issue --json body -q .body > /tmp/epic-body.md

  # 勾选此任务
  sed -i "s/- \[ \] #$ARGUMENTS/- [x] #$ARGUMENTS/" /tmp/epic-body.md

  # 更新 epic issue
  gh issue edit $epic_issue --body-file /tmp/epic-body.md

  echo "✓ 已在 GitHub 上更新 epic 进度"
fi
```

### 6. 更新 Epic 进度

- 统计 epic 中的总任务数
- 统计已关闭的任务数
- 计算新的进度百分比
- 更新 epic.md frontmatter 的 progress 字段

### 7. 输出

```
✅ 已关闭 issue #$ARGUMENTS
  本地：任务已标记为完成
  GitHub：Issue 已关闭 & epic 已更新
  Epic 进度：{new_progress}%（{closed}/{total} 个任务完成）

下一步：运行 /pm:next 获取下一个优先任务
```

## 重要说明

遵循 `/rules/frontmatter-operations.md` 进行更新。
遵循 `/rules/github-operations.md` 执行 GitHub 命令。
始终先同步本地状态再同步 GitHub。