# Health AI

Health AI 是一个以 iOS 客户端 + Next.js 后端为核心的健康数据管理系统，支持设备登录、健康数据同步、报告与 AI 解读。

> 仅用于健康管理与趋势参考，不构成医疗诊断建议。

## 项目简介

Health AI 目标是把分散在多个渠道的健康数据，整合成一个可持续跟踪、可解释、可复盘的个人健康工作台。  
当前项目同时覆盖了：

- **移动端体验**：iOS 客户端支持设备登录、Apple 登录绑定、数据导入、报告查看。
- **数据中台能力**：统一导入、指标标准化、结构化规则分析、报告快照。
- **AI 解读能力**：基于结构化结果生成日/周/月洞察，降低理解门槛。
- **隐私与安全基线**：本地优先存储、敏感字段脱敏、数据导出/删除接口预留。

你可以把它理解为“个人健康数据的操作系统雏形”，不是一次性报表工具，而是长期健康运营的基础设施。

## 核心能力

- **多源健康数据接入**：支持体检、血检、体脂秤、运动等导入与标准化。
- **账号与身份稳定性**：设备身份与账号绑定、主账号收敛、跨服务器一致性治理。
- **健康趋势与报告**：首页总览 + 周报/月报 + 报告详情。
- **主备部署方案**：支持主服务器对外服务，备服务器灾备与定时数据同步。
- **可发布工程化链路**：iOS 构建脚本、TestFlight 上传脚本、部署脚本齐备。

## 快速开始

### 1) 环境要求

- Node.js 22
- npm 10+
- Xcode 16+（iOS 构建）

### 2) 启动后端

```bash
npm install
npm run dev
```

默认地址：`http://localhost:3000`

如需局域网给手机访问：

```bash
npm run dev:lan
```

## iOS 内测安装（开发包）

在 `ios/` 目录构建并安装到真机：

```bash
xcodebuild -project VitalCommandIOS.xcodeproj -scheme VitalCommandIOS -configuration Debug -destination "id=<DEVICE_ID>" -allowProvisioningUpdates build
xcrun devicectl device install app --device <DEVICE_UDID> "build/DerivedDataDeviceLatest/Build/Products/Debug-iphoneos/VitalCommandIOS.app"
```

查看设备列表：

```bash
xcrun devicectl list devices
```

## TestFlight 发布流程

### 1) 更新版本号

- iOS 工程里更新：
  - `MARKETING_VERSION`
  - `CURRENT_PROJECT_VERSION`

### 2) 执行归档与上传

```bash
cd ios
DEVELOPMENT_TEAM=<TEAM_ID> ./build-ipa.sh testflight
```

默认上传配置使用 `ExportOptions-testflight.plist`。

### 3) 常见问题

- 若出现 `No profiles for 'com.xihe.healthai' were found`：
  - 在 Xcode `Signing & Capabilities` 里确认 Team 与 Bundle ID
  - 确认账号下已生成可用 Development/Distribution 证书与 Profile
  - 先在 Xcode GUI 成功 Archive 一次，再回到 CLI 上传

## 目录说明

- `src/`：Web + API + 服务层
- `ios/`：iOS 客户端与共享核心模块
- `migrations/`：数据库迁移脚本
- `scripts/`：部署与运维脚本
- `deploy/`：主备部署与公网接入脚本

## 相关文档

- 部署与公网接入：`deploy/PUBLIC_ACCESS.md`
- 导入标准化：`docs/import-standardization.md`
- 隐私与安全：`docs/privacy-security.md`
- iOS 架构说明：`docs/ios-client-architecture.md`
