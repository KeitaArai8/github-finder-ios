/*
 Abstract:
 FavoriteModelの状態遷移をテストする。
 */

import Foundation
import Testing
import GitHubFinderDomain
import GitHubFinderData
import GitHubFinderDesignSystem
@testable import FeatureFavorite

@Suite("FavoriteModel")
@MainActor
struct FavoriteModelTests {

    @Test("初期状態はidleである")
    func initialStateIsIdle() {
        // Arrange: デフォルトの初期状態で生成
        let model = FavoriteModelTests.makeModel()

        // Assert: idle状態
        #expect(model.viewState == .idle)
        #expect(model.errorMessage == nil)
        #expect(model.isErrorPresented == false)
    }

    @Test("お気に入りがある場合loaded状態になる")
    func loadWithFavoritesTransitionsToLoaded() async throws {
        // Arrange: お気に入り1件を返すモック
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [TestData.makeFavorite(id: 1)]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)

        // Act: load() でデータ読み込み
        await model.load()

        // Assert: loaded状態で1件表示
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(items.count == 1)
    }

    @Test("お気に入りが空の場合empty状態になる")
    func loadWithNoFavoritesTransitionsToEmpty() async throws {
        // Arrange: 空のお気に入りを返すモック
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = []
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)

        // Act: load() でデータ読み込み
        await model.load()

        // Assert: empty状態
        #expect(model.viewState == .empty)
    }

    @Test("お気に入り削除後にリストが更新される")
    func removeFavoriteUpdatesState() async throws {
        // Arrange: お気に入り2件の状態にする
        let mockFavorite = MockFavoriteRepository()
        let fav1 = TestData.makeFavorite(id: 1, fullName: "owner/repo1")
        let fav2 = TestData.makeFavorite(id: 2, fullName: "owner/repo2")
        mockFavorite.favorites = [fav1, fav2]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act: fav1を削除（モックのfavoritesを手動更新してremoveFavoriteを呼ぶ）
        mockFavorite.favorites = [fav2]
        await model.removeFavorite(fav1)

        // Assert: 1件のみ残りfav2が表示される
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items.count == 1)
        #expect(items[0].fullName == "owner/repo2")
        #expect(mockFavorite.removeCallCount == 1)
    }

    // MARK: - 最後の1件削除

    @Test("最後の1件を削除するとempty状態になる")
    func removeLastFavoriteTransitionsToEmpty() async throws {
        // Arrange: お気に入り1件の状態
        let mockFavorite = MockFavoriteRepository()
        let fav = TestData.makeFavorite(id: 1)
        mockFavorite.favorites = [fav]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act: 1件を削除
        mockFavorite.favorites = []
        await model.removeFavorite(fav)

        // Assert: empty状態になる
        #expect(model.viewState == .empty)
    }

    // MARK: - 読み込み失敗

    @Test("表示できるお気に入りが無いまま読み込みに失敗するとerror状態になる")
    func loadFailureWithoutDataTransitionsToError() async throws {
        // Arrange: getAll が失敗するリポジトリ（お気に入りは未取得）
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.shouldThrowOnGetAll = true
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)

        // Act: 画面表示時の読み込み
        await model.load()

        // Assert: 「0 件」ではなくエラーとして見せる
        guard case .error = model.viewState else {
            Issue.record("Expected error state, got \(model.viewState)")
            return
        }
    }

    @Test("読み込み失敗のあと再試行が成功するとerror状態から抜ける")
    func retryAfterLoadFailureRecovers() async throws {
        // Arrange: 1 回目の読み込みが失敗して error 状態のモデル
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.shouldThrowOnGetAll = true
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act: リポジトリが復旧し、お気に入り 1 件を返す状態で再試行
        mockFavorite.shouldThrowOnGetAll = false
        mockFavorite.favorites = [TestData.makeFavorite(id: 1)]
        await model.onRefresh()

        // Assert: 取得した 1 件が loaded で表示される
        #expect(model.viewState == .loaded(mockFavorite.favorites))
    }

    @Test("表示中のお気に入りがあるときの更新失敗では一覧を維持する")
    func refreshFailureWithDataKeepsList() async throws {
        // Arrange: お気に入り 1 件を読み込み済みのモデル
        let mockFavorite = MockFavoriteRepository()
        let favorite = TestData.makeFavorite(id: 1)
        mockFavorite.favorites = [favorite]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act: 更新が失敗する
        mockFavorite.shouldThrowOnGetAll = true
        await model.onRefresh()

        // Assert: 一覧は前回の内容のまま（error にしない）
        #expect(model.viewState == .loaded([favorite]))
    }

    // MARK: - 削除失敗

    @Test("削除失敗時にerrorMessageがセットされリストが維持される")
    func removeFailureShowsErrorAndKeepsList() async throws {
        // Arrange:
        let mockFavorite = MockFavoriteRepository()
        let fav = TestData.makeFavorite(id: 1)
        mockFavorite.favorites = [fav]
        mockFavorite.shouldThrowOnRemove = true
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act:
        await model.removeFavorite(fav)

        // Assert: loaded状態のまま、errorMessageがセットされる
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items.count == 1)
        #expect(model.errorMessage != nil)
        #expect(model.isErrorPresented == true)
    }

    // MARK: - エラーメッセージ dismiss

    @Test("dismissErrorでerrorMessageがnilになる")
    func dismissErrorClearsMessage() async throws {
        // Arrange: 削除失敗でerrorMessageをセット
        let mockFavorite = MockFavoriteRepository()
        let fav = TestData.makeFavorite(id: 1)
        mockFavorite.favorites = [fav]
        mockFavorite.shouldThrowOnRemove = true
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        await model.removeFavorite(fav)
        #expect(model.errorMessage != nil)

        // Act:
        model.dismissError()

        // Assert:
        #expect(model.errorMessage == nil)
        #expect(model.isErrorPresented == false)
    }

    // MARK: - onRefresh

    @Test("onRefreshで最新データに更新される")
    func onRefreshReloadsLatestData() async throws {
        // Arrange: 初回読み込み（1件）
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [TestData.makeFavorite(id: 1, fullName: "owner/repo1")]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act: お気に入りが増えた状態でrefresh
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1, fullName: "owner/repo1"),
            TestData.makeFavorite(id: 2, fullName: "owner/repo2"),
        ]
        await model.onRefresh()

        // Assert: 2件に更新される
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(items.count == 2)
    }

    // MARK: - 編集モード（複数選択・一括削除）

    @Test("enterEditModeでisEditModeがtrueになる")
    func enterEditModeActivatesEditMode() async throws {
        // Arrange: loaded状態
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [TestData.makeFavorite(id: 1)]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act: 編集モード開始
        model.enterEditMode()

        // Assert: isEditMode=true, selectedIDs=空
        #expect(model.isEditMode == true)
        #expect(model.selectedIDs.isEmpty)
    }

    @Test("loaded状態でないときはenterEditModeが無視される")
    func enterEditModeIgnoredWhenNotLoaded() async throws {
        // Arrange: 空のお気に入り（empty状態）
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = []
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act: 編集モード開始を試みる
        model.enterEditMode()

        // Assert: 編集モードに入らない
        #expect(model.isEditMode == false)
    }

    @Test("exitEditModeでisEditModeがfalseになり選択がクリアされる")
    func exitEditModeResetsState() async throws {
        // Arrange: 編集モードで選択済み
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [TestData.makeFavorite(id: 1), TestData.makeFavorite(id: 2)]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()
        model.toggleSelection(id: 1)

        // Act: 編集モード終了
        model.exitEditMode()

        // Assert: isEditMode=false, 選択もクリア
        #expect(model.isEditMode == false)
        #expect(model.selectedIDs.isEmpty)
    }

    @Test("toggleSelectionで選択状態がトグルされる")
    func toggleSelectionAddsAndRemovesID() async throws {
        // Arrange: 編集モード開始
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [TestData.makeFavorite(id: 42)]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()

        // Act 1: id=42 を選択
        model.toggleSelection(id: 42)

        // Assert 1: 選択された
        #expect(model.selectedIDs == [42])

        // Act 2: 同じ id=42 を再度トグル
        model.toggleSelection(id: 42)

        // Assert 2: 選択解除
        #expect(model.selectedIDs.isEmpty)
    }

    @Test("selectAllで全お気に入りIDが選択される")
    func selectAllSelectsEveryItem() async throws {
        // Arrange: 3件のお気に入りを編集モード
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1),
            TestData.makeFavorite(id: 2),
            TestData.makeFavorite(id: 3),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()
        // Arrange: 未選択時のボタンタイトルを基準にする（ロケールに依存させない）
        let selectAllTitle = model.selectAllButtonTitle

        // Act: 全選択
        model.selectAll()

        // Assert: 全 ID が選択される + isAllSelected が true
        #expect(model.selectedIDs == [1, 2, 3])
        #expect(model.isAllSelected == true)
        #expect(model.selectAllButtonTitle != selectAllTitle)
    }

    @Test("toggleSelectAllは未選択状態から全選択へ切り替える")
    func toggleSelectAllFromEmptyToAll() async throws {
        // Arrange: 編集モードで未選択
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1),
            TestData.makeFavorite(id: 2),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()
        // Arrange: 未選択時のボタンタイトルを基準にする（ロケールに依存させない）
        let selectAllTitle = model.selectAllButtonTitle

        // Act:
        model.toggleSelectAll()

        // Assert:
        #expect(model.selectedIDs == [1, 2])
        #expect(model.isAllSelected == true)
        #expect(model.selectAllButtonTitle != selectAllTitle)
    }

    @Test("toggleSelectAllは全選択状態から全解除へ切り替える")
    func toggleSelectAllFromAllToEmpty() async throws {
        // Arrange: 編集モードで全選択済み
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1),
            TestData.makeFavorite(id: 2),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()
        // Arrange: 未選択時のボタンタイトルを基準にする（ロケールに依存させない）
        let selectAllTitle = model.selectAllButtonTitle
        model.selectAll()
        #expect(model.isAllSelected == true)

        // Act:
        model.toggleSelectAll()

        // Assert:
        #expect(model.selectedIDs.isEmpty)
        #expect(model.isAllSelected == false)
        #expect(model.selectAllButtonTitle == selectAllTitle)
    }

    @Test("toggleSelectAllは部分選択状態から全選択へ切り替える（iOS Photos 同等）")
    func toggleSelectAllFromPartialToAll() async throws {
        // Arrange: 3件中1件のみ選択
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1),
            TestData.makeFavorite(id: 2),
            TestData.makeFavorite(id: 3),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()
        model.toggleSelection(id: 2)

        // Act: 部分選択中のトグル → iOS Photos.app では「全選択」扱い
        model.toggleSelectAll()

        // Assert:
        #expect(model.selectedIDs == [1, 2, 3])
        #expect(model.isAllSelected == true)
    }

    @Test("isAllSelectedはフィルタ後の表示件数で判定する")
    func isAllSelectedRespectsLanguageFilter() async throws {
        // Arrange: Swift と Kotlin が混在し、Swift にフィルタ
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1, language: "Swift"),
            TestData.makeFavorite(id: 2, language: "Kotlin"),
            TestData.makeFavorite(id: 3, language: "Swift"),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()
        model.setFilterLanguage("Swift")

        // Act: 表示中の Swift 2 件のみ全選択
        model.selectAll()

        // Assert: 非表示の Kotlin は含めず、isAllSelected は true
        #expect(model.selectedIDs == [1, 3])
        #expect(model.isAllSelected == true)
    }

    @Test("requestRemoveSelectedで選択件数が0なら確認ダイアログが出ない")
    func requestRemoveSelectedIgnoredWhenNoSelection() async throws {
        // Arrange: 編集モードで選択なし
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [TestData.makeFavorite(id: 1)]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()

        // Act:
        model.requestRemoveSelected()

        // Assert: 確認ダイアログは表示されない
        #expect(model.isDeleteConfirmationPresented == false)
    }

    @Test("requestRemoveSelectedで選択ありなら確認ダイアログが出る")
    func requestRemoveSelectedShowsConfirmation() async throws {
        // Arrange: 編集モードで1件選択
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [TestData.makeFavorite(id: 1)]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()
        model.toggleSelection(id: 1)

        // Act: 削除要求
        model.requestRemoveSelected()

        // Assert: 確認ダイアログ表示
        #expect(model.isDeleteConfirmationPresented == true)
    }

    @Test("confirmRemoveSelectedで選択中の項目が一括削除される")
    func confirmRemoveSelectedDeletesSelectedItems() async throws {
        // Arrange: 3件のお気に入り、2件選択
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1),
            TestData.makeFavorite(id: 2),
            TestData.makeFavorite(id: 3),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()
        model.toggleSelection(id: 1)
        model.toggleSelection(id: 2)

        // Act: 削除後にモックのfavoritesも1件に更新
        mockFavorite.favorites = [TestData.makeFavorite(id: 3)]
        await model.confirmRemoveSelected()

        // Assert: remove が2回呼ばれ、残り1件、選択クリア、確認ダイアログ閉
        #expect(mockFavorite.removeCallCount == 2)
        #expect(model.selectedIDs.isEmpty)
        #expect(model.isDeleteConfirmationPresented == false)
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state after bulk delete")
            return
        }
        #expect(items.count == 1)
    }

    // MARK: - ソート機能

    @Test("デフォルトのソートは savedAtDesc（保存が新しい順）")
    func defaultSortIsSavedAtDesc() async throws {
        // Arrange: savedAt が異なる 3 件（古い→新しい の順で配列に格納）
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let midDate = Date(timeIntervalSince1970: 2_000)
        let newDate = Date(timeIntervalSince1970: 3_000)
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(
                id: 1,
                fullName: "owner/old",
                savedAt: oldDate
            ),
            TestData.makeFavorite(
                id: 2,
                fullName: "owner/mid",
                savedAt: midDate
            ),
            TestData.makeFavorite(
                id: 3,
                fullName: "owner/new",
                savedAt: newDate
            ),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)

        // Act: 読み込み（デフォルト sortKey = savedAtDesc）
        await model.load()

        // Assert: 新しい順 (id=3, 2, 1) で並ぶ
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items.map(\.id) == [3, 2, 1])
        #expect(model.sortKey == .savedAtDesc)
    }

    @Test("setSortKey(.starCountDesc) で Star が多い順に並ぶ")
    func setSortKeyStarCountDescOrdersByStars() async throws {
        // Arrange: starCount が異なる 3 件
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(
                id: 1,
                fullName: "a/repo",
                starCount: 100
            ),
            TestData.makeFavorite(
                id: 2,
                fullName: "b/repo",
                starCount: 5_000
            ),
            TestData.makeFavorite(
                id: 3,
                fullName: "c/repo",
                starCount: 500
            ),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act: ソートキー切替
        model.setSortKey(.starCountDesc)

        // Assert: Star 多い順 (5000, 500, 100)
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items.map(\.starCount) == [5_000, 500, 100])
    }

    @Test("setSortKey(.fullNameAsc) でリポジトリ名昇順に並ぶ")
    func setSortKeyFullNameAscOrdersAlphabetically() async throws {
        // Arrange:
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1, fullName: "zoo/repo"),
            TestData.makeFavorite(id: 2, fullName: "apple/swift"),
            TestData.makeFavorite(id: 3, fullName: "microsoft/vscode"),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act:
        model.setSortKey(.fullNameAsc)

        // Assert: A→Z で並ぶ
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items.map(\.fullName) == ["apple/swift", "microsoft/vscode", "zoo/repo"])
    }

    // MARK: - 言語フィルタ

    @Test("setFilterLanguage で指定言語のみに絞り込まれる")
    func setFilterLanguageFiltersByLanguage() async throws {
        // Arrange: Swift と Kotlin のお気に入りが混在
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(
                id: 1,
                fullName: "a/swift1",
                language: "Swift"
            ),
            TestData.makeFavorite(
                id: 2,
                fullName: "b/kotlin1",
                language: "Kotlin"
            ),
            TestData.makeFavorite(
                id: 3,
                fullName: "c/swift2",
                language: "Swift"
            ),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act: Swift にフィルタ
        model.setFilterLanguage("Swift")

        // Assert: Swift の 2 件のみ
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.language == "Swift" })
        #expect(model.filterLanguage == "Swift")
    }

    @Test("setFilterLanguage(nil) でフィルタが解除される")
    func setFilterLanguageNilClearsFilter() async throws {
        // Arrange: フィルタ済み状態
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1, language: "Swift"),
            TestData.makeFavorite(id: 2, language: "Kotlin"),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.setFilterLanguage("Swift")

        // Act: フィルタクリア
        model.setFilterLanguage(nil)

        // Assert: 全件が再表示される
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items.count == 2)
        #expect(model.filterLanguage == nil)
    }

    @Test("フィルタ対象の言語が消失したら自動でクリアされる")
    func filterLanguageAutoClearsWhenLanguageGone() async throws {
        // Arrange: Swift にフィルタ
        let mockFavorite = MockFavoriteRepository()
        let swiftFav = TestData.makeFavorite(id: 1, language: "Swift")
        mockFavorite.favorites = [
            swiftFav,
            TestData.makeFavorite(id: 2, language: "Kotlin"),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.setFilterLanguage("Swift")

        // Act: Swift のお気に入りを全削除
        mockFavorite.favorites = [TestData.makeFavorite(id: 2, language: "Kotlin")]
        await model.removeFavorite(swiftFav)

        // Assert: filterLanguage が自動クリアされ、Kotlin の 1 件が表示される
        #expect(model.filterLanguage == nil)
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items.count == 1)
    }

    @Test("availableLanguages が重複なくソート済みで返る")
    func availableLanguagesIsDistinctAndSorted() async throws {
        // Arrange: 重複あり、未指定（nil）あり
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1, language: "Swift"),
            TestData.makeFavorite(id: 2, language: "Kotlin"),
            TestData.makeFavorite(id: 3, language: "Swift"),
            TestData.makeFavorite(id: 4, language: nil),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()

        // Act:
        let languages = model.availableLanguages

        // Assert:
        #expect(languages == ["Kotlin", "Swift"])
    }

    @Test("全件削除すると編集モードが自動終了する")
    func bulkDeleteAllExitsEditMode() async throws {
        // Arrange: 2件のお気に入りを全選択
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1),
            TestData.makeFavorite(id: 2),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()
        model.selectAll()

        // Act: 削除後にfavoritesを空に
        mockFavorite.favorites = []
        await model.confirmRemoveSelected()

        // Assert: empty に遷移し、編集モードが自動終了
        #expect(model.viewState == .empty)
        #expect(model.isEditMode == false)
    }

    @Test("お気に入りが空になって編集モードが終わった後、お気に入りが増えても編集モード・選択は戻らない")
    func editModeAndSelectionDoNotComeBackAfterEmptied() async throws {
        // Arrange: 2件を全選択した編集モードから、一括削除で全件空にする
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 1),
            TestData.makeFavorite(id: 2),
        ]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.enterEditMode()
        model.selectAll()
        mockFavorite.favorites = []
        await model.confirmRemoveSelected()

        // Act: 空になった後にお気に入りが1件増えて再読み込みされる
        mockFavorite.favorites = [TestData.makeFavorite(id: 3)]
        await model.onRefresh()

        // Assert: loaded に戻るが、編集モードは終了したまま・選択も空のまま
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(items.count == 1)
        #expect(model.isEditMode == false)
        #expect(model.selectedIDs.isEmpty)
    }

    @Test("フィルタ対象の言語が消失してクリアされた後、その言語が戻ってもフィルタは復活しない")
    func filterLanguageDoesNotComeBackAfterLanguageReturns() async throws {
        // Arrange: Swift にフィルタし、Swift のお気に入りを削除してフィルタがクリアされた状態にする
        let mockFavorite = MockFavoriteRepository()
        let swiftFav = TestData.makeFavorite(id: 1, language: "Swift")
        mockFavorite.favorites = [swiftFav, TestData.makeFavorite(id: 2, language: "Kotlin")]
        let model = FavoriteModelTests.makeModel(favoriteRepository: mockFavorite)
        await model.load()
        model.setFilterLanguage("Swift")
        mockFavorite.favorites = [TestData.makeFavorite(id: 2, language: "Kotlin")]
        await model.removeFavorite(swiftFav)

        // Act: Swift のお気に入りが再び増えて再読み込みされる
        mockFavorite.favorites = [
            TestData.makeFavorite(id: 2, language: "Kotlin"),
            TestData.makeFavorite(id: 4, language: "Swift"),
        ]
        await model.onRefresh()

        // Assert: フィルタは nil のままで、Kotlin / Swift の 2 件が表示される
        #expect(model.filterLanguage == nil)
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(items.count == 2)
    }

    @Test("初回読み込み中は loading で、完了後に loaded になる")
    func firstLoadShowsLoadingUntilCompleted() async {
        // Arrange: テストが解放するまで getAll が完了しないリポジトリ（お気に入り1件）
        let gatedRepository = GatedFavoriteRepository(favorites: [TestData.makeFavorite(id: 1)])
        let model = FavoriteModel(favoriteStore: FavoriteStore(favoriteRepository: gatedRepository))

        // Act: 読み込みを開始し、getAll に入ったことをリポジトリからの通知で確認する
        let loading = Task { await model.load() }
        await gatedRepository.waitUntilGetAllEntered()

        // Assert: getAll が未完了の間は loading
        #expect(model.viewState == .loading)

        // Act: getAll を解放して読み込み完了を待つ
        gatedRepository.releaseGetAll()
        await loading.value

        // Assert: 完了後は 1 件の loaded
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(items.count == 1)
    }
}

// MARK: - Helper

extension FavoriteModelTests {
    fileprivate static func makeModel(
        favoriteRepository: MockFavoriteRepository = MockFavoriteRepository()
    ) -> FavoriteModel {
        let favoriteStore = FavoriteStore(favoriteRepository: favoriteRepository)
        return FavoriteModel(favoriteStore: favoriteStore)
    }
}

/// getAll がテストの解放まで完了しないリポジトリ（読み込み中の状態を sleep 無しで観測するため）。
/// getAll に入ったことは entered ストリームで通知し、完了は release ストリームへの送信で解放する。
/// 各ゲートは getAll 1 回・待機側 1 つ分だけを想定している
private final class GatedFavoriteRepository: FavoriteRepositoryProtocol, Sendable {
    let favorites: [FavoriteEntity]
    private let entered: AsyncStream<Void>
    private let enteredContinuation: AsyncStream<Void>.Continuation
    private let release: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init(favorites: [FavoriteEntity]) {
        self.favorites = favorites
        (entered, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
        (release, releaseContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func getAll() async throws -> [FavoriteEntity] {
        enteredContinuation.yield()
        for await _ in release { break }
        return favorites
    }

    /// getAll に入るまで待つ
    func waitUntilGetAllEntered() async {
        for await _ in entered { break }
    }

    /// 待機中（または今後入る）getAll を完了させる
    func releaseGetAll() {
        releaseContinuation.yield()
    }

    func add(_ repository: RepositoryEntity) async throws {}
    func remove(id: Int) async throws {}
}
