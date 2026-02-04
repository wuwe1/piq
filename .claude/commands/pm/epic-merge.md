---
allowed-tools: Bash, Read, Write
---

# Epic Merge

将已完成的 epic 从 worktree 合并回 main 分支。

## 用法
```
/pm:epic-merge <epic_name>
```

## 快速检查

1. **验证 worktree 存在：**
   ```bash
   git worktree list | grep "epic-$ARGUMENTS" || echo "❌ 未找到 epic 的 worktree：$ARGUMENTS"
   ```

2. **检查活跃的 agent：**
   读取 `.claude/epics/$ARGUMENTS/execution-status.md`
   如果存在活跃的 agent："⚠️ 检测到活跃的 agent。请先停止它们：/pm:epic-stop $ARGUMENTS"

## 说明

### 1. 合并前验证

进入 worktree 并检查状态：
```bash
cd ../epic-$ARGUMENTS

# 检查未提交的更改
if [[ $(git status --porcelain) ]]; then
  echo "⚠️ worktree 中有未提交的更改："
  git status --short
  echo "合并前请提交或暂存更改"
  exit 1
fi

# 检查分支状态
git fetch origin
git status -sb
```

### 2. 运行测试（可选但推荐）

```bash
# 根据项目类型查找测试命令
if [ -f package.json ]; then
  npm test || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f pom.xml ]; then
  mvn test || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  ./gradlew test || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f composer.json ]; then
  ./vendor/bin/phpunit || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f *.sln ] || [ -f *.csproj ]; then
  dotnet test || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f Cargo.toml ]; then
  cargo test || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f go.mod ]; then
  go test ./... || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f Gemfile ]; then
  bundle exec rspec || bundle exec rake test || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f pubspec.yaml ]; then
  flutter test || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f Package.swift ]; then
  swift test || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f CMakeLists.txt ]; then
  cd build && ctest || echo "⚠️ 测试失败。仍要继续？(yes/no)"
elif [ -f Makefile ]; then
  make test || echo "⚠️ 测试失败。仍要继续？(yes/no)"
fi
```

### 3. 更新 Epic 文档

获取当前日期时间：`date -u +"%Y-%m-%dT%H:%M:%SZ"`

更新 `.claude/epics/$ARGUMENTS/epic.md`：
- 将状态设置为 "completed"
- 更新完成日期
- 添加最终摘要

### 4. 尝试合并

```bash
# 返回主仓库
cd {main-repo-path}

# 确保 main 是最新的
git checkout main
git pull origin main

# 尝试合并
echo "正在将 epic/$ARGUMENTS 合并到 main..."
git merge epic/$ARGUMENTS --no-ff -m "Merge epic: $ARGUMENTS

Completed features:
# 生成功能列表
feature_list=""
if [ -d ".claude/epics/$ARGUMENTS" ]; then
  cd .claude/epics/$ARGUMENTS
  for task_file in [0-9]*.md; do
    [ -f "$task_file" ] || continue
    task_name=$(grep '^name:' "$task_file" | cut -d: -f2 | sed 's/^ *//')
    feature_list="$feature_list\n- $task_name"
  done
  cd - > /dev/null
fi

echo "$feature_list"

# 提取 epic issue 编号
epic_github_line=$(grep 'github:' .claude/epics/$ARGUMENTS/epic.md 2>/dev/null || true)
if [ -n "$epic_github_line" ]; then
  epic_issue=$(echo "$epic_github_line" | grep -oE '[0-9]+' || true)
  if [ -n "$epic_issue" ]; then
    echo "\nCloses epic #$epic_issue"
  fi
fi"
```

### 5. 处理合并冲突

如果合并因冲突而失败：
```bash
# 检查冲突状态
git status

echo "
❌ 检测到合并冲突！

冲突文件：
$(git diff --name-only --diff-filter=U)

选项：
1. 手动解决：
   - 编辑冲突文件
   - git add {files}
   - git commit

2. 中止合并：
   git merge --abort

3. 获取帮助：
   /pm:epic-resolve $ARGUMENTS

worktree 保留在：../epic-$ARGUMENTS
"
exit 1
```

### 6. 合并后清理

如果合并成功：
```bash
# 推送到远程
git push origin main

# 清理 worktree
git worktree remove ../epic-$ARGUMENTS
echo "✅ worktree 已删除：../epic-$ARGUMENTS"

# 删除分支
git branch -d epic/$ARGUMENTS
git push origin --delete epic/$ARGUMENTS 2>/dev/null || true

# 本地归档 epic
mkdir -p .claude/epics/archived/
mv .claude/epics/$ARGUMENTS .claude/epics/archived/
echo "✅ Epic 已归档：.claude/epics/archived/$ARGUMENTS"
```

### 7. 更新 GitHub Issues

关闭相关 issues：
```bash
# 从 epic 获取 issue 编号
# 提取 epic issue 编号
epic_github_line=$(grep 'github:' .claude/epics/archived/$ARGUMENTS/epic.md 2>/dev/null || true)
if [ -n "$epic_github_line" ]; then
  epic_issue=$(echo "$epic_github_line" | grep -oE '[0-9]+$' || true)
else
  epic_issue=""
fi

# 关闭 epic issue
gh issue close $epic_issue -c "Epic completed and merged to main"

# 关闭任务 issues
for task_file in .claude/epics/archived/$ARGUMENTS/[0-9]*.md; do
  [ -f "$task_file" ] || continue
  # 提取任务 issue 编号
  task_github_line=$(grep 'github:' "$task_file" 2>/dev/null || true)
  if [ -n "$task_github_line" ]; then
    issue_num=$(echo "$task_github_line" | grep -oE '[0-9]+$' || true)
  else
    issue_num=""
  fi
  if [ ! -z "$issue_num" ]; then
    gh issue close $issue_num -c "Completed in epic merge"
  fi
done
```

### 8. 最终输出

```
✅ Epic 合并成功：$ARGUMENTS

摘要：
  分支：epic/$ARGUMENTS → main
  合并的提交数：{count}
  更改的文件数：{count}
  关闭的 issues：{count}

清理完成：
  ✓ worktree 已删除
  ✓ 分支已删除
  ✓ Epic 已归档
  ✓ GitHub issues 已关闭

后续步骤：
  - 如需要则部署更改
  - 开始新的 epic：/pm:prd-new {feature}
  - 查看已完成的工作：git log --oneline -20
```

## 冲突解决帮助

如果需要解决冲突：
```
epic 分支与 main 有冲突。

这通常发生在以下情况：
- epic 开始后 main 已更改
- 多个 epic 修改了相同的文件
- 依赖已更新

解决方法：
1. 打开冲突文件
2. 查找 <<<<<<< 标记
3. 选择正确的版本或合并
4. 删除冲突标记
5. git add {resolved files}
6. git commit
7. git push

或中止稍后再试：
  git merge --abort
```

## 重要说明

- 始终先检查未提交的更改
- 尽可能在合并前运行测试
- 使用 --no-ff 保留 epic 历史
- 归档而不是删除 epic 数据
- 关闭 GitHub issues 以保持同步