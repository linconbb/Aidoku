# 云端验证记录

日期：2026-09-08

- 上游基线：`f9836a736ccf477c91df11bbebdafd19086cb9d0`（Aidoku v0.9/main）。
- 实测源码提交：`fae61517eba487c8f289579ea0ea6ed78589f0e1`。
- [完整成功运行](https://github.com/linconbb/Aidoku/actions/runs/34178683934)。
- [DMG 下载 artifact](https://github.com/linconbb/Aidoku/actions/runs/34178683934/artifacts/10038184150)。
- [原生构建与运行日志](https://github.com/linconbb/Aidoku/actions/runs/34178683934/artifacts/10038184383)。
- 后续提交 `a668b14db9ad55b795f437c40af8d52f42311313` 仅将云端生成的项目、scheme 和锁定文件检入仓库；未修改实测 Swift 源码。

## 通过项目

- macOS Release 编译成功。
- 原生 Mach-O：`platform MACOS`；arm64；最低 macOS 14.0；SDK 15.5。
- ad-hoc 签名与严格签名验证成功。
- DMG 创建和 hdiutil 校验成功；内容由 Aidoku.app 与 Applications → /Applications 链接组成。
- 最终 artifact 内 DMG 与 SHA-256 文件匹配。
- iOS 原工程在云端预装 Xcode 26.3 下 Release Simulator 构建成功。
- 相对上游，`Aidoku/`、`Aidoku.xcodeproj/`、`AidokuTests/` 改动为零。

SHA-256（Aidoku-macOS-arm64.dmg）：

```text
dc09d8f541d00bfc93e43fbbe158e4b12b36728d3eac6b4eca658f453e6e13be
```

## 实际应用运行测试：12 项通过

1. v0.9 章节文件名解析。
2. 非法源标识拒绝。
3. 漫画页面自然排序。
4. CBZ 图片解码。
5. AIX 压缩包路径穿越拒绝。
6. 本地漫画导入及原生阅读器。
7. 阅读进度落盘与重新加载。
8. 官方演示源通过原生模型搜索。
9. 官方演示源漫画详情与章节。
10. 官方演示源文本页通过原生阅读器展示。
11. 官方 WASM fixture 初始化。
12. 官方 WASM fixture getHome 调用。

测试在一次性云端目录运行；没有修改用户电脑的书库。

## 验证边界

这是原生 macOS **预览实现**，不是完整 iOS 功能移植。
演示源验证的是引擎与原生界面的数据流；官方 WASM fixture 验证的是源引擎。
尚未针对用户实际使用的第三方源完成真实联网验证，也未验证完整 UI 的人工交互体验。
旧源 ABI、Cloudflare 窗口、源设置/登录、自托管内置源、Core Data/备份迁移、
iCloud、追踪器、下载队列、OCR 等限制见 [使用说明](README.zh-CN.md)。

首次 iOS 检查失败原因是 runner 默认 Xcode 16.4 的 Swift 6.1
无法解析上游要求 Swift 6.2 的依赖；切换预装 Xcode 26.3 后成功。
没有修改 iOS 源码来绕过此问题。
