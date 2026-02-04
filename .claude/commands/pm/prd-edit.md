---
allowed-tools: Read, Write, LS
---

# PRD Edit

编辑现有的产品需求文档。

## 用法
```
/pm:prd-edit <feature_name>
```

## 说明

### 1. 读取当前 PRD

读取 `.claude/prds/$ARGUMENTS.md`：
- 解析 frontmatter
- 读取所有部分

### 2. 交互式编辑

询问用户要编辑哪些部分：
- 执行摘要
- 问题陈述
- 用户故事
- 需求（功能性/非功能性）
- 成功标准
- 约束与假设
- 范围之外
- 依赖项

### 3. 更新 PRD

获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

更新 PRD 文件：
- 保留 frontmatter，除了 `updated` 字段
- 将用户的编辑应用到选定的部分
- 使用当前日期时间更新 `updated` 字段

### 4. 检查 Epic 影响

如果 PRD 有关联的 epic：
- 通知用户："此 PRD 有 epic: {epic_name}"
- 询问："Epic 可能需要根据 PRD 更改进行更新。是否查看 epic？(yes/no)"
- 如果是，显示："使用以下命令查看：/pm:epic-edit {epic_name}"

### 5. 输出

```
✅ 已更新 PRD: $ARGUMENTS
  已编辑的部分: {list_of_sections}

{如果有 epic}: ⚠️ Epic 可能需要审查: {epic_name}

下一步: /pm:prd-parse $ARGUMENTS 更新 epic
```

## 重要说明

保留原始创建日期。
如果需要，在 frontmatter 中保持版本历史。
遵循 `/rules/frontmatter-operations.md`。