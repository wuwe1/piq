# Test Execution Rule

所有测试命令运行测试的标准模式。

## 核心原则

1. **始终使用 test-runner agent** - 来自 `.claude/agents/test-runner.md`
2. **禁止 mock** - 使用真实服务以获得准确结果
3. **详细输出** - 捕获所有内容以便调试
4. **优先检查测试结构** - 在假设代码有 bug 之前先检查

## 执行模式

```markdown
Execute tests for: {target}

Requirements:
- Run with verbose output
- No mock services
- Capture full stack traces
- Analyze test structure if failures occur
```

## 输出重点

### 成功
保持简洁：
```
✅ All tests passed ({count} tests in {time}s)
```

### 失败
聚焦于失败内容：
```
❌ Test failures: {count}

{test_name} - {file}:{line}
  Error: {message}
  Fix: {suggestion}
```

## 常见问题

- 找不到测试 → 检查文件路径
- 超时 → 终止进程，报告未完成
- 缺少框架 → 安装依赖

## 清理

测试后始终进行清理：
```bash
# Kill test processes for all supported frameworks
pkill -f "jest|mocha|pytest|phpunit|rspec|ctest" 2>/dev/null || true
pkill -f "mvn.*test|gradle.*test|gradlew.*test" 2>/dev/null || true
pkill -f "dotnet.*test|cargo.*test|go.*test|swift.*test|flutter.*test" 2>/dev/null || true
```

## 重要说明

- 不要并行化测试（避免冲突）
- 让每个测试完整执行
- 报告失败时提供可操作的修复建议
- 输出聚焦于失败，而非成功