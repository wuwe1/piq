---
allowed-tools: Bash, Read, Write, LS, Task
---

# Epic Decompose

将 epic 分解为具体的、可操作的任务。

## 用法
```
/pm:epic-decompose <feature_name>
```

## 必需的规则

**重要：** 执行此命令前，请阅读并遵循：
- `.claude/rules/datetime.md` - 用于获取真实的当前日期/时间

## 预检清单

在继续之前，完成这些验证步骤。
不要用预检进度打扰用户（"我不会..."）。只需执行它们然后继续。

1. **验证 epic 存在：**
   - 检查 `.claude/epics/$ARGUMENTS/epic.md` 是否存在
   - 如果未找到，告知用户："❌ 未找到 Epic：$ARGUMENTS。请先创建：/pm:prd-parse $ARGUMENTS"
   - 如果 epic 不存在则停止执行

2. **检查现有任务：**
   - 检查 `.claude/epics/$ARGUMENTS/` 中是否已存在编号任务文件（001.md、002.md 等）
   - 如果任务存在，列出它们并询问："⚠️ 发现 {count} 个现有任务。删除并重新创建所有任务？(yes/no)"
   - 只有在明确确认"yes"后才继续
   - 如果用户说 no，建议："使用 /pm:epic-show $ARGUMENTS 查看现有任务"

3. **验证 epic frontmatter：**
   - 验证 epic 有有效的 frontmatter，包含：name、status、created、prd
   - 如果无效，告知用户："❌ 无效的 epic frontmatter。请检查：.claude/epics/$ARGUMENTS/epic.md"

4. **检查 epic 状态：**
   - 如果 epic 状态已经是 "completed"，警告用户："⚠️ Epic 已标记为已完成。你确定要重新分解它吗？"

## 说明

你正在为 **$ARGUMENTS** 将 epic 分解为具体的、可操作的任务

### 1. 阅读 Epic
- 从 `.claude/epics/$ARGUMENTS/epic.md` 加载 epic
- 理解技术方案和需求
- 审查任务分解预览

### 2. 分析并行创建

确定任务是否可以并行创建：
- 如果任务大部分独立：使用 Task agent 并行创建
- 如果任务有复杂依赖：顺序创建
- 最佳结果：将独立任务分组进行并行创建

### 3. 并行任务创建（可能时）

如果任务可以并行创建，生成子 agent：

```yaml
Task:
  description: "Create task files batch {X}"
  subagent_type: "general-purpose"
  prompt: |
    Create task files for epic: $ARGUMENTS

    Tasks to create:
    - {list of 3-4 tasks for this batch}

    For each task:
    1. Create file: .claude/epics/$ARGUMENTS/{number}.md
    2. Use exact format with frontmatter and all sections
    3. Follow task breakdown from epic
    4. Set parallel/depends_on fields appropriately
    5. Number sequentially (001.md, 002.md, etc.)

    Return: List of files created
```

### 4. 带 Frontmatter 的任务文件格式
为每个任务创建具有以下确切结构的文件：

```markdown
---
name: [任务标题]
status: open
created: [当前 ISO 日期/时间]
updated: [当前 ISO 日期/时间]
github: [同步到 GitHub 时更新]
depends_on: []  # 此任务依赖的任务编号列表，例如 [001, 002]
parallel: true  # 此任务可以与其他任务并行运行吗？
conflicts_with: []  # 修改相同文件的任务，例如 [003, 004]
---

# Task: [任务标题]

## 描述
清晰、简洁地描述需要完成的工作

## 验收标准
- [ ] 具体标准 1
- [ ] 具体标准 2
- [ ] 具体标准 3

## 技术细节
- 实现方案
- 关键考虑因素
- 涉及的代码位置/文件

## 依赖
- [ ] 任务/Issue 依赖
- [ ] 外部依赖

## 工作量估算
- 规模：XS/S/M/L/XL
- 小时数：估计小时数
- 并行：true/false（可以与其他任务并行运行）

## 完成定义
- [ ] 代码已实现
- [ ] 测试已编写并通过
- [ ] 文档已更新
- [ ] 代码已审查
- [ ] 已部署到 staging
```

### 3. 任务命名约定
将任务保存为：`.claude/epics/$ARGUMENTS/{task_number}.md`
- 使用顺序编号：001.md、002.md 等
- 保持任务标题简短但描述性强

### 4. Frontmatter 指南
- **name**：使用描述性任务标题（不带 "Task:" 前缀）
- **status**：新任务始终以 "open" 开始
- **created**：通过运行 `date -u +"%Y-%m-%dT%H:%M:%SZ"` 获取真实当前日期时间
- **updated**：新任务使用与 created 相同的真实日期时间
- **github**：留空占位文本——将在同步时更新
- **depends_on**：列出必须在此任务开始前完成的任务编号（例如 [001, 002]）
- **parallel**：如果此任务可以与其他任务无冲突地并行运行则设为 true
- **conflicts_with**：列出修改相同文件的任务编号（有助于协调）

### 5. 要考虑的任务类型
- **设置任务**：环境、依赖、脚手架
- **数据任务**：Models、schemas、migrations
- **API 任务**：Endpoints、services、integration
- **UI 任务**：Components、pages、styling
- **测试任务**：单元测试、集成测试
- **文档任务**：README、API docs
- **部署任务**：CI/CD、基础设施

### 6. 并行化
如果任务可以同时进行而不会冲突，则用 `parallel: true` 标记。

### 7. 执行策略

根据任务数量和复杂性选择：

**小型 Epic（< 5 个任务）**：为简单起见顺序创建

**中型 Epic（5-10 个任务）**：
- 分成 2-3 组
- 为每组生成 agent
- 整合结果

**大型 Epic（> 10 个任务）**：
- 首先分析依赖关系
- 分组独立任务
- 启动并行 agent（最多 5 个并发）
- 在前置条件完成后创建依赖任务

并行执行示例：
```markdown
生成 3 个 agent 进行并行任务创建：
- Agent 1：创建任务 001-003（数据库层）
- Agent 2：创建任务 004-006（API 层）
- Agent 3：创建任务 007-009（UI 层）
```

### 8. 任务依赖验证

创建有依赖的任务时：
- 确保引用的依赖存在（例如，如果任务 003 依赖任务 002，验证 002 已创建）
- 检查循环依赖（任务 A → 任务 B → 任务 A）
- 如果发现依赖问题，警告但继续："⚠️ 任务依赖警告：{details}"

### 9. 用任务摘要更新 Epic
创建所有任务后，通过添加此部分更新 epic 文件：
```markdown
## 已创建的任务
- [ ] 001.md - {任务标题} (parallel: true/false)
- [ ] 002.md - {任务标题} (parallel: true/false)
- 等等。

总任务数：{count}
并行任务数：{parallel_count}
顺序任务数：{sequential_count}
估计总工作量：{sum of hours}
```

如果需要，也更新 epic 的 frontmatter progress（在任务实际开始前仍为 0%）。

### 9. 质量验证

在最终确定任务之前，验证：
- [ ] 所有任务都有明确的验收标准
- [ ] 任务规模合理（每个 1-3 天）
- [ ] 依赖关系合理且可实现
- [ ] 并行任务之间不冲突
- [ ] 组合任务覆盖所有 epic 需求

### 10. 分解后

成功创建任务后：
1. 确认："✅ 为 epic 创建了 {count} 个任务：$ARGUMENTS"
2. 显示摘要：
   - 创建的总任务数
   - 并行与顺序的分解
   - 估计的总工作量
3. 建议下一步："准备同步到 GitHub？运行：/pm:epic-sync $ARGUMENTS"

## 错误恢复

如果任何步骤失败：
- 如果任务创建部分完成，列出已创建的任务
- 提供清理部分任务的选项
- 绝不让 epic 处于不一致状态

目标是创建可在 1-3 天内完成的任务。为 "$ARGUMENTS" epic 将较大的任务分解为较小的、可管理的部分。
