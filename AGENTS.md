# AGENTS.md

## Project Overview

RsUI is a native LOB (Line of Business) application framework built with **Swift on Windows** + **WinUI 3** / **Windows App SDK**. It provides a tabbed multiple-window shell with a modular plugin system.

- **Platform**: Windows only (Swift for Windows, NOT Apple Swift)
- **Package manager**: Swift Package Manager (SPM), `swift-tools-version 5.10` (see Toolchain Version Note below)
- **Outputs**: `RsUI` library + three executables: `SampleApp` (the demo app), `PageControlTests` (GUI test host) and `WindowTests` (window-shell GUI test host)
- **Build**: `swift build` | **Run**: `swift run SampleApp` | **Test**: `swift test`

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift on Windows; tools-version pinned to 5.10 for swift-winrt compat, see Toolchain Version Note |
| UI Framework | WinUI 3 (via swift-winrt WinRT projection) |
| Runtime | Windows App SDK (1.8+) |
| Dependencies | swift-cwinrt → swift-windowsfoundation → swift-uwp → swift-windowsappsdk → swift-winui → swift-cppwinrt, plus RsFoundation |

**Critical distinction**: This is NOT SwiftUI. All UI is built imperatively in Swift by calling WinUI 3 WinRT APIs directly. Static structure is expressed as XAML strings loaded with `XamlReader.load`, after which named controls are retrieved with `findName` and props/events are wired in Swift. There is no Storyboard, no `{x:Bind}`, no XAML resource dictionary scripting.

### Toolchain Version Note

- `Package.swift` declares `swift-tools-version: 5.10`. This pin is temporary: the swift-winrt projection code currently produces Swift 6 concurrency errors and cannot build under Swift 6 language mode.
- Code outside the UI/projection layer is still expected to follow Swift 6+ conventions (strict concurrency, `Sendable`, `async/await`, structured concurrency). Only the swift-winrt compatibility issue keeps the tools version pinned today.
- Do not treat the `5.10` marker as permission to write pre-Swift-6 code in non-UI / non-projection modules.

## Architecture

```
App (entry point, lifecycle, single-instance, module init)
  └── Module[] (plugin protocol — nav items, footer items, URL routing, settings, title-bar right header)
        └── Page (protocol — url, title, header [Any?] and content [UIElement])
```

- **`App`** — `open class App: SwiftApplication` ([`Sources/RsUI/App/App.swift`](./Sources/RsUI/App/App.swift)). The single source of truth is `static let context = AppContext()`. The convenience initializer `init(group:product:resourceBundle:moduleTypes:)` calls `App.context.bootstrap(...)` then `AppInstance.redirectOrRegister(for:)` for single-instance coordination. `onLaunched` runs `bootstrapGUI()` + `initializeModules()`, registers the JumpList "New Window" entry, and creates a `MainWindow` (either via `--new-window` CLI/launch arg, or at the persisted `App.context.route.lastPageURL`). `onActivated` and `onShutdown` are overridden.
- **`Module`** — `public protocol Module: ExpressibleByEmptyLiteral` ([`Sources/RsUI/Models/Module.swift`](./Sources/RsUI/Models/Module.swift)). Requires `var id: String` plus a set of defaultable methods modules override to contribute to the shell: `titleBarRightHeaderItem(in:)`, `navigationViewMenuItems(in:)`, `navigationViewFooterMenuItems(in:)`, `settingsGroup()`, `navigationDidRequest(for:in:)`. The protocol provides empty/`nil` defaults, so a conforming type may implement only what it needs.
- **`Page`** — `public protocol Page: AnyObject` ([`Sources/RsUI/Models/Page.swift`](./Sources/RsUI/Models/Page.swift)). Meta info `var url: URL` + `var title: String`; UI `var header: Any?` (default `nil`) and `var content: UIElement`. The lifecycle hook `func windowContextDidChange(to: WindowContext)` (default no-op) is called when the page is moved to another window or the host window enters/exits fullscreen (Page impls that cache a `WindowContext` should rebind it here, and flip fullscreen UI affordances). The defaultable `startObserving(_:onChanged:)` helper drives the UI off an `@Observable` state via the RsFoundation `Observations` async sequence.
- **`WindowContext`** — `public struct WindowContext` ([`Sources/RsUI/Models/WindowContext.swift`](./Sources/RsUI/Models/WindowContext.swift)). Window-scoped service facade exposed to modules/pages; it delegates to a weak `WindowContextHost` (internal protocol, see below). Public surface: `pickFolder(_:)`, `open(_:mode:transitionInfoOverride:)` overloads (single `Page`, `[Page]`, single `URL`, `[URL]`), `openOrFocus(_:)` (focus an existing tab matching the URL, else open a new one) and `isInFullscreen` / `enterFullscreen()` / `exitFullscreen()`, plus `NavigationOpenMode` (`.inplace` / `.newTab` / `.newTabNoFocus`).
- **`MainWindow`** — `class MainWindow: NavigationViewWindow, WindowContextHost` ([`Sources/RsUI/App/MainWindow/MainWindow.swift`](./Sources/RsUI/App/MainWindow/MainWindow.swift)). Modern minimal shell: it owns a `PageControl` (instantiated as a `PageTabView`) and wires host-event surface to it (see Core UI Composition Model). The only file with active tear-out scaffolding is [`MainWindow+TearOutTabs.swift`](./Sources/RsUI/App/MainWindow/MainWindow+TearOutTabs.swift), but it is **entirely a `/* ... */` commented-out block** — see [Tab Tear-Out Currently Disabled](#tab-tear-out-currently-disabled).
- **`AppContext`** — `@Observable public final class AppContext` ([`Sources/RsUI/Models/AppContext.swift`](./Sources/RsUI/Models/AppContext.swift)). Global singleton (`App.context`) holding `groupName`/`productName`/`supportDirectory`/`preferences` (`JSONPreferences`)/`resourceBundle`, the observable `theme`/`language` enums, `route: AppRoute` (persisted last page + `maxHistoryPages`), and the loaded `[any Module]`. Methods: `bootstrap(...)` / `bootstrapGUI()` / `initializeModules()` / `releaseModules()`, the localization helpers `tr(_:table:)` and `tr(xaml:table:)` (the latter substitutes `{x:Tr key}` placeholders in XAML strings), and `openNewWindow(with:forceMinimalMode:)`.

## Core UI Composition Model

RsUI 的窗口内容由四个层级组合而成，自下而上依次为 Page → PageFrame → PageTabView → MainWindow。

1. **Page（基本页面单元）** — 见 [`Sources/RsUI/Models/Page.swift`](./Sources/RsUI/Models/Page.swift) 与 [`Sources/RsUI/App/PageControls/Page+View.swift`](./Sources/RsUI/App/PageControls/Page+View.swift)。每个 Page 的 UI 由 `header`（`Any?`，可为 `String` / `UIElement` / `nil`）和 `content`（`UIElement`）两部分构成，加上 `url`、`title` 元信息。Page 是框架内最小的可导航、可渲染单元。
   - `Page+View.swift` 提供文件内 `extension Page { var view: UIElement }`：用一段固定 XAML（`XamlReader.load` → `findName`）渲染成「Row0 顶部 header（`headerBorder`/`headerContainer`/`headerText`），Row1 content（`contentBorder`）」的 `Grid`。`header` 为 `String` 时填进 `TextBlock`，为 `UIElement` 时塞进 `headerContainer.child`，为 `nil` 时折叠整条 header。这是单个 Page 的标准渲染管线，`PageFrame`/`PageTabView` 调用 `page.view` 得到可挂载的元素。

2. **`PageModel`（导航栈模型）+ `PageTransitionHost`（转场容器）** — 见 [`PageModels.swift`](./Sources/RsUI/App/PageControls/PageModels.swift) 与 [`PageTransitionHost.swift`](./Sources/RsUI/App/PageControls/PageTransitionHost.swift)。
   - `PageModel`（`internal class`）持有三段：`backwardPages: [Page]` / `forwardPages: [Page]` / `currentPage: Page?`。`navigate(to:)` 推栈（受限 `App.context.route.maxHistoryPages`，超出 `removeFirst`），`goBack()`/`goForward()` 在两端栈间搬运 `currentPage`。这是「单个 tab 的导航历史」的事实载体。
   - `PageTransitionHost`（`class PageTransitionHost: Grid`）持有一组 `Border` wrapper 做进/出/滑动/淡入淡出转场：`transition(to:transitionInfo:)` 按传入的 `NavigationTransitionInfo`（`SuppressNavigationTransitionInfo` / `SlideNavigationTransitionInfo(.fromLeft|.fromRight|.fromBottom)`）决定 200ms / 40px 的 `Storyboard` 动画，动画进行中暂存 `pendingTransition`，结束后在 `dispatcherQueue` 上清理旧 wrapper 并续作；`Suppress` 分支直接即时互换、不走动画。它内部用 `children.append/removeChild` 自管 wrapper，因此天然遵守 [UIElement Single-Parent Rule](#uielement-single-parent-rule)。

3. **`PageFrame`（页面栈容器）** — 见 [`Sources/RsUI/App/PageControls/PageFrame.swift`](./Sources/RsUI/App/PageControls/PageFrame.swift)。`class PageFrame: PageTransitionHost, PageControl`——**注意它是 `PageTransitionHost` 的子类，而非直接继承 `Grid`**，所以本身就是一个 `Grid` 视图。它持有一个 `PageModel`，每个 `navigate`/`goBack`/`goForward` 都是「先 mutate model → `transition(to: currentPage?.view, ...)` → `Task { @MainActor in pageChanged.invoke(...) }`」三步走，渲染与 `pageChanged` 事件一并触发。
   - **不能直接复用 WinUI 的 `Frame`**：WinUI `Frame` 的导航参数是 `Any?` / WinRT 对象，无法承载 Swift 的 `Page` 协议类型，故等价实现了 `PageFrame` = `PageTransitionHost` + `PageModel`。
   - `init(model: PageModel = PageModel())`：默认空 model；构造即 `transition` 到当前页 + 触发 `pageChanged`。
   - `rebind(to newModel: PageModel)`：重设 model 并即时（`Suppress` 转场）渲染 + 触发 `pageChanged`。这是「单 `PageFrame` 在多 tab 间共享」的关键——`PageTabView` 切 tab 时把共享 frame 的 model 重设到目标 tab 的 `PageModel`，复用同一条渲染管线。
   - 可放入任意 WinUI 容器（`window.content`、`NavigationView.content`、任意 `Grid` 等），与具体外壳解耦。
   - `updateAppearance()`（重新 `transition` 一遍当前页，用于主题/语言切换后强制重建视觉）与 `updateWindowContext(_:)`（把新 `WindowContext` 通知给当前页 + back/forward 栈上所有页，触发它们的 `windowContextDidChange(to:)`）。

4. **`PageTabView`（组合 WinUI.TabView + 共享 PageFrame）** — 见 [`Sources/RsUI/App/PageControls/PageTabView.swift`](./Sources/RsUI/App/PageControls/PageTabView.swift)。`class PageTabView: Grid, PageControl`，自身为 2 行 `Grid`（Row0 Auto = strip、Row1 star = 内容），把 `WinUI.TabView`（仅作 strip）和单一共享 `PageFrame` 装进来。
   - **结构**：`tabView`（XAML 字符串 `XamlReader.load` → `findName("closeOthersButton")` 回填；XAML 默认 `Visibility="Collapsed"`，`CanTearOutTabs="False"`——见下文 tear-out 禁用说明）+ 一个 `private let pageFrame = PageFrame()`。
   - 每个 `TabViewItem` 的 `tag` 持有该 tab 独立的 `PageModel`（`tag = PageModel(page:)` 或新建 tab 的 `PageModel()`），导航栈彼此独立，只是渲染管线复用同一条。`selectionChanged` → `pageFrame.rebind(to: item.tag as! PageModel)`；`pageFrame.pageChanged` → 把当前页的 `title` 回写到选中 `TabViewItem.header`。
   - **TabStrip 自动隐藏**：`addTabItems` 里按 `tabItems.count > 1` 翻 `tabView.visibility`（`.visible` / `.collapsed`）；`tabCloseRequested` 与 `closeOthersButton.click` 也会重新评估。因 page 内容挂在共享 frame（Row1）而非 `TabViewItem.content` 上，隐藏整个 `TabView` 时内容仍显示——单 tab 窗口看起来就是一个普通 `PageFrame`，无 strip 痕迹。
   - `PageTabView` 自身代入门槛低；现在 `MainWindow` 直接装配它（见下文）。

5. **`PageControl` 协议（`PageFrame` / `PageTabView` 的公共驱动接口）** — 见 [`Sources/RsUI/App/PageControls/PageControl.swift`](./Sources/RsUI/App/PageControls/PageControl.swift)。两者都 `: PageControl`，把「mutate + 即时渲染 + 触发 `pageChanged`」的语义统一。`internal protocol`——其成员涉及 `PageModel`（`internal`），故暂不能提为 public；当前仅同模块内与 `@testable import` 的测试可执行文件使用。成员：
   - 查询：`var currentPage: Page?` / `var canGoBack: Bool` / `var canGoForward: Bool`。
   - 视图：`var rootView: FrameworkElement`（给宿主塞进 `NavigationView.content`）/ `var fullscreenView: UIElement`（全屏要展示的内容；`PageFrame` 返回 `self`，`PageTabView` 返回 `pageFrame.fullscreenView` 即共享 frame 本身）。
   - 事件：`var pageChanged: EventWithArgumentHandler<PageControl, Page?>`（实现是 `PageFrame` 自持的 `EventWithArgumentHandler`，`PageTabView` 直接转发同一实例）。
   - 命令：`goBack()`、`goForward()`、`navigate(to page: Page, mode: NavigationOpenMode, transitionInfoOverride: NavigationTransitionInfo)`、`navigate(to pages: [Page], mode: NavigationOpenMode, transitionInfoOverride: NavigationTransitionInfo) -> Int`、`selectPage(matchingURL url: URL) -> Bool`、`updateAppearance()`、`updateWindowContext(_:)`。
   - 命令统一用 `navigate(to:)`（带 `mode` 与 `transitionInfoOverride`），与 `PageFrame` 本类 `navigate(...)` 同名同形参——语义和签名都不再冲突，故 **不存在 `pushPage`**（旧文档中的 `pushPage` 描述已废弃）。`PageFrame`/`PageTabView` 各自的 `goBack()`/`goForward()` 内部固定走 `.fromLeft` / `.fromRight` 转场。

6. **MainWindow（NavigationView 窗口装配 PageTabView）** — 见 [`MainWindow.swift`](./Sources/RsUI/App/MainWindow/MainWindow.swift)。`class MainWindow: NavigationViewWindow, WindowContextHost`。构造 `init(url: URL? = nil, forceMinimalMode: Bool = false)`：`super.init(forceMinimalMode)` → `useMicaBackdrop()` → `useRestoration()` → `setupUI()`（把 `ui.navigationView.content = pageControl.rootView`、禁用 Back/Forward 按钮）→ `bindEvents()` → 在 `MainActor` Task 里 `context.open(url)` 或 fallback 到 `firstItemURL`。其内容容器只持有一个 `PageTabView`（`private lazy var pageControl: PageControl = PageTabView()`）；`bindEvents` 把窗口壳事件（`appearanceChanged`、`fullscreenChanged`、`NavigationView.itemInvoked`、Back/Forward click、`pageControl.pageChanged`）翻译为 ViewModel 维度：`itemInvoked`（Ctrl 点击 = `.newTabNoFocus`，否则 `.inplace`，并透传 `recommendedNavigationTransitionInfo`）；`pageChanged` 时同步 `NavigationView` 选中项 / Back/Forward 使能 / `App.context.route.lastPageURL` / 当前页为 `nil` 时 fallback 再开 `firstItemURL`。
   - `WindowContextHost` 的实现就在本文件：`hwnd`、`isInFullscreenPage` / `enterFullscreenPage()` / `exitFullscreenPage()`（把 `pageControl.fullscreenView` 交给 `enterFullscreen(for:)`）、`open(_:mode:transitionInfoOverride:)` 两形态、`selectPage(matchingURL:)` 全部转发给 `pageControl`。
   - 早期重构目标「MainWindow 不再内联 Frame/TabView，改为直接装配 `PageTabView`」**已经达成**——现在 MainWindow 只负责 NavigationView / TitleBar / 生命周期 / 窗口级偏好 / 事件翻译，不再内联任何 tab/frame 细节。

7. **`PageFrame` 作为 frame-per-tab 形态的替代用法** — `PageFrame` 虽然设计上可独立用，但主窗口只用 `PageTabView`。frame-per-tab（每个 tab 一个独立 `PageFrame`、各搭工具条）的形态仍保留在 GUI 测试窗 [`Tests/PageControlTests/TabViewPageFrameTestWindow.swift`](./Tests/PageControlTests/TabViewPageFrameTestWindow.swift) 中，作为另一种装配模式的演示与回归点；它和 PageTabView 形成「frame-per-tab vs 共享单 frame」的对照测试。

## Window Shell (AppearanceWindow → NavigationViewWindow)

- **`AppearanceWindow`** — 见 [`Sources/RsUI/App/Windows/AppearanceWindow.swift`](./Sources/RsUI/App/Windows/AppearanceWindow.swift)。`class AppearanceWindow: Window`。窗口级主题/语言观察基底：构造时 `startObserving { (App.context.theme, App.context.language) } onChanged: { ... }`——值变化时（带 `isApplyingAppearance` 重入守卫 + `self.appWindow != nil` 死窗口守卫）触发公共 `let appearanceChanged = EventHandler<AppearanceWindow>()`。`closed` 里 `cancel()` 那个观测 Task。
- **`NavigationViewWindow`** — 见 [`Sources/RsUI/App/Windows/NavigationViewWindow.swift`](./Sources/RsUI/App/Windows/NavigationViewWindow.swift)。`class NavigationViewWindow: AppearanceWindow`。窗口壳三职责：TitleBar + NavigationView + 侧栏拖拽 Splitter，外加一个通用全屏宿主。
  - **对外窗口 UI 走命名元组**：`private(set) var ui: (root, titleBar, backButton, forwardButton, searchBox, titleBarRightHeader, navWrapper, navigationView, splitterBorder, fullscreenOverlay)!`，构造时一次性 `findName` 回填。`MainWindow` 与 `WindowTests` 都通过 `ui.titleBar`、`ui.navigationView.content = ...`、`ui.backButton.isEnabled` 这类形式访问；不存在独立的 `lazy var navigationView` 等延迟属性。
  - **静态结构在 XAML**（`xamlUI` 计算属性）：`Grid` 两行 + `TitleBar`（`TitleBar.IconSource` 用 `{x:IconPath}` 占位运行时替换；`TitleBar.Content` 内含 `BackButton`/`ForwardButton` 两个 `AppBarButton` 与 `SearchBox` AutoSuggestBox；`TitleBar.RightHeader` 内含 `RightHeader` 空占位 `StackPanel`）+ `NavWrapper` 内的 `NavigationView`（`PaneDisplayMode="Auto"`、`IsSettingsVisible="True"`、`IsTitleBarAutoPaddingEnabled="False"`、`CompactModeThresholdWidth="0"` 等创建期定值）+ 透明 `SplitterBorder` 占位 + 跨两行、ZIndex 在上的 `FullscreenOverlay` `Border`（默认 `Collapsed`）。`swift-winrt` **无 `x:Name` 绑定**，统一以 XAML 默认命名空间的 `Name="..."` 声明，加载后 `findName` 取回。
  - **运行时值与事件在 Swift**：`init(_ forceMinimalMode: Bool = false)` 走 `setupUI()` → 必要时强制 `paneDisplayMode = .leftMinimal` → `bindEvents()`。`setupUI()` 回填 `windowLayout.navigationViewPaneOpen`、`splitterBorder.protectedCursor`、初始 `splitterBorder.visibility` 与 `applyPaneLength(openPaneLength)`，并把窗口 `content` 设为 `root`、`setTitleBar(ui.titleBar)`。`bindEvents()` 绑 `titleBar.paneToggleRequested`、`paneClosed`/`paneOpened`（更新 splitter 可见性）、`bindSplitterEvents()`（splitter 的 `pointerPressed/Moved/Released/CaptureLost` 实现拖拽改 `navigationView.openPaneLength` + `expandedModeThresholdWidth` + `splitterBorder.margin`）、`bindWindowEvents()`（订阅 `appearanceChanged` 调整 caption / 标题 / Back·Forward ToolTip / SearchBox placeholder；订阅 `closed`：若全屏则先退出、按 `saveWindowLayoutPreferences` 决定是否写回 `windowLayout`）。
  - **窗口级偏好**：`private struct WindowLayout: PreferenceValue { minPaneLength=100; maxPaneLength=400; expandedModeThresholdContentWidth=688; paneOpen=true; openPaneLength=320 }`，由 `App.context.preferences` 持久化。`forceMinimalMode` 用一次性 viewer 窗（如 slide presenter）：`paneDisplayMode = .leftMinimal` 且 `saveWindowLayoutPreferences = false`（关窗不写回全局 `windowLayout`，不污染主窗口下次启动），用户手工展开后才重新写回。
  - **通用全屏宿主在窗口壳层**：`let fullscreenChanged = EventWithArgumentHandler<NavigationViewWindow, Bool>()` + `private(set) var isInFullscreen: Bool` + `func enterFullscreen(for element: UIElement)` / `func exitFullscreen()`。实现：进全屏时记录 `element.detachFromVisualParent()` 得到的 `(parent, index)`、`OverlappedPresenter.state`（出全屏还原 maximize）、装一次 Esc `KeyboardAccelerator`（`installedEscapeAccelerator` 守护，窗口最多装一次）；把元素 reparent 进 `ui.fullscreenOverlay`、置可见、`collapsed` 掉 `ui.titleBar`/`ui.navWrapper`、临时关 `extendsContentIntoTitleBar`、`hwnd.setPresenter(.fullScreen)`、`fullscreenChanged.invoke(self, true)`。退出反向。`MainWindow` 把 `enterFullscreenPage()`/`exitFullscreenPage()` 转发给 `enterFullscreen(for: pageControl.fullscreenView)`/`exitFullscreen()`，从而对 page control 透明。`WindowTests/App.swift` 里有独立的进/出全屏 + `fullscreenChanged` 验收。
  - **注意：Back/Forward 按钮完全在 XAML 声明（`AppBarButton Icon="Back"/"Forward"`），没有 Swift 画刷 override**——不存在旧文档所说的 `makeNavButton` 手写 `Color(a:0x18,...)` 灰色画刷路径；它已随 XAML 化迁移移除。
- **`WindowContextHost`** — 见 [`Sources/RsUI/App/Windows/WindowContextHost.swift`](./Sources/RsUI/App/Windows/WindowContextHost.swift)。`protocol WindowContextHost: AnyObject`，`internal`。`WindowContext` 弱引用它，把它对外暴露成 `hwnd`、进/出全屏、`open(_:mode:transitionInfoOverride:)` 两形态、`selectPage(matchingURL:)`。`MainWindow` 是目前唯一的实现。
- **`EventHandler` / `EventWithArgumentHandler`** — 见 [`Sources/RsUI/App/Windows/EventHandler.swift`](./Sources/RsUI/App/Windows/EventHandler.swift)。框架内部极简事件分发器（非 WinUI 投影）：`addHandler` 闭包追加到数组、`invoke(...)` 顺序调用，`appearanceChanged` / `fullscreenChanged` / `pageChanged` 都用它。
- **`TabViewWindow`** — 见 [`Sources/RsUI/App/Windows/TabViewWindow.swift`](./Sources/RsUI/App/Windows/TabViewWindow.swift)。目前是占位（`class TabViewWindow: AppearanceWindow {}`），留给未来以 `TabView` 为主的窗口形态演进。

## File Organization

```
Sources/RsUI/
  App/
    App.swift                          — `open class App: SwiftApplication`, single-instance, module init, launch / activation / shutdown, MainWindow creation
    Windows/
      AppearanceWindow.swift           — `class AppearanceWindow: Window`; theme/language Observation + `appearanceChanged` Event
      NavigationViewWindow.swift       — TitleBar + NavigationView + Splitter window shell + generic fullscreen host (XAML-first); also defines private `WindowLayout` PreferenceValue
      WindowContextHost.swift          — internal protocol that `WindowContext` weakly wraps (`hwnd`, fullscreen, `open`, `selectPage(matchingURL:)`)
      EventHandler.swift               — minimal generic event dispatchers (`EventHandler<T>`, `EventWithArgumentHandler<T,U>`)
      TabViewWindow.swift               — placeholder window subclass reserved for future TabView-first windows
    MainWindow/
      MainWindow.swift                 — `class MainWindow: NavigationViewWindow, WindowContextHost`; owns a `PageTabView` via `pageControl: PageControl`, wires shell events to it, implements `WindowContextHost`
      MainWindow+TearOutTabs.swift     — RESERVED: entire body is a `/* ... */` block comment containing disabled tear-out scaffolding (do NOT treat as live code; see Tab Tear-Out pitfall)
    PageControls/
      PageModels.swift                  — `class PageModel` (backwardPages / forwardPages / currentPage, navigate/goBack/goForward, capped by `App.context.route.maxHistoryPages`)
      PageTransitionHost.swift          — `class PageTransitionHost: Grid`; wrapper-based enter/exit slide+fade Storyboard transitions (200ms, 40px); handles `Suppress*` / `Slide*` transition info
      PageControl.swift                 — internal `protocol PageControl`: the shared `navigate + render + pageChanged` surface for PageFrame / PageTabView
      PageFrame.swift                   — `class PageFrame: PageTransitionHost, PageControl` (single page-stack; `rebind(to:)` for sharing across tabs)
      PageTabView.swift                 — `class PageTabView: Grid, PageControl` (WinUI.TabView strip + one shared PageFrame; strip auto-hide ≤1 tab; `CanTearOutTabs="False"` in XAML)
      Page+View.swift                   — `extension Page { var view: UIElement }`: standard header/content Grid built from XAML
    Settings/
      SettingsPage.swift                — `class SettingsPage: Page` with `static let url = "rs://ui/settings"`; imperative content (personalization combo + per-module groups + about / dependencies)
  Controls/
    NavigationViewItem+Extensions.swift — `startObserving` mirror + `static build(icon( ​:iconGlyph):label:url:)` factories and `build(…:actionGlyph:actionTooltip:actionHandler:)` (the url is stored in `tag` as `HString`)
    SettingsCard.swift                  — Fluent-style settings row
    SettingsExpander.swift              — Expander for nested rows
    SettingsGroup.swift                 — Group container with title
    SettingsBrushes.swift               — Theme-aware brush factories (also contains a `UWP.Color(a:0x18,...)` call for a card top-stop, not for nav buttons)
    ChevronIcon.swift                   — Chevron glyph helper
  Support/
    AppInstance+Extensions.swift        — `AppInstance.redirectOrRegister(for:onActivated:)` single-instance extension
    JumpList+Extensions.swift           — `JumpList.register(arguments:displayName:logo:)` taskbar jump-list extension
    NavigationTransitionInfo+Extensions.swift — `static func make(slideEffect:)` factory
    NavigationView+Extensions.swift     — `selectItem(with:)`, `selectFirstItem()`, `firstItemURL`, settings-item handling
    NavigationViewItemBase+Extensions.swift — `var url: URL?` computed from `tag as? HString`
    ProgressBar+Extensions.swift / ProgressRing+Extensions.swift — `startObserving` mirrors
    RuntimeInfo+Extensions.swift        — `static var sdkVersion` mapping Windows App SDK 1.8.x versions to display strings
    TabView+Extentions.swift            — `var canAutoCloseTabs` setter-only convenience (pairs `tabCloseRequested` to strip removal)
    UIElement+Extensions.swift          — `detachFromVisualParent()` / `attachToParent(_:index:)` canonical single-parent helpers
    Window+Extensions.swift             — `useMicaBackdrop()`, `useRestoration(_:)`, `startObserving(_:onChanged:)`; defines private `WindowPosition` PreferenceValue
  Models/
    AppContext.swift                    — `@Observable public final class AppContext` (theme/language/route/modules/preferences + bootstrap / tr / openNewWindow)
    AppTheme.swift                      — `enum AppTheme: RawPreferenceValue` (undefined/dark/light/auto + applicationTheme/elementTheme/titleBarTheme helpers)
    AppLanguage.swift                   — `enum AppLanguage: RawPreferenceValue` (undefined/en_US/zh_CN/auto + availableCases/displayName/locale)
    AppRoute.swift                      — `struct AppRoute: PreferenceValue` (maxHistoryPages=32, lastPageURL)
    Module.swift                        — `public protocol Module: ExpressibleByEmptyLiteral` with defaultable methods
    Page.swift                          — `public protocol Page: AnyObject` (url/title/header/content + `windowContextDidChange(to:)` + `startObserving`)
    WindowContext.swift                 — `public struct WindowContext` (NavigationOpenMode enum + open/openOrFocus/pickFolder/fullscreen)
Samples/
  SampleApp/
    SampleApp.swift                     — `@main class SampleApp: App`; registration via `super.init(group:product:resourceBundle:moduleTypes:)`
    SampleModule/SampleModule.swift     — `@Observable final class SampleModule: Module`; demo of nav items / footer items / settingsGroup / navigationDidRequest
    SampleModule/Pages/*.swift          — demo pages (Overview / Fullscreen / NavigationModes / OpenOrFocus / BatchOpen / NewWindow / Appearance / FolderPicker + FeaturePageHelpers)
  Assets/                               — SampleApp.ico / .rc / .res / Localizable.xcstrings / SettingsPage.xcstrings
Tests/
  RsUITests/PageModelTests.swift        — Swift Testing `@Suite struct PageModelTests`: PageModel navigate/goBack/goForward/history-limit/clears-forward history
  PageControlTests/                     — GUI test host executable target
    App.swift                           — launches PageControlTestWindow(mode: .frame/.tabView) + TabViewPageFrameTestWindow()
    MockPages.swift                     — test Page impls (string/UIElement/nil header) + `makePage(name:headerKind:effect:)` helper
    PageControlTestWindow.swift          — single window, runs PageFrame or PageTabView behind a shared `any PageControl`, drives Back/Forward/+Page polymorphically; reads `PageTabView.tabCount` to assert strip auto-hide
    TabViewPageFrameTestWindow.swift    — frame-per-tab demonstration (each TabViewItem.content = toolbar + PageFrame; `framesByName` keyed by `TabViewItem.name`)
  WindowTests/                          — window-shell GUI test host executable target
    App.swift                           — raw `NavigationViewWindow` + `useMicaBackdrop`/`useRestoration`, and a fullscreen element enter/exit / `fullscreenChanged` test
```

## Coding Conventions

- **Line Break**: Always use LF (Unix).
- **Comments**: The package is unstable, so do NOT require documentation comments (`///`) on public declarations. Do not flag missing doc comments as issues in reviews; focus on naming, labels, logic, and API shape instead. Internal comments (`//`) for non-obvious code are welcome. All comments (and this file) are advisory — code always wins.
- **Code sectioning**: `// MARK: -` comments for logical sections.
- **Projected APIs**: Use the projected APIs in the packages of swift-foundation, swift-uwp, swift-windowsappsdk, swift-winui (and swift-cppwinrt when needed) for Windows features.
- **UI construction — XAML-first (target direction)**: Build static layouts from XAML strings loaded with `XamlReader.load`, then retrieve named controls with `findName` and wire runtime values / event handlers in Swift. Avoid long chains of imperative `Control()` + property assignment + `children.append` when XAML can express the layout compactly. The shell (`NavigationViewWindow`), `PageTabView`, and the GUI test windows all follow this pattern; `Page+View.swift` is a small example of a page's own rendering.
- **Mixed fallback**: `SettingsPage.swift` and several `Controls/` (per `SettingsCard` etc.) still build most UI imperatively with `children.append`. Treat that as existing tech debt, not a pattern to copy. Keep a concise imperative fallback only where XAML genuinely cannot express the layout.
- **Event handling**: `addHandler { [weak self] _, args in ... }` with weak capture lists; inside the handler, prefer calling ViewModel / model methods over mutating controls directly.
- **Type casting**: `as? Type` → `let` → safe-unwrap chain.
- **Preferences**: `PreferenceValue` protocol (with `RawPreferenceValue` conformance for simple raw-representable enums).

### UI & MVVM Conventions

- **Architecture pattern — MVVM**: Follow Model-View-ViewModel. ViewModels are the source of truth for UI state. Mark ViewModel types `@Observable` (see `AppContext` in `Models/` and `SampleModule` in `Samples/`). In event-handler closures, call ViewModel methods rather than mutating UI controls directly.
- **Observation driver**: UI reacts to `@Observable` state through the `Observations` async-sequence helper from `RsFoundation`, surfaced via `startObserving(emitting:onChanged:)` extended on `Page` (`Page.swift`), `NavigationViewItem` (`Controls/NavigationViewItem+Extensions.swift`), `ProgressBar`/`ProgressRing` (`Support/`), and `Window` (`Support/Window+Extensions.swift`). Prefer this flow: emit the relevant ViewModel state, run the update on `MainActor`, and mutate UI only inside the `onChanged` callback. (The concrete `appearanceChanged` / `fullscreenChanged` shells — `AppearanceWindow` and `NavigationViewWindow` — additionally expose a plain `EventHandler`/`EventWithArgumentHandler` for surface-level one-shot fan-out that is not tied to a long-lived ViewModel.)

### Naming Conventions for Events & Templates

Use the **API Design Guidelines** of swift.org as basic standard for naming.

Besides, GUI callback and template-method naming follows four distinct rules — do not collapse them into a single "on X Changed" / "X Changed" style.

- **Observation-callback closure parameters**: the tense suffix is decided by *when the callback fires relative to the change*:
  - Fires **before** the change → `onChange` (about-to-change semantics). Example: `Observation.withObservationTracking(_:onChange:)` re-runs `apply` later, so the closure runs before re-application — `onChange` is correct.
  - Fires **after** the change → `onChanged` (already-changed semantics). Example: `startObserving(emitting:onChanged:)` runs the callback once the `Observations` async sequence has emitted a new value, so the new value is already produced — `-ed` is correct, not a Windows-ism.
  - Add the observed entity when it aids clarity (`onTabClosed`, `onDocumentLoaded`). For pure "notify me of what just emitted" drivers, `onChanged` alone is fine.
- **Delegate / life-cycle methods** (protocol member, `will`/`did`): `will` for "about to happen", `did` for "already happened" + past-tense verb, e.g. `tabWillClose(_:)`, `tabDidClose(_:)`, `applicationDidEnterBackground(_:)`. Do NOT use the C# `onClosing`/`onClosed` prefix for Swift delegate protocols — `on` is reserved for the closure-parameter form above. (The existing `Page.windowContextDidChange(to:)` follows this convention.)
- **Protocol "provide something" requirements** (template methods returning a value): plain noun phrase or noun phrase + context label, no `Required` / `get` suffix: `titleBarRightHeaderItem(in:)`, `settingsGroup()`, `navigationViewMenuItems(in:)`, `navigationViewFooterMenuItems(in:)`, `navigationDidRequest(for:in:)`. Reserve the `make` prefix for factory methods constructing a new object: `makePage(for:in:)`, `IteratorProtocol.makeIterator()`.
- **WinUI event-handler closures**: the event-property name is fixed by the swift-winrt projection (`loaded`, `selectionChanged`, `click`, `sizeChanged`, `itemInvoked`, `paneClosed`, `paneOpened`, `tabCloseRequested`, `addTabButtonClick`, `pointerPressed`…) — do not rename it. Inside `addHandler { … }`, use `[weak self] _, args in`; the first parameter (`sender`) is usually ignored, so prefer `_` over an unused `sender` label.

## Important Pitfalls

### Swift on Windows Specifics
- This is NOT Apple Swift. Some toolchain behaviors and available APIs differ.
- All WinUI types are WinRT projections. `HString`, `AnyIVector<Any?>`, `Uri`, `Color`, etc. are projection types, not native Swift types.

### COM Callback Exceptions
- Swift exceptions thrown inside COM callback paths do NOT propagate correctly to the main thread. The process won't terminate but UI operations will fail silently. Prefer `try?` / `do-catch`-to-log at WinRT call boundaries and surface failures through logging (`log.warning`), not through thrown errors.

### UIElement Single-Parent Rule
- A `UIElement` can only have one visual parent. Before reparenting, you MUST remove it from its current parent. The canonical helpers live in [`Support/UIElement+Extensions.swift`](./Sources/RsUI/Support/UIElement+Extensions.swift): `detachFromVisualParent() -> (parent: UIElement, index: UInt32?)?` (handles `Border` / `Panel` / `ContentControl` / `ContentPresenter`, logs for unsupported parents) and `attachToParent(_:index:)` (reverse — `Panel` branch uses `insertAt` with a clamped index).
- `PageTransitionHost`/`PageFrame` do not reuse a single page `view` element across page swaps; each swap builds a fresh page `view` and wraps it in a new `Border`, so there is no cross-page reparenting inside the frame.
- The one production reparenting path is window-level fullscreen in `NavigationViewWindow`: `enterFullscreen(for:)` calls `element.detachFromVisualParent()`, reparents into `ui.fullscreenOverlay`, and `exitFullscreen()` calls `attachToParent(_:index:)` to restore. `MainWindow`'s `enterFullscreenPage()`/`exitFullscreenPage()` route through it; do not add parallel reparenting code.

### Single-Instance Coordination
- Single-instance is provided by `AppInstance.redirectOrRegister(for:onActivated:)` (`Support/AppInstance+Extensions.swift`). The framework key is `"\(group)/\(product)"`. When a second instance launches, `isCurrent` is `false`: it fetches its activation args, redirects them to the running instance via `redirectActivationToAsync`, logs and `exit(0)`. The primary instance's `activated` handler is wired to `App.onActivated(_:)`, which currently activates a fresh `MainWindow`. (There is **no** type called `AppInstanceCoordinator` in this codebase — that name in earlier docs is obsolete.)
- Taskbar "New Window" is the JumpList entry registered in `App.onLaunched` via `JumpList.register(arguments: "--new-window", …)`; the same `onLaunched` honors `--new-window` in `CommandLine.arguments` or launch `args.arguments` and activates a fresh `MainWindow`.

### Tab Tear-Out Currently Disabled
- Native WinUI tab tear-out is **fully disabled**. The single `WinUI.TabView` declared in `PageTabView`'s XAML hard-codes `CanTearOutTabs="False"` (along with `CanDragTabs="True"` / `CanReorderTabs="True"`); 
- The cross-window tear-out / merge / spare-receiver / pending-state scaffolding still exists in [`MainWindow+TearOutTabs.swift`](./Sources/RsUI/App/MainWindow/MainWindow+TearOutTabs.swift), but **the entire file body is wrapped in a `/* ... */` block comment** — it does NOT compile into the binary and must NOT be treated as live code. It is kept as a future rehabilitation site for when the two known WinUI `CanTearOutTabs` bugs (referenced in the commented XAML in `PageTabView.swift`: `microsoft-ui-xaml#10155` and `#11170`) are fixed. When you need tear-out behavior back, uncomment that file and flip the XAML flag; until then, ignore its internals.

### C# Documentation Requires Conversion
- Microsoft's official WinUI docs, samples, and Stack Overflow answers are ALL in C# / XAML. They cannot be used directly in swift-winrt. Key conversions:
  - XAML declarative UI → Swift imperative construction (no `{x:Bind}`, no XAML resource dictionaries as scriptable dictionaries; here XAML is only ever loaded as a *string* via `XamlReader.load`).
  - C# PascalCase properties → Swift camelCase (e.g. `IsPaneOpen` → `isPaneOpen`, `CanTearOutTabs` → `canTearOutTabs`).
  - C# event syntax (`+=`) → Swift `addHandler` closures.
  - C# `async/await` → Swift `async/await` (via the WinRT-projected `IAsyncOperation` / `get()`).
  - C# `IList<T>` → Swift `AnyIVector<Any?>` projection type.
  - You CAN reference C# docs for API discovery, but MUST convert to the swift-winrt projection rules when writing code.

## Module Development Guide

To create a new module:

1. Implement the `Module` protocol (conform to `ExpressibleByEmptyLiteral`) and give it `let id: String`.
2. Register the module type from your `App` subclass convenience init:
   ```swift
   super.init(group: "Group", product: "Product",
              resourceBundle: Bundle.module,
              moduleTypes: [YourModule.self])
   ```
   See `Samples/SampleApp/SampleApp.swift`.
3. Use URL routing format `rs://{moduleId}/{path}`. Support the root (`rs://{moduleId}` / `""` / `/`) as the module landing page (see `SampleModule.navigationDidRequest`).
4. Return `Page?` from `navigationDidRequest(for url: URL, in context: WindowContext)`. Match `url.host == self.id`, then switch on `url.path`.
5. Provide navigation items via `navigationViewMenuItems(in context: WindowContext) -> [NavigationViewItemBase]` (use `NavigationViewItem.build(iconGlyph:label:url:)` and action variants; the URL is stored in `tag` as `HString` and read back via `NavigationViewItemBase.url`). Optionally add footer items via `navigationViewFooterMenuItems(in:)`.
6. Contribute a settings group via `settingsGroup() -> (title: String, cards: [UIElement])?`. The built-in settings page (`SettingsPage`) collects all modules' groups automatically.
7. Optionally contribute a title-bar right header element via `titleBarRightHeaderItem(in:)` (e.g. a `ProgressRing` observing module state — see `SampleModule`).
8. Use `WindowContext` (passed into every `titleBarRightHeaderItem(in:)` / `navigationViewMenuItems(in:)` / `navigationViewFooterMenuItems(in:)` / `navigationDidRequest(for:in:)` call, and delivered to pages) for navigation (`open(_:mode:)`, `openOrFocus(_:)`), folder picking (`pickFolder`), and fullscreen. If a page caches a `WindowContext`, update it in `windowContextDidChange(to:)`.

## AI-Assisted Development

### Available Skills
- **`winui-design`** — WinUI 3 design guidance: layout, control selection, Fluent Design, theming, accessibility, spacing. Load before authoring new UI or reviewing UI PRs.
- **`winui-code-review`** — WinUI 3 code quality review: MVVM compliance, x:Bind correctness, accessibility, theming, security, performance. Use before committing.
- **`swift-api-design-guidelines`** — Swift API Design Guidelines: argument labels, naming, `mutating`/`nonmutating` pairs, etc.

### Documentation Strategy
When encountering WinUI 3 API questions:
1. **First**: Query the Microsoft Learn MCP server for official documentation.
2. **Remember**: Official docs are C# — apply the conversion rules from "C# Documentation Requires Conversion" above.
3. **If MCP is unavailable**: Refer to the swift-winrt repository (github.com/rayman-zhao/swift-winrt) for projection rules.
4. **Best reference**: Existing codebase — search for similar patterns first when unsure about usage.
