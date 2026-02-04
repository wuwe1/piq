---
allowed-tools: Bash, Read, Write, LS
---

# Import

将现有的 GitHub issues 导入到 PM 系统。

## 用法
```
/pm:import [--epic <epic_name>] [--label <label>]
```

选项：
- `--epic` - 导入到特定 epic
- `--label` - 仅导入具有特定标签的 issues
- 无参数 - 导入所有未跟踪的 issues

## 说明

### 1. 获取 GitHub Issues

```bash
# 根据过滤器获取 issues
if [[ "$ARGUMENTS" == *"--label"* ]]; then
  gh issue list --label "{label}" --limit 1000 --json number,title,body,state,labels,createdAt,updatedAt
else
  gh issue list --limit 1000 --json number,title,body,state,labels,createdAt,updatedAt
fi
```

### 2. 识别未跟踪的 Issues

对于每个 GitHub issue：
- 在本地文件中搜索匹配的 github URL
- 如果未找到，则为未跟踪且需要导入

### 3. 分类 Issues

基于标签：
- 带有 "epic" 标签的 issues → 创建 epic 结构
- 带有 "task" 标签的 issues → 在适当的 epic 中创建任务
- 带有 "epic:{name}" 标签的 issues → 分配到该 epic
- 没有 PM 标签 → 询问用户或在 "imported" epic 中创建

### 4. 创建本地结构

对于每个要导入的 issue：

**如果是 Epic：**
```bash
mkdir -p .claude/epics/{epic_name}
# 用 GitHub 内容和 frontmatter 创建 epic.md
```

**如果是任务：**
```bash
# 找到下一个可用编号（001.md、002.md 等）
# 用 GitHub 内容创建任务文件
```

设置 frontmatter：
```yaml
name: {issue_title}
status: {open|closed 基于 GitHub}
created: {GitHub createdAt}
updated: {GitHub updatedAt}
github: https://github.com/{org}/{repo}/issues/{number}
imported: true
```

### 5. 输出

```
📥 导入完成

已导入：
  Epics：{count}
  任务：{count}

创建的结构：
  {epic_1}/
    - {count} 个任务
  {epic_2}/
    - {count} 个任务

已跳过（已跟踪）：{count}

后续步骤：
  运行 /pm:status 查看导入的工作
  运行 /pm:sync 确保完全同步
```

## 重要说明

在 frontmatter 中保留所有 GitHub 元数据。
用 `imported: true` 标志标记导入的文件。
不要覆盖现有的本地文件。