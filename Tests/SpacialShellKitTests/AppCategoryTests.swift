import Testing
@testable import SpacialShellKit

@Suite struct AppCategoryTests {
    /// The measurement that justifies the table existing at all: every browser on a real machine
    /// either declares nothing or declares `productivity`, so the system key can never say "web".
    @Test func browsersAreWebDespiteWhatMacOSSaysAboutThem() {
        #expect(AppCategories.category(bundleID: "com.google.Chrome", systemCategory: nil) == .web)
        #expect(AppCategories.category(bundleID: "com.brave.Browser", systemCategory: nil) == .web)
        #expect(AppCategories.category(bundleID: "com.apple.Safari",
                                       systemCategory: "public.app-category.productivity") == .web)
        #expect(AppCategories.category(bundleID: "org.mozilla.firefox",
                                       systemCategory: "public.app-category.productivity") == .web)
    }

    /// macOS has no terminal category, so the table is the only possible source.
    @Test func terminalsHaveNoSystemCategoryToFallBackOn() {
        #expect(AppCategories.category(bundleID: "com.apple.Terminal") == .terminal)
        #expect(AppCategories.category(bundleID: "com.mitchellh.ghostty") == .terminal)
        #expect(AppCategories.fromSystem("public.app-category.developer-tools") != .terminal)
    }

    @Test func systemCategoryIsTheFallbackForUnknownApps() {
        #expect(AppCategories.category(bundleID: "com.example.Unheard",
                                       systemCategory: "public.app-category.developer-tools") == .coding)
        #expect(AppCategories.category(bundleID: "com.example.Unheard",
                                       systemCategory: "public.app-category.utilities") == .utilities)
    }

    /// No answer is a real answer. A wrong label on the rail is worse than a blank one.
    @Test func unknownEverythingIsUnlabelled() {
        #expect(AppCategories.category(bundleID: "com.example.Unheard", systemCategory: nil) == nil)
        #expect(AppCategories.category(bundleID: nil, systemCategory: nil) == nil)
        #expect(AppCategories.category(bundleID: "com.example.Unheard", systemCategory: "public.app-category.games") == nil)
    }

    @Test func overrideBeatsTheTableAndTheSystem() {
        let o: [String: AppCategory] = ["com.apple.Safari": .productivity, "com.example.Unheard": .terminal]
        #expect(AppCategories.category(bundleID: "com.apple.Safari", systemCategory: nil, overrides: o) == .productivity)
        #expect(AppCategories.category(bundleID: "com.example.Unheard",
                                       systemCategory: "public.app-category.developer-tools", overrides: o) == .terminal)
    }

    @Test func summariseTakesTheWeightOfTheRow() {
        #expect(AppCategories.summarise([.coding, .web, .coding]) == .coding)
        #expect(AppCategories.summarise([nil, .web, nil]) == .web)
        #expect(AppCategories.summarise([nil, nil]) == nil)
        #expect(AppCategories.summarise([]) == nil)
    }

    /// A tie goes to whatever came first in the row, so the label does not flicker between two
    /// equally-weighted categories as unrelated windows come and go.
    @Test func tiesGoToTheFirstInTheRow() {
        #expect(AppCategories.summarise([.web, .coding]) == .web)
        #expect(AppCategories.summarise([.coding, .web]) == .coding)
    }

    /// #183: the one name a row goes by, on the hover card and in the spatial view alike. Its
    /// category, capitalised; else its stored name; never a row number.
    @Test func aRowIsTitledByItsCategoryElseItsName() {
        #expect(AppCategories.rowTitle(name: "Code", category: .web, isTrailingEmpty: false) == "Web browsing")
        #expect(AppCategories.rowTitle(name: "Code", category: .terminal, isTrailingEmpty: false) == "Terminal")
        #expect(AppCategories.rowTitle(name: "Code", category: nil, isTrailingEmpty: false) == "Code")
        #expect(AppCategories.rowTitle(name: "Workspace", category: .web, isTrailingEmpty: true) == "New workspace")
    }

    /// A category the row carries is its identity; otherwise its apps decide, one vote per app.
    @Test func aRowsCategoryIsItsOwnElseItsAppsSummarised() {
        let windows = [WindowRef(id: 1, pid: 1), WindowRef(id: 2, pid: 1), WindowRef(id: 3, pid: 1),
                       WindowRef(id: 4, pid: 2), WindowRef(id: 5, pid: 3)]
        let categoryOf: (Int32) -> AppCategory? = { [1: .web, 2: .coding, 3: .coding][$0] }
        #expect(AppCategories.rowCategory(nil, windows: windows, categoryOf: categoryOf) == .coding)
        #expect(AppCategories.rowCategory(.media, windows: windows, categoryOf: categoryOf) == .media)
        #expect(AppCategories.rowCategory(nil, windows: [], categoryOf: categoryOf) == nil)
    }
}
