---
allowed-tools: Bash, Read, Write, LS
---

# Sync

本地和 GitHub 之间的完整双向同步。

## 用法
```
/pm:sync [epic_name]
```

如果提供了 epic_name，则仅同步该 epic。否则同步全部。

## 说明

### 1. 从 GitHub 拉取

获取所有 issue 的当前状态：
```bash
# 获取所有 epic 和 task issue
gh issue list --label "epic" --limit 1000 --json number,title,state,body,labels,updatedAt
gh issue list --label "task" --limit 1000 --json number,title,state,body,labels,updatedAt
```

### 2. 从 GitHub 更新本地

对于每个 GitHub issue：
- 通过 issue 编号查找对应的本地文件
- 比较状态：
  - 如果 GitHub 状态更新（updatedAt > 本地更新时间），更新本地
  - 如果 GitHub 已关闭但本地为打开状态，关闭本地
  - 如果 GitHub 重新打开但本地为关闭状态，重新打开本地
- 更新 frontmatter 以匹配 GitHub 状态

### 3. 推送本地到 GitHub

对于每个本地任务/epic：
- 如果有 GitHub URL 但未找到 GitHub issue，说明已被删除 - 将本地标记为已归档
- 如果没有 GitHub URL，创建新 issue（如 epic-sync）
- 如果本地更新时间 > GitHub updatedAt，推送更改：
  ```bash
  gh issue edit {number} --body-file {local_file}
  ```

### 4. 处理冲突

如果双方都有更改（自上次同步以来本地和 GitHub 都有更新）：
- 显示两个版本
- 询问用户："本地和 GitHub 都有更改。保留：(local/github/merge)？"
- 应用用户的选择

### 5. 更新同步时间戳

使用 last_sync 时间戳更新所有已同步的文件。

### 6. 输出

```
🔄 同步完成

从 GitHub 拉取:
  已更新: {count} 个文件
  已关闭: {count} 个 issue

推送到 GitHub:
  已更新: {count} 个 issue
  已创建: {count} 个新 issue

已解决的冲突: {count}

状态:
  ✅ 所有文件已同步
  {或列出任何同步失败}
```

## 重要说明

遵循 `/rules/github-operations.md` 执行 GitHub 命令。
遵循 `/rules/frontmatter-operations.md` 进行本地更新。
始终在同步前备份以防出现问题。