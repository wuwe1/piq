---
allowed-tools: Bash, Read, LS
---

# Issue Status

检查 issue 状态（open/closed）和当前状态。

## 用法
```
/pm:issue-status <issue_number>
```

## 说明

你正在检查 GitHub issue 的当前状态并提供快速状态报告：**Issue #$ARGUMENTS**

### 1. 获取 Issue 状态
使用 GitHub CLI 获取当前状态：
```bash
gh issue view #$ARGUMENTS --json state,title,labels,assignees,updatedAt
```

### 2. 状态显示
显示简洁的状态信息：
```
🎫 Issue #$ARGUMENTS: {Title}

📊 状态: {OPEN/CLOSED}
   最后更新: {timestamp}
   负责人: {assignee 或 "未分配"}

🏷️ 标签: {label1}, {label2}, {label3}
```

### 3. Epic 上下文
如果 issue 是 epic 的一部分：
```
📚 Epic 上下文:
   Epic: {epic_name}
   Epic 进度: {completed_tasks}/{total_tasks} 个任务完成
   当前任务: 第 {task_position} 个，共 {total_tasks} 个
```

### 4. 本地同步状态
检查本地文件是否同步：
```
💾 本地同步:
   本地文件: {存在/缺失}
   最后本地更新: {timestamp}
   同步状态: {已同步/需要同步/本地领先/远程领先}
```

### 5. 快速状态指示器
使用清晰的视觉指示器：
- 🟢 已打开且就绪
- 🟡 已打开但有阻塞
- 🔴 已打开但逾期
- ✅ 已关闭且完成
- ❌ 已关闭但未完成

### 6. 可操作的下一步
根据状态建议操作：
```
🚀 建议操作:
   - 开始工作: /pm:issue-start $ARGUMENTS
   - 同步更新: /pm:issue-sync $ARGUMENTS
   - 关闭 issue: gh issue close #$ARGUMENTS
   - 重新打开 issue: gh issue reopen #$ARGUMENTS
```

### 7. 批量状态
如果检查多个 issue，支持逗号分隔的列表：
```
/pm:issue-status 123,124,125
```

保持输出简洁但信息丰富，适合在开发 Issue #$ARGUMENTS 期间进行快速状态检查。
