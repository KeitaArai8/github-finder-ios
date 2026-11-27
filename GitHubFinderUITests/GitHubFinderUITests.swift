//
//  GitHubFinderUITests.swift
//  GitHubFinderUITests
//
//  Created by k-arai on 2026/04/12.
//

import XCTest

final class GitHubFinderUITests: XCTestCase {

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        // 向きでタブバーの構成が変わるため、縦向きに固定する
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - CUJ: 起動時の初期画面

    @MainActor
    func testLaunch_showsSearchScreenAndCollapsedTabBar() throws {
        let app = XCUIApplication.makeForUITest()
        app.launch()

        // 検索タブが選択された状態で起動し、初期メッセージが表示される
        XCTAssertTrue(app.navigationBars["検索"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["リポジトリを検索"].exists)

        // 検索タブ（role: .search）の選択中は、タブバーが検索フィールドと折りたたまれたタブのボタンになる。
        // 「検索」「設定」のボタンはこの状態では存在しない（3 タブの行き来は次のテストで確かめる）
        XCTAssertTrue(app.searchFields["リポジトリを検索"].exists)
        XCTAssertTrue(app.tabBars.buttons["お気に入り"].exists)
    }

    // MARK: - CUJ: 3タブ間の画面遷移

    @MainActor
    func testTabSwitching_navigatesAcrossAllThreeTabs() throws {
        let app = XCUIApplication.makeForUITest()
        app.launch()

        // お気に入りタブに切替 → ナビゲーションタイトル "お気に入り" が表示
        app.tabBars.buttons["お気に入り"].tap()
        XCTAssertTrue(app.navigationBars["お気に入り"].waitForExistence(timeout: 2))

        // 設定タブに切替 → "プライバシーポリシー" ボタンが表示
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.staticTexts["プライバシーポリシー"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["利用規約"].exists)

        // 検索タブに戻る → ナビゲーションタイトル "検索" が表示
        app.tabBars.buttons["検索"].tap()
        XCTAssertTrue(app.navigationBars["検索"].waitForExistence(timeout: 2))
    }

    // MARK: - Launch Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication.makeForUITest().launch()
        }
    }
}

extension XCUIApplication {
    /// UI テスト用の起動設定を入れたアプリを作る。
    /// 引数は UserDefaults の引数ドメインとして読まれるので、アプリ側にテスト用の分岐は要らない
    static func makeForUITest() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            // 初回起動のチュートリアルを出さない（TutorialLocalDataSource が読むキー）
            "-hasCompletedTutorial", "YES",
            // 画面の文言で要素を探すため、端末の設定に関わらず日本語で起動する
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
        ]
        return app
    }
}
