---
allowed-tools: Bash, Read, Write, LS
---

# Issue Sync

将本地更新推送为 GitHub issue 评论，用于透明的审计跟踪。

## 用法
```
/pm:issue-sync <issue_number>
```

## 必需规则

**重要：** 在执行此命令之前，请阅读并遵循：
- `.claude/rules/datetime.md` - 用于获取真实的当前日期/时间

## 预检清单

在继续之前，完成这些验证步骤。
不要用预检进度打扰用户（"我不会..."）。只需执行它们然后继续。

0. **仓库保护检查：**
   遵循 `/rules/github-operations.md` - 检查 remote origin：
   ```bash
   remote_url=$(git remote get-url origin 2>/dev/null || echo "")
   if [[ "$remote_url" == *"wuwe1/ccpm"* ]]; then
     echo "❌ 错误：无法同步到 CCPM 模板仓库！"
     echo "更新你的 remote: git remote set-url origin https://github.com/YOUR_USERNAME/YOUR_REPO.git"
     exit 1
   fi
   ```

1. **GitHub 认证：**
   - 运行：`gh auth status`
   - 如果未认证，告诉用户："❌ GitHub CLI 未认证。运行：gh auth login"

2. **Issue 验证：**
   - 运行：`gh issue view $ARGUMENTS --json state`
   - 如果 issue 不存在，告诉用户："❌ Issue #$ARGUMENTS 未找到"
   - 如果 issue 已关闭且完成度 < 100%，警告："⚠️ Issue 已关闭但工作未完成"

3. **本地更新检查：**
   - 检查 `.claude/epics/*/updates/$ARGUMENTS/` 目录是否存在
   - 如果未找到，告诉用户："❌ 未找到 issue #$ARGUMENTS 的本地更新。运行：/pm:issue-start $ARGUMENTS"
   - 检查 progress.md 是否存在
   - 如果不存在，告诉用户："❌ 未找到进度跟踪。使用以下命令初始化：/pm:issue-start $ARGUMENTS"

4. **检查上次同步：**
   - 从 progress.md frontmatter 读取 `last_sync`
   - 如果最近同步过（< 5 分钟），询问："⚠️ 最近已同步。是否强制同步？(yes/no)"
   - 计算自上次同步以来的新内容

5. **验证更改：**
   - 检查是否有实际更新需要同步
   - 如果没有更改，告诉用户："ℹ️ 自 {last_sync} 以来没有新的更新需要同步"
   - 如果没有需要同步的内容，优雅退出

## 说明

你正在将本地开发进度同步到 GitHub 作为 issue 评论：**Issue #$ARGUMENTS**

### 1. 收集本地更新
收集 issue 的所有本地更新：
- 从 `.claude/epics/{epic_name}/updates/$ARGUMENTS/` 读取
- 检查以下文件中的新内容：
  - `progress.md` - 开发进度
  - `notes.md` - 技术笔记和决策
  - `commits.md` - 最近的提交和更改
  - 任何其他更新文件

### 2. 更新进度跟踪 Frontmatter
获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

更新 progress.md 文件的 frontmatter：
```yaml
---
issue: $ARGUMENTS
started: [保留现有日期]
last_sync: [使用上述命令的真实日期时间]
completion: [计算的百分比 0-100%]
---
```

### 3. 确定新内容
与之前的同步比较以识别新内容：
- 查找同步时间戳标记
- 识别新的部分或更新
- 仅收集自上次同步以来的增量更改

### 4. 格式化更新评论
创建全面的更新评论：

```markdown
## 🔄 进度更新 - {current_date}

### ✅ 已完成工作
{list_completed_items}

### 🔄 进行中
{current_work_items}

### 📝 技术笔记
{key_technical_decisions}

### 📊 验收标准状态
- ✅ {completed_criterion}
- 🔄 {in_progress_criterion}
- ⏸️ {blocked_criterion}
- □ {pending_criterion}

### 🚀 下一步
{planned_next_actions}

### ⚠️ 阻塞项
{any_current_blockers}

### 💻 最近提交
{commit_summaries}

---
*进度: {completion}% | 从本地更新同步于 {timestamp}*
```

### 5. 发布到 GitHub
使用 GitHub CLI 添加评论：
```bash
gh issue comment #$ARGUMENTS --body-file {temp_comment_file}
```

### 6. 更新本地任务文件
获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

使用同步信息更新任务文件 frontmatter：
```yaml
---
name: [任务标题]
status: open
created: [保留现有日期]
updated: [使用上述命令的真实日期时间]
github: https://github.com/{org}/{repo}/issues/$ARGUMENTS
---
```

### 7. 处理完成
如果任务完成，更新所有相关的 frontmatter：

**任务文件 frontmatter**：
```yaml
---
name: [任务标题]
status: closed
created: [现有日期]
updated: [当前日期/时间]
github: https://github.com/{org}/{repo}/issues/$ARGUMENTS
---
```

**进度文件 frontmatter**：
```yaml
---
issue: $ARGUMENTS
started: [现有日期]
last_sync: [当前日期/时间]
completion: 100%
---
```

**Epic 进度更新**：根据已完成的任务重新计算 epic 进度并更新 epic frontmatter：
```yaml
---
name: [Epic 名称]
status: in-progress
created: [现有日期]
progress: [基于已完成任务计算的百分比]%
prd: [现有路径]
github: [现有 URL]
---
```

### 8. 完成评论
如果任务完成：
```markdown
## ✅ 任务完成 - {current_date}

### 🎯 所有验收标准已满足
- ✅ {criterion_1}
- ✅ {criterion_2}
- ✅ {criterion_3}

### 📦 交付物
- {deliverable_1}
- {deliverable_2}

### 🧪 测试
- 单元测试: ✅ 通过
- 集成测试: ✅ 通过
- 手动测试: ✅ 完成

### 📚 文档
- 代码文档: ✅ 已更新
- README 更新: ✅ 完成

此任务已准备好进行审查并可以关闭。

---
*任务完成: 100% | 同步于 {timestamp}*
```

### 9. 输出摘要
```
☁️ 已同步更新到 GitHub Issue #$ARGUMENTS

📝 更新摘要:
   进度项: {progress_count}
   技术笔记: {notes_count}
   引用的提交: {commit_count}

📊 当前状态:
   任务完成度: {task_completion}%
   Epic 进度: {epic_progress}%
   已完成标准: {completed}/{total}

🔗 查看更新: gh issue view #$ARGUMENTS --comments
```

### 10. Frontmatter 维护
- 始终使用当前时间戳更新任务文件 frontmatter
- 在进度文件中跟踪完成百分比
- 当任务完成时更新 epic 进度
- 维护同步时间戳以供审计跟踪

### 11. 增量同步检测

**防止重复评论：**
1. 每次同步后在本地文件中添加同步标记：
   ```markdown
   <!-- SYNCED: 2024-01-15T10:30:00Z -->
   ```
2. 仅同步最后一个标记之后添加的内容
3. 如果没有新内容，跳过同步并显示消息："自上次同步以来没有更新"

### 12. 评论大小管理

**处理 GitHub 的评论限制：**
- 最大评论大小：65,536 字符
- 如果更新超过限制：
  1. 拆分为多个评论
  2. 或者总结并链接到完整详情
  3. 警告用户："⚠️ 由于大小限制，更新已截断。完整详情在本地文件中。"

### 13. 错误处理

**常见问题和恢复：**

1. **网络错误：**
   - 消息："❌ 发布评论失败：网络错误"
   - 解决方案："检查网络连接并重试"
   - 保留本地更新以便重试

2. **速率限制：**
   - 消息："❌ GitHub 速率限制已超过"
   - 解决方案："等待 {minutes} 分钟或使用不同的 token"
   - 将评论保存到本地以供稍后同步

3. **权限被拒绝：**
   - 消息："❌ 无法评论 issue（权限被拒绝）"
   - 解决方案："检查仓库访问权限"

4. **Issue 已锁定：**
   - 消息："⚠️ Issue 已锁定评论"
   - 解决方案："联系仓库管理员解锁"

### 14. Epic 进度计算

更新 epic 进度时：
1. 计算 epic 目录中的总任务数
2. 计算 frontmatter 中 `status: closed` 的任务数
3. 计算：`progress = (closed_tasks / total_tasks) * 100`
4. 四舍五入到最接近的整数
5. 仅当百分比改变时更新 epic frontmatter

### 15. 同步后验证

成功同步后：
- [ ] 验证评论已发布到 GitHub
- [ ] 确认 frontmatter 已使用同步时间戳更新
- [ ] 如果任务完成，检查 epic 进度是否已更新
- [ ] 验证本地文件没有数据损坏

这为 Issue #$ARGUMENTS 创建了一个透明的开发进度审计跟踪，利益相关者可以实时跟进，同时在所有项目文件中维护准确的 frontmatter。
