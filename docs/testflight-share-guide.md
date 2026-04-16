# TestFlight 公共链接与二维码分享指南

## 目标

让用户无需邮箱邀请，直接通过链接或二维码加入 TestFlight 内测。

如果当前 build 还在 `Waiting for Review` 或 `In Beta Review`，先看：

- [TestFlight 外部测试发布清单](/Users/xmly/Projects/HealthAI/docs/testflight-release-checklist.md)

## 第一步：在 App Store Connect 开启 Public Link

1. 进入 `App Store Connect` -> `TestFlight` -> 你的 App。
2. 选择目标测试组（建议外部测试组）。
3. 在该测试组页面开启 `Public Link`。
4. 复制生成的链接，格式通常为：

```text
https://testflight.apple.com/join/XXXXXXX
```

> 备注：如果构建仍在审核中，用户能看到链接但可能暂时不能安装，需等待 Beta 审核通过。

## 第二步：本地生成二维码（自动）

在项目根目录执行：

```bash
python3 scripts/generate_testflight_qr.py "https://testflight.apple.com/join/XXXXXXX"
```

默认输出：

- `output/testflight-public-link-qr.png`

可自定义大小/输出位置：

```bash
python3 scripts/generate_testflight_qr.py "https://testflight.apple.com/join/XXXXXXX" --size 800 --output output/tf-qr-v1.0.2.png
```

## 建议的用户分享文案（可直接复制）

```text
Health AI iOS 内测邀请

1) iPhone 先安装 Apple 官方 TestFlight App
2) 点击链接或扫码加入：
https://testflight.apple.com/join/XXXXXXX
3) 打开 TestFlight 后点击“安装/更新”

如果看得到版本但暂时无法安装，通常是该构建仍在 TestFlight 审核处理中，请稍后再试。
```
