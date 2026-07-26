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

RsUI 的窗口内容由四个层级组合而成，自下而上依次为 Page → Frame → TabView → MainWindow。当前代码中的 `MainWindow+*` 扩展文件混合承担了 Frame/TabView 的职责，长期重构方向是将这些职责抽成独立的 RsUI 控件，使 MainWindow 退化为纯粹的 NavigationView 容器。

1. **Page（基本页面单元）** — 见 [`Sources/RsUI/Models/Page.swift`](./Sources/RsUI/Models/Page.swift)。每个 Page 的 UI 由 `header` 和 `content`（`UIElement`）两部分构成，加上 `url`、`title` 元信息。Page 是框架内最小的可导航、可渲染单元。

2. **RsUI.Frame（页面栈容器）** — 管理一组 Page 的导航栈。支持在栈内 Back / Forward，并配有转场动画。
   - **不能直接复用 WinUI 的 `Frame`**：WinUI Frame 的导航参数是 `Any?` / WinRT 对象，无法承载 Swift 的 `Page` 协议类型，因此需要自实现一个等价的 RsUI.Frame（当前的 `PageTransitionHost` + `MainWindowTab`（currentPage + back/forward 栈）即其雏形，见 `MainWindowViewModel.swift`）。
   - RsUI.Frame 内部维护当前 Page 的 header/content 渲染、单 parent 重绑定（见 [`UIElement Single-Parent Rule`](#uielement-single-parent-rule)），以及切换时的转场动画。

3. **RsUI.Frame 可放入任意 WinUI 容器** — 例如 `TabView.TabViewItem.content`、`NavigationView.content`、`Grid` 等。它是与具体外壳解耦的可复用控件。

4. **RsUI.TabView（组合 WinUI.TabView + RsUI.Frame）** — WinUI 标准 `TabView` 不符合当前 UI 设计需求（最典型的是：只有一个 Page 时无法自动隐藏 TabStrip）。因此需要一个 RsUI.TabView：内部由 `WinUI.TabView`（仅作为 tab strip）+ 多个 `RsUI.Frame`（每个 tab 一个）组成。
   - 当 Page 数量 ≤ 1 时，自动隐藏 TabViewStrip，仅显示单个 Frame 内容；Page 数量 ≥ 2 时恢复 strip。
   - 当前的实现雏形见 `MainWindow+Tabs.swift` / `MainWindow+TabFrames.swift`：`tabContentHost` 外置于 TabView 之外、以 visibility 切换 frame，正是为这一行为预留的。

5. **MainWindow（标准 NavigationView 窗口）** — 一个标准的带 TitleBar + NavigationView 的窗口。其 NavigationView 的 Content 可以选择以下三种形态之一：
   - **RsUI.Frame** — 单页面栈模式，无 tab。适用于简单模块窗口。
   - **WinUI.TabView（内嵌 RsUI.Frame）** — 直接使用标准 TabView，每个 tab 内容为一个 RsUI.Frame。当标准 TabView 行为已满足需求时使用。
   - **RsUI.TabView** — 组合形态，支持单 Page 自动隐藏 strip。当前 MainWindow 默认形态即此模式的内联实现。

   重构目标：MainWindow 不再内联 Frame/TabView 的实现细节，而是按上述三种模式之一装配 Content，自身只负责 NavigationView、TitleBar、生命周期与窗口级偏好。

> **重构方向提示**：上述 RsUI.Frame 与 RsUI.TabView 在当前代码中尚未作为独立类型存在，而是散落在 `MainWindow+Tabs.swift`、`MainWindow+TabFrames.swift`、`MainWindow+PageRendering.swift`、`MainWindowViewModel.swift` 等文件中。新增 / 重构 UI 时应朝“把它们抽成独立控件”的方向推进，每次抽取须净减少 MainWindow 的字段数与扩展文件数。

## File Organization

```
Sources/RsUI/
  App/
    App.swift                         — Entry point, inherits SwiftApplication
    Launch/                           — Single-instance coordination, taskbar jump list
    MainWindow/                       — Main window (split into extension files)
      MainWindow.swift                — Core properties, lazy UI controls, init
      MainWindow+Content.swift        — Layout assembly, event binding
      MainWindow+Navigation.swift     — Navigation logic, URL route resolution
      MainWindow+Tabs.swift           — TabContext definition, tab CRUD
      MainWindow+TabInteraction.swift — Close / tear-out / detach tabs
      MainWindow+TabFrames.swift      — Tab content frame visibility
      MainWindow+PageRendering.swift  — Page rendering, header layout
      MainWindow+Splitter.swift       — NavigationView drag splitter
      MainWindow+Fullscreen.swift     — Tab fullscreen mode
      MainWindow+WindowLifecycle.swift — Window lifecycle, appearance switching
      MainWindowModels.swift          — WindowPosition / WindowLayout / RoutePreferences
      MainWindowViewModel.swift       — MainWindowTab (nav history), MainWindowViewModel
    Settings/                         — Built-in settings page
  Controls/                           — Reusable UI controls
    SettingsCard.swift / SettingsExpander.swift / SettingsGroup.swift — Fluent-style settings controls
    SettingsBrushes.swift             — Theme-aware brush factory functions
    PageTransitionHost.swift          — Page transition animation container
    NavigationView+Extensions.swift   — NavigationView helpers
    NavigationViewItem+Extensions.swift — NavigationViewItem builder helpers
  Models/                             — Data models
    AppContext.swift                  — Global singleton (theme/language/modules/preferences)
    AppTheme.swift / AppLanguage.swift — Theme and language enums
    Module.swift / Page.swift         — Core protocols
    WindowContext.swift               — Window context (public API)
Samples/SampleApp/                    — Demo app showing framework usage
Tests/RsUITests/                      — Unit tests
```

## Coding Conventions

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
- A `UIElement` can only have one visual parent. Before reparenting, you MUST call `detachFromVisualParent()` to remove it from its current parent. See `MainWindow+PageRendering.swift`.

### Lazy Var Initialization Order
- `navigationView` and other lazy vars depend on `viewModel`. They must be initialized AFTER `viewModel` is assigned (before `setupContent()` triggers them).

### Single-Instance Coordination
- `AppInstanceCoordinator` ensures only one process runs. Taskbar "New Window" redirects activation to the primary instance.

### Tab Tear-Out Currently Disabled
- `tabTearOutEnabled = false` due to two unfixed WinUI bugs (see issue links in `MainWindow.swift`).

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
