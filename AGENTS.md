# AGENTS.md

## Project Overview

RsUI is a native LOB (Line of Business) application framework built with **Swift on Windows** + **WinUI 3** / **Windows App SDK**. It provides a tabbed multiple window shell with a modular plugin system.

- **Platform**: Windows only (Swift for Windows, NOT Apple Swift)
- **Package manager**: Swift Package Manager (SPM), swift-tools-version 6.3
- **Outputs**: `RsUI` library + `SampleApp` executable
- **Build**: `swift build` | **Run**: `swift run SampleApp` | **Test**: `swift test`

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6.3+ (Windows) |
| UI Framework | WinUI 3 (via swift-winrt WinRT projection) |
| Runtime | Windows App SDK |
| Dependencies | swift-cwinrt → swift-windowsfoundation → swift-uwp → swift-windowsappsdk → swift-winui → swift-cppwinrt, plus RsFoundation |

**Critical distinction**: This is NOT SwiftUI. All UI is built imperatively in Swift by calling WinUI 3 WinRT APIs directly. There are some embeded XAML strings, but no Storyboard, no `{x:Bind}`.

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

- **Comments**: Chinese comments, English code identifiers
- **Code sectioning**: `// MARK: -` comments for logical sections
- **UI construction**: XAML and imperative Swift. Controls usually created programmatically based on XAML string.
- **Event handling**: `addHandler { [weak self] _, args in ... }` with weak capture lists
- **Type casting**: `as? Type` → `let` → safe unwrap chain
- **WinRT calls**: Use `try?` to avoid crashes from COM exceptions
- **Lazy init**: `lazy var` for deferred UI control initialization
- **Preferences**: `PreferenceValue` protocol + `JSONPreferences` for persistence
- **Localization**: `tr()` function + `.xcstrings` localized string files
- **Logging**: RsFoundation's `log.info` / `log.warning`
- **Threading**: UI on MainActor, background via `Task` + `dispatcherQueue`

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
