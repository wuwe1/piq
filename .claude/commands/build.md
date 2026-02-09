# Build

构建和测试 PIQ Xcode 项目。

## 参数

- `$ARGUMENTS` — 可选，`test` 表示运行测试，不提供则只构建。

## 流程

### 仅构建（默认）

```bash
xcodebuild build \
  -project PIQ.xcodeproj \
  -scheme PIQ \
  -configuration Debug \
  -destination 'platform=macOS'
```

### 构建 + 测试（参数为 `test`）

```bash
xcodebuild test \
  -project PIQ.xcodeproj \
  -scheme PIQ \
  -destination 'platform=macOS'
```

## 输出

成功：
```
✅ Build succeeded（{time}s）
```

或（含测试）：
```
✅ All tests passed（{count} tests in {time}s）
```

失败时提取关键错误信息，给出修复建议。
