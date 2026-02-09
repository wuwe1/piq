# Release

macOS app 完整发布流水线：Archive → Export → DMG → Notarize → Staple → GitHub Release。

## 参数

- `$ARGUMENTS` — 可选，版本号（如 `0.2.0`）。不提供则从 Info.plist 读取当前版本。

## 流程

### 1. 确定版本号

如果提供了版本号参数，先更新 `PIQ/Info.plist` 中的 `CFBundleShortVersionString`。
如果没有提供，从 Info.plist 读取当前版本作为 tag。

### 2. 清理旧产物

```bash
rm -rf /tmp/piq-release/PIQ.xcarchive /tmp/piq-release/export /tmp/piq-release/PIQ.dmg /tmp/piq-release/dmg-staging
mkdir -p /tmp/piq-release
```

### 3. Archive

```bash
xcodebuild archive \
  -project PIQ.xcodeproj \
  -scheme PIQ \
  -configuration Release \
  -archivePath /tmp/piq-release/PIQ.xcarchive
```

如果失败，停止并报告错误。

### 4. Export

需要 ExportOptions.plist（已存在于 `/tmp/piq-release/ExportOptions.plist`）：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>Y5RD58553T</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

如果 ExportOptions.plist 不存在，先创建它，然后：

```bash
xcodebuild -exportArchive \
  -archivePath /tmp/piq-release/PIQ.xcarchive \
  -exportOptionsPlist /tmp/piq-release/ExportOptions.plist \
  -exportPath /tmp/piq-release/export
```

### 5. 创建 DMG

```bash
rm -rf /tmp/piq-release/dmg-staging
mkdir -p /tmp/piq-release/dmg-staging
cp -R /tmp/piq-release/export/PIQ.app /tmp/piq-release/dmg-staging/
ln -s /Applications /tmp/piq-release/dmg-staging/Applications
hdiutil create -volname "PIQ" -srcfolder /tmp/piq-release/dmg-staging -ov -format UDZO /tmp/piq-release/PIQ.dmg
```

### 6. Notarize

```bash
xcrun notarytool submit /tmp/piq-release/PIQ.dmg --keychain-profile "PIQ-notary" --wait
```

如果 keychain profile 不存在，提示用户运行：
```
xcrun notarytool store-credentials "PIQ-notary" --apple-id <email> --team-id Y5RD58553T
```

### 7. Staple

```bash
xcrun stapler staple /tmp/piq-release/PIQ.dmg
```

### 8. GitHub Release（需用户确认）

询问用户是否要创建 GitHub Release。如果确认：

- Tag: `v{version}`
- Title: `PIQ v{version}`
- 从 git log 生成 release notes
- 上传 `/tmp/piq-release/PIQ.dmg`

```bash
gh release create v{version} /tmp/piq-release/PIQ.dmg --title "PIQ v{version}" --notes-file /tmp/release-notes.md
```

## 输出

```
✅ Release v{version} 完成
  - DMG: /tmp/piq-release/PIQ.dmg ({size})
  - Signed: Developer ID Application
  - Notarized: Apple Accepted
  - Stapled: Yes
  - GitHub: {release_url}（如有）
```
