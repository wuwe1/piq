---
allowed-tools: Bash, Read, Write, LS
---

# Clean

清理已完成的工作并归档旧的 epic。

## 用法
```
/pm:clean [--dry-run]
```

选项：
- `--dry-run` - 显示将要清理的内容而不实际执行

## 说明

### 1. 识别已完成的 Epic

查找具有以下特征的 epic：
- frontmatter 中 `status: completed`
- 所有任务已关闭
- 最后更新超过 30 天

### 2. 识别过时的工作

查找：
- 已关闭 issue 的进度文件
- 已完成工作的更新目录
- 孤立的任务文件（epic 已删除）
- 空目录

### 3. 显示清理计划

```
🧹 清理计划

待归档的已完成 Epic：
  {epic_name} - {days} 天前完成
  {epic_name} - {days} 天前完成

待删除的过时进度：
  {count} 个已关闭 issue 的进度文件

空目录：
  {list_of_empty_dirs}

可恢复的空间：~{size}KB

{如果 --dry-run}：这是预演。未做任何更改。
{否则}：继续清理？(yes/no)
```

### 4. 执行清理

如果用户确认：

**归档 Epic：**
```bash
mkdir -p .claude/epics/.archived
mv .claude/epics/{completed_epic} .claude/epics/.archived/
```

**删除过时文件：**
- 删除超过 30 天的已关闭 issue 的进度文件
- 删除空的更新目录
- 清理孤立文件

**创建归档日志：**
创建 `.claude/epics/.archived/archive-log.md`：
```markdown
# 归档日志

## {current_date}
- 已归档：{epic_name}（完成于 {date}）
- 已删除：{count} 个过时进度文件
- 已清理：{count} 个空目录
```

### 5. 输出

```
✅ 清理完成

已归档：
  {count} 个已完成的 epic

已删除：
  {count} 个过时文件
  {count} 个空目录

恢复的空间：{size}KB

系统已清理完毕，井然有序。
```

## 重要说明

始终提供 --dry-run 以预览更改。
绝不删除 PRD 或未完成的工作。
保留归档日志以记录历史。