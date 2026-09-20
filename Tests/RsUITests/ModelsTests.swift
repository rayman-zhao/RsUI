import Foundation
import Testing
import WinAppSDK
import WinUI

@testable import RsUI

@Suite
struct AppThemeTests {
    @Test
    func explicitThemesMapConsistently() {
        #expect(AppTheme.dark.isDark)
        #expect(!AppTheme.light.isDark)
        #expect(AppTheme.dark.applicationTheme == .dark)
        #expect(AppTheme.light.applicationTheme == .light)
        #expect(AppTheme.dark.elementTheme == .dark)
        #expect(AppTheme.light.elementTheme == .light)
        #expect(AppTheme.dark.titleBarTheme == .dark)
        #expect(AppTheme.light.titleBarTheme == .light)
    }

    @Test
    func undefinedDefaultsToDark() {
        #expect(AppTheme() == .undefined)
        #expect(AppTheme.undefined.isDark)
    }

    @Test
    func toggleSwitchesBetweenDarkAndLight() {
        var theme = AppTheme.dark
        theme.toggle()
        #expect(theme == .light)
        theme.toggle()
        #expect(theme == .dark)
    }
}

@Suite
struct AppLanguageTests {
    @Test
    func availableCasesExcludeUndefinedAndAuto() {
        #expect(AppLanguage.availableCases == [.en_US, .zh_CN])
    }

    @Test
    func displayNamesAndLocales() {
        #expect(AppLanguage.en_US.displayName == "English")
        #expect(AppLanguage.zh_CN.displayName == "简体中文")
        #expect(AppLanguage.en_US.locale.identifier == "en")
        #expect(AppLanguage.zh_CN.locale.identifier == "zh-Hans")
        // undefined/auto 兜底英文 locale
        #expect(AppLanguage.undefined.locale.identifier == "en")
        #expect(AppLanguage.auto.locale.identifier == "en")
    }

    @Test
    func initResolvesToUndefined() {
        #expect(AppLanguage() == .undefined)
    }
}

@Suite
struct AppRouteTests {
    @Test
    func defaults() {
        let route = AppRoute()
        #expect(route.maxHistoryPages == 32)
        #expect(route.lastPageURL == nil)
    }
}
