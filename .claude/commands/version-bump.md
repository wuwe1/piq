# Version Bump

更新 PIQ 的版本号。

## 参数

- `$ARGUMENTS` — 必填，新版本号（如 `0.2.0`）或递增类型（`major`、`minor`、`patch`）。

## 流程

### 1. 读取当前版本

从 `PIQ/Info.plist` 读取：
- `CFBundleShortVersionString`（显示版本，如 `0.1.0`）
- `CFBundleVersion`（构建号，如 `1`）

### 2. 计算新版本

如果参数是具体版本号（如 `0.2.0`），直接使用。

如果参数是递增类型：
- `major`: `0.1.0` → `1.0.0`
- `minor`: `0.1.0` → `0.2.0`
- `patch`: `0.1.0` → `0.1.1`

构建号 `CFBundleVersion` 始终 +1。

### 3. 更新 Info.plist

使用 Edit 工具更新 `PIQ/Info.plist` 中的两个字段。

### 4. 输出

```
✅ Version bumped
  - Version: {old} → {new}
  - Build: {old_build} → {new_build}
```

不自动 commit，让用户决定何时提交。
