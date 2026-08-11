# RsUI

A native LOB (Line of Business) application framework built with **Swift on Windows** and **WinUI 3 / Windows App SDK**. RsUI gives you a tabbed, multi-window shell with a sidebar + title bar, a URL-based navigation model, and a small plugin system — so you can write the actual app as one or more `Module`s and let the framework own the window chrome, tabs, settings, and theming.

<img width="2491" height="1619" alt="image" src="https://github.com/user-attachments/assets/beeb0529-88d6-40bf-bb7c-e82c8e0473a2" />

> **Not SwiftUI.** All UI is constructed imperatively in Swift by calling WinUI 3 WinRT projection APIs (via [swift-winrt](https://github.com/thebrowsercompany/swift-winrt)). Static layout is expressed as XAML strings loaded with `XamlReader.load` and wired up in Swift; there is no Storyboard, no `{x:Bind}`, no XAML resource-dictionary scripting.

---

## Table of Contents

- [Project Structure](#project-structure)
- [Architecture at a Glance](#architecture-at-a-glance)
- [Getting Started](#getting-started)
- [Building an App with RsUI](#building-an-app-with-rsui)
  - [1. Create an `App` subclass and register modules](#1-create-an-app-subclass-and-register-modules)
  - [2. Implement the `Module` protocol](#2-implement-the-module-protocol)
  - [3. Implement `Page`s and return them from routing](#3-implement-pages-and-return-them-from-routing)
  - [4. Build page UI (XAML-first)](#4-build-page-ui-xaml-first)
  - [5. Navigate from pages with `WindowContext`](#5-navigate-from-pages-with-windowcontext)
  - [6. Contribute settings](#6-contribute-settings)
  - [7. Localization](#7-localization)
- [Threading, Lifecycle, and Pitfalls](#threading-lifecycle-and-pitfalls)
- [Testing](#testing)
- [Repository Layout](#repository-layout)

---

## Project Structure

RsUI is a Swift Package (`Package.swift`, `swift-tools-version 5.10`) with four products:

| Product | Kind | Purpose |
|---------|------|---------|
| `RsUI` | library | The framework itself — link this from your app. |
| `SampleApp` | executable | A demo app showing every public RsUI surface. |
| `PageControlTests` | executable | GUI test host for `PageFrame` / `PageTabView` / frame-per-tab. |
| `WindowTests` | executable | GUI test host for the `NavigationViewWindow` shell + fullscreen. |

Dependencies (from `Package.swift`):

```
swift-cwinrt → swift-windowsfoundation → swift-uwp
            → swift-windowsappsdk → swift-winui → swift-cppwinrt
            → RsFoundation
```

> The `swift-tools-version: 5.10` pin is temporary — the swift-winrt projection code currently produces Swift 6 concurrency errors and cannot build under Swift 6 language mode. Code outside the UI/projection layer is still expected to follow Swift 6+ conventions (strict concurrency, `Sendable`, `async/await`).

---

## Architecture at a Glance

```
App (entry point, lifecycle, single-instance, module init)
  └── Module[] (plugin protocol — nav items, footer items, URL routing, settings, title-bar right header)
        └── Page (protocol — url + title + header [Any?] + content [UIElement])
```

The window content is composed bottom-up across four layers:

1. **`Page`** — smallest navigable, renderable unit. Each page exposes `url`, `title`, `header` (`Any?`) and `content` (`UIElement`). The standard header+content layout is built from a small XAML snippet in `Page+View.swift` (`Page.view`).
2. **`PageFrame`** (RsUI.Frame) — a single navigation stack (`PageModel` = backward / current / forward pages) on top of a `PageTransitionHost` that animates enter/exit (200ms, 40px slide+fade). `navigate` / `goBack` / `goForward` both mutate the model *and* render immediately, then fire `pageChanged`.
3. **`PageTabView`** (RsUI.TabView) — a WinUI `TabView` (used only as the tab strip) on top of *one shared* `PageFrame`. Each `TabViewItem.tag` carries its own `PageModel`; switching tabs rebinds the shared frame to the new model. The strip auto-hides when there is ≤1 page, so a single-page tab looks like a plain `PageFrame`.
4. **`MainWindow`** — `class MainWindow: NavigationViewWindow, WindowContextHost`. It owns one `PageTabView` (via a `pageControl: PageControl`) and only translates shell events (nav-pane item invoked, Back/Forward, appearance change, fullscreen) into `PageControl` / `WindowContext` calls. It does **not** inline any tab/frame logic.

Supporting types:

- **`AppContext`** (`@Observable`, `App.context` singleton) — theme / language / `route (AppRoute)` / modules / preferences / localization (`tr`) / `openNewWindow`.
- **`WindowContext`** (`public struct`) — window-scoped service facade passed into every module/page call. Delegates to a weak `WindowContextHost` (`MainWindow` is the only implementer). Exposes `open(_:mode:)`, `openOrFocus(_:)`, `pickFolder(_:)`, and fullscreen.
- **`NavigationViewWindow` ← `AppearanceWindow` ← `Window`** — the shell. TitleBar + NavigationView + drag Splitter are all XAML-first (one `xamlUI` string, `XamlReader.load`, `findName`); fullscreen lives at this level (`enterFullscreen(for:)` / `exitFullscreen()` on `FullscreenOverlay`).

`PageFrame` and `PageTabView` both conform to the `internal PageControl` protocol — a shared `navigate + render + pageChanged` surface — so the host can treat them polymorphically. See [`AGENTS.md`](./AGENTS.md) for the full composition model and rationale.

---

## Getting Started

### Prerequisites
- Windows 10/11
- Swift for Windows toolchain (matching `swift-tools-version: 5.10`)
- Windows App SDK 1.8+ runtime

### Build / Run / Test
```bash
swift build                  # Build everything
swift run SampleApp          # Run the demo app
swift run PageControlTests    # GUI test host: PageFrame vs PageTabView vs frame-per-tab
swift run WindowTests         # GUI test host: window shell + fullscreen
swift test                    # Swift Testing unit tests (PageModel, etc.)
```

### Link RsUI from your app
Your `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/rayman-zhao/RsUI", branch: "main"),
            // + the swift-winrt / swift-windowsappsdk / RsFoundation deps RsUI needs
],
targets: [
    .executableTarget(name: "MyApp", dependencies: ["RsUI"], …)
]
```

---

## Building an App with RsUI

A RsUI app is an `App` subclass that registers `Module` types. Each module contributes navigation items, URL routes, optional footer items and a settings group. Routes follow `rs://{moduleId}/{path}`; each route produces a `Page`, and the shell renders the page inside the current window's `PageTabView`.

The full reference is in [`AGENTS.md`](./AGENTS.md); the steps below are the minimum path with copyable snippets, all drawn from `Samples/SampleApp`.

### 1. Create an `App` subclass and register modules

```swift
import Foundation
import RsUI

@main
class SampleApp: App {
    public required init() {
        super.init(
            group: "SampleCompany",
            product: "SampleApp",
            resourceBundle: Bundle.module,   // .xcstrings live next to your sources
            moduleTypes: [SampleModule.self]
        )
    }
}
```

That's the whole entry point. `App.onLaunched` loads theme/language/route from preferences, instantiates the registered `Module` types, registers the JumpList "New Window" entry, and opens a `MainWindow` at the persisted last URL (or `--new-window` to start an empty window). Single-instance coordination (`AppInstance.redirectOrRegister`) is handled for you.

### 2. Implement the `Module` protocol

`Module: ExpressibleByEmptyLiteral` has one required property and a set of defaultable methods — implement only what you need:

```swift
import Foundation
import Observation
import RsFoundation
import RsUI
import UWP
import WinUI

@Observable
final class SampleModule: Module {
    let id = "sample"
    var state = "loading"

    init() { log.info("SampleModule init") }

    // Optional: a control in the title-bar's right header area.
    func titleBarRightHeaderItem(in context: WindowContext) -> UIElement? {
        let ring = ProgressRingEx()
        ring.startObserving { [weak self] in self?.state }
            onChanged: { ring, value in ring.isActive = value == "loading" }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.state = ""
        }
        return ring
    }

    // Sidebar items. The URL is stored on item.tag (as HString) and read back
    // via NavigationViewItemBase.url — see NavigationViewItem.build(...).
    func navigationViewMenuItems(in context: WindowContext) -> [NavigationViewItemBase] {
        let header = NavigationViewItemHeader()
        header.content = tr("Samples")
        return [
            header,
            NavigationViewItem.build(iconGlyph: "\u{E80F}", label: tr("Overview"),        url: "rs://\(id)"),
            NavigationViewItem.build(iconGlyph: "\u{E740}", label: tr("Fullscreen"),       url: "rs://\(id)/fullscreen"),
            NavigationViewItem.build(iconGlyph: "\u{ECCD}", label: tr("Navigation Modes"), url: "rs://\(id)/navigation"),
            // …more items
        ]
    }

    // Optional footer items (e.g. a "pick a folder" action button).
    func navigationViewFooterMenuItems(in context: WindowContext) -> [NavigationViewItemBase] {
        let header = NavigationViewItemHeader()
        header.content = tr("Footer")
        return [
            NavigationViewItemSeparator(),
            header,
            NavigationViewItem.build(
                iconGlyph: "\u{E8B7}", label: tr("Folder Picker"),
                url: "rs://\(id)/footer-picker",
                actionGlyph: "\u{E8F4}", actionTooltip: tr("Pick a folder right from the nav"),
                actionHandler: { _, _ in context.pickFolder { print($0) } }
            ),
        ]
    }

    // Optional: a card group appended to the built-in Settings page.
    func settingsGroup() -> (title: String, cards: [UIElement])? {
        let toggle = ToggleSwitch(); toggle.isOn = true
        let card = SettingsCard(
            headerIconGlyph: "\u{E946}", header: tr("Basic SettingsCard"),
            description: tr("Header icon + description + right-side control."),
            content: toggle
        )
        return (tr("Settings Controls Demo"), [card])
    }

    // The router: match this module's host, switch on the path.
    func navigationDidRequest(for url: URL, in context: WindowContext) -> RsUI.Page? {
        guard url.host == self.id else { return nil }
        switch url.path {
        case "", "/":            return OverviewPage(context: context)
        case "/fullscreen":      return FullscreenPage(context: context)
        case "/navigation":      return NavigationModesPage(context: context)
        case "/openorfocus":     return OpenOrFocusPage(context: context)
        case "/new-window":      return NewWindowPage(context: context)
        case "/appearance":      return AppearancePage(context: context)
        case "/folder-picker", "/footer-picker":
            return FolderPickerPage(context: context, path: url.path)
        default:                 return nil
        }
    }
}
```

### 3. Implement `Page`s and return them from routing

`Page` is `AnyObject` with `url` / `title` / `header` (`Any?`) / `content` (`UIElement`). Pages that cache a `WindowContext` should rebind it in `windowContextDidChange(to:)`, which is called on tab tear-out / window changes / fullscreen toggle:

```swift
import Foundation
import RsUI
import UWP
import WinUI

final class FullscreenPage: RsUI.Page {
    var context: WindowContext

    init(context: WindowContext) { self.context = context }

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
        (statusCard.headerIcon as! FontIcon).glyph =
            context.isInFullscreen ? "\u{E922}" : "\u{E93A}"
    }

    var url: URL { URL(string: "rs://sample/fullscreen")! }
    var title: String { tr("Fullscreen") }

    var header: Any? {
        featurePageHeader(title: tr("Fullscreen"), description: tr("…"))
    }

    var content: WinUI.UIElement {
        let enterCard = SettingsCard(headerIconGlyph: "\u{E740}", header: tr("Enter tab fullscreen"),
                                      description: tr("Calls context.enterFullscreen()."))
        enterCard.isClickEnabled = true
        enterCard.click.addHandler { [weak self] _, _ in self?.context.enterFullscreen() }

        let exitCard = SettingsCard(headerIconGlyph: "\u{E73F}", header: tr("Exit tab fullscreen"),
                                     description: tr("Calls context.exitFullscreen()."))
        exitCard.isClickEnabled = true
        exitCard.click.addHandler { [weak self] _, _ in self?.context.exitFullscreen() }

        return featurePageContent([enterCard, exitCard])
    }
}
```

`Page` provides a defaultable `startObserving(_:onChanged:)` helper to drive UI off an `@Observable` state via the RsFoundation `Observations` async sequence — emit the state, mutate the UI in the `onChanged` callback on `MainActor`.

### 4. Build page UI (XAML-first)

Prefer XAML strings loaded with `XamlReader.load` over long chains of `Control()` + property assignment + `children.append`. Retrieve named controls with `findName` and wire runtime values and event handlers in Swift. A page's own rendering goes through `Page.view` (`Page+View.swift`), which builds a standard header (`headerBorder` / `headerContainer` / `headerText`) + content (`contentBorder`) grid:

```swift
var content: UIElement {
    let xaml = """
    <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Border Background="#F2F2F2" Margin="16,0,16,16"
                Padding="24,24,24,24" CornerRadius="8">
            <StackPanel Spacing="6">
                <TextBlock Text="\(escapedTitle)" FontSize="24" FontWeight="SemiBold"/>
                <TextBlock Text="\(escapedSubtitle)" Opacity="0.7"/>
            </StackPanel>
        </Border>
    </Grid>
    """
    return (try? XamlReader.load(xaml)) as! UIElement
}
```

For richer Fluent rows, the framework ships `SettingsCard` / `SettingsExpander` / `SettingsGroup` (in `Sources/RsUI/Controls/`). Use these for settings-like layouts instead of hand-rolling grids.

### 5. Navigate from pages with `WindowContext`

`WindowContext` is what you use from page code for navigation, folder picking, and fullscreen. It's passed into every `Module`/`Page` call:

```swift
// In-place navigation (default Suppress transition)
context.open(targetURL)

// Open in a new tab and switch to it (or new-tab background)
context.open(targetURL, mode: .newTab)          // .newTab / .newTabNoFocus

// Focus the existing tab matching this URL, or open a new one — the typical
// "navigate to content" path with deduplication.
context.openOrFocus(targetURL)

// Batch-open many URLs into new tabs
context.open([url1, url2, url3], mode: .newTab)   // returns Int (#opened)

// Folder picker parented to this window
context.pickFolder { path in print("Selected: \(path)") }

// Fullscreen
context.enterFullscreen()
context.exitFullscreen()
context.isInFullscreen  // Bool

// Open a brand-new MainWindow at a URL (forceMinimalMode => collapsed nav pane
// for viewer-style windows; layout won't be persisted back).
App.context.openNewWindow(with: someURL, forceMinimalMode: true)
```

> `Module` is the one registered type; one `Module` instance is created per registered type in `App.context.initializeModules()` and shared across all windows. `WindowContext` is per-window and gets delivered to pages on creation and on `windowContextDidChange(to:)`.

### 6. Contribute settings

Return a `(title, cards)` tuple from `settingsGroup()`. The built-in `SettingsPage` (`rs://ui/settings`) automatically collects every module's group and lays them out in `SettingsGroup`s:

```swift
func settingsGroup() -> (title: String, cards: [UIElement])? {
    let card = SettingsCard(headerIconGlyph: "\u{E790}",
                            header: tr("Theme"),
                            description: tr("Application color mode."),
                            content: themeComboBox)
    return (tr("My Module"), [card])
}
```

### 7. Localization

Strings live in `.xcstrings` files (e.g. `Samples/Assets/Localizable.xcstrings`, `Samples/Assets/SettingsPage.xcstrings`) bundled via your executable target's `resources: [.process("Assets")]`. Resolve them through the public `App.context.tr(_:table:)`:

```swift
let label = App.context.tr("Samples")          // root table
let title = App.context.tr("title", table: "SettingsPage")

// Convenience: a module-level wrapper that maps the module's language and
// surfaces an "untranslated" placeholder for missing zh-Hans keys.
func tr(_ keyAndValue: String) -> String {
    let text = App.context.tr(keyAndValue)
    return (text == keyAndValue && App.context.language == .zh_CN) ? "待翻译（\(keyAndValue)）" : text
}
```

There's also `App.context.tr(xaml:table:)` to substitute `{x:Tr key}` placeholders inside XAML strings before `XamlReader.load`.

---

## Threading, Lifecycle, and Pitfalls

- **UI on MainActor.** Background work goes through `Task` + `dispatcherQueue`. WinRT callbacks (`addHandler { _, args in … }`) run on the UI thread; capture `[weak self]` and prefer `_` for the ignored sender parameter.
- **COM callback exceptions don't propagate.** Use `try?` / `do-catch`-to-log at WinRT boundaries; failures surface through `log.warning`, not thrown errors.
- **Single instance** is enforced by `AppInstance.redirectOrRegister(for:)` keyed on `"\(group)/\(product)"`. A second launch redirects activation to the primary instance and `exit(0)`s.
- **Tab tear-out is disabled.** `PageTabView`'s XAML hard-codes `CanTearOutTabs="False"`; the cross-window tear-out scaffolding in `MainWindow+TearOutTabs.swift` is commented out and not part of the build. Use `openNewWindow(with:)` for multi-window flows.
- **C# docs need conversion.** Microsoft's WinUI docs are all C#/XAML. Convert PascalCase → camelCase (`IsPaneOpen` → `isPaneOpen`), `+=` → `addHandler`, `IList<T>` → `AnyIVector<Any?>`, and `async/await` → Swift `async/await` via WinRT-projected `IAsyncOperation`.

Full conventions (naming, MVVM, event/template naming rules) are in [`AGENTS.md`](./AGENTS.md).

---

## Testing

- **`swift test`** runs the Swift Testing `@Suite`/`@Test`s in `Tests/RsUITests/` — currently `PageModelTests` covering `PageModel.navigate/goBack/goForward/history-limit/clears-forward` behavior.
- **`swift run PageControlTests`** is a GUI test host launching three windows side-by-side:
  - `PageControlTestWindow(mode: .frame)` — drives a bare `PageFrame` through the `any PageControl` protocol.
  - `PageControlTestWindow(mode: .tabView)` — same host, drives a `PageTabView`; reads `tabCount` to verify strip auto-hide.
  - `TabViewPageFrameTestWindow` — the frame-per-tab alternative (a `PageFrame` per `TabViewItem`).
- **`swift run WindowTests`** is a GUI test host for the raw `NavigationViewWindow` shell and the generic `enterFullscreen(for:)` / `exitFullscreen()` / `fullscreenChanged` flow.

---
