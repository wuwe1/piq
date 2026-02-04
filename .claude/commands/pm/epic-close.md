---
allowed-tools: Bash, Read, Write, LS
---

# Epic Close

当所有任务完成后，将 epic 标记为已完成。

## 用法
```
/pm:epic-close <epic_name>
```

## 说明

### 1. 验证所有任务已完成

检查 `.claude/epics/$ARGUMENTS/` 中的所有任务文件：
- 验证所有文件的 frontmatter 中都有 `status: closed`
- 如果发现任何未完成的任务："❌ 无法关闭 epic。仍有未完成的任务：{list}"

### 2. 更新 Epic 状态

获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

更新 epic.md frontmatter：
```yaml
status: completed
progress: 100%
updated: {current_datetime}
completed: {current_datetime}
```

### 3. 更新 PRD 状态

如果 epic 引用了 PRD，将其状态更新为 "complete"。

### 4. 在 GitHub 上关闭 Epic

如果 epic 有 GitHub issue：
```bash
gh issue close {epic_issue_number} --comment "✅ Epic completed - all tasks done"
```

### 5. 归档选项

询问用户："归档已完成的 epic？(yes/no)"

如果是：
- 将 epic 目录移动到 `.claude/epics/.archived/{epic_name}/`
- 创建包含完成日期的归档摘要

### 6. 输出

```
✅ Epic 已关闭：$ARGUMENTS
  完成的任务：{count}
  持续时间：{days_from_created_to_completed}

{如果已归档}：已归档到 .claude/epics/.archived/

下一个 epic：运行 /pm:next 查看优先工作
```

## 重要说明

只有当所有任务完成时才关闭 epic。
归档时保留所有数据。
更新相关的 PRD 状态。