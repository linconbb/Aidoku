# Aidoku 原生 macOS 预览版

基于 Aidoku v0.9/main，新增真正使用 macOS SDK 的 SwiftUI/AppKit 应用。
这是功能尚未齐全的移植预览，不是 IPA 重打包，也不是 Mac Catalyst。

## 下载及安装

在 GitHub → Actions → Native macOS DMG → 成功的运行中下载
`Aidoku-macOS-arm64` artifact。解压后打开 `Aidoku-macOS-arm64.dmg`，
将 Aidoku.app 拖到 Applications。需要 Apple Silicon 和 macOS 14 或更新版本。

应用仅 ad-hoc 签名，没有 Developer ID 和 notarization。
下载后 macOS 可能要求在“系统设置 → 隐私与安全性”中允许打开。
请核对本 fork 和 SHA-256；无需关闭系统 Gatekeeper。

## 云端重新构建

Actions → Native macOS DMG → Run workflow。使用标准 `macos-15` arm64 runner，
不使用付费大型 runner。源代码、Xcode 依赖与编译产物仅位于 GitHub runner，
本机无需安装 Xcode。DMG artifact 保留 7 天，诊断资料保留 3 天。

若主动选择自行在装有 Xcode 的 Mac 上编译：

```sh
bash scripts/build-macos.sh
bash scripts/smoke-macos.sh
```

前一命令生成独立的 `Aidoku-macOS.xcodeproj` 和共享 `Aidoku-macOS` scheme，
执行 Release 编译、签名、Mach-O 平台验证和 DMG 打包。
打包阶段也可单独执行：
`bash scripts/package-macos.sh /path/to/Aidoku.app`。

## 实现范围

- 原生窗口、菜单和打开文件面板；键盘左右键翻页，适应页面/宽度。
- 导入本地 CBZ、ZIP、PDF、图片文件夹，保存书库和阅读位置。
- 安装新版 AIX 源；读取新版 JSON 源列表。
- 复用 AidokuRunner 的搜索、漫画详情、章节和页面接口。
- 原生图片显示、文本页、源自定义图片请求及页面处理接口。
- 原样编译 v0.9 SourceList、ExternalSourceInfo、SourceInfo、
  SemanticVersion、LocalFileNameParser 和 Archive 扩展，无代码副本。
- 新平台代码按 macOS/App、Core、Features 分层。
- iOS target、项目和原有源码不修改。

## 明确尚未完成的兼容性工作

| 功能 | 状态 |
| --- | --- |
| 旧版 AIX / legacy WASM ABI | 未接入；显示明确错误 |
| Cloudflare 验证窗口、网页登录和源设置表单 | 未接入；依赖这些流程的源可能不可用 |
| 自托管 Komga/Kavita/Suwayomi 内置源 | 未移植 |
| v0.9 Core Data 书库、历史、分类、备份迁移 | 未接入；目前使用独立 JSON 书库 |
| iCloud 同步 | 未启用；空 entitlements，不请求 Apple 团队身份 |
| 后台更新、离线下载队列、追踪器 | 未移植 |
| Webtoon 连续阅读、自动滚动、OCR/Yomitan、放大增强 | 未移植 |
| 在线 ZIP-backed 页面和 EPUB | 未接入 |
| 图片封面需要特殊请求/后处理 | 封面使用基础 AsyncImage，可能无法显示 |
| 真实第三方源联网功能 | 实现了接口，但需要逐源实际验证；不保证所有源工作 |
| 重复源更新、源卸载和丰富搜索过滤器 | 待完成 |

本机书库保存在 `~/Library/Application Support/app.aidoku.macOS`。
原始漫画通过书签引用，不复制；移动文件后可能需要重新打开。
它不读取或覆盖现有 iOS/iCloud 数据库。

## 验证

云端 workflow 会执行：
1. Release 编译；验证 arm64 与 Mach-O `platform MACOS`。
2. ad-hoc 签名完整性、DMG 校验。
3. 实际运行应用的 `--smoke-test`：本地 CBZ 解码、自然排序、
   阅读位置保存、压缩包路径穿越拒绝，以及官方 WASM fixture 加载/getHome。
4. 独立的 iOS baseline 编译，输出原工程的构建日志。

具体通过/失败以对应运行日志为准。此文档不等于通过声明。
v0.8.4 仅作为入口、配置和 entitlements 的历史参考；
该版本 macOS LibraryView 实际是 Spacer，不能视为完整旧版桌面实现。
