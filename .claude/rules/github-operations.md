# GitHub 操作规则

所有命令中 GitHub CLI 操作的标准模式。

## 关键：仓库保护

**在任何创建/修改 issue 或 PR 的 GitHub 操作之前：**

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

此检查必须在所有以下命令中执行：
- 创建 issue（`gh issue create`）
- 编辑 issue（`gh issue edit`）
- 评论 issue（`gh issue comment`）
- 创建 PR（`gh pr create`）
- 任何其他修改 GitHub 仓库的操作

## 认证

**不要预先检查认证。** 直接运行命令并处理失败：

```bash
gh {command} || echo "❌ GitHub CLI failed. Run: gh auth login"
```

## 常见操作

### 获取 Issue 详情
```bash
gh issue view {number} --json state,title,labels,body
```

### 创建 Issue
```bash
# 始终指定 repo 以避免默认到错误的仓库
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
REPO=$(echo "$remote_url" | sed 's|.*github.com[:/]||' | sed 's|\.git$||')
[ -z "$REPO" ] && REPO="user/repo"
gh issue create --repo "$REPO" --title "{title}" --body-file {file} --label "{labels}"
```

### 更新 Issue
```bash
# 始终先检查 remote origin！
gh issue edit {number} --add-label "{label}" --add-assignee @me
```

### 添加评论
```bash
# 始终先检查 remote origin！
gh issue comment {number} --body-file {file}
```

## 错误处理

如果任何 gh 命令失败：
1. 显示清晰的错误："❌ GitHub operation failed: {command}"
2. 建议修复："Run: gh auth login" 或检查 issue 编号
3. 不要自动重试

## 重要说明

- 在任何 GitHub 写操作之前**始终**检查 remote origin
- 相信 gh CLI 已安装并已认证
- 解析时使用 --json 获取结构化输出
- 保持操作原子性 - 每个动作一个 gh 命令
- 不要预先检查速率限制
