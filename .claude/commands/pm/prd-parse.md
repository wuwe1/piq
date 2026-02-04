---
allowed-tools: Bash, Read, Write, LS
---

# PRD Parse

将 PRD 转换为技术实施 epic。

## 用法
```
/pm:prd-parse <feature_name>
```

## 必需规则

**重要：** 在执行此命令之前，请阅读并遵循：
- `.claude/rules/datetime.md` - 用于获取真实的当前日期/时间

## 预检清单

在继续之前，完成这些验证步骤。
不要用预检进度打扰用户（"我不会..."）。只需执行它们然后继续。

### 验证步骤
1. **验证 <feature_name> 是否作为参数提供：**
   - 如果没有，告诉用户："❌ <feature_name> 未作为参数提供。请运行：/pm:prd-parse <feature_name>"
   - 如果未提供 <feature_name>，停止执行

2. **验证 PRD 存在：**
   - 检查 `.claude/prds/$ARGUMENTS.md` 是否存在
   - 如果未找到，告诉用户："❌ 未找到 PRD：$ARGUMENTS。首先使用以下命令创建：/pm:prd-new $ARGUMENTS"
   - 如果 PRD 不存在，停止执行

3. **验证 PRD frontmatter：**
   - 验证 PRD 具有有效的 frontmatter，包含：name、description、status、created
   - 如果 frontmatter 无效或缺失，告诉用户："❌ PRD frontmatter 无效。请检查：.claude/prds/$ARGUMENTS.md"
   - 显示缺少或无效的内容

4. **检查现有 epic：**
   - 检查 `.claude/epics/$ARGUMENTS/epic.md` 是否已存在
   - 如果存在，询问用户："⚠️ Epic '$ARGUMENTS' 已存在。是否覆盖？(yes/no)"
   - 仅在明确确认 'yes' 后继续
   - 如果用户说 no，建议："使用以下命令查看现有 epic：/pm:epic-show $ARGUMENTS"

5. **验证目录权限：**
   - 确保 `.claude/epics/` 目录存在或可以创建
   - 如果无法创建，告诉用户："❌ 无法创建 epic 目录。请检查权限。"

## 说明

你是一名技术负责人，正在将产品需求文档转换为详细的实施 epic：**$ARGUMENTS**

### 1. 读取 PRD
- 从 `.claude/prds/$ARGUMENTS.md` 加载 PRD
- 分析所有需求和约束
- 理解用户故事和成功标准
- 从 frontmatter 提取 PRD 描述

### 2. 技术分析
- 确定所需的架构决策
- 确定技术栈和方法
- 将功能需求映射到技术组件
- 确定集成点和依赖项

### 3. 带 Frontmatter 的文件格式
在以下位置创建 epic 文件：`.claude/epics/$ARGUMENTS/epic.md`，使用以下精确结构：

```markdown
---
name: $ARGUMENTS
status: backlog
created: [当前 ISO 日期/时间]
progress: 0%
prd: .claude/prds/$ARGUMENTS.md
github: [同步到 GitHub 时将更新]
---

# Epic: $ARGUMENTS

## 概述
实施方法的简要技术摘要

## 架构决策
- 关键技术决策和理由
- 技术选择
- 要使用的设计模式

## 技术方法
### 前端组件
- 所需的 UI 组件
- 状态管理方法
- 用户交互模式

### 后端服务
- 所需的 API 端点
- 数据模型和架构
- 业务逻辑组件

### 基础设施
- 部署考虑
- 扩展需求
- 监控和可观察性

## 实施策略
- 开发阶段
- 风险缓解
- 测试方法

## 任务分解预览
将创建的高级任务类别：
- [ ] 类别 1：描述
- [ ] 类别 2：描述
- [ ] 等等

## 依赖项
- 外部服务依赖项
- 内部团队依赖项
- 前置工作

## 成功标准（技术）
- 性能基准
- 质量门禁
- 验收标准

## 估计工作量
- 整体时间线估计
- 资源需求
- 关键路径项目
```

### 4. Frontmatter 指南
- **name**：使用确切的功能名称（与 $ARGUMENTS 相同）
- **status**：新 epic 始终以 "backlog" 开始
- **created**：通过运行以下命令获取真实的当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`
- **progress**：新 epic 始终以 "0%" 开始
- **prd**：引用源 PRD 文件路径
- **github**：保留占位符文本 - 将在同步期间更新

### 5. 输出位置
如果目录结构不存在则创建：
- `.claude/epics/$ARGUMENTS/`（目录）
- `.claude/epics/$ARGUMENTS/epic.md`（epic 文件）

### 6. 质量验证

保存 epic 之前，验证：
- [ ] 所有 PRD 需求都在技术方法中得到解决
- [ ] 任务分解类别涵盖所有实施领域
- [ ] 依赖项在技术上准确
- [ ] 工作量估计是现实的
- [ ] 架构决策是有理由的

### 7. 创建后

成功创建 epic 后：
1. 确认："✅ Epic 已创建：.claude/epics/$ARGUMENTS/epic.md"
2. 显示摘要：
   - 识别的任务类别数量
   - 关键架构决策
   - 估计工作量
3. 建议下一步："准备分解为任务？运行：/pm:epic-decompose $ARGUMENTS"

## 错误恢复

如果任何步骤失败：
- 清楚地解释出了什么问题
- 如果 PRD 不完整，列出具体缺失的部分
- 如果技术方法不清楚，确定需要澄清的内容
- 永远不要创建信息不完整的 epic

专注于创建技术上合理的实施计划，解决所有 PRD 需求，同时对 "$ARGUMENTS" 保持实用和可实现。

## 重要：
- 尽量减少任务数量，并将任务总数限制在 10 个或更少。
- 创建 epic 时，识别简化和改进的方法。尽可能寻找利用现有功能而不是创建更多代码的方法。
