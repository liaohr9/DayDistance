# 日距独立安装版准备

本项目选择 Developer ID 签名、公证的 macOS 独立安装版。当前唯一安装版 `/Applications/日距.app` 仍为 1.3.5/build10 本地 ad hoc 开发版；本指南和预检工具不把它转换为发行版。账户登录、证书和私钥操作、公证提交、实际安装升级及公开发布由所有者在确认后执行。本轮没有执行这些操作。

## 正式配置

主应用与扩展的 `Release` 使用 `Config/Release.xcconfig`：Developer ID Application、Hardened Runtime、禁止注入调试基础 entitlement、shared 存储；保持 macOS 14、仅 Apple Silicon（arm64） 和相同版本。主应用使用 `Config/App.entitlements`，含 sandbox、App Group 及用户选择文件读写权限；组件使用 `Config/Shared.entitlements`，没有文件面板权限。`DebugLocal` 的本地数据路径和签名方式不受此配置影响。`DayDistanceSigned` scheme 的 Debug 配置仅供开发，不用作独立发行。

Release 的 App Group 为 `<真实10位TeamID>.local.daydistance.shared`，取自 `DEVELOPMENT_TEAM`。Apple 允许 macOS 应用使用团队前缀 App Group，不要求注册此组或使用 provisioning profile；本应用仅支持 macOS，也不共享钥匙串，采用此路线。实际签名团队、两份 entitlement 和 Info.plist 的值必须完全一致。若以后增加其他 Apple 平台或共享钥匙串，需另行改用注册的 `group.` 标识并验证 profile；当前预检会拒绝该不同路线。

依据：[Apple App Group 容器](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)、[Developer ID 发行签名](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)、[公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 所有者准备正式产物

先由所有者准备有效 Developer ID Application 身份和对应团队。不要使用测试中的 `A1B2C3D4E5`：它只是配置展开和政策测试夹具，不是本项目的真实团队。正式身份尚未就绪时，可做 `CODE_SIGNING_ALLOWED=NO` 的编译验证；这种产物不可安装发行，预检会拒绝。

以下是供所有者手动执行的归档示例，先填入自己的真实 Team ID。归档和导出都在 `.noindex` 目录，避免 Spotlight 重复应用；不使用 Xcode Run 启动候选。归档使用全新目录，不覆盖现有产物。

```bash
export DEVELOPER_DIR='/Volumes/haoran 1/Applications/Xcode.app/Contents/Developer'
RELEASE_TEAM='填入真实10位TeamID'
xcodebuild -project DayDistance.xcodeproj -scheme DayDistance \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build.noindex/Distribution \
  -archivePath build.noindex/Distribution/DayDistance.xcarchive \
  DEVELOPMENT_TEAM="$RELEASE_TEAM" archive
```

Xcode 可能注册构建/归档中的应用，即使目录不索引。构建结束或失败后，逐一清理候选登记并恢复唯一安装版登记，保留产物供检查，不启动或替换安装版：

```bash
python3 script/install_app.py build.noindex/Distribution/Build/Products/Release/DayDistance.app \
  --destination /Applications/日距.app --cleanup-registration
python3 script/install_app.py build.noindex/Distribution/DayDistance.xcarchive/Products/Applications/DayDistance.app \
  --destination /Applications/日距.app --cleanup-registration
```

归档配置不证明签名成功。使用实际归档 app 执行下方检查；有临时目录例外、调试 entitlement、缺时间戳或错误身份时不能靠改 plist、补 ad hoc 签名或关闭系统保护绕过。若证书、签名或 archive export 的平台要求发生变化，先核对 Xcode 与 Apple 官方文档。

## 预检与本地 ZIP

`script/prepare_release.py` 只读检查签名；可选的 `--package` 仅生成本地 ZIP，不签名、不提交、不 stapler staple、不安装。命令在工程根目录执行。`RELEASE_TEAM` 必须来自真实签名，`RELEASE_APP` 指向上面归档中的真实产物；确保输出文件尚不存在。

```bash
RELEASE_APP='build.noindex/Distribution/DayDistance.xcarchive/Products/Applications/DayDistance.app'
RELEASE_GROUP="$RELEASE_TEAM.local.daydistance.shared"
python3 script/prepare_release.py "$RELEASE_APP" \
  --team "$RELEASE_TEAM" --group "$RELEASE_GROUP" \
  --stage notarization-input \
  --package build.noindex/Distribution/日距-公证输入.zip
```

检查主应用和唯一扩展的实际 Developer ID 证书链与代码标识、团队、所有架构签名、Hardened Runtime、签名时间戳、版本、共享组、沙盒/文件权限；逐架构读取 Mach-O 部署目标，检查嵌套签名并拒绝意外嵌套代码、逃逸链接和调试二进制。主应用和组件的组必须与参数一致，不能依赖本地目录临时例外。

打包先复制到私有 `.noindex` 暂存，检查副本，再由 ditto 压缩、校验 ZIP CRC、解压并重新检查，最后原子创建输出。已有 ZIP 不覆盖；输出不得位于源 app 内，包含符号链接和大小写别名。任何失败返回非零及 JSON `status: blocked`；不会留下标为成功的 ZIP。暂存自动清理。对打包时恶意修改输出祖先或源文件的外部进程不作安全保证；在所有者控制的本地目录使用。

`ready_for_notarization` 仅表示符合本工具的公证输入条件；`distributable` 仍为 false。所有者完成公证并将 ticket staple 到实际 app 后，重新生成最终 ZIP：

```bash
python3 script/prepare_release.py "$RELEASE_APP" \
  --team "$RELEASE_TEAM" --group "$RELEASE_GROUP" \
  --stage distribution \
  --package build.noindex/Distribution/日距-安装包.zip
```

此阶段额外要求 `xcrun stapler validate` 和 `spctl --assess --type execute` 成功。ZIP 本身不作为 staple 对象；必须先对 app 完成票据附加，再压缩。`signature_and_notarization_passed` / `distributable: true` 只表示本工具的签名与公证检查通过，不代表产品全部发布验收完成，也不构成公开发布授权。正式凭证、公证与 Gatekeeper 成功路径尚待实际产物验证。

## 数据与实际验收

先在本地版通过「文件 → 导出事件…」保存副本。正式版使用新的 App Group；通过「导入事件…」迁移 UUID/日期等全部字段，不自动读取开发目录。保留原数据与导出文件；同 ID 冲突拒绝整次导入，不能以旧备份覆盖修改。

更新 `/Applications/日距.app` 前确认无未保存编辑并正常退出。实际签名安装后需验证正式容器保存和导入、干净安装/升级、Gatekeeper 首次打开、受支持系统，以及真实桌面小/中组件的配置 ID、timeline 和可见日期。当前完整桌面像素、正式容器和另一受支持系统仍未验收。详细产品门槛见 `RELEASE_PLAN.md`。

## 回归证据

```bash
DEVELOPER_DIR='/Volumes/haoran 1/Applications/Xcode.app/Contents/Developer' python3 script/test_release.py
```

测试使用临时 universal Mach-O 嵌套 app 和 ad hoc 签名，不依赖已安装应用或用户文件。它验证原生检查/ZIP 解压仍保留严格签名，以及错误条件拒绝；模拟的通过政策事实不能代替真实 Developer ID 成功路径。此回归已接入 `build_and_run.sh` 的构建前检查。验证记录在 `验证记录.md` 与 `Validation/release-gate-*`。

## GitHub 应用内更新（Sparkle 2.10.0）

SPM 固定版本与 Package.resolved 应一并保留。仅主应用链接 Sparkle；构建阶段裁掉框架/安装器的 Intel slice，移除未使用的 Downloader.xpc，再按嵌套顺序重新签名。主应用运行时沙盒保持开启；需要网络 client 与文档要求的两项、固定应用标识的 mach lookup。组件权限不变。该框架处理 ZIP 校验、替换与重启，应用委托在编辑/文件操作期间阻止检查与延后安装。

更新源为 `https://raw.githubusercontent.com/liaohr9/DayDistance/main/appcast.xml`。`SURequireSignedFeed` 和 `SUVerifyUpdateBeforeExtraction` 均开启；不允许自动下载安装。只在应用正常运行时启动，提醒专用后台进程不启动。默认检查周期为一天，开关直接使用 Sparkle 持久化设置。

官方 `generate_keys --account local.daydistance.mac.updates` 已创建本机专用 EdDSA 密钥；私钥留在钥匙串，没有导出到工程。Info.plist 只包含公钥。发布者应自行保管钥匙串备份；不要重新生成一把不同的密钥覆盖公钥，也不要将私钥提交 GitHub。

本地准备示例（不会上传）：

```sh
python3 script/prepare_update.py /Applications/日距.app --preview \
  --tag v1.13.0-preview.1 --sparkle-tools build.noindex/SparkleTools \
  --output ../Release.noindex/DayDistance-1.13.0-preview.1
```

`prepare_update.py` 拒绝覆盖现有输出，检查版本/签名、公钥匹配，创建仅含日距.app 的 ZIP，调用官方 generate_appcast 产生并验证签名更新源、安装包和 UPDATE_INFO.json。正式模式必须先通过 Developer ID/公证/共享容器预检；预览模式要求 local 存储与明确 preview 标签。

经人工发布授权后，先上传 ZIP 到对应 GitHub Release，再将生成的 appcast.xml 原样提交仓库根目录。上传完成和远程 feed 签名验证通过之前，不宣称线上自动更新已启用。每次递增 CFBundleVersion，旧安装包不能复用新签名或版本；修改签名后的 XML/ZIP 必须重新生成。正常更新不应修改 bundle ID、数据路径或 EdDSA 公钥。

本地 ad hoc 沙盒测试不替代互联网下载后的 Gatekeeper、Developer ID、公证与正式 App Group 升级验收。保留正式发布门槛。

当前 `main/appcast.xml` 只用于 local 存储的预览升级。`prepare_update.py` 拒绝把正式 shared/App Group 包推入这个更新源，避免自动升级后事件不可见。正式版须先完成旧数据迁移现场验收并配置独立更新源，不能仅凭正式签名通过就混发。
