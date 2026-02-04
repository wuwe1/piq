---
allowed-tools: Bash, Read, Write, LS
---

# Issue Edit

在本地和 GitHub 上编辑 issue 详情。

## 用法
```
/pm:issue-edit <issue_number>
```

## 说明

### 1. 获取当前 Issue 状态

```bash
# 从 GitHub 获取
gh issue view $ARGUMENTS --json title,body,labels

# 查找本地任务文件
# 搜索包含 github:.*issues/$ARGUMENTS 的文件
```

### 2. 交互式编辑

询问用户要编辑什么：
- 标题
- 描述/正文
- 标签
- 验收标准（仅本地）
- 优先级/规模（仅本地）

### 3. 更新本地文件

获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

用更改更新任务文件：
- 如果标题已更改，更新 frontmatter `name`
- 如果描述已更改，更新正文内容
- 用当前日期时间更新 `updated` 字段

### 4. 更新 GitHub

如果标题已更改：
```bash
gh issue edit $ARGUMENTS --title "{new_title}"
```

如果正文已更改：
```bash
gh issue edit $ARGUMENTS --body-file {updated_task_file}
```

如果标签已更改：
```bash
gh issue edit $ARGUMENTS --add-label "{new_labels}"
gh issue edit $ARGUMENTS --remove-label "{removed_labels}"
```

### 5. 输出

```
✅ 已更新 issue #$ARGUMENTS
  更改：
    {list_of_changes_made}

已同步到 GitHub：✅
```

## 重要说明

始终先更新本地，再更新 GitHub。
保留未编辑的 frontmatter 字段。
遵循 `/rules/frontmatter-operations.md`。