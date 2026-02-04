---
allowed-tools: Read, Write, LS
---

# Epic Edit

创建后编辑 epic 详情。

## 用法
```
/pm:epic-edit <epic_name>
```

## 说明

### 1. 读取当前 Epic

读取 `.claude/epics/$ARGUMENTS/epic.md`：
- 解析 frontmatter
- 读取内容部分

### 2. 交互式编辑

询问用户要编辑什么：
- 名称/标题
- 描述/概述
- 架构决策
- 技术方案
- 依赖
- 成功标准

### 3. 更新 Epic 文件

获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

更新 epic.md：
- 保留除 `updated` 外的所有 frontmatter
- 将用户的编辑应用到内容
- 用当前日期时间更新 `updated` 字段

### 4. 更新 GitHub 的选项

如果 epic 的 frontmatter 中有 GitHub URL：
询问："更新 GitHub issue？(yes/no)"

如果是：
```bash
gh issue edit {issue_number} --body-file .claude/epics/$ARGUMENTS/epic.md
```

### 5. 输出

```
✅ 已更新 epic：$ARGUMENTS
  更改的部分：{sections_edited}

{如果 GitHub 已更新}：GitHub issue 已更新 ✅

查看 epic：/pm:epic-show $ARGUMENTS
```

## 重要说明

保留 frontmatter 历史（created、github URL 等）。
编辑 epic 时不要更改任务文件。
遵循 `/rules/frontmatter-operations.md`。