# TestFlight 外部测试发布清单

## 结论先说

- 项目已经在 iOS 工程里声明 `ITSAppUsesNonExemptEncryption = NO`。
- 如果 App Store Connect 里看到的是 `Waiting for Review`、`In Beta Review` 或类似状态，这通常不是“加密合规”卡住，而是外部测试的 `TestFlight App Review`。
- Apple 官方说明：
  - 外部测试需要先有 internal group，再创建 external group，并把 build 加进 group。
  - 同一个版本号一次只能有一个 build 处于 TestFlight App Review。
  - 该版本提交的第一版需要完整评审，后续同版本 build 可能不需要完整评审。

官方参考：

- https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/
- https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds/

## 常见状态怎么判断

### 1) `Missing Compliance` / `Missing Export Compliance`

这是“出口合规/加密申报”问题。

处理方式：

1. 打开对应 build 详情。
2. 完成 export compliance 问卷。
3. 如果你的情况确实属于不使用受限加密，按实际情况填写即可。

补充：

- 本项目已经在包内声明 `ITSAppUsesNonExemptEncryption = NO`，这通常能减少重复提问，但不代表 App Store Connect 永远不会再要求你确认。

### 2) `Waiting for Review` / `In Beta Review`

这是外部测试审核，不是加密问卷。

常见原因：

1. 这是某个版本第一次提交 external testing。
2. External group 的测试说明、反馈邮箱、联系信息还不完整。
3. 该版本已经有一个 build 在 review，中途又想推同版本另一个 build。
4. Apple 还没处理完 Beta App Review 队列。

### 3) `Ready to Test` / `Testing`

说明外部测试已经通过，可以开始：

1. 邮箱邀请外部测试用户。
2. 开启 Public Link。
3. 生成二维码并对外分发。

## 当前项目推荐的发布做法

为了避免继续和旧的卡审 build 纠缠，推荐直接发一个新的外测版本：

- `MARKETING_VERSION`: `1.0.2`
- `CURRENT_PROJECT_VERSION`: `2026041401`

这样做的意义：

1. 让你在 App Store Connect 里更容易分辨“旧 build”和“这次重提的 build”。
2. 避免因为同版本已有 build 在 review，导致后续操作混乱。

## 本地打包命令

在 `ios/` 目录：

```bash
./build-ipa.sh testflight-export
```

作用：

- 归档并导出本地 `.ipa`
- 不自动上传
- 适合你自己在 Xcode Organizer 或 Transporter 里手动点击分发

如果要直接上传：

```bash
./build-ipa.sh testflight
```

作用：

- 归档
- 导出
- 调用 `xcodebuild` 上传到 App Store Connect

## App Store Connect 最短点击路径

### 上传后

1. `App Store Connect` -> `Apps` -> 选择 `Health AI`
2. 打开 `TestFlight`
3. 等待 build 从 `Processing` 变成可选状态
4. 准备一个 `Internal Testing` group
5. 新建或进入一个 `External Testing` group
6. 点击 `Add Builds`
7. 填 `What to Test`
8. 确认 `Feedback Email` 和联系人信息
9. 点击 `Submit Review`

### 通过审核后

可选两种发法：

1. 邮箱邀请
2. `Public Link`

Apple 官方支持这两种方式同时开启。

## 如果旧 build 一直卡着怎么办

优先按下面顺序处理：

1. 先确认旧 build 的精确状态名称。
2. 如果是 `Waiting for Review` / `In Beta Review`：
   - 去 external testing group 检查 `What to Test`、反馈邮箱、联系人信息。
   - 检查是否是该版本第一次 external review。
   - 检查是否同版本已经有一个 build 在 review。
3. 如果是 `Missing Compliance`：
   - 去 build 详情补 export compliance。
4. 如果你想尽快重新走外测：
   - 直接上传新的 `1.0.2 (2026041401)`。
   - 用新版本重新加到 external group 并提交 review。
