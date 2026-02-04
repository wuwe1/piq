# 路径标准工具

## 概述
此目录包含用于维护项目文档中路径格式标准的工具。

## 可用脚本

### 1. 验证脚本
```bash
./.claude/scripts/check-path-standards.sh
```
**用途**：扫描项目文档以检测路径格式违规
**输出**：显示通过/失败状态的彩色验证报告

### 2. 修复脚本
```bash
./.claude/scripts/fix-path-standards.sh
```
**用途**：自动修复文档中的绝对路径问题
**安全性**：自动创建备份文件，支持回滚

## 使用工作流

### 常规维护
1. **定期检查**：运行 `./check-path-standards.sh`
2. **发现问题时**：运行 `./fix-path-standards.sh`
3. **验证修复**：再次运行验证脚本

### CI/CD 集成
将验证脚本添加到你的 CI 流水线：
```yaml
- name: Path Standards Check
  run: ./.claude/scripts/check-path-standards.sh
```

### 清理备份
确认修复正确后：
```bash
find .claude/ -name '*.backup' -delete
```

## 标准参考
详细的路径使用指南，请参见：`.claude/rules/path-standards.md`