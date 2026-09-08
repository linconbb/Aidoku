# Aidoku 原生 macOS 预览版 · 第 2 版

基于 Aidoku v0.9/main，使用 macOS SDK、SwiftUI 与 AppKit。不是 IPA 重打包或 Mac Catalyst。
需要 Apple Silicon、macOS 14 或更新版本。

## 下载与安装

进入 GitHub → Actions → **Native macOS DMG** → 最近成功的运行，
下载 **Aidoku-macOS-arm64** artifact。解压后打开 DMG，把 Aidoku.app 拖到 Applications。
已有第 1 版时退出应用后替换；书库与阅读位置保留。

使用官方 Aidoku 图像生成完整 16–1024 像素的 macOS ICNS，应用包声明并包含 AppIcon.icns。
签名仍为 ad-hoc，没有 Developer ID 或 notarization。
首次启动若被拦截，可核对本 fork 和 SHA-256 后，在系统设置的“隐私与安全性”中允许打开；
无需关闭 Gatekeeper。

## 这一版新增

### 阅读器

- 单页、双页和纵向连续滚动。
- 从左向右 / 从右向左；左右方向键遵循阅读方向。
- 双页可选“封面单独显示”，最后一页与反向翻页有边界处理。
- 适应页面 / 宽度，50%–300% 缩放、双击 100% / 200%、分页模式触控板缩放。
- 页码输入跳转，全屏，上一章 / 下一章，漫画详情中的“继续阅读”。
- 应用级阅读模式、方向、背景与适应方式自动记忆。
- 相邻页预取；解码缓存最多 12 张、目标 128 MB，连续滚动离屏页面释放视图图像。
- 页面错误在对应页面显示，可重试；切换漫画会取消旧请求，避免旧图片覆盖新文档。
- 空格 / Page Down 下一页，Page Up 上一页。可编辑文本框由系统优先处理键盘输入。

连续模式按垂直位置记录进度；长条漫画在该模式下按图片宽度排列。
当前没有 iOS 版的复杂手势映射、双页横图自动拆分或连续阅读自动滚动。

### 源与书库

- 多个源列表，刷新、移除、合并去重并优先显示较新版本。
- 接受新版列表 JSON 和旧式列表 JSON / index.min.json 元数据；
  **旧式列表不等于已支持旧版 WASM ABI**。
- 新格式 AIX 安装、更新、停用、重新启用和移除。
- 更新先验证新包，替换失败时还原原包；停用源在重启后也不会加载 WASM。
- 移除源将包移到废纸篓，书库记录保留，可重新安装源恢复访问。
- 本地漫画重复导入会打开已有记录；新增书库搜索。
- 搜索结果分页去重，切换源时清理旧结果。
- 读取本地 CBZ、ZIP、PDF 和图片文件夹，保存阅读进度。

### 离线保存

阅读器工具栏的下载按钮将**当前章节**保存为 CBZ。
按页取图并显示进度，可取消；完成前不会覆盖目标文件。
保存后用“打开”导入，即可离线阅读。
这还不是 iOS 版的后台下载队列；应用必须保持运行。
文本章节不支持导出为 CBZ，失败或取消时保留目标原文件。

## 云端构建

Actions → Native macOS DMG → Run workflow。
标准 `macos-15` arm64 runner；DMG 保留 7 天，诊断保留 3 天。
默认只重建 macOS；需要再次验证原 iOS 工程时勾选 **verify_ios**，
使用 runner 预装的 Xcode 26.3。此前 iOS 基线已通过，本轮没有修改 iOS 工程或源码。

无需在个人电脑下载源码、Xcode 或构建依赖。若主动选择在装有 Xcode 的 Mac 自行构建：

```sh
bash scripts/build-macos.sh
bash scripts/smoke-macos.sh
```

构建先生成官方图标与独立工程，再 Release 编译、签名、
验证 Mach-O `platform MACOS` 和 arm64，最后创建包含 Aidoku.app 与 Applications 链接的 DMG。
项目和 `Aidoku-macOS` scheme 也提交在仓库中，可直接用 Xcode 打开。
生成器原样引用 v0.9 的源列表模型、SourceInfo、文件名解析、版本比较和 Archive 扩展；
源执行复用固定版本 AidokuRunner。

## 仍未完整移植

| 功能 | 状态 |
| --- | --- |
| 旧版 AIX / legacy WASM ABI | 未接入，显示明确错误 |
| Cloudflare 验证窗口、网页登录和源设置表单 | 未接入；依赖这些功能的源可能无法使用 |
| Komga/Kavita/Suwayomi 内置源 | 未移植 |
| v0.9 Core Data、分类、完整历史和备份迁移 | 未接入；使用独立 JSON 书库 |
| iCloud、追踪器、后台更新和下载队列 | 未移植 |
| OCR/Yomitan、图像增强、Webtoon 自动滚动 | 未移植 |
| 在线 ZIP-backed 页面、EPUB | 未接入 |
| 需自定义请求或后处理的封面 | 封面仍采用基础 AsyncImage，可能无法显示 |
| 真实第三方源兼容性 | 需要逐源验证，不能用演示源通过来代替 |
| 源搜索过滤器和完整设置界面 | 待移植 |

数据保存在 `~/Library/Application Support/app.aidoku.macOS`。
本地漫画通过书签引用原文件；它不读取或覆盖 iOS/iCloud 数据库。

具体实测结果与下载链接见 [验证记录](VALIDATION.md)。
