# Changelog

Notable changes to RsUI. Format follows [Keep a Changelog](https://keepachangelog.com/); versions are tagged on `main`.

## [Unreleased]

### Breaking

- **`Module.settingsGroup()` now returns `SettingsGroup?`** instead of `(title: String, cards: [UIElement])?`. Modules construct the group themselves, so they control `isExpandable` and the initial `isExpanded` (previously `SettingsPage` always wrapped the tuple in an expandable group). `SettingsPage` appends the returned group as-is.

## [0.1.0] — 2026-09-21

First tagged version. Changes below are summarized from the `main` history before this tag (the full-review refactor batches); "Breaking" entries are relative to earlier `main` commits that downstream projects may still target.

### Breaking

- **`SettingsGroup.expand` renamed to `isExpandedChanged`** (matches the `pageChanged` / `valueChanged` past-tense convention; fires with the new `isExpanded` value after a user toggle).
- **`NavigationViewWindow.init(_ forceMinimalMode:)` gained a parameter label**: `init(forceMinimalMode: Bool = false)`. Positional callers must switch to the labeled form.
- **`SettingsExpander` has a single data source**: the init `items:` parameter now writes directly into the public `itemsSource` property (initialization does not trigger `didSet`). Assigning `itemsSource = nil` no longer falls back to init-provided items — it means "no items".
- `WindowContextHost.hwnd` is now `WindowId?` (internal protocol): `MainWindow` returns `appWindow?.id`, so `WindowContext.pickFolder` / `pickSaveFile` become a silent no-op after the host window closes instead of trapping on the nil IUO.

### Behavior changes

- `PageTabView`: closing the last remaining tab now rebinds the shared `PageFrame` to an empty `PageModel` and fires `pageChanged(nil)`, letting the host reopen the first nav item. Previously the closed page stayed rendered with the strip hidden and no way back.
- `PageControl.navigate(to pages:) -> Int` (both conformances) now returns **the number of pages actually opened**; previously `PageTabView` returned the total tab count.
- `AppInstance.redirectOrRegister`: the second instance now waits for the activation redirect to complete (5s timeout guard) before `exit(0)` — fixes the flaky "second launch doesn't focus the running window".
- Fullscreen round-trips save and restore `extendsContentIntoTitleBar` (previously hardcoded back to `true`, corrupting caption layout on windows that never used `useMicaBackdrop()`).
- `SettingsCard` / `SettingsExpander` refresh their Fluent token brushes on `actualThemeChanged` (previously stale until the next pointer state change).
- `SettingsExpander` / `SettingsGroup` / `ChevronIcon` coalesce expand/collapse requests that arrive mid-animation instead of dropping them (`pendingExpanded` replay; chevron continues from the current angle).
- `RangeSlider.snapped(_:)` anchors its step grid at `minimum`, matching `settleToStep()` — values no longer jump on release when `minimum != 0`.
- `exitFullscreen` force-resets local state (with a warning log) if the fullscreen state ever diverges, instead of staying stuck.
- `App.onLaunched` no longer has a `--new-window` flag helper; launches with `--new-window` (e.g. the JumpList entry) reach the primary instance through single-instance redirection → `onActivated` opens the new window.

### Added

- `EventHandler` / `EventWithArgumentHandler`: `addHandler` returns an `EventHandlerToken`, and `removeHandler(_:)` unregisters.
- All five `startObserving(_:onChanged:)` mirrors (`Page`, `NavigationViewItem`, `ProgressBar`, `ProgressRing`, `Window`) return a cancellable `Task<Void, Never>` and share one implementation (`Support/StartObserving.swift`).
- `fluentThemeBrush(_:)` shared Fluent token brush lookup (`Support/Brush+Extensions.swift`).
- Automation names for icon-only controls: shell Back/Forward, tab-strip "close others", `SettingsGroup` expand toggle, `SettingsPage` theme/language combos; `NavigationViewItemWithAction` label gets `textTrimming`.
- `AppearancePage` MVVM reference implementation (`@Observable` view model + observation-driven UI + cancel-on-rebuild).
- Unit test suites: `PageModelTests`, `RangeSliderStateTests` (minimum-anchored snap), `GridViewSelectionModelTests`, `ModelsTests` (AppTheme / AppLanguage / AppRoute). 39 tests total.
- Sample helpers: `makeClickableCard`, `makeCaption`, `makeSectionTitle/Subtitle`, `sampleModuleID` single source for module routes; sample captions use `TextFillColorSecondary/TertiaryBrush` instead of hardcoded grays.

### Fixed

- `PageTabView.navigate(to: [])` no longer traps (bounds guard + `as?` instead of `as!`).
- `SettingsCard` description is built as a plain `TextBlock` — text containing `&` / `<` / `>` no longer crashes `XamlReader`.
- `SettingsPage` combo `selectedIndex == -1` (deselect events) no longer crashes / flips the theme.
- `Viewer` splitter drag handlers no longer retain the splitter (self-reference cycle); `setPaneLengthRange` logs on unsupported edges.
- `AppBarButton.makeIconOnly` XML-escapes the glyph substitution.
- `AppContext.iconAppxUri` returns `nil` with a warning when the icon is not under the package root (no malformed `ms-appx://` URI); `openNewWindow` logs activation failures instead of swallowing them.
- `AppRoute.maxHistoryPages` is clamped to a minimum of 1 (runtime `didSet` + after-preferences-load guard).
- Numerous `(try? …) as!` force casts replaced with guarded fallbacks across samples and GUI test hosts.

### Known limitations

- `AppTheme.auto` always resolves to dark; real system-theme following needs `UISettings` projected into swift-uwp (TODO in code).
- Native tab tear-out remains disabled (`CanTearOutTabs="False"`, see the two linked microsoft-ui-xaml issues in `PageTabView`).
- GridView marquee selection re-syncs at O(n) per pointer-move frame; fine for small lists, unmeasured for large ones.
- `PageControl` is internal; hosts outside the RsUI module cannot drive `PageFrame` / `PageTabView` polymorphically.
