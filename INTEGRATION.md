# Integrating RsUI into an App

This guide is for **consumers** of RsUI (apps built on the framework). For working *on* RsUI itself — architecture, conventions, pitfalls — see [`AGENTS.md`](./AGENTS.md); for the API surface tour see [`README.md`](./README.md).

## Requirements

- Swift for Windows toolchain matching `swift-tools-version: 5.10`
- Windows App SDK 1.8+ runtime
- Dependencies resolve from the `rayman-zhao/*` forks (see `Package.swift`); pin with your own committed `Package.resolved`

## 1. Package setup

Reference a tagged version (recommended over `branch: main` — breaking changes are announced in [`CHANGELOG.md`](./CHANGELOG.md) per tag):

```swift
dependencies: [
    .package(url: "https://github.com/rayman-zhao/RsUI", from: "0.1.0"),
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [.product(name: "RsUI", package: "RsUI")],
        resources: [.process("Assets")],   // your Localizable.xcstrings, icon, .rc/.res
        linkerSettings: GUILinkerSettings  // see §2 — required
    ),
]
```

## 2. Executable linker settings (required)

GUI executables must copy the linker block from RsUI's own `Package.swift`:

```swift
let GUILinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS"], .when(configuration: .release)),
    .unsafeFlags(["-Xlinker", "/ENTRY:mainCRTStartup"], .when(configuration: .release)),
    .unsafeFlags(["-Xlinker", "path/to/YourApp.res"]),   // compiled Win32 resources
]
```

Without `/SUBSYSTEM:WINDOWS` a release build flashes a console window; without `mainCRTStartup` the release entry point is wrong. The `.res` carries your icon and version info (compile the `.rc` with `rc.exe`; no regeneration step is automated yet).

## 3. Entry point

```swift
@main
class MyApp: App {
    required init() {
        super.init(
            group: "MyCompany",              // single-instance key = "\(group)/\(product)"
            product: "MyApp",
            resourceBundle: Bundle.module,   // your .xcstrings live here
            moduleTypes: [HomeModule.self, ...])
    }
}
```

Facts your app inherits:

- **Single instance** keyed on `"\(group)/\(product)"`. A second launch redirects its activation args to the primary and exits. The JumpList "New Window" entry (`--new-window`) is handled through this redirect → `App.onActivated` opens a fresh `MainWindow`.
- **Preferences** persist under the app-support directory `…/<group>/<product>/` (via RsFoundation `JSONPreferences`).
- **Route restoration**: the last visited page URL is persisted and reopened on launch.

## 4. JumpList icon contract

The taskbar JumpList entry uses `App.context.iconAppxUri`, which resolves to **`<productName>.ico` inside your resource bundle, expected under the package root (exe directory)**. Concretely:

- Name your icon file exactly `\(productName).ico` (e.g. product `"MyApp"` → `MyApp.ico`).
- If the icon is missing or not under the package root, `iconAppxUri` returns `nil` with a warning log and the JumpList entry simply has no logo — nothing crashes, but check the log if the logo doesn't show.

## 5. Localization key contract

RsUI is a library: **its user-facing strings are looked up in *your app's* `.xcstrings` tables** through `App.context.tr`. Missing keys fall back to the key text itself (English). Your tables must provide:

**Root table (`Localizable.xcstrings`)** — shell & control strings:

| Key | Where |
|-----|-------|
| `newWindow` | JumpList "New Window" display name |
| `Back`, `Forward`, `Search ...` | shell title bar |
| `CloseOthers` | tab-strip "close others" button |
| `Expand or collapse` | `SettingsGroup` expand toggle |
| `OK` | `WindowContext.showDialog` fallback close button |

**`SettingsPage.xcstrings` table** — the entire built-in settings page (theme/language/personalization, per-module group chrome, about/dependencies sections; ~60 keys). Copy `Samples/Assets/SettingsPage.xcstrings` from the RsUI repo as your starting point and translate. **If you don't ship this table, the settings page renders in English.**

## 6. Module & page author rules (the short list)

- **`Page.content` is re-evaluated on theme/language change.** Never store UIElements across content rebuilds and never assume a previous build's element tree is still valid — build fresh every time (see `FullscreenPage` for the "store only what's currently mounted" pattern). Localize inside `content` so strings refresh.
- **`startObserving` returns a cancellable `Task`.** If you observe inside `content` (recommended), cancel the previous tasks first so stale tasks stop updating detached controls — see `AppearancePage` for the full MVVM pattern (`@Observable` view model, event handlers only touch the view model).
- Cache a `WindowContext`? Rebind it in `windowContextDidChange(to:)` (fires on fullscreen toggle and window changes).
- WinRT calls in event handlers: `try?` or do-catch-to-log; Swift errors must not cross COM callback boundaries.
- Custom dialogs: parent them to the host window and pin `requestedTheme` from the host window's `actualTheme` — the popup layer does not inherit the app theme (RsUI does this internally for `WindowContext.showDialog`; your own dialogs need the same treatment).
- URL routing: `rs://{moduleId}/{path}`; support the bare root as the module landing page.

## 7. Known limitations to code around

- Theme setting only supports dark/light; `.auto` currently resolves to dark (see CHANGELOG).
- Tab tear-out is disabled; use `App.context.openNewWindow(with:)` for multi-window flows.
- `PageControl` is internal — build your own host composition if you need `PageFrame`/`PageTabView` outside the provided `MainWindow` shell.
- GridView marquee selection is O(n) per pointer-move; keep item counts moderate until measured.
