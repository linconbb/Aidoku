# macOS Preview 3 验证记录

测试源码：`8ddb6176cee5dcd714c16a7811aab6fab406e069`。

本轮加入官方图标圆角与透明边距、320 × 420 点最小窗口、窄窗口顶部导航与阅读工具栏换行、源首页分区、分类列表、首页筛选入口、分类分页，以及海报墙/列表切换。封面请求使用源提供的请求头和封面处理接口，并使用有容量上限的内存缓存。

验证环境为 GitHub 标准 macOS runner，原生 macOS SDK / arm64 Release / ad-hoc signing。没有在用户本地保存工程或安装编译依赖。本轮未修改上游 iOS 工程和共享源码，未重跑 iOS baseline。

## 检查边界
- 官方 Demo 与 WASM fixture 验证首页、分类与分页；不代表所有第三方漫画网站已经兼容。
- 截图使用固定测试封面，检查 320 点和 900 点宽度的海报布局、320 点阅读工具栏。缓存复用有自动检查，特殊站点的封面请求与处理仍需实站验证。
- 首页各组件统一呈现为海报网格或列表；自动轮播、排行编号、章节摘要和完整筛选编辑器尚未移植。
- 网页登录、Cloudflare、旧 ABI、追踪、iCloud 迁移和完整后台下载队列仍不完整。
- 既有书库持久化字段未变更。升级前退出旧应用，再替换应用。

## 最终结果

[Actions 运行](https://github.com/linconbb/Aidoku/actions/runs/34328823375) 成功，53 项运行检查通过。已检查最终版阅读与海报截图，320 点两列海报、900 点六列海报，阅读工具栏窄窗口换行。

[下载 DMG artifact](https://github.com/linconbb/Aidoku/actions/runs/34328823375/artifacts/10095046644) · [诊断日志与截图](https://github.com/linconbb/Aidoku/actions/runs/34328823375/artifacts/10095047061)

DMG SHA-256（已在内存中重新计算并匹配附带校验文件）：`f8b0bcec5346b45fe8a09c9d4b8b44fd882076b43e9abb84227d4ec6a519af59`。

生成工程、依赖锁和圆角 ICNS 与成功构建的诊断 artifact 同步。DMG 内包含 Aidoku.app 与 Applications 链接。构建使用 ad-hoc 签名，未进行 Developer ID 签名或 notarization。Artifacts 有保留期限，过期后可手动运行 workflow 重新生成。

完整检查日志：
```text
PASS: shared v0.9 chapter parser
PASS: reject invalid source identifiers
PASS: natural page ordering
PASS: CBZ page decoding
PASS: reject archive path traversal
PASS: local import and native reader
PASS: persistent reading progress
PASS: native ICNS resource decodes
PASS: icon has transparent outer corners
PASS: icon rounded corner mask
PASS: icon artwork remains opaque
PASS: bundle declares native app icon
PASS: spread cover displayed alone
PASS: spread pairing after cover
PASS: backward spread navigation
PASS: last spread boundary
PASS: page cache reuses decoded image
PASS: reimport does not duplicate a local book
PASS: CBZ export contains every page
PASS: exported CBZ page decodes
PASS: RTL left arrow advances one spread
PASS: RTL right arrow returns one spread
PASS: reading preferences persist
PASS: reader single renders a full-size window
PASS: reader spread renders a full-size window
PASS: reader continuous renders a full-size window
PASS: reader-narrow requested width
PASS: library-narrow requested width
PASS: old document load cannot overwrite new reader
PASS: demo source home and categories
PASS: category displays manga grid data
PASS: category pagination deduplicates entries
PASS: old category response cannot overwrite new source
PASS: shared engine search through native model
PASS: search pagination deduplicates repeated results
PASS: shared engine manga and chapters
PASS: shared engine page list through native reader
PASS: failed text chapter export preserves destination
PASS: official WASM fixture initialization
PASS: official WASM getHome
PASS: source home loads through native model
PASS: source listings load through native model
PASS: listing opens through native model
PASS: poster cache reuses decoded cover
PASS: browse-narrow requested width
PASS: browse-wide requested width
PASS: browse-list requested width
PASS: changing source clears old browsing content
PASS: AIX package installs through native source manager
PASS: source update replaces without duplicating
PASS: source disable unloads the runtime
PASS: disabled source persists without loading WASM
PASS: source enable restores runtime
ALL NATIVE SMOKE TESTS PASSED
```
