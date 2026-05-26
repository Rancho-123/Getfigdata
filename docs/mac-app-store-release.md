# Getfigdata Mac App Store 发布指南

## 前置准备
- Apple 开发者账号（个人或公司）并加入开发者计划
- 在 App Store Connect 创建 App（平台选择 macOS），Bundle ID 与工程一致：`com.getfigdata.app`
- 在 Xcode 登录账号（`Xcode > Settings > Accounts`），确保可获取证书与描述文件

## 工程设置（已为你完成的部分）
- 已添加沙盒权限文件：`Sources/gfd-app/Getfigdata.entitlements`
  - `com.apple.security.app-sandbox = true`
  - `com.apple.security.files.user-selected.read-write = true`
  - `com.apple.security.automation.apple-events = true`
  - `com.apple.security.device.camera = true`
- 已在 `Getfigdata.xcodeproj` 的 Debug/Release 配置中设置：
  - `CODE_SIGN_ENTITLEMENTS = Sources/gfd-app/Getfigdata.entitlements`
  - 已启用 Hardened Runtime

## 你需要在 Xcode 中确认/补充
- Target: `Getfigdata`
  - Signing & Capabilities：
    - 开启 `App Sandbox` 并检查上述权限是否满足你的真实需求（尽量最小化权限）
    - Team 选择你的开发者团队，`Signing (Release)` 使用 `Apple Distribution` 证书
  - General：
    - `Bundle Identifier`：`com.getfigdata.app`
    - 版本号：`MARKETING_VERSION`（外显版本，例如 1.0.0），`CURRENT_PROJECT_VERSION`（构建号，整数自增）
    - Category（已设置为 Graphics & Design，可按需调整）

## 命令行打包
- 归档与导出脚本：
  - `scripts/build_mac_app_store.sh`（需要 Xcode 安装）
  - 导出配置：`scripts/exportOptions.plist`（`method=app-store`，自动签名）
- 执行：
  - `bash scripts/build_mac_app_store.sh`
  - 产物路径：`build/appstore/`

> 说明：导出 IPA 需要正确的签名与描述文件；若自动签名不可用，请在 `exportOptions.plist` 中填入 `provisioningProfiles` 的实际名称。

## 通过 Xcode 上传
- `Product > Archive` 生成归档
- `Organizer > Distribute App > App Store Connect > Upload`（登录后即可上传）
- 也可使用 `Transporter` 应用上传 IPA

## App Store Connect 配置
- 填写应用名称、副标题、描述、关键字、隐私政策 URL
- 上传截图（支持 13"、14"/15" 等分辨率），App 图标从 `Assets.xcassets` 提供
- 隐私问卷与数据收集声明
- 提交审核

## 测试与审核建议
- 在沙盒权限开启后，逐项验证：文件读写、相机、Apple Events 行为
- 使用 TestFlight（macOS）进行预发布测试
- 确保未使用被拒的私有 API；Metal 与 SwiftUI 均为系统 API 可用

## 若你想发布到 iOS App Store
- 当前工程为 `macOS` 原生应用；要支持 iOS：
- 在工程中新增 `iOS` App Target，复用 `Shared/` 中代码，用条件编译区分 `macOS/iOS`
- 添加 iOS 专用 `Info.plist`、图标与启动画面，调整权限键（如 `NSCameraUsageDescription`）
- 设置签名与打包，使用 `Any iOS Device (Arm64)` 归档并上传到 App Store Connect（iOS 平台）

## 版本号策略
- `MARKETING_VERSION`：用户可见版本（如 `1.0.1`），每次发布需递增
- `CURRENT_PROJECT_VERSION`：构建号（整数），每次提交需递增

## 常见问题
- 无法导出 IPA：检查证书与描述文件是否有效，或改为手动签名
- 被审核拒绝：检查权限声明是否准确、沙盒是否最小化、描述是否清楚并贴合功能

