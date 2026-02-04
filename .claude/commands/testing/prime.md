---
allowed-tools: Bash, Read, Write, LS
---

# Prime Testing Environment

此命令通过检测测试框架、验证依赖项并配置 test-runner agent 以进行最佳测试执行来准备测试环境。

## 预检清单

在继续之前，完成这些验证步骤。
不要用预检进度打扰用户（"我不会..."）。只需执行它们然后继续。

### 1. 测试框架检测

**JavaScript/Node.js：**
- 检查 package.json 中的测试脚本：`grep -E '"test"|"spec"|"jest"|"mocha"' package.json 2>/dev/null`
- 查找测试配置文件：`ls -la jest.config.* mocha.opts .mocharc.* 2>/dev/null`
- 检查测试目录：`find . -type d \( -name "test" -o -name "tests" -o -name "__tests__" -o -name "spec" \) -maxdepth 3 2>/dev/null`

**Python：**
- 检查 pytest：`find . -name "pytest.ini" -o -name "conftest.py" -o -name "setup.cfg" 2>/dev/null | head -5`
- 检查 unittest：`find . -path "*/test*.py" -o -path "*/test_*.py" 2>/dev/null | head -5`
- 检查 requirements：`grep -E "pytest|unittest|nose" requirements.txt 2>/dev/null`

**Rust：**
- 检查 Cargo 测试：`grep -E '\[dev-dependencies\]' Cargo.toml 2>/dev/null`
- 查找测试模块：`find . -name "*.rs" -exec grep -l "#\[cfg(test)\]" {} \; 2>/dev/null | head -5`

**Go：**
- 检查测试文件：`find . -name "*_test.go" 2>/dev/null | head -5`
- 检查 go.mod 是否存在：`test -f go.mod && echo "找到 Go 模块"`

**PHP：**
- 检查 PHPUnit：`find . -name "phpunit.xml" -o -name "phpunit.xml.dist" -o -name "composer.json" -exec grep -l "phpunit" {} \; 2>/dev/null`
- 检查 Pest：`find . -name "composer.json" -exec grep -l "pestphp/pest" {} \; 2>/dev/null`
- 查找测试目录：`find . -type d \( -name "tests" -o -name "test" \) -maxdepth 3 2>/dev/null`

**C#/.NET：**
- 检查 MSTest/NUnit/xUnit：`find . -name "*.csproj" -exec grep -l -E "Microsoft\.NET\.Test|NUnit|xunit" {} \; 2>/dev/null`
- 检查测试项目：`find . -name "*.csproj" -exec grep -l "<IsTestProject>true</IsTestProject>" {} \; 2>/dev/null`
- 查找解决方案文件：`find . -name "*.sln" 2>/dev/null`

**Java：**
- 检查 JUnit (Maven)：`find . -name "pom.xml" -exec grep -l "junit" {} \; 2>/dev/null`
- 检查 JUnit (Gradle)：`find . -name "build.gradle" -o -name "build.gradle.kts" -exec grep -l -E "junit|testImplementation" {} \; 2>/dev/null`
- 查找测试目录：`find . -path "*/src/test/java" -type d 2>/dev/null`

**Kotlin：**
- 检查 Kotlin 测试：`find . -name "build.gradle.kts" -exec grep -l -E "kotlin.*test|spek" {} \; 2>/dev/null`
- 查找 Kotlin 测试文件：`find . -name "*Test.kt" -o -name "*Spec.kt" 2>/dev/null | head -5`

**Swift：**
- 检查 XCTest：`find . -name "Package.swift" -exec grep -l "XCTest" {} \; 2>/dev/null`
- 检查 Xcode 测试目标：`find . -name "*.xcodeproj" -o -name "*.xcworkspace" 2>/dev/null`
- 查找测试文件：`find . -name "*Test.swift" -o -name "*Tests.swift" 2>/dev/null | head -5`

**Dart/Flutter：**
- 检查 Flutter 测试：`test -f pubspec.yaml && grep -q "flutter_test" pubspec.yaml && echo "找到 Flutter test"`
- 查找测试文件：`find . -name "*_test.dart" 2>/dev/null | head -5`
- 检查测试目录：`test -d test && echo "找到测试目录"`

**C/C++：**
- 检查 GoogleTest：`find . -name "CMakeLists.txt" -exec grep -l -E "gtest|GTest" {} \; 2>/dev/null`
- 检查 Catch2：`find . -name "CMakeLists.txt" -exec grep -l "Catch2" {} \; 2>/dev/null`
- 查找测试文件：`find . -name "*test.cpp" -o -name "*test.c" -o -name "test_*.cpp" 2>/dev/null | head -5`

**Ruby：**
- 检查 RSpec：`find . -name ".rspec" -o -name "spec_helper.rb" 2>/dev/null`
- 检查 Minitest：`find . -name "Gemfile" -exec grep -l "minitest" {} \; 2>/dev/null`
- 查找测试文件：`find . -name "*_spec.rb" -o -name "*_test.rb" 2>/dev/null | head -5`

### 2. 测试环境验证

如果未检测到测试框架：
- 告诉用户："⚠️ 未检测到测试框架。请指定您的测试设置。"
- 询问："我应该使用什么测试命令？示例：
  - Node.js：npm test, pnpm test, yarn test
  - Python：pytest, python -m unittest, poetry run pytest
  - PHP：./vendor/bin/phpunit, composer test
  - Java：mvn test, ./gradlew test
  - C#/.NET：dotnet test
  - Swift：swift test
  - Dart/Flutter：flutter test
  - C/C++：ctest, make test
  - Ruby：bundle exec rspec, rake test
  - Go：go test ./...
  - Rust：cargo test"
- 存储响应以供将来使用

### 3. 依赖项检查

**对于检测到的框架：**
- Node.js：运行 `npm list --depth=0 2>/dev/null | grep -E "jest|mocha|chai|jasmine"`
- Python：运行 `pip list 2>/dev/null | grep -E "pytest|unittest|nose"`
- PHP：运行 `composer show 2>/dev/null | grep -E "phpunit|pestphp"`
- Java (Maven)：运行 `mvn dependency:list 2>/dev/null | grep -E "junit|testng"`
- Java (Gradle)：运行 `./gradlew dependencies --configuration testImplementation 2>/dev/null | grep -E "junit|testng"`
- C#/.NET：运行 `dotnet list package 2>/dev/null | grep -E "Microsoft.NET.Test|NUnit|xunit"`
- Ruby：运行 `bundle list 2>/dev/null | grep -E "rspec|minitest"`
- Dart/Flutter：运行 `flutter pub deps 2>/dev/null | grep flutter_test`
- 验证测试依赖项已安装

如果缺少依赖项：
- 告诉用户："❌ 测试依赖项未安装"
- 建议安装命令：
  - Node.js："npm install" 或 "pnpm install"
  - Python："pip install -r requirements.txt" 或 "poetry install"
  - PHP："composer install"
  - Java (Maven)："mvn clean install"
  - Java (Gradle)："./gradlew build"
  - C#/.NET："dotnet restore"
  - Ruby："bundle install"
  - Dart/Flutter："flutter pub get"
  - Swift："swift package resolve"
  - C/C++："mkdir build && cd build && cmake .. && make"

## 说明

### 1. 框架特定配置

根据检测到的框架，创建测试配置：

#### JavaScript/Node.js (Jest)
```yaml
framework: jest
test_command: npm test
test_directory: __tests__
config_file: jest.config.js
options:
  - --verbose
  - --no-coverage
  - --runInBand
environment:
  NODE_ENV: test
```

#### JavaScript/Node.js (Mocha)
```yaml
framework: mocha
test_command: npm test
test_directory: test
config_file: .mocharc.js
options:
  - --reporter spec
  - --recursive
  - --bail
environment:
  NODE_ENV: test
```

#### Python (Pytest)
```yaml
framework: pytest
test_command: pytest
test_directory: tests
config_file: pytest.ini
options:
  - -v
  - --tb=short
  - --strict-markers
environment:
  PYTHONPATH: .
```

#### Rust
```yaml
framework: cargo
test_command: cargo test
test_directory: tests
config_file: Cargo.toml
options:
  - --verbose
  - --nocapture
environment: {}
```

#### Go
```yaml
framework: go
test_command: go test
test_directory: .
config_file: go.mod
options:
  - -v
  - ./...
environment: {}
```

#### PHP (PHPUnit)
```yaml
framework: phpunit
test_command: ./vendor/bin/phpunit
test_directory: tests
config_file: phpunit.xml
options:
  - --verbose
  - --testdox
environment:
  APP_ENV: testing
```

#### C#/.NET
```yaml
framework: dotnet
test_command: dotnet test
test_directory: .
config_file: *.sln
options:
  - --verbosity normal
  - --logger console
environment: {}
```

#### Java (Maven)
```yaml
framework: maven
test_command: mvn test
test_directory: src/test/java
config_file: pom.xml
options:
  - -Dtest.verbose=true
environment: {}
```

#### Java (Gradle)
```yaml
framework: gradle
test_command: ./gradlew test
test_directory: src/test/java
config_file: build.gradle
options:
  - --info
  - --continue
environment: {}
```

#### Kotlin
```yaml
framework: kotlin
test_command: ./gradlew test
test_directory: src/test/kotlin
config_file: build.gradle.kts
options:
  - --info
environment: {}
```

#### Swift
```yaml
framework: swift
test_command: swift test
test_directory: Tests
config_file: Package.swift
options:
  - --verbose
environment: {}
```

#### Dart/Flutter
```yaml
framework: flutter
test_command: flutter test
test_directory: test
config_file: pubspec.yaml
options:
  - --verbose
environment: {}
```

#### C/C++ (CMake)
```yaml
framework: cmake
test_command: ctest
test_directory: build
config_file: CMakeLists.txt
options:
  - --verbose
  - --output-on-failure
environment: {}
```

#### Ruby (RSpec)
```yaml
framework: rspec
test_command: bundle exec rspec
test_directory: spec
config_file: .rspec
options:
  - --format documentation
  - --color
environment:
  RAILS_ENV: test
```

### 2. 测试发现

扫描测试文件：
- 计算找到的测试文件总数
- 识别使用的测试命名模式
- 注意任何测试工具或辅助程序
- 检查测试 fixture 或数据

```bash
# 按语言的示例：

# JavaScript/TypeScript
find . -path "*/node_modules" -prune -o -name "*.test.js" -o -name "*.spec.js" -o -name "*.test.ts" -o -name "*.spec.ts" | wc -l

# Python
find . -name "test_*.py" -o -name "*_test.py" -o -path "*/tests/*.py" | wc -l

# PHP
find . -path "*/tests/*" -name "*.php" -o -name "*Test.php" | wc -l

# Java/Kotlin
find . -path "*/src/test/*" -name "*Test.java" -o -name "*Test.kt" | wc -l

# C#/.NET
find . -name "*Test.cs" -o -name "*Tests.cs" | wc -l

# Swift
find . -name "*Test.swift" -o -name "*Tests.swift" | wc -l

# Dart/Flutter
find . -name "*_test.dart" | wc -l

# C/C++
find . -name "*test.cpp" -o -name "*test.c" -o -name "test_*.cpp" | wc -l

# Ruby
find . -name "*_spec.rb" -o -name "*_test.rb" | wc -l

# Go
find . -name "*_test.go" | wc -l

# Rust
find . -name "*.rs" -exec grep -l "#\[cfg(test)\]" {} \; | wc -l
```

### 3. 创建 Test Runner 配置

使用发现的信息创建 `.claude/testing-config.md`：

```markdown
---
framework: {detected_framework}
test_command: {detected_command}
created: [使用真实日期时间：date -u +"%Y-%m-%dT%H:%M:%SZ"]
---

# 测试配置

## 框架
- 类型：{framework_name}
- 版本：{framework_version}
- 配置文件：{config_file_path}

## 测试结构
- 测试目录：{test_dir}
- 测试文件：找到 {count} 个文件
- 命名模式：{pattern}

## 命令
- 运行所有测试：`{full_test_command}`
- 运行特定测试：`{specific_test_command}`
- 带调试运行：`{debug_command}`

## 环境
- 必需的 ENV 变量：{list}
- 测试数据库：{如果适用}
- 测试服务器：{如果适用}

## Test Runner Agent 配置
- 使用详细输出进行调试
- 顺序运行测试（不并行）
- 捕获完整的堆栈跟踪
- 不使用 mocking - 使用真实实现
- 等待每个测试完成
```

### 4. 配置 Test-Runner Agent

根据框架准备 agent 上下文：

```markdown
# Test-Runner Agent 配置

## 项目测试设置
- 框架：{framework}
- 测试位置：{directories}
- 总测试数：{count}
- 上次运行：从未

## 执行规则
1. 始终使用 `.claude/agents/test-runner.md` 中的 test-runner agent
2. 使用最大详细程度运行以进行调试
3. 不使用 mock 服务 - 使用真实实现
4. 顺序执行测试 - 不并行执行
5. 捕获完整输出包括堆栈跟踪
6. 如果测试失败，在假设代码问题之前先分析测试结构
7. 报告带上下文的详细失败分析

## 测试命令模板
- 完整套件：`{full_command}`
- 单个文件：`{single_file_command}`
- 模式匹配：`{pattern_command}`
- 监视模式：`{watch_command}`（如果可用）

## 要检查的常见问题
- 环境变量正确设置
- 测试数据库/服务正在运行
- 依赖项已安装
- 正确的文件权限
- 运行之间的清洁测试状态
```

### 5. 验证步骤

配置后：
- 尝试运行简单测试以验证设置
- 检查测试命令是否有效：`{test_command} --version` 或等效命令
- 验证测试文件可被发现
- 确保没有权限问题

### 6. 输出摘要

```
🧪 测试环境已 Prime

🔍 检测结果：
  ✅ 框架：{framework_name} {version}
  ✅ 测试文件：{directories} 中有 {count} 个文件
  ✅ 配置：{config_file}
  ✅ 依赖项：全部已安装

📋 测试结构：
  - 模式：{test_file_pattern}
  - 目录：{test_directories}
  - 工具：{test_helpers}

🤖 Agent 配置：
  ✅ Test-runner agent 已配置
  ✅ 详细输出已启用
  ✅ 顺序执行已设置
  ✅ 真实服务（无 mock）

⚡ 就绪命令：
  - 运行所有测试：/testing:run
  - 运行特定：/testing:run {test_file}
  - 运行模式：/testing:run {pattern}

💡 提示：
  - 始终使用详细输出运行测试
  - 如果测试失败，检查测试结构
  - 使用真实服务，而不是 mock
  - 让每个测试完全完成
```

### 7. 错误处理

**常见问题：**

**未检测到框架：**
- 消息："⚠️ 未找到测试框架"
- 解决方案："请手动指定测试命令"
- 存储用户的响应以供将来使用

**缺少依赖项：**
- 消息："❌ 测试框架未安装"
- 解决方案："首先根据项目类型安装依赖项："
  - Node.js："npm install" 或 "pnpm install"
  - Python："pip install -r requirements.txt" 或 "poetry install"
  - PHP："composer install"
  - Java："mvn clean install" 或 "./gradlew build"
  - C#/.NET："dotnet restore"
  - Ruby："bundle install"
  - Dart/Flutter："flutter pub get"

**无测试文件：**
- 消息："⚠️ 未找到测试文件"
- 解决方案："首先创建测试或检查测试目录位置"

**权限问题：**
- 消息："❌ 无法访问测试文件"
- 解决方案："检查文件权限"

### 8. 保存配置

如果成功，保存配置供将来会话使用：
- 存储在 `.claude/testing-config.md`
- 包括所有发现的设置
- 如果检测到更改，在后续运行时更新

## 重要说明

- **始终检测**而不是假设测试框架
- **验证依赖项**后再声称就绪
- **配置用于调试** - 详细输出至关重要
- **不使用 mocking** - 使用真实服务进行准确测试
- **顺序执行** - 避免并行测试问题
- **存储配置**以保持将来运行的一致性

$ARGUMENTS
