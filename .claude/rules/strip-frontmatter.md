# Strip Frontmatter

在将内容发送到 GitHub 之前移除 YAML frontmatter 的标准方法。

## 问题

YAML frontmatter 包含不应出现在 GitHub issue 中的内部元数据：
- status、created、updated 字段
- 内部引用和 ID
- 本地文件路径

## 解决方案

使用 sed 从任何 markdown 文件中剥离 frontmatter：

```bash
# 剥离 frontmatter（前两个 --- 行之间的所有内容）
sed '1,/^---$/d; 1,/^---$/d' input.md > output.md
```

这会移除：
1. 开始的 `---` 行
2. 所有 YAML 内容
3. 结束的 `---` 行

## 何时剥离 Frontmatter

在以下情况始终剥离 frontmatter：
- 从 markdown 文件创建 GitHub issue
- 将文件内容作为评论发布
- 向外部用户显示内容
- 同步到任何外部系统

## 示例

### 从文件创建 issue
```bash
# 坏 - 包含 frontmatter
gh issue create --body-file task.md

# 好 - 剥离 frontmatter 并指定仓库
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
REPO=$(echo "$remote_url" | sed 's|.*github.com[:/]||' | sed 's|\.git$||')
[ -z "$REPO" ] && REPO="user/repo"
sed '1,/^---$/d; 1,/^---$/d' task.md > /tmp/clean.md
gh issue create --repo "$REPO" --body-file /tmp/clean.md
```

### 发布评论
```bash
# 发布前剥离 frontmatter
sed '1,/^---$/d; 1,/^---$/d' progress.md > /tmp/comment.md
gh issue comment 123 --body-file /tmp/comment.md
```

### 在循环中
```bash
for file in *.md; do
  # 从每个文件剥离 frontmatter
  sed '1,/^---$/d; 1,/^---$/d' "$file" > "/tmp/$(basename $file)"
  # 使用清理后的版本
done
```

## 替代方法

如果 sed 不可用或你需要更多控制：

```bash
# 使用 awk
awk 'BEGIN{fm=0} /^---$/{fm++; next} fm==2{print}' input.md > output.md

# 使用带行号的 grep
grep -n "^---$" input.md | head -2 | tail -1 | cut -d: -f1 | xargs -I {} tail -n +$(({}+1)) input.md
```

## 重要说明

- 始终先用示例文件测试
- 保持原始文件完整
- 使用临时文件存放清理后的内容
- 某些文件可能没有 frontmatter - 该命令会优雅地处理这种情况