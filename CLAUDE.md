# IceReverse — jordanbaird/Ice（macOS 菜单栏管理器）的 macOS 27 适配 fork

## 技术栈
- macOS app，Swift / SwiftUI / AppKit；`Ice.xcodeproj`，scheme `Ice`、`MenuBarItemService`；最低 macOS 14.0；GPL-3.0。
- 本地 SPM（swift-tools 6.0）：`Packages/IceCore`（纯逻辑）、`MenuBarCapture`、`MenuBarDiscovery`（含 MenuBarDetectorFeed）。
- 远程依赖：Sparkle、LaunchAtLogin-Modern、AXSwift、Ifrit、Semaphore。

## 目录地图
- `Ice/`、`MenuBarItemService/`、`Shared/`、`Resources/` — 上游代码；本 fork 只改了 `Ice/` 下少量文件，其余与上游一致。
- `Packages/IceCore`、`MenuBarCapture`、`MenuBarDiscovery` — 本 fork 新增，macOS 27 相关逻辑放这里。
- `Packages/CompactSlider` — vendor 自 1.2.1 加一个补丁，原因与升级条件见其 `VENDORING.md`。
- `docs/macos-27/` — `STATUS.md`（现状）、`FINDINGS.md`（证据）、`probes/`（一次性实验工具，不在任何 Xcode target 里）。
- `docs/plans/` — 按日期的 plan / 协议；`checks/` 是 grep 断言脚本。

## 常用命令
| 用途 | 命令 | 来源 |
|---|---|---|
| Package 测试 | `cd Packages/<Pkg> && swift test --enable-code-coverage --scratch-path <~/Documents 之外的目录>` | docs/plans/2026-09-23-ax-discovery.md |
| Probe 测试 | `cd docs/macos-27/probes/visibility && swift test --scratch-path <~/Documents 之外的目录>`（I7 组约 7 分钟） | docs/plans/2026-09-26-c1-protocol.md |
| 构建 app | `xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath <~/Documents 之外的目录> build` | docs/plans/2026-09-24-ice-first-run.md |
| Probe 工具 | `docs/macos-27/probes/<safewidth|visibility>/build.sh [scratch-dir]` | 各 build.sh |
| Lint | CI 对 `Ice/` 跑 SwiftLint `--strict`（本机未装 swiftlint） | .github/workflows/lint.yml |

## 专案约定
- 构建产物、scratch、DerivedData 一律放在 `~/Documents` 之外：iCloud 会给文件加扩展属性，导致 codesign 拒签（docs/macos-27/probes/README.md）。
- 上游文件风格以 `.swiftlint.yml` 为准：文件头 `//  <文件名>` + `//  Ice`，4 空格缩进，强制 trailing comma，modifier 顺序按配置。
- 现状描述沿用 `docs/macos-27/STATUS.md` 写法：每条标 MEASURED 或 INFERRED，并写明构建号与日期。
- 每个 plan 先写 `docs/plans/YYYY-MM-DD-<topic>.md`，再在 `wip/<topic>` 分支实施。

## 禁区与注意
- 真机实验只用自建的牺牲 helper（bundle id `com.icespike4.target` / `com.icespike4.protected`），不碰我菜单栏上已有的项。
- C1 活体跑要等我指定时间才能开始（docs/plans/2026-09-26-c1-protocol.md）。
- `probes/inject3.swift` 会注入鼠标事件，`axspike2.swift` 会创建并缩放 status item；运行前先读 `probes/README.md` 的 side effects 列。
- `/Applications/Ice.app` 是我的日常版（自 2026-11-13，`io.github.tk88101.Ice`，team `Q6WP7U2GDM`），本地 build 与它共用 bundle id 与偏好域：启动本地 build 前先 export `io.github.tk88101.Ice`，结束后 restore；实验一律用 lab 身份副本（docs/plans/2026-11-13-untested-limits.md 第 5 节）。上游 release 已归档到 `~/Ice-release-archive/`。
- `Packages/MenuBarCapture` 与检测器文件冻结，不改（docs/macos-27/FINDINGS.md；c1-protocol I6 检查项）。
- 截图与含 app 名的输出只放 `~/IceReverse-evidence/<run id>/`，不进仓库（docs/macos-27/probes/README.md）。
- 上游同步策略：TBD（无文档；upstream/main 与 upstream/macos-26 已全部合入）。

## 关联仓库
- 无。上游：jordanbaird/Ice；vendored：buh/CompactSlider。
