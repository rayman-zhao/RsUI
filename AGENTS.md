# AGENTS.md

## Project Overview

RsUI is a native LOB (Line of Business) application framework built with **Swift on Windows** + **WinUI 3** / **Windows App SDK**. It provides a tabbed multiple window shell with a modular plugin system.

- **Platform**: Windows only (Swift for Windows, NOT Apple Swift)
- **Package manager**: Swift Package Manager (SPM), swift-tools-version 5.10 (see Toolchain Version Note below)
- **Outputs**: `RsUI` library + `SampleApp` executable
- **Build**: `swift build` | **Run**: `swift run SampleApp` | **Test**: `swift test`

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6.3+ (Windows); tools-version pinned to 5.10 for swift-winrt compat, see Toolchain Version Note |
| UI Framework | WinUI 3 (via swift-winrt WinRT projection) |
| Runtime | Windows App SDK |
| Dependencies | swift-cwinrt → swift-windowsfoundation → swift-uwp → swift-windowsappsdk → swift-winui → swift-cppwinrt, plus RsFoundation |

**Critical distinction**: This is NOT SwiftUI. All UI is built imperatively in Swift by calling WinUI 3 WinRT APIs directly. There are some embeded XAML strings, but no Storyboard, no `{x:Bind}`.

### Toolchain Version Note

- `Package.swift` declares `swift-tools-version: 5.10`. This pin is temporary: the swift-winrt projection code currently produces Swift 6 concurrency errors and cannot build under Swift 6 language mode.
- Code outside the UI/projection layer is still expected to follow Swift 6+ conventions (strict concurrency, `Sendable`, `async/await`, structured concurrency). Only the swift-winrt compatibility issue keeps the tools version pinned today.
- Do not treat the `5.10` marker as permission to write pre-Swift-6 code in non-UI / non-projection modules.

## Architecture

```
App (entry point, lifecycle, single-instance, module init)
  └── Module[] (plugin protocol — provides nav items, URL routing, settings)
        └── Page (protocol — url, title, content UIElement)
```

- **`App`** — Entry point. Inherits `SwiftApplication`. Manages app lifecycle, single-instance coordination via `AppInstanceCoordinator`, and module initialization.
- **`Module`** — Plugin protocol. Modules register navigation items, handle URL-based routing (`rs://{moduleId}/{path}`), and contribute settings panels.
- **`Page`** — Represents a displayable page with `url`, `title`, `header`, and `content` (UIElement).
- **`WindowContext`** — Window-scoped service facade. Module code uses this for navigation, tab management, fullscreen, folder picking, etc.
- **`MainWindow`** — Shell window containing NavigationView sidebar + TabView tab strip + content area. Split into multiple extension files by responsibility.
- **`AppContext`** — Global singleton holding theme, language, modules, preferences, and localization.

## Core UI Composition Model

RsUI 的窗口内容由四个层级组合而成，自下而上依次为 Page → Frame → TabView → MainWindow。

1. **Page（基本页面单元）** — 见 [`Sources/RsUI/Models/Page.swift`](./Sources/RsUI/Models/Page.swift)。每个 Page 的 UI 由 `header` 和 `content`（`UIElement`）两部分构成，加上 `url`、`title` 元信息。Page 是框架内最小的可导航、可渲染单元。

2. **`PageFrame`（页面栈容器，即 RsUI.Frame）** — 见 [`Sources/RsUI/App/PageControls/PageFrame.swift`](./Sources/RsUI/App/PageControls/PageFrame.swift)。管理一组 Page 的导航栈，支持在栈内 Back / Forward，并配有转场动画；内部维护当前 Page 的 header/content 渲染、单 parent 重绑定（见 [`UIElement Single-Parent Rule`](#uielement-single-parent-rule)）与转场动画。
   - **不能直接复用 WinUI 的 `Frame`**：WinUI Frame 的导航参数是 `Any?` / WinRT 对象，无法承载 Swift 的 `Page` 协议类型，因此自实现一个等价的 `PageFrame`（`PageTransitionHost` + `MainWindowTab`（currentPage + back/forward 栈），见 `MainWindowViewModel.swift`）。
   - `PageFrame` 是 `Grid` 子类，可放入任意 WinUI 容器（`TabView.TabViewItem.content`、`NavigationView.content`、`Grid` 等），与具体外壳解耦。

3. **`PageTabView`（组合 WinUI.TabView + 共享 PageFrame，即 RsUI.TabView）** — 见 [`Sources/RsUI/App/PageControls/PageTabView.swift`](./Sources/RsUI/App/PageControls/PageTabView.swift)。WinUI 标准 `TabView` 不符合当前 UI 设计需求（最典型的是：只有一个 Page 时无法自动隐藏 TabStrip），故封装之：内部为 `WinUI.TabView`（仅作 tab strip）+ 一个共享的 `PageFrame`，切 tab 时用 `PageFrame.rebind(to:)` 把共享 frame 的 model 重设到目标 `MainWindowTab`。
   - 当 Page 数量 ≤ 1 时整体隐藏 `TabView`（内容靠共享 frame 在 strip 下方显示），单 tab 窗口看起来就是一个普通 `PageFrame`；Page 数量 ≥ 2 时恢复 strip。
   - 原生 tab tear-out 由 `PageTabView.tabTearOutEnabled` 单点控制（见 [`Tab Tear-Out Currently Disabled`](#tab-tear-out-currently-disabled)）。

4. **`PageControl` 协议（`PageFrame` / `PageTabView` 的公共驱动接口）** — 见 [`Sources/RsUI/App/PageControls/PageControl.swift`](./Sources/RsUI/App/PageControls/PageControl.swift)。两者「mutate 后渲染」的语义原本不同（`PageFrame` 的 `navigate/goBack/goForward` 只改 model、由调用方再触发 render；`PageTabView` 的 `*Current` 已内含 render），协议把它们统一到「mutate + 即时渲染」。宿主窗口可持有一个 `any PageControl` 多态驱动，无需关心渲染时机差异。
   - 协议命令用 `pushPage` 而非 `navigate`，避免与 `PageFrame` 本类 `navigate(...)` 的「仅 mutate」方法撞签名。`goBack()` / `goForward()` 用默认 `fromLeft` / `fromRight` 转场。
   - 协议为 `internal`：`MainWindowTab` 是 internal 类型，故 `PageControl` 暂不能 public；当前仅同模块内与 `@testable import` 的测试可执行文件使用。若未来需跨模块暴露，须先把 `MainWindowTab` 提为 public。

5. **MainWindow（标准 NavigationView 窗口）** — 带 TitleBar + NavigationView 的窗口。其 Content 可装配为以下三种形态之一：
   - **`PageFrame`** — 单页面栈模式，无 tab。适用于简单模块窗口。
   - **WinUI.TabView（每个 tab 内嵌一个 `PageFrame`）** — 即 frame-per-tab：一个 tab 一个独立 `PageFrame`（见 `MainWindow+Tabs.swift` 的 `TabContext.frame` 与 `MainWindow+TabFrames.swift` 的 `tabContentHost` 外置 + visibility 切换）。当前 MainWindow 用的就是这个形态**内联实现**，尚未装配 `PageTabView`。
   - **`PageTabView`** — 共享单 frame 形态，单 Page 自动隐藏 strip。控件本身已完成并经 `Tests/PageControlTests/` 验证，但 MainWindow 尚未切换过去。

   重构目标：MainWindow 不再内联 Frame/TabView 的实现细节，而是按上述三种模式之一装配 Content，自身只负责 NavigationView、TitleBar、生命周期与窗口级偏好。当前已抽出 `PageFrame` / `PageTabView` / `PageControl`（shell 职责与渲染已分离，`MainWindow+PageRendering.swift` 已并入 `PageFrame`），下一步是把 MainWindow 从 frame-per-tab 内联实现改为直接装配 `PageTabView`。

6. **`NavigationViewWindow`（窗口壳 XAML-first 构建）** — 见 [`Sources/RsUI/App/Windows/NavigationViewWindow.swift`](./Sources/RsUI/App/Windows/NavigationViewWindow.swift)。`AppearanceWindow` 的子类、`MainWindow` 的父类，负责 TitleBar + NavigationView + 侧栏拖拽 Splitter 这三层窗口壳的构建与生命周期/偏好。当前已改为 **XAML 字符串 + `XamlReader.load` + `findName` 回填 + Swift 事件绑定** 的模式（参照 `Tests/PageControlTests/PageControlTestWindow.swift` 与 `TabViewPageFrameTestWindow.swift`），落地 WinUI Gallery "End to end TitleBar sample" 的 `Grid(Row0=Auto TitleBar, Row1=* NavigationView)` 结构：
   - **静态结构在 XAML**（`shellXAML` 计算属性）：`Grid` 两行、`TitleBar`（含 `TitleBar.Content` 的 Back/Forward Button + 折叠 AutoSuggestBox、`TitleBar.RightHeader` 空占位）、`NavWrapper` 内的 `NavigationView`（`PaneDisplayMode`/`IsSettingsVisible`/`IsTitleBarAutoPaddingEnabled` 等创建期定值）+ 透明 `SplitterBorder` 占位。`swift-winrt` **无 `x:Name` 绑定**，统一以 XAML 默认命名空间的 `Name="..."` 声明，加载后 `findName` 取回。
   - **运行时值与事件在 Swift**：`init` 里 `loadShellFromXAML()` → `applyRuntimeSettings()` → `bindEvents()`。`applyRuntimeSettings()` 回填依赖偏好的 `openPaneLength` / `expandedModeThresholdWidth` / `isPaneOpen`、条件性的 `iconSource`、Back/Forward 按钮的资源画刷 override + `isEnabled`/`allowFocusOnInteraction`、Splitter 的 `margin` + `protectedCursor` + 初始 `visibility`。`bindEvents()` 绑 `paneToggleRequested` / Back/Forward click / `paneClosed`/`paneOpened` / Splitter 的 `pointerPressed/Moved/Released/CaptureLost`。
   - **为什么 Back/Forward 画刷保留 Swift**：原 `makeNavButton` 用 `UWP.Color(a:0x18,...)` 半透明灰手写画刷、既非主题资源也非 Fluent 推荐做法。为不改变行为并控制风险，XAML 只声明按钮结构（`IsEnabled=False`/`AllowFocusOnInteraction=False` 便于回读），画刷资源 override 仍在 Swift 注入。迁移到 `{ThemeResource}` 属独立后续任务。
   - **对外 API 不变**：`titleBar` / `searchBox` / `titleBarRightHeader` / `navigationView` / `navWrapper` / `backButton` / `forwardButton` 依旧暴露（类型与原 `lazy var` 一致，只是从延迟求值改为 `init` 里一次性 `findName` 回填的 IUO），`MainWindow` 及其 extension 的所有访问点（`titleBar.visibility`、`titleBarRightHeader.children.clear/append`、`navigationView.menuItems`、`navWrapper?.visibility`、`backButton.isEnabled` 等）无需改动。`splitterBorder` 仍 `private`。
   - **对未来 window shell 重构的约定**：XAML 表达静态结构 + 命名占位，动态值（运行时算出的长度/阈值/开关）与所有事件用 Swift 在 `findName` 之后回填/绑定；同样适用于未来把 `PageTabView` 装配进 `MainWindow` 时新写的窗口壳 XAML。

## File Organization

```
Sources/RsUI/
  App/
    App.swift                         — Entry point, inherits SwiftApplication
    Windows/
      AppearanceWindow.swift          — Window base class, theme/language observation
      NavigationViewWindow.swift      — TitleBar + NavigationView + Splitter window shell (XAML-first, see Core UI Composition Model §6)
    MainWindow/                       — Main window (split into extension files)
      MainWindow.swift                — Core properties, lazy UI controls, init
      MainWindow+Content.swift        — Layout assembly, event binding
      MainWindow+Navigation.swift     — Navigation logic, URL route resolution
      MainWindow+Tabs.swift           — TabContext definition, tab CRUD (frame-per-tab)
      MainWindow+TabInteraction.swift — Close / tear-out / detach tabs
      MainWindow+TabFrames.swift      — Tab content frame visibility (tabContentHost)
      MainWindow+Fullscreen.swift     — Tab fullscreen mode
      MainWindow+WindowLifecycle.swift — Window lifecycle, appearance switching
      MainWindowModels.swift          — WindowPosition / WindowLayout / RoutePreferences
      MainWindowViewModel.swift       — MainWindowTab (nav history), MainWindowViewModel
    PageControls/                     — Extracted RsUI.Frame / RsUI.TabView (see Core UI Composition Model)
      PageControl.swift               — Shared "mutate + render" protocol for PageFrame / PageTabView
      PageFrame.swift                 — Page-stack container (= RsUI.Frame); owns PageTransitionHost + page view layout
      PageTabView.swift               — WinUI.TabView strip + shared PageFrame (= RsUI.TabView); single-frame strip auto-hide
      PageTransitionHost.swift        — Page transition animation container
    Settings/
      SettingsPage.swift              — Built-in settings page
  Controls/                           — Reusable UI controls
    SettingsCard.swift / SettingsExpander.swift / SettingsGroup.swift — Fluent-style settings controls
    SettingsBrushes.swift             — Theme-aware brush factory functions
  Support/                            — WinRT/WinUI projection helpers (extensions on projected types)
    AppInstance+Extensions.swift      — Single-instance coordination extension
    JumpList+Extensions.swift         — Taskbar jump list extension
    NavigationTransitionInfo+Extensions.swift — Slide/suppress transition factories
    NavigationView+Extensions.swift   — NavigationView helpers
    ProgressBar+Extensions.swift / ProgressRing+Extensions.swift / RuntimeInfo+Extensions.swift / TabView+Extentions.swift — misc helpers
  Models/                             — Data models
    AppContext.swift                  — Global singleton (theme/language/modules/preferences)
    AppTheme.swift / AppLanguage.swift — Theme and language enums
    Module.swift / Page.swift         — Core protocols
    WindowContext.swift               — Window context (public API)
Samples/SampleApp/                    — Demo app showing framework usage
Tests/
  RsUITests/                          — Unit tests
  PageControlTests/                   — GUI test host (executable target): PageControlTestWindow (PageTabView shared-frame),
                                        TabViewPageFrameTestWindow (frame-per-tab), MockPages
```

## Coding Conventions

- **Line Break**: Always use LF (Unix).
- **Comments**: The package is still unstable, so do not require documentation comments (`///`) on public declarations. Do not flag missing doc comments as issues in reviews; focus on naming, labels, logic, and API shape instead. Internal comments (`//`) for non-obvious code are still welcome.
- **Code sectioning**: `// MARK: -` comments for logical sections
- **Projected APIs**: Use the projected APIs in packages of swift-foundation, swift-uwp, swift-windowsappsdk, swift-winui and swift-webview2 for Windows features.
- **UI construction**: XAML and imperative Swift. Controls usually created programmatically based on XAML string.
- **Event handling**: `addHandler { [weak self] _, args in ... }` with weak capture lists
- **Type casting**: `as? Type` → `let` → safe unwrap chain
- **Lazy init**: `lazy var` for deferred UI control initialization
- **Preferences**: `PreferenceValue` protocol + `JSONPreferences` for persistence
- **Localization**: `tr()` function + `.xcstrings` localized string files
- **Logging**: RsFoundation's `log.info` / `log.warning`
- **Threading**: UI on MainActor, background via `Task` + `dispatcherQueue`

### Tooling Constraints

- `swift-format` on Windows still has open issues; do not run it automatically — not as a pre-commit hook, an editor on-save trigger, or a CI step. Apply formatting only by manual invocation at an appropriate point, opportunistically. Until the upstream issues are fixed, treat formatting as a manual step rather than an enforced gate.

### UI & MVVM Conventions

- **Architecture pattern — MVVM**: Follow Model-View-ViewModel. ViewModels are the source of truth for UI state. Mark ViewModel types with `@Observable` (see existing `AppContext` and `MainWindowViewModel`). Use the Swift `Observation` framework: UI observes ViewModel state changes and re-renders in response; in event handler closures, call ViewModel methods rather than mutating UI controls directly.
- **Observation driver**: UI reacts to `@Observable` state through the `Observations` async-sequence helper provided by `RsFoundation`, surfaced via the `startObserving` extension on `Page` (`Page.swift`) and mirrored on `NavigationViewItem` and the `Progress*` controls. Prefer this flow: emit the relevant ViewModel state from the closure, run the update on `MainActor`, and mutate UI only inside the `onChanged` callback.
- **XAML-first UI construction (target direction)**: Prefer building UI from XAML strings loaded with `XamlReader.load`, then find named controls and bind event-handler callbacks in Swift. Avoid long chains of imperative WinUI API calls (`Control()` + property assignment + `children.append`) when the same UI can be expressed compactly in XAML.
- **Current reality vs. the target**: The legacy code still builds most UI imperatively (e.g. `SettingsPage.swift`, `MainWindow+Content.swift`, and several Controls together hold ~46 `children.append` call sites). Treat that as existing tech debt, not a pattern to copy. New and refactored UI should move toward the XAML-string approach where practical; keep a concise imperative fallback only where XAML genuinely cannot express the layout (see `SettingsCard.swift` for a mixed fallback pattern).

### Naming Conventions for Events & Templates

GUI callback and template-method naming follows four distinct rules depending on the API category — do not collapse them into a single "on X Changed" or "X Changed" style.

- **Event-callback closure parameters** (Observation-driven, single handler): the tense suffix is decided by **when the callback fires relative to the change**, not by a fixed "on + noun" rule:
  - Fires **before** the change → `onChange` (about-to-change semantics). Example: `Observation.withObservationTracking(_:onChange:)` invokes the closure before re-running `apply`, so `onChange` is correct.
  - Fires **after** the change → `onChanged` (already-changed semantics). Example: `Page.startObserving(emitting:onChanged:)` is driven by the `Observations` async sequence, so by the time `onChanged` runs the new value is already produced — the `-ed` suffix is therefore correct, not a Windows-ism.
  - Add the observed entity when it aids clarity (`onTabClosed`, `onDocumentLoaded`). For pure "notify me of what I just emitted" drivers, `onChanged` alone is fine.
  - Lifecycle `will`/`did` pairs below obey the same before/after tense rule; prefer them over separate `on`/`onChanged` closures when a protocol models both stages.
- **Delegate / life-cycle methods** (protocol member, `will`/`did` semantics): use `will` for "about to happen" and `did` for "already happened" + past-tense verb, e.g. `tabWillClose(_:)`, `tabDidClose(_:)`, `applicationDidEnterBackground(_:)`. Do NOT use the C# `onClosing`/`onClosed` prefix for Swift delegate protocols — `on` is reserved for the closure-parameter form above.
- **Protocol "provide something" requirements** (template methods returning a value): use a plain noun phrase or noun phrase + context label, with no `Required` / `get` suffix. E.g. `titleBarRightHeaderItem(in:)`, `settingsGroup()`, `navigationViewMenuItems(in:)`. Reserve the `make` prefix for factory methods that construct a new object, e.g. `makePage(for:in:)` (see `IteratorProtocol.makeIterator()`).
- **WinUI event-handler closures**: the event-property name is fixed by the swift-winrt projection (`loaded`, `selectionChanged`, `click`, `sizeChanged`) — do not rename it. Inside `addHandler { ... }`, use the conventional `[weak self] _, args in` capture; the first parameter (`sender`) is usually ignored, so prefer `_` over an unused `sender` label. In the handler body, call ViewModel methods per the MVVM rule above rather than mutating controls directly.

## Important Pitfalls

### Swift on Windows Specifics
- This is NOT Apple Swift. Some toolchain behaviors and available APIs differ.
- All WinUI types are WinRT projections. `HString`, `AnyIVector<Any?>` etc. are projection types, not native Swift types.

### WinRT Identity Instability
- `TabViewItem` identity via `===` is unstable in WinRT projection. Always use `name` property as dictionary key (see `tabContextsByName`).

### COM Callback Exceptions
- Swift exceptions thrown inside COM callback paths do NOT propagate correctly to the main thread. The process won't terminate but UI operations will fail silently.

### UIElement Single-Parent Rule
- A `UIElement` can only have one visual parent. Before reparenting, you MUST remove it from its current parent (`detachFromVisualParent`). The canonical implementation now lives in `PageFrame` (`safelyAssignChild` + `detachFromVisualParent`); `MainWindow` carries the older reparent-on-fullscreen path (see `MainWindow+Fullscreen.swift`).

### Lazy Var Initialization Order
- `navigationView` and other lazy vars depend on `viewModel`. They must be initialized AFTER `viewModel` is assigned (before `setupContent()` triggers them).

### Single-Instance Coordination
- `AppInstanceCoordinator` ensures only one process runs. Taskbar "New Window" redirects activation to the primary instance.

### Tab Tear-Out Currently Disabled
- Native WinUI tab tear-out is gated by `PageTabView.tabTearOutEnabled = false` (the single source of truth — `MainWindow` mirrors it onto its strip via `tabs.canTearOutTabs = PageTabView.tabTearOutEnabled`). Disabled due to two unfixed WinUI bugs (issue links in `PageTabView.swift`). The cross-window tear-out handlers / pending state still live in `MainWindow` (`configureTabTearOutEvents`) and remain gated on the same flag.

### C# Documentation Requires Conversion
- Microsoft's official WinUI docs, samples, and Stack Overflow answers are ALL in C# / XAML. They cannot be used directly in swift-winrt. Key conversions:
  - XAML declarative UI → Swift imperative construction (no `{x:Bind}`, no XAML resource dictionaries)
  - C# PascalCase properties → Swift camelCase (e.g. `IsPaneOpen` → `isPaneOpen`)
  - C# event syntax (`+=`) → Swift `addHandler` closures
  - C# `async/await` → Swift `async/await` (via WinRT projected `IAsyncOperation`)
  - C# `IList<T>` → Swift `AnyIVector<Any?>` projection type
  - You CAN reference C# docs for API discovery, but MUST convert to swift-winrt projection rules when writing code

## Module Development Guide

To create a new module:

1. Implement the `Module` protocol (requires `ExpressibleByEmptyLiteral` conformance)
2. Register the module type in your `App` subclass init: `super.init("Group", "Product", bundle, [YourModule.self])`
3. Use URL routing format: `rs://{moduleId}/{path}`
4. Return `Page` instances from `navigationRequested(for:in:)`
5. Provide navigation menu items via `navigationViewMenuItemsRequired(in:)`
6. Contribute settings via `settingsGroupRequired()`
7. Use `WindowContext` for all navigation operations from page code

## AI-Assisted Development

### Available Skills
- **`winui-design`** — WinUI 3 design guidance: layout, control selection, Fluent Design, theming, accessibility, spacing. Load before authoring new UI or reviewing UI PRs.
- **`winui-code-review`** — WinUI 3 code quality review: MVVM compliance, x:Bind correctness, accessibility, theming, security, performance. Use before committing.

### Documentation Strategy
When encountering WinUI 3 API questions:
1. **First**: Query Microsoft Learn MCP server for official documentation
2. **Remember**: Official docs are C# — apply the conversion rules from the "C# Documentation Requires Conversion" section above
3. **If MCP is unavailable**: Refer to the swift-winrt repository (github.com/thebrowsercompany/swift-winrt) for projection rules
4. **Best reference**: Existing codebase — search for similar patterns first when unsure about usage
