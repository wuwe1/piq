---
allowed-tools: Bash, Read, Write, LS, Task
---

# Epic Sync

将 epic 和任务作为 issues 推送到 GitHub。

## 用法
```
/pm:epic-sync <feature_name>
```

## 快速检查

```bash
# 验证 epic 存在
test -f .claude/epics/$ARGUMENTS/epic.md || echo "❌ 未找到 Epic。运行：/pm:prd-parse $ARGUMENTS"

# 统计任务文件
ls .claude/epics/$ARGUMENTS/*.md 2>/dev/null | grep -v epic.md | wc -l
```

如果未找到任务："❌ 没有可同步的任务。运行：/pm:epic-decompose $ARGUMENTS"

## 说明

### 0. 检查远程仓库

遵循 `/rules/github-operations.md` 确保不会同步到 CCPM 模板：

```bash
# Check if remote origin is the CCPM template repository
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$remote_url" == *"wuwe1/ccpm"* ]] || [[ "$remote_url" == *"wuwe1/ccpm.git"* ]]; then
  echo "❌ ERROR: You're trying to sync with the CCPM template repository!"
  echo ""
  echo "This repository (wuwe1/ccpm) is a template for others to use."
  echo "You should NOT create issues or PRs here."
  echo ""
  echo "To fix this:"
  echo "1. Fork this repository to your own GitHub account"
  echo "2. Update your remote origin:"
  echo "   git remote set-url origin https://github.com/YOUR_USERNAME/YOUR_REPO.git"
  echo ""
  echo "Or if this is a new project:"
  echo "1. Create a new repository on GitHub"
  echo "2. Update your remote origin:"
  echo "   git remote set-url origin https://github.com/YOUR_USERNAME/YOUR_REPO.git"
  echo ""
  echo "Current remote: $remote_url"
  exit 1
fi
```

### 1. 创建 Epic Issue

#### 首先，检测 GitHub 仓库：
```bash
# Get the current repository from git remote
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
REPO=$(echo "$remote_url" | sed 's|.*github.com[:/]||' | sed 's|\.git$||')
[ -z "$REPO" ] && REPO="user/repo"
echo "Creating issues in repository: $REPO"
```

剥离 frontmatter 并准备 GitHub issue 正文：
```bash
# Extract content without frontmatter
sed '1,/^---$/d; 1,/^---$/d' .claude/epics/$ARGUMENTS/epic.md > /tmp/epic-body-raw.md

# Remove "## Tasks Created" section and replace with Stats
awk '
  /^## Tasks Created/ {
    in_tasks=1
    next
  }
  /^## / && in_tasks {
    in_tasks=0
    # When we hit the next section after Tasks Created, add Stats
    if (total_tasks) {
      print "## Stats"
      print ""
      print "Total tasks: " total_tasks
      print "Parallel tasks: " parallel_tasks " (can be worked on simultaneously)"
      print "Sequential tasks: " sequential_tasks " (have dependencies)"
      if (total_effort) print "Estimated total effort: " total_effort " hours"
      print ""
    }
  }
  /^Total tasks:/ && in_tasks { total_tasks = $3; next }
  /^Parallel tasks:/ && in_tasks { parallel_tasks = $3; next }
  /^Sequential tasks:/ && in_tasks { sequential_tasks = $3; next }
  /^Estimated total effort:/ && in_tasks {
    gsub(/^Estimated total effort: /, "")
    total_effort = $0
    next
  }
  !in_tasks { print }
  END {
    # If we were still in tasks section at EOF, add stats
    if (in_tasks && total_tasks) {
      print "## Stats"
      print ""
      print "Total tasks: " total_tasks
      print "Parallel tasks: " parallel_tasks " (can be worked on simultaneously)"
      print "Sequential tasks: " sequential_tasks " (have dependencies)"
      if (total_effort) print "Estimated total effort: " total_effort
    }
  }
' /tmp/epic-body-raw.md > /tmp/epic-body.md

# Determine epic type (feature vs bug) from content
if grep -qi "bug\|fix\|issue\|problem\|error" /tmp/epic-body.md; then
  epic_type="bug"
else
  epic_type="feature"
fi

# Create epic issue with labels
epic_number=$(gh issue create \
  --repo "$REPO" \
  --title "Epic: $ARGUMENTS" \
  --body-file /tmp/epic-body.md \
  --label "epic,epic:$ARGUMENTS,$epic_type" \
  --json number -q .number)
```

保存返回的 issue 编号用于更新 epic frontmatter。

### 2. 创建任务子 Issues

检查 gh-sub-issue 是否可用：
```bash
if gh extension list | grep -q "yahsan2/gh-sub-issue"; then
  use_subissues=true
else
  use_subissues=false
  echo "⚠️ gh-sub-issue not installed. Using fallback mode."
fi
```

统计任务文件以确定策略：
```bash
task_count=$(ls .claude/epics/$ARGUMENTS/[0-9][0-9][0-9].md 2>/dev/null | wc -l)
```

### 小批量（< 5 个任务）：顺序创建

```bash
if [ "$task_count" -lt 5 ]; then
  # Create sequentially for small batches
  for task_file in .claude/epics/$ARGUMENTS/[0-9][0-9][0-9].md; do
    [ -f "$task_file" ] || continue

    # Extract task name from frontmatter
    task_name=$(grep '^name:' "$task_file" | sed 's/^name: *//')

    # Strip frontmatter from task content
    sed '1,/^---$/d; 1,/^---$/d' "$task_file" > /tmp/task-body.md

    # Create sub-issue with labels
    if [ "$use_subissues" = true ]; then
      task_number=$(gh sub-issue create \
        --parent "$epic_number" \
        --title "$task_name" \
        --body-file /tmp/task-body.md \
        --label "task,epic:$ARGUMENTS" \
        --json number -q .number)
    else
      task_number=$(gh issue create \
        --repo "$REPO" \
        --title "$task_name" \
        --body-file /tmp/task-body.md \
        --label "task,epic:$ARGUMENTS" \
        --json number -q .number)
    fi

    # Record mapping for renaming
    echo "$task_file:$task_number" >> /tmp/task-mapping.txt
  done

  # After creating all issues, update references and rename files
  # This follows the same process as step 3 below
fi
```

### 大批量：并行创建

```bash
if [ "$task_count" -ge 5 ]; then
  echo "Creating $task_count sub-issues in parallel..."

  # Check if gh-sub-issue is available for parallel agents
  if gh extension list | grep -q "yahsan2/gh-sub-issue"; then
    subissue_cmd="gh sub-issue create --parent $epic_number"
  else
    subissue_cmd="gh issue create --repo \"$REPO\""
  fi

  # Batch tasks for parallel processing
  # Spawn agents to create sub-issues in parallel with proper labels
  # Each agent must use: --label "task,epic:$ARGUMENTS"
fi
```

使用 Task 工具进行并行创建：
```yaml
Task:
  description: "Create GitHub sub-issues batch {X}"
  subagent_type: "general-purpose"
  prompt: |
    Create GitHub sub-issues for tasks in epic $ARGUMENTS
    Parent epic issue: #$epic_number

    Tasks to process:
    - {list of 3-4 task files}

    For each task file:
    1. Extract task name from frontmatter
    2. Strip frontmatter using: sed '1,/^---$/d; 1,/^---$/d'
    3. Create sub-issue using:
       - If gh-sub-issue available:
         gh sub-issue create --parent $epic_number --title "$task_name" \
           --body-file /tmp/task-body.md --label "task,epic:$ARGUMENTS"
       - Otherwise: 
         gh issue create --repo "$REPO" --title "$task_name" --body-file /tmp/task-body.md \
           --label "task,epic:$ARGUMENTS"
    4. Record: task_file:issue_number

    IMPORTANT: Always include --label parameter with "task,epic:$ARGUMENTS"

    Return mapping of files to issue numbers.
```

整合并行 agents 的结果：
```bash
# Collect all mappings from agents
cat /tmp/batch-*/mapping.txt >> /tmp/task-mapping.txt

# IMPORTANT: After consolidation, follow step 3 to:
# 1. Build old->new ID mapping
# 2. Update all task references (depends_on, conflicts_with)
# 3. Rename files with proper frontmatter updates
```

### 3. 重命名任务文件并更新引用

首先，构建旧编号到新 issue ID 的映射：
```bash
# Create mapping from old task numbers (001, 002, etc.) to new issue IDs
> /tmp/id-mapping.txt
while IFS=: read -r task_file task_number; do
  # Extract old number from filename (e.g., 001 from 001.md)
  old_num=$(basename "$task_file" .md)
  echo "$old_num:$task_number" >> /tmp/id-mapping.txt
done < /tmp/task-mapping.txt
```

然后重命名文件并更新所有引用：
```bash
# Process each task file
while IFS=: read -r task_file task_number; do
  new_name="$(dirname "$task_file")/${task_number}.md"

  # Read the file content
  content=$(cat "$task_file")

  # Update depends_on and conflicts_with references
  while IFS=: read -r old_num new_num; do
    # Update arrays like [001, 002] to use new issue numbers
    content=$(echo "$content" | sed "s/\b$old_num\b/$new_num/g")
  done < /tmp/id-mapping.txt

  # Write updated content to new file
  echo "$content" > "$new_name"

  # Remove old file if different from new
  [ "$task_file" != "$new_name" ] && rm "$task_file"

  # Update github field in frontmatter
  # Add the GitHub URL to the frontmatter
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  github_url="https://github.com/$repo/issues/$task_number"

  # Update frontmatter with GitHub URL and current timestamp
  current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Use sed to update the github and updated fields
  sed -i.bak "/^github:/c\github: $github_url" "$new_name"
  sed -i.bak "/^updated:/c\updated: $current_date" "$new_name"
  rm "${new_name}.bak"
done < /tmp/task-mapping.txt
```

### 4. 用任务列表更新 Epic（仅回退方案）

如果没有使用 gh-sub-issue，将任务列表添加到 epic：

```bash
if [ "$use_subissues" = false ]; then
  # Get current epic body
  gh issue view ${epic_number} --json body -q .body > /tmp/epic-body.md

  # Append task list
  cat >> /tmp/epic-body.md << 'EOF'

  ## Tasks
  - [ ] #${task1_number} ${task1_name}
  - [ ] #${task2_number} ${task2_name}
  - [ ] #${task3_number} ${task3_name}
  EOF

  # Update epic issue
  gh issue edit ${epic_number} --body-file /tmp/epic-body.md
fi
```

使用 gh-sub-issue 时，这是自动的！

### 5. 更新 Epic 文件

用 GitHub URL、时间戳和真实任务 ID 更新 epic 文件：

#### 5a. 更新 Frontmatter
```bash
# Get repo info
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
epic_url="https://github.com/$repo/issues/$epic_number"
current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Update epic frontmatter
sed -i.bak "/^github:/c\github: $epic_url" .claude/epics/$ARGUMENTS/epic.md
sed -i.bak "/^updated:/c\updated: $current_date" .claude/epics/$ARGUMENTS/epic.md
rm .claude/epics/$ARGUMENTS/epic.md.bak
```

#### 5b. 更新已创建任务部分
```bash
# Create a temporary file with the updated Tasks Created section
cat > /tmp/tasks-section.md << 'EOF'
## Tasks Created
EOF

# Add each task with its real issue number
for task_file in .claude/epics/$ARGUMENTS/[0-9]*.md; do
  [ -f "$task_file" ] || continue

  # Get issue number (filename without .md)
  issue_num=$(basename "$task_file" .md)

  # Get task name from frontmatter
  task_name=$(grep '^name:' "$task_file" | sed 's/^name: *//')

  # Get parallel status
  parallel=$(grep '^parallel:' "$task_file" | sed 's/^parallel: *//')

  # Add to tasks section
  echo "- [ ] #${issue_num} - ${task_name} (parallel: ${parallel})" >> /tmp/tasks-section.md
done

# Add summary statistics
total_count=$(ls .claude/epics/$ARGUMENTS/[0-9]*.md 2>/dev/null | wc -l)
parallel_count=$(grep -l '^parallel: true' .claude/epics/$ARGUMENTS/[0-9]*.md 2>/dev/null | wc -l)
sequential_count=$((total_count - parallel_count))

cat >> /tmp/tasks-section.md << EOF

Total tasks: ${total_count}
Parallel tasks: ${parallel_count}
Sequential tasks: ${sequential_count}
EOF

# Replace the Tasks Created section in epic.md
# First, create a backup
cp .claude/epics/$ARGUMENTS/epic.md .claude/epics/$ARGUMENTS/epic.md.backup

# Use awk to replace the section
awk '
  /^## Tasks Created/ {
    skip=1
    while ((getline line < "/tmp/tasks-section.md") > 0) print line
    close("/tmp/tasks-section.md")
  }
  /^## / && !/^## Tasks Created/ { skip=0 }
  !skip && !/^## Tasks Created/ { print }
' .claude/epics/$ARGUMENTS/epic.md.backup > .claude/epics/$ARGUMENTS/epic.md

# Clean up
rm .claude/epics/$ARGUMENTS/epic.md.backup
rm /tmp/tasks-section.md
```

### 6. 创建映射文件

创建 `.claude/epics/$ARGUMENTS/github-mapping.md`：
```bash
# Create mapping file
cat > .claude/epics/$ARGUMENTS/github-mapping.md << EOF
# GitHub Issue Mapping

Epic: #${epic_number} - https://github.com/${repo}/issues/${epic_number}

Tasks:
EOF

# Add each task mapping
for task_file in .claude/epics/$ARGUMENTS/[0-9]*.md; do
  [ -f "$task_file" ] || continue

  issue_num=$(basename "$task_file" .md)
  task_name=$(grep '^name:' "$task_file" | sed 's/^name: *//')

  echo "- #${issue_num}: ${task_name} - https://github.com/${repo}/issues/${issue_num}" >> .claude/epics/$ARGUMENTS/github-mapping.md
done

# Add sync timestamp
echo "" >> .claude/epics/$ARGUMENTS/github-mapping.md
echo "Synced: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> .claude/epics/$ARGUMENTS/github-mapping.md
```

### 7. 创建 Worktree

遵循 `/rules/worktree-operations.md` 创建开发 worktree：

```bash
# Ensure main is current
git checkout main
git pull origin main

# Create worktree for epic
git worktree add ../epic-$ARGUMENTS -b epic/$ARGUMENTS

echo "✅ Created worktree: ../epic-$ARGUMENTS"
```

### 8. 输出

```
✅ 已同步到 GitHub
  - Epic：#{epic_number} - {epic_title}
  - 任务：创建了 {count} 个子 issues
  - 已应用标签：epic、task、epic:{name}
  - 文件已重命名：001.md → {issue_id}.md
  - 引用已更新：depends_on/conflicts_with 现在使用 issue ID
  - Worktree：../epic-$ARGUMENTS

后续步骤：
  - 开始并行执行：/pm:epic-start $ARGUMENTS
  - 或处理单个 issue：/pm:issue-start {issue_number}
  - 查看 epic：https://github.com/{owner}/{repo}/issues/{epic_number}
```

## 错误处理

遵循 `/rules/github-operations.md` 处理 GitHub CLI 错误。

如果任何 issue 创建失败：
- 报告成功的内容
- 记录失败的内容
- 不要尝试回滚（部分同步没问题）

## 重要说明

- 信任 GitHub CLI 认证
- 不要预先检查重复
- 仅在成功创建后更新 frontmatter
- 保持操作简单和原子化
