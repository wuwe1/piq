# DateTime 规则

## 获取当前日期和时间

当任何命令需要当前日期/时间（用于 frontmatter、时间戳或日志）时，你必须从系统获取真实的当前日期/时间，而不是估计或使用占位符值。

### 如何获取当前日期时间

使用 `date` 命令获取当前的 ISO 8601 格式日期时间：

```bash
# 获取 ISO 8601 格式的当前日期时间（在 Linux/Mac 上有效）
date -u +"%Y-%m-%dT%H:%M:%SZ"

# 支持的系统的替代方法
date --iso-8601=seconds

# 对于 Windows（如果使用 PowerShell）
Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
```

### 必需的格式

frontmatter 中的所有日期必须使用 ISO 8601 格式和 UTC 时区：
- 格式：`YYYY-MM-DDTHH:MM:SSZ`
- 示例：`2024-01-15T14:30:45Z`

### 在 Frontmatter 中的用法

在任何文件（PRD、Epic、Task、Progress）中创建或更新 frontmatter 时，始终使用真实的当前日期时间：

```yaml
---
name: feature-name
created: 2024-01-15T14:30:45Z  # 使用 date 命令的实际输出
updated: 2024-01-15T14:30:45Z  # 使用 date 命令的实际输出
---
```

### 实现说明

1. **在写入任何带 frontmatter 的文件之前：**
   - 运行：`date -u +"%Y-%m-%dT%H:%M:%SZ"`
   - 存储输出
   - 在 frontmatter 中使用这个确切的值

2. **对于创建文件的命令：**
   - PRD 创建：对 `created` 字段使用真实日期
   - Epic 创建：对 `created` 字段使用真实日期
   - Task 创建：对 `created` 和 `updated` 字段都使用真实日期
   - 进度跟踪：对 `started` 和 `last_sync` 字段使用真实日期

3. **对于更新文件的命令：**
   - 始终用当前真实日期时间更新 `updated` 字段
   - 保留原始的 `created` 字段
   - 对于同步操作，用真实日期时间更新 `last_sync`

### 示例

**创建新的 PRD：**
```bash
# 首先，获取当前日期时间
CURRENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# 输出：2024-01-15T14:30:45Z

# 然后在 frontmatter 中使用：
---
name: user-authentication
description: User authentication and authorization system
status: backlog
created: 2024-01-15T14:30:45Z  # 使用实际的 $CURRENT_DATE 值
---
```

**更新现有任务：**
```bash
# 获取更新的当前日期时间
UPDATE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 仅更新 'updated' 字段：
---
name: implement-login-api
status: in-progress
created: 2024-01-10T09:15:30Z  # 保留原始值
updated: 2024-01-15T14:30:45Z  # 使用新的 $UPDATE_DATE 值
---
```

### 重要说明

- **永远不要使用占位符日期**，如 `[Current ISO date/time]` 或 `YYYY-MM-DD`
- **永远不要估计日期** - 始终获取实际的系统时间
- **始终使用 UTC**（`Z` 后缀）以保持跨时区的一致性
- **保持时区一致性** - 系统中的所有日期都使用 UTC

### 跨平台兼容性

如果你需要确保跨不同系统的兼容性：

```bash
# 首先尝试主要方法
date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
# 对于没有 -u 标志的系统的回退
date +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
# 最后手段：如果可用则使用 Python
python3 -c "from datetime import datetime; print(datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>/dev/null || \
python -c "from datetime import datetime; print(datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>/dev/null
```

## 规则优先级

此规则具有**最高优先级**，必须被所有以下命令遵循：
- 创建带 frontmatter 的新文件
- 更新带 frontmatter 的现有文件
- 跟踪时间戳或进度
- 记录任何基于时间的信息

受影响的命令：prd-new、prd-parse、epic-decompose、epic-sync、issue-start、issue-sync 以及任何写入时间戳的其他命令。