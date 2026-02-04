---
allowed-tools: Read, Write, LS
---

# Epic Refresh

根据任务状态更新 epic 进度。

## 用法
```
/pm:epic-refresh <epic_name>
```

## 说明

### 1. 统计任务状态

扫描 `.claude/epics/$ARGUMENTS/` 中的所有任务文件：
- 统计总任务数
- 统计 `status: closed` 的任务数
- 统计 `status: open` 的任务数
- 统计进行中的任务数

### 2. 计算进度

```
progress = (closed_tasks / total_tasks) * 100
```

四舍五入到最接近的整数。

### 3. 更新 GitHub 任务列表

如果 epic 有 GitHub issue，同步任务复选框：

```bash
# 从 epic.md frontmatter 获取 epic issue 编号
epic_issue={extract_from_github_field}

if [ ! -z "$epic_issue" ]; then
  # 获取当前 epic 正文
  gh issue view $epic_issue --json body -q .body > /tmp/epic-body.md

  # 对于每个任务，检查其状态并更新复选框
  for task_file in .claude/epics/$ARGUMENTS/[0-9]*.md; do
    # 提取任务 issue 编号
    task_github_line=$(grep 'github:' "$task_file" 2>/dev/null || true)
    if [ -n "$task_github_line" ]; then
      task_issue=$(echo "$task_github_line" | grep -oE '[0-9]+$' || true)
    else
      task_issue=""
    fi
    task_status=$(grep 'status:' $task_file | cut -d: -f2 | tr -d ' ')

    if [ "$task_status" = "closed" ]; then
      # 标记为已勾选
      sed -i "s/- \[ \] #$task_issue/- [x] #$task_issue/" /tmp/epic-body.md
    else
      # 确保未勾选（以防手动勾选）
      sed -i "s/- \[x\] #$task_issue/- [ ] #$task_issue/" /tmp/epic-body.md
    fi
  done

  # 更新 epic issue
  gh issue edit $epic_issue --body-file /tmp/epic-body.md
fi
```

### 4. 确定 Epic 状态

- 如果 progress = 0% 且未开始工作：`backlog`
- 如果 progress > 0% 且 < 100%：`in-progress`
- 如果 progress = 100%：`completed`

### 5. 更新 Epic

获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

更新 epic.md frontmatter：
```yaml
status: {calculated_status}
progress: {calculated_progress}%
updated: {current_datetime}
```

### 6. 输出

```
🔄 Epic 已刷新：$ARGUMENTS

任务：
  已关闭：{closed_count}
  未完成：{open_count}
  总计：{total_count}

进度：{old_progress}% → {new_progress}%
状态：{old_status} → {new_status}
GitHub：任务列表已更新 ✓

{如果完成}：运行 /pm:epic-close $ARGUMENTS 关闭 epic
{如果进行中}：运行 /pm:next 查看优先任务
```

## 重要说明

这在手动编辑任务或 GitHub 同步后很有用。
不要修改任务文件，只修改 epic 状态。
保留所有其他 frontmatter 字段。