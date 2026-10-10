# 构建与发行

## 三种配置

| 配置 | 存储与签名 | 适用范围 |
| --- | --- | --- |
| DebugLocal | 本地共享目录、ad hoc 签名、开发沙盒目录例外 | 无账号本机开发与明确标记的开发预览 |
| Debug | 开发者签名、App Group | 有效团队下的开发验证 |
| Release | Developer ID、Hardened Runtime、团队前缀 App Group | 正式独立发行，需签名与公证 |

开发预览的发布是明确的例外渠道；它没有绕过、修改或宣称通过 `prepare_release.py` 的正式发行门槛。

## v1.8.1-preview.1 实际构建

macOS 27 / Xcode 27.0 (27A266a)，源码版本1.8.1/build24，arm64 + x86_64，最低macOS14。与源码同一快照构建，未打包用户数据或测试夹具。

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project DayDistance.xcodeproj -scheme DayDistance \
  -configuration DebugLocal -destination 'generic/platform=macOS' \
  -derivedDataPath build-preview.noindex \
  SWIFT_OPTIMIZATION_LEVEL=-O ENABLE_TESTABILITY=NO \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO ENABLE_DEBUG_DYLIB=NO build
```

预览去掉调试注入与debug dylib，仍保持App Sandbox和明确的本地目录例外；它**仍然只有ad hoc签名、无Developer ID/公证票据**。ZIP和DMG只封装App，不使其成为已公证软件。

核对本地包：

```bash
codesign --verify --deep --strict build-preview.noindex/Build/Products/DebugLocal/DayDistance.app
lipo -archs build-preview.noindex/Build/Products/DebugLocal/DayDistance.app/Contents/MacOS/DayDistance
```

Xcode会自动登记构建的扩展，构建目录不索引也不能保证没有重复登记。如果已经安装了 `/Applications/日距.app`，构建后可只清理候选登记：

```bash
python3 script/install_app.py build-preview.noindex/Build/Products/DebugLocal/DayDistance.app \
  --destination /Applications/日距.app --cleanup-registration
```

`build_and_run.sh --build-only`不会安装或启动；候选登记清理只在安装版存在时恢复其登记。首次开发也可以直接在Xcode中构建与调试。

## 正式签名与公证

由维护者准备真实Developer ID Application身份与对应10位Team ID。不要将私钥、p12、凭证、签名配置或用户数据提交到仓库。不能用ad hoc重签名、移除票据要求或关闭Gatekeeper代替正式发行。

```bash
RELEASE_TEAM='YOUR_REAL_TEAM_ID'
xcodebuild -project DayDistance.xcodeproj -scheme DayDistance \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build.noindex/Distribution \
  -archivePath build.noindex/Distribution/DayDistance.xcarchive \
  DEVELOPMENT_TEAM="$RELEASE_TEAM" archive
```

正式App Group为 `${RELEASE_TEAM}.local.daydistance.shared`。正式版不依赖开发目录例外，主应用和扩展的容器、entitlement及版本必须一致。

用真实归档执行 `script/prepare_release.py --help`，先以 `--stage notarization-input` 检查，完成Apple公证并staple实际App后，再以 `--stage distribution` 检查。预检会检查两架构签名、证书链、Runtime、时间戳、部署目标、共享组、嵌套代码、票据与Gatekeeper；缺任何必要条件都会拒绝正式打包。

正式Release前还需要实际验证：干净安装、升级与JSON导入迁移、真实App Group读写、桌面组件配置ID/timeline/可见日期、不同受支持系统、后台与通知跨退出送达。开发预览不能替代这些验收。
