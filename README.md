# RsUI

A native LOB (Line of Business) application framework built with **Swift on Windows** and **WinUI 3 / Windows App SDK**. RsUI gives you a tabbed, multi-window shell with a sidebar + title bar, a URL-based navigation model, and a small plugin system — so you can write the actual app as one or more `Module`s and let the framework own the window chrome, tabs, settings, and theming.

<img width="2491" height="1619" alt="image" src="https://github.com/user-attachments/assets/beeb0529-88d6-40bf-bb7c-e82c8e0473a2" />

> **Not SwiftUI.** All UI is constructed imperatively in Swift by calling WinUI 3 WinRT projection APIs (via [swift-winrt](https://github.com/rayman-zhao/swift-winrt) forks). Static layout is expressed as XAML strings loaded with `XamlReader.load` and wired up in Swift; there is no Storyboard, no `{x:Bind}`, no XAML resource-dictionary scripting.

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

> **Building an app on RsUI?** See [`INTEGRATION.md`](./INTEGRATION.md) (linker settings, JumpList icon contract, localization key contract, page-author rules) and [`CHANGELOG.md`](./CHANGELOG.md) for per-tag changes.

---

## Project Structure

RsUI is a Swift Package (`Package.swift`, `swift-tools-version 6.4`) with four products:

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

> `Package.swift` declares `swift-tools-version: 6.4` and builds in the Swift 6 language mode. The framework targets and the GUI test hosts use explicit isolation (`@MainActor` on the UI types); only `SampleApp` opts into `.defaultIsolation(MainActor.self)` to show the downstream-app form.

---

## Architecture at a Glance

```
App (entry point, lifecycle, single-instance, module init)
  └── Module[] (plugin protocol — nav items, footer items, URL routing, settings, title-bar right header)
        └── Page (protocol — url + title + header [Any?] + content [UIElement])
```

The window content is composed bottom-up across four layers:

1. **`Page`** — smallest navigable, renderable unit. Each page exposes `url`, `title`, an optional `header` (`Any?`) and an optional `content` (`UIElement?`). The standard header+content layout is assembled by the default `makeView()` (`Page+View.swift`); a page with a full-page custom layout overrides `makeView()`.
2. **`PageFrame`** — a single navigation stack (`PageModel` = backward / current / forward pages) on top of a `PageTransitionHost` that animates enter/exit (200ms, 40px slide+fade). `navigate` / `goBack` / `goForward` both mutate the model *and* render immediately, then fire `pageChanged`.
3. **`PageTabView`** — a WinUI `TabView` (used only as the tab strip) on top of *one shared* `PageFrame`. Each `TabViewItem.tag` carries its own `PageModel`; switching tabs rebinds the shared frame to the new model. The strip auto-hides when there is ≤1 page, so a single-page tab looks like a plain `PageFrame`.
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
- Swift for Windows toolchain matching `swift-tools-version: 6.4`
- Windows App SDK runtime matching the version the `swift-windowsappsdk` projection targets (2.5.x today — see that package's `projections.json`)

### Build / Run / Test
```bash
swift build                  # Build everything
swift run SampleApp          # Run the demo app
swift run PageControlTests    # GUI test host: PageFrame vs PageTabView vs frame-per-tab
swift run WindowTests         # GUI test host: window shell + fullscreen
swift test                    # Swift Testing unit tests (PageModel, etc.)
```

### Link RsUI from your app
Your `Package.swift` — RsUI's own dependencies (the swift-winrt forks, RsFoundation) resolve transitively:
```swift
dependencies: [
    .package(url: "https://github.com/rayman-zhao/RsUI", branch: "main"),
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [.product(name: "RsUI", package: "RsUI")],
        resources: [.process("Assets")],        // your .xcstrings, icon, .rc/.res
        linkerSettings: GUILinkerSettings       // required — see INTEGRATION.md §2
    ),
]
```
The full consumer contract (linker block, `<productName>.ico`, localization tables) is in [`INTEGRATION.md`](./INTEGRATION.md).

---

## Building an App with RsUI

A RsUI app is an `App` subclass that registers `Module` types. Each module contributes navigation items, URL routes, optional footer items and a settings group. Routes follow `rs://{moduleId}/{path}`; each route produces a `Page`, and the shell renders the page inside the current window's `PageTabView`.

The full reference is in [`AGENTS.md`](./AGENTS.md); the steps below are the minimum path with copyable snippets, all drawn from `Samples/SampleApp`.

### 1. Create an `App` subclass and register modules

```swift
import Foundation
import RsUI
// @main's main() witness lives in WinUI.SwiftApplication; without this import Swift 6.4 warns
import WinUI

@main
class SampleApp: App, @unchecked Sendable {
    override class var groupName: String { "SampleCompany" }
    override class var productName: String { "SampleApp" }
    override class var resourceBundle: Bundle { .module }   // your .xcstrings live here

    override class var modules: [any Module] { [SampleModule()] }
}
```

That's the whole entry point: app identity is the three `class var` overrides `groupName` / `productName` / `resourceBundle` (the defaults keep the framework's own), and modules are declared through the `modules` class var (default `[]` — leave it out for an app without modules). `SampleApp` additionally declares `nonisolated required init() { super.init() }` only because its target opts into `.defaultIsolation(MainActor.self)`, which synthesizes a conflicting `MainActor` override for the inherited nonisolated required initializer; without `defaultIsolation` the initializer is simply inherited.

`App.onLaunched` loads theme/language/route from preferences, reads `modules` once, registers the JumpList "New Window" entry, and opens a `MainWindow` at the persisted last URL (the built-in Settings page when there is nothing to restore). Single-instance coordination (`AppInstance.redirectOrRegister`) is handled for you: a `--new-window` launch (e.g. from the JumpList) is redirected to the primary instance, which activates a fresh `MainWindow`.

### 2. Implement the `Module` protocol

`Module` is a `@MainActor` protocol with one required property (`id`) and a set of defaultable methods — implement only what you need:

```swift
import Foundation
import Observation
import RsFoundation
import RsUI
import UWP
import WinUI

// `tr` is the sample's module-level wrapper over App.context.tr — see section 7.
@Observable
final class SampleModule: @MainActor Module {
    let id = "sample"
    var state = "loading"

    init() { log.info("SampleModule init") }

    // Optional: a control in the title-bar's right header area.
    func titleBarRightHeaderItem(in context: WindowContext) -> UIElement? {
        let ring = ProgressRing()
        startObserving { [weak self] in
            self?.state
        } onChanged: { value in
            ring.isActive = (value == "loading")
            // `false` stops the observation from inside the callback.
            return value == "loading"
        }
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
        let newWindowActionURL = URL(string: "rs://\(id)/new-window")!
        return [
            header,
            NavigationViewItem.build(
                iconGlyph: "\u{E80F}", label: tr("Overview"), url: "rs://\(id)"),
            NavigationViewItem.build(
                iconGlyph: "\u{E740}", label: tr("Fullscreen"), url: "rs://\(id)/fullscreen"),
            // A row with a hover-revealed action button.
            NavigationViewItemWithAction(
                iconGlyph: "\u{E78B}", label: tr("New Window"), url: "rs://\(id)/new-window",
                actionGlyph: "\u{E8F4}",
                actionTooltip: tr("Open this page in a new window"),
                actionHandler: { _, _ in
                    App.context.openNewWindow(with: [newWindowActionURL])
                }
            ),
            // …more items
        ]
    }

    // Optional footer items (e.g. a "pick a folder" row).
    func navigationViewFooterMenuItems(in context: WindowContext) -> [NavigationViewItemBase] {
        let header = NavigationViewItemHeader()
        header.content = tr("Footer")
        let pickerItem = NavigationViewItemWithAction(
            iconGlyph: "\u{E8B7}",
            label: tr("Folder Picker"),
            url: "rs://\(id)/footer-picker",
            actionGlyph: "\u{E8B7}",
            actionTooltip: tr("Pick a folder right from the nav"),
            actionHandler: { _, _ in
                context.pickFolder { path in
                    log.info("picked folder: \(String(describing: path))")
                }
            }
        )
        return [NavigationViewItemSeparator(), header, pickerItem]
    }

    // Optional: a group appended to the built-in Settings page.
    func settingsGroup() -> SettingsGroup? {
        let toggle = ToggleSwitch()
        toggle.isOn = true
        let basicCard = SettingsCard(
            headerIconGlyph: "\u{E946}",
            header: tr("Basic SettingsCard"),
            description: tr("Header icon + description + right-side control."),
            content: toggle
        )
        return SettingsGroup(title: tr("Settings Controls Demo"), cards: [basicCard])
    }

    // The router: match this module's host, switch on the path.
    func navigationDidRequest(for url: URL, in context: WindowContext) -> RsUI.Page? {
        guard url.host == self.id else { return nil }
        switch url.path {
        case "", "/":            return OverviewPage()
        case "/fullscreen":      return FullscreenPage()
        case "/navigation":      return NavigationModesPage()
        case "/picker":          return PickerPage()
        default:                 return nil
        }
    }
}
```

### 3. Implement `Page`s and return them from routing

`Page` is a `@MainActor` protocol with `url` / `title` / `header` (`Any?`, default `nil`) / `content` (`UIElement?`), plus the `view` cache slot the framework manages. Pages never receive the `WindowContext` from the module factory or their own initializer — store it in `windowContextDidChange(to:)`, which is called when the page is attached to a window (before its content is first rendered), again on window changes, and on fullscreen toggles:

```swift
import Foundation
import RsUI
import UWP
import WinUI

final class FullscreenPage: RsUI.Page {
    var view: UIElement?   // framework-managed cache slot; do not read or write it yourself
    var context: WindowContext?

    func windowContextDidChange(to context: WindowContext) {
        self.context = context
        // Refresh fullscreen-derived UI here; this may fire before the content is first built.
    }

    let url = URL(string: "rs://sample/fullscreen")!
    var title: String { tr("Fullscreen") }
    var header: Any? { "Fullscreen" }

    var content: WinUI.UIElement? {
        let enterCard = SettingsCard(
            headerIconGlyph: "\u{E740}",
            header: tr("Enter tab fullscreen"),
            description: tr("Calls context.enterFullscreen().")
        )
        enterCard.isClickEnabled = true
        enterCard.click.addHandler { [weak self] _, _ in
            self?.context?.enterFullscreen()
        }
        return featurePageContent([enterCard])   // sample-local helper that stacks cards
    }
}
```

The public free function `startObserving(emitting:onChanged:)` (`Support/Observation.swift`) drives UI off `@Observable` state through the `Observations` async sequence of the toolchain's `Observation` module: emit the state, mutate the UI inside the `onChanged` callback on `MainActor`, and return `false` to stop observing from inside the callback — or cancel the returned `Task` when the UI it drives goes away.

### 4. Build page UI (XAML-first)

Prefer XAML strings loaded with `XamlReader.load` over long chains of `Control()` + property assignment + `children.append`. Retrieve named controls with `findName` and wire runtime values and event handlers in Swift. A page's standard rendering goes through the default `makeView()` (`Page+View.swift`), which lays out `header` (`headerBorder`) and `content` (`contentBorder`) in a Grid — override `makeView()` for a full-page custom layout. The page itself may build either part from XAML:

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
    guard let element = (try? XamlReader.load(xaml)) as? UIElement else {
        log.warning("failed to load page content XAML")
        return Grid()
    }
    return element
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

> `Module` is the one registered type: the app's `modules` class var is read once in `App.onLaunched`, and the instances are shared across all windows. `WindowContext` is per-window and reaches pages only through `windowContextDidChange(to:)`.

### 6. Contribute settings

Return a `SettingsGroup` from `settingsGroup()` — you construct the group yourself, so its `isExpandable` / `isExpanded` init parameters decide whether the group can be toggled and how it starts. The built-in `SettingsPage` (`rs://ui/settings`) appends every module's group as-is:

```swift
func settingsGroup() -> SettingsGroup? {
    let card = SettingsCard(headerIconGlyph: "\u{E790}",
                            header: tr("Theme"),
                            description: tr("Application color mode."),
                            content: themeComboBox)
    return SettingsGroup(title: tr("My Module"), cards: [card])
}
```

### 7. Localization

Strings live in `.xcstrings` string catalogs bundled via your executable target's `resources: [.process("Assets")]` and are resolved through the public `App.context.tr(_:table:)`. Three kinds of table are in play:

- **`Localizable`** (shell strings) and **`SettingsPage`** (the built-in settings page) are app-independent: copy them verbatim from `Samples/Assets`. A missing key falls back to the key text.
- **`App`** holds the hosting app's display names, keyed by identity: `productName` is the window title and the title of the Settings About card, `groupName` is the copyright holder on that card. Without these keys the raw identity strings are shown.
- Your own tables — SampleApp keeps its demo strings in `SampleApp.xcstrings`.

```swift
let label = App.context.tr("Back")                         // framework shell table
let title = App.context.tr("title", table: "SettingsPage")

// SampleApp's module-level wrapper: routes to the sample's own table and
// surfaces an "untranslated" placeholder for missing zh-Hans keys.
let sampleTrTable = "SampleApp"

func tr(_ keyAndValue: String) -> String {
    let text = App.context.tr(keyAndValue, table: sampleTrTable)
    return (text == keyAndValue && App.context.language == .zh_CN) ? "待翻译（\(keyAndValue)）" : text
}
```

The full key contract (including the keys the shell reads) is in [`INTEGRATION.md` §5](./INTEGRATION.md#5-localization-key-contract).

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

- **`swift test`** runs the Swift Testing `@Suite`/`@Test`s in `Tests/RsUITests/` — `PageModelTests` (navigate / goBack / goForward / history limit / clears-forward history), `RangeSliderStateTests`, `ModelsTests` (`AppTheme` / `AppLanguage` / `AppRoute`), `ImageCarouselTests` and `StartObservingTests`.
- **`swift run PageControlTests`** is a GUI test host launching three windows side-by-side:
  - `PageControlTestWindow(mode: .frame)` — drives a bare `PageFrame` through the `any PageControl` protocol.
  - `PageControlTestWindow(mode: .tabView)` — same host, drives a `PageTabView`; reads `tabCount` to verify strip auto-hide.
  - `TabViewPageFrameTestWindow` — the frame-per-tab alternative (a `PageFrame` per `TabViewItem`).
- **`swift run WindowTests`** is a GUI test host for the raw `NavigationViewWindow` shell and the generic `enterFullscreen(for:)` / `exitFullscreen()` / `fullscreenChanged` flow.

---
