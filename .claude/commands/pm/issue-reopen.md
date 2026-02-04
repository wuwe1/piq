---
allowed-tools: Bash, Read, Write, LS
---

# Issue Reopen

重新打开已关闭的 issue。

## 用法
```
/pm:issue-reopen <issue_number> [reason]
```

## 说明

### 1. 查找本地任务文件

搜索 frontmatter 中包含 `github:.*issues/$ARGUMENTS` 的任务文件。
如果未找到："❌ 没有 issue #$ARGUMENTS 的本地任务"

### 2. 更新本地状态

获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

更新任务文件 frontmatter：
```yaml
status: open
updated: {current_datetime}
```

### 3. 重置进度

如果进度文件存在：
- 保留原始开始日期
- 将完成度重置为之前的值或 0%
- 添加关于重新打开原因的说明

### 4. 在 GitHub 上重新打开

```bash
# 带评论重新打开
echo "🔄 Reopening issue

Reason: $ARGUMENTS

---
Reopened at: {timestamp}" | gh issue comment $ARGUMENTS --body-file -

# 重新打开 issue
gh issue reopen $ARGUMENTS
```

### 5. 更新 Epic 进度

重新计算 epic 进度，此任务现在重新打开。

### 6. 输出

```
🔄 已重新打开 issue #$ARGUMENTS
  原因：{reason_if_provided}
  Epic 进度：{updated_progress}%

开始工作：/pm:issue-start $ARGUMENTS
```

## 重要说明

在进度文件中保留工作历史。
不要删除之前的进度，只重置状态。