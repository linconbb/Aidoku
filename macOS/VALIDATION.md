# macOS Preview 2 验证记录

本次测试源码：`ae5533a1ad71563919ceb497589dd860b7c3ee28`。

- [成功的云端构建与测试](https://github.com/linconbb/Aidoku/actions/runs/34184052864)
- [DMG artifact](https://github.com/linconbb/Aidoku/actions/runs/34184052864/artifacts/10039946511)
- [构建日志、截图及生成工程](https://github.com/linconbb/Aidoku/actions/runs/34184052864/artifacts/10039946949)

标准 GitHub macOS runner 完成 macOS SDK arm64 Release 构建、ad-hoc signing 和 DMG 打包。DMG 包含 Aidoku.app 与 Applications 链接。本次同步的 Xcode 工程、依赖锁和 ICNS 直接取自该成功构建的诊断 artifact。

DMG SHA-256（已在内存中重新计算并与附带校验文件比对）：

`a627e0267daa8e5697e0130c814dd695d0b574d95bd662cac34b6ad561d8cc14`

## 验证范围

36 项原生运行检查全部通过，完整逐项日志在诊断 artifact 的 build/smoke.log：

- 共享文件名解析、自然排序、CBZ 解码、路径穿越拒绝、本地导入与进度持久化。
- 图标资源解码、bundle 图标声明。
- 单页、双页、连续阅读窗口渲染；双页封面、配对、前后边界、RTL 方向、阅读偏好持久化。
- 页面缓存、过期阅读会话隔离、本地重复导入去重。
- CBZ 导出内容完整且可解码；不支持的文字章节导出失败时保留原目标文件。
- 引擎搜索、分页去重、漫画详情、章节和页面列表。
- 官方 WASM 测试包初始化与 getHome；AIX 安装与更新、停用、停用状态重启持久化、重新启用。

已检查 1000×720 的单页、双页和连续阅读截图。自动化使用测试图片及官方 WASM fixture；不等于逐个验证第三方真实站点，也未覆盖用户实际设备上的全部窗口/手势操作。

本轮没有修改上游 Aidoku/、Aidoku.xcodeproj/、AidokuTests/ 文件，也没有改动已有 SavedBook 持久化字段。本轮未重复运行 iOS baseline；上一轮使用 Xcode 26.3 的 iOS baseline 已通过。手动 workflow 的 verify_ios 输入可再次运行。

## 仍未完成

这仍是原生 macOS 预览版，不是 iOS 功能完整对等版。旧版源 ABI、Cloudflare/网页登录会话、iCloud/Core Data 数据迁移、追踪服务以及完整后台下载队列尚未完成。CBZ 保存是当前章节的前台操作。实际第三方源兼容性需按站点验证。更多用法和限制见 [中文说明](README.zh-CN.md)。

所有本轮源码修改与构建均通过云端仓库/API/Actions 完成，未在用户本地保存工程或下载安装编译依赖。Artifacts 有保留期限，过期后可在 Actions 手动重新构建。
