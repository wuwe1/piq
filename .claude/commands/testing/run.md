---
allowed-tools: Bash, Read, Write, LS, Task
---

# Run Tests

使用已配置的 test-runner agent 执行测试。

## 用法
```
/testing:run [test_target]
```

其中 `test_target` 可以是：
- 空（运行所有测试）
- 测试文件路径
- 测试模式
- 测试套件名称

## 快速检查

```bash
# 检查测试是否已配置
test -f .claude/testing-config.md || echo "❌ 测试未配置。请先运行 /testing:prime"
```

如果提供了测试目标，验证其是否存在：
```bash
# 对于文件目标
test -f "$ARGUMENTS" || echo "⚠️ 未找到测试文件：$ARGUMENTS"
```

## 说明

### 1. 确定测试命令

基于 testing-config.md 和目标：
- 无参数 → 从配置运行完整测试套件
- 文件路径 → 运行特定测试文件
- 模式 → 运行匹配模式的测试

### 2. 执行测试

使用 `.claude/agents/test-runner.md` 中的 test-runner agent：

```markdown
执行测试：$ARGUMENTS（如果为空则为 "all"）

要求：
- 使用详细输出运行以进行调试
- 不使用 mock - 使用真实服务
- 捕获完整输出包括堆栈跟踪
- 如果测试失败，在假设代码问题之前先检查测试结构
```

### 3. 监控执行

- 显示测试进度
- 捕获 stdout 和 stderr
- 记录执行时间

### 4. 报告结果

**成功：**
```
✅ 所有测试通过（{count} 个测试在 {time}s 内）
```

**失败：**
```
❌ 测试失败：{total_count} 个中有 {failed_count} 个

{test_name} - {file}:{line}
  错误：{error_message}
  可能是：{测试问题 | 代码问题}
  修复：{suggestion}

运行更多详情：/testing:run {specific_test}
```

**混合：**
```
测试完成：{passed} 个通过，{failed} 个失败，{skipped} 个跳过

失败：
- {test_1}：{brief_reason}
- {test_2}：{brief_reason}
```

### 5. 清理

```bash
# 终止任何挂起的测试进程
# 终止所有支持框架的测试进程
pkill -f "jest|mocha|pytest|phpunit|rspec|ctest" 2>/dev/null || true
pkill -f "mvn.*test|gradle.*test|gradlew.*test" 2>/dev/null || true
pkill -f "dotnet.*test|cargo.*test|go.*test|swift.*test|flutter.*test" 2>/dev/null || true
```

## 错误处理

- 测试命令失败 → "❌ 测试执行失败：{error}。请检查测试框架是否已安装。"
- 超时 → 终止进程并报告："❌ 测试在 {time}s 后超时"
- 未找到测试 → "❌ 未找到匹配的测试：$ARGUMENTS"

## 重要说明

- 始终使用 test-runner agent 进行分析
- 不使用 mocking - 仅使用真实服务
- 如果发生失败，检查测试结构
- 保持输出专注于失败