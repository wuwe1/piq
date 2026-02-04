---
allowed-tools: Bash, Read, LS
---

# Issue Show

显示 issue 和子 issues 的详细信息。

## 用法
```
/pm:issue-show <issue_number>
```

## 说明

你正在显示 GitHub issue 及相关子 issues 的综合信息：**Issue #$ARGUMENTS**

### 1. 获取 Issue 数据
- 使用 `gh issue view #$ARGUMENTS` 获取 GitHub issue 详情
- 查找本地任务文件：首先检查 `.claude/epics/*/$ARGUMENTS.md`（新命名）
- 如果未找到，搜索 frontmatter 中包含 `github:.*issues/$ARGUMENTS` 的文件（旧命名）
- 检查相关 issues 和子任务

### 2. Issue 概述
显示 issue 标题：
```
🎫 Issue #$ARGUMENTS：{Issue Title}
   状态：{open/closed}
   标签：{labels}
   指派：{assignee}
   创建于：{creation_date}
   更新于：{last_update}

📝 描述：
{issue_description}
```

### 3. 本地文件映射
如果本地任务文件存在：
```
📁 本地文件：
   任务文件：.claude/epics/{epic_name}/{task_file}
   更新：.claude/epics/{epic_name}/updates/$ARGUMENTS/
   最后本地更新：{timestamp}
```

### 4. 子 Issues 和依赖
显示相关 issues：
```
🔗 相关 Issues：
   父 Epic：#{epic_issue_number}
   依赖：#{dep1}、#{dep2}
   阻塞：#{blocked1}、#{blocked2}
   子任务：#{sub1}、#{sub2}
```

### 5. 最近活动
显示最近的评论和更新：
```
💬 最近活动：
   {timestamp} - {author}：{comment_preview}
   {timestamp} - {author}：{comment_preview}

   查看完整讨论：gh issue view #$ARGUMENTS --comments
```

### 6. 进度跟踪
如果任务文件存在，显示进度：
```
✅ 验收标准：
   ✅ 标准 1（已完成）
   🔄 标准 2（进行中）
   ⏸️ 标准 3（被阻塞）
   □ 标准 4（未开始）
```

### 7. 快捷操作
```
🚀 快捷操作：
   开始工作：/pm:issue-start $ARGUMENTS
   同步更新：/pm:issue-sync $ARGUMENTS
   添加评论：gh issue comment #$ARGUMENTS --body "your comment"
   在浏览器中查看：gh issue view #$ARGUMENTS --web
```

### 8. 错误处理
- 优雅处理无效的 issue 编号
- 检查网络/认证问题
- 提供有用的错误消息和替代方案

为 Issue #$ARGUMENTS 提供全面的 issue 信息，帮助开发者了解上下文和当前状态。
