---
allowed-tools: Task, Read, Edit, MultiEdit, Write, LS, Grep
---

# CodeRabbit Review Handler

使用上下文感知的判断处理 CodeRabbit 审查评论。

## 用法
```
/code-rabbit
```

然后粘贴一个或多个 CodeRabbit 评论。

## 说明

### 1. 初始上下文

告知用户：
```
我将谨慎审查 CodeRabbit 的评论，因为 CodeRabbit 无法访问整个代码库，可能无法理解完整的上下文。

对于每条评论，我会：
- 评估它在我们代码库上下文中是否有效
- 接受能改善代码质量的建议
- 忽略不适用于我们架构的建议
- 解释我接受/忽略决定的原因
```

### 2. 处理评论

#### 单文件评论
如果所有评论都与一个文件相关：
- 读取文件以获取上下文
- 评估每个建议
- 使用 MultiEdit 批量应用已接受的更改
- 报告哪些建议被接受/忽略及原因

#### 多文件评论
如果评论涉及多个文件：

使用 Task 工具启动并行子 agent：
```yaml
Task:
  description: "CodeRabbit fixes for {filename}"
  subagent_type: "general-purpose"
  prompt: |
    Review and apply CodeRabbit suggestions for {filename}.

    Comments to evaluate:
    {relevant_comments_for_this_file}

    Instructions:
    1. Read the file to understand context
    2. For each suggestion:
       - Evaluate validity given codebase patterns
       - Accept if it improves quality/correctness
       - Ignore if not applicable
    3. Apply accepted changes using Edit/MultiEdit
    4. Return summary:
       - Accepted: {list with reasons}
       - Ignored: {list with reasons}
       - Changes made: {brief description}

    Use discretion - CodeRabbit lacks full context.
```

### 3. 整合结果

所有子 agent 完成后：
```
📋 CodeRabbit 审查摘要

处理的文件数：{count}

已接受的建议：
  {file}：{changes_made}

已忽略的建议：
  {file}：{reason_ignored}

总计：应用了 {X}/{Y} 条建议
```

### 4. 常见应忽略的模式

- **风格偏好**——与项目惯例冲突的
- **通用最佳实践**——不适用于我们特定用例的
- **性能优化**——针对非性能关键代码的
- **无障碍建议**——针对内部工具的
- **安全警告**——针对已验证模式的
- **导入重组**——会破坏我们结构的

### 5. 常见应接受的模式

- **实际 bug**（null 检查、错误处理）
- **安全漏洞**（除非是误报）
- **资源泄漏**（未关闭的连接、内存泄漏）
- **类型安全问题**（TypeScript/type hints）
- **逻辑错误**（差一错误、错误条件）
- **缺失的错误处理**

## 决策框架

对于每个建议，考虑：
1. **它正确吗？**——问题确实存在吗？
2. **它相关吗？**——适用于我们的用例吗？
3. **它有益吗？**——修复它会改善代码吗？
4. **它安全吗？**——更改可能引入问题吗？

只有当所有答案都是"是"或收益明显大于风险时才应用。

## 重要说明

- CodeRabbit 很有帮助但缺乏上下文
- 相信你对代码库的理解胜过通用建议
- 简要解释决定以保持审计跟踪
- 批量处理相关更改以提高效率
- 使用并行 agent 进行多文件审查以节省时间