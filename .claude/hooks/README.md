# Claude Hooks 配置

## Bash Worktree 修复 Hook

此 hook 自动修复在 git worktree 中工作时 Bash 工具的目录重置问题。

### 问题

Bash 工具在每个命令后会重置到主项目目录，这使得在 worktree 中工作时不可能不手动为每个命令添加 `cd /path/to/worktree &&` 前缀。

### 解决方案

pre-tool-use hook 自动检测你是否在 worktree 中，并向所有 Bash 命令注入必要的 `cd` 前缀。

### 工作原理

1. **检测**：在任何 Bash 命令执行之前，hook 检查 `.git` 是文件（worktree）还是目录（主仓库）
2. **注入**：如果在 worktree 中，在命令前添加 `cd /absolute/path/to/worktree && `
3. **透明性**：Agent 不需要知道这一点 - 这是自动发生的

### 配置

添加到你的 `.claude/settings.json`：


```json
{
  "hooks": {
    "pre-tool-use": {
      "Bash": {
        "enabled": true,
        "script": ".claude/hooks/bash-worktree-fix.sh",
        "apply_to_subagents": true
      }
    }
  }
}
```

### 测试

要测试 hook：

```bash
# 启用调试模式
export CLAUDE_HOOK_DEBUG=true

# 在主仓库中测试（应该直接通过）
.claude/hooks/bash-worktree-fix.sh "ls -la"

# 在 worktree 中测试（应该注入 cd）
cd /path/to/worktree
.claude/hooks/bash-worktree-fix.sh "npm install"
# 输出: cd "/path/to/worktree" && npm install
```

### 高级功能

脚本处理：

- 后台进程（`&`）
- 管道命令（`|`）
- 环境变量前缀（`VAR=value command`）
- 已经有 `cd` 的命令
- 使用绝对路径的命令
- 使用 `CLAUDE_HOOK_DEBUG=true` 的调试日志

### 处理的边缘情况

1. **双重前缀预防**：如果命令已经以 `cd` 开头则不会添加前缀
2. **绝对路径**：跳过使用绝对路径的命令的注入
3. **特殊命令**：跳过不需要上下文的 `pwd`、`echo`、`export` 等命令
4. **后台进程**：正确处理命令末尾的 `&`
5. **管道链**：仅在管道链的开头注入

### 故障排除

如果 hook 不工作：

1. **验证 hook 是否可执行：**
   ```bash
   chmod +x .claude/hooks/bash-worktree-fix.sh
   ```

2. **启用调试日志以查看发生了什么：**
   ```bash
   export CLAUDE_HOOK_DEBUG=true
   ```

3. **使用示例命令手动测试 hook：**
   ```bash
   cd /path/to/worktree
   .claude/hooks/bash-worktree-fix.sh "npm test"
   ```

4. **检查你的 settings.json 是否是有效的 JSON：**
   ```bash
   cat .claude/settings.json | python -m json.tool
   ```

### 与 Claude 集成

配置后，此 hook 将：

- 自动应用于所有 Bash 工具调用
- 对主 agent 和子 agent 都有效
- 对用户完全透明
- 消除对 worktree 特定说明的需要

### 结果

有了这个 hook，agent 可以自然地在 worktree 中工作：

**Agent 写入：**

```bash
npm install
git status
npm run build
```

**Hook 转换为：**

```bash
cd /path/to/my/project/epic-feature && npm install
cd /path/to/my/project/epic-feature && git status
cd /path/to/my/project/epic-feature && npm run build
```

**Agent 不需要知道或关心 worktree 上下文！**
