/*
 Abstract:
 SearchModelの状態遷移とビジネスロジックをテストする。
 非同期メソッドを直接 await することで、Task.sleep 依存の flakyなタイミング制御を排除している。
 */

import Testing
import GitHubFinderDomain
import GitHubFinderData
import GitHubFinderDesignSystem
@testable import FeatureSearch

@Suite("SearchModel")
@MainActor
struct SearchModelTests {

    // MARK: - 初期状態

    @Test("初期状態はidleである")
    func initialStateIsIdle() {
        // Arrange: デフォルトの初期状態で生成
        let model = SearchModelTests.makeModel()

        // Assert: 全プロパティが初期値
        #expect(model.viewState == .idle)
        #expect(model.searchQuery == "")
        #expect(model.isLoadingMore == false)
        #expect(model.errorMessage == nil)
        #expect(model.isErrorPresented == false)
    }

    @Test("初回起動時は検索前なので idle のまま")
    func loadBeforeAnySearchKeepsIdle() async {
        // Arrange: 未検索・お気に入り0件の初回起動状態のモデル
        let model = SearchModelTests.makeModel()

        // Act: 画面表示時の load（お気に入り再取得）を実行
        await model.load()

        // Assert: 検索結果0件でも .empty にならず .idle のまま
        #expect(model.viewState == .idle)
    }

    // MARK: - 検索

    @Test("検索成功時にloaded状態になる")
    func searchSuccessTransitionsToLoaded() async {
        // Arrange: 検索結果1件を返すモック
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 1)
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo]))
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)

        // Act: クエリを設定して検索を実行
        model.searchQuery = "swift"
        await model.search()

        // Assert: loaded状態で検索結果が反映されている
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(items.count == 1)
        #expect(items[0].fullName == "owner/repo")
        #expect(mockSearch.lastSearchQuery == "swift")
    }

    @Test("検索結果が空の場合empty状態になる")
    func searchEmptyResultTransitionsToEmpty() async {
        // Arrange: 空の検索結果を返すモック
        let mockSearch = MockSearchRepository()
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: []))
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)

        // Act: クエリを設定して検索を実行
        model.searchQuery = "nonexistent"
        await model.search()

        // Assert: 検索結果なしでempty状態
        #expect(model.viewState == .empty)
    }

    @Test("検索失敗時にerror状態になる")
    func searchFailureTransitionsToError() async {
        // Arrange: エラーを返すモック
        let mockSearch = MockSearchRepository()
        mockSearch.searchResult = .failure(AppError.network)
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)

        // Act: クエリを設定して検索を実行
        model.searchQuery = "test"
        await model.search()

        // Assert: error状態に遷移
        guard case .error = model.viewState else {
            Issue.record("Expected error state, got \(model.viewState)")
            return
        }
    }

    @Test("クエリを空にするとidle状態に戻る")
    func clearQueryResetsToIdle() async {
        // Arrange: まず検索を実行してloaded状態にする
        let mockSearch = MockSearchRepository()
        mockSearch.searchResult = .success(TestData.makeSearchResult())
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "swift"
        await model.search()

        // Act: クエリを空にする
        model.searchQuery = ""
        await model.search()

        // Assert: idle状態にリセットされる
        #expect(model.viewState == .idle)
    }

    @Test("検索済みと同じクエリで search を再実行してもAPIは再呼び出しされない")
    func searchSkipsAlreadySearchedQuery() async {
        // Arrange: "swift" で検索済みのloaded状態（検索結果1件）
        let mockSearch = MockSearchRepository()
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [TestData.makeRepository(id: 1)]))
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "swift"
        await model.search()
        #expect(mockSearch.searchCallCount == 1)

        // Act: タブ復帰で .task が再走した状況を想定し、同じクエリのまま search を再度呼ぶ
        await model.search()

        // Assert: API呼び出しは1回のままで、loaded状態が維持される
        #expect(mockSearch.searchCallCount == 1)
        guard case .loaded = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
    }

    @Test("未検索の空クエリで search を呼んでも状態を変えない")
    func searchWithEmptyQueryBeforeAnySearchKeepsState() async {
        // Arrange: 検索履歴のないidle状態の初期モデル
        let mockSearch = MockSearchRepository()
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)

        // Act: 空クエリのまま search（画面表示直後の .task を想定）
        await model.search()

        // Assert: idleのままAPIも呼ばれない
        #expect(model.viewState == .idle)
        #expect(mockSearch.searchCallCount == 0)
    }

    @Test("検索タスクがキャンセルされた後は同じクエリで再検索できる")
    func searchRetriesSameQueryAfterCancellation() async {
        // Arrange: 検索結果1件を返すモック
        let mockSearch = MockSearchRepository()
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [TestData.makeRepository(id: 1)]))
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "swift"

        // Act: 1回目の検索を開始直後にキャンセルし、同じクエリで再度 search を呼ぶ
        let cancelled = Task { await model.search() }
        cancelled.cancel()
        await cancelled.value
        await model.search()

        // Assert: 2回目の検索が実行されloaded状態になる（loadingのまま固まらない）
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(items.count == 1)
    }

    @Test("検索が CancellationError で終わっても error 状態にならない")
    func searchCancellationDoesNotShowError() async {
        // Arrange: CancellationError を投げるモック（Repository が URLError(.cancelled) から変換するエラー）
        let mockSearch = MockSearchRepository()
        mockSearch.searchResult = .failure(CancellationError())
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "swift"

        // Act: 検索を実行
        await model.search()

        // Assert: error 状態にならない
        if case .error = model.viewState {
            Issue.record("Cancellation must not surface as error, got \(model.viewState)")
        }
    }

    @Test("キャンセル済みタスク内で通信エラーが返っても error 状態にならない")
    func searchErrorInCancelledTaskDoesNotShowError() async {
        // Arrange: AppError.network を返すモック（キャンセル競合で .network に変換されたケース）
        let mockSearch = MockSearchRepository()
        mockSearch.searchResult = .failure(AppError.network)
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "swift"

        // Act: 開始直後にキャンセルしたタスクで検索する
        let cancelled = Task { await model.search() }
        cancelled.cancel()
        await cancelled.value

        // Assert: error 状態にならない
        if case .error = model.viewState {
            Issue.record("Error in cancelled task must not be shown, got \(model.viewState)")
        }
    }

    @Test("エラー後に同じクエリで再検索できる")
    func searchRetriesSameQueryAfterError() async {
        // Arrange: 1回目は失敗するモック
        let mockSearch = MockSearchRepository()
        mockSearch.searchResult = .failure(AppError.network)
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "swift"
        await model.search()

        // Act: 2回目は成功する状態にして同じクエリで search を呼ぶ
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [TestData.makeRepository(id: 1)]))
        await model.search()

        // Assert: スキップされず再検索され loaded 状態になる
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(items.count == 1)
        #expect(mockSearch.searchCallCount == 2)
    }

    // MARK: - お気に入り

    @Test("お気に入りトグルでisFavoriteがtrueになる")
    func toggleFavoriteSetsIsFavorite() async {
        // Arrange: 検索結果1件でloaded状態にする
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 42)
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo]))
        let mockFavorite = MockFavoriteRepository()
        let model = SearchModelTests.makeModel(
            searchRepository: mockSearch,
            favoriteRepository: mockFavorite
        )
        model.searchQuery = "test"
        await model.search()

        // Act: お気に入りに追加
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        await model.toggleFavorite(items[0])

        // Assert: isFavoriteがtrueに変更、addが1回呼ばれる
        guard case .loaded(let updatedItems) = model.viewState else {
            Issue.record("Expected loaded state after toggle")
            return
        }
        #expect(updatedItems[0].isFavorite == true)
        #expect(mockFavorite.addCallCount == 1)
    }

    @Test("お気に入り解除でisFavoriteがfalseになる")
    func toggleFavoriteRemovesSetsIsFavoriteFalse() async {
        // Arrange: お気に入り済みの状態で検索結果を表示
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 42)
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo]))
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.favoriteIDs = [42]
        mockFavorite.favorites = [TestData.makeFavorite(id: 42)]
        let model = SearchModelTests.makeModel(
            searchRepository: mockSearch,
            favoriteRepository: mockFavorite
        )
        model.searchQuery = "test"
        await model.search()

        // Act: お気に入りから解除
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items[0].isFavorite == true)
        await model.toggleFavorite(items[0])

        // Assert: isFavoriteがfalseに変更、removeが1回呼ばれる
        guard case .loaded(let updatedItems) = model.viewState else {
            Issue.record("Expected loaded state after toggle")
            return
        }
        #expect(updatedItems[0].isFavorite == false)
        #expect(mockFavorite.removeCallCount == 1)
    }

    @Test("お気に入りタブ側での変更が、画面復帰時の load 後に検索結果の isFavorite へ反映される")
    func isFavoriteFollowsFavoriteStoreChangesMadeElsewhere() async throws {
        // Arrange: 検索結果1件を表示し、共有 favoriteStore を直接操作できるようにモデルを組む
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 42)
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo]))
        let favoriteStore = FavoriteStore(favoriteRepository: MockFavoriteRepository())
        let model = SearchModel(
            searchRepository: mockSearch,
            favoriteStore: favoriteStore,
            searchHistoryStore: MockSearchHistoryStore()
        )
        model.searchQuery = "test"
        await model.search()

        // Act: お気に入りタブ相当の操作（store への直接追加）の後、検索タブへ戻って load が走る
        try await favoriteStore.add(repo)
        await model.load()

        // Assert: 追加が isFavorite == true として反映される
        guard case .loaded(let added) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(added[0].isFavorite == true)

        // Act: お気に入りタブ相当の操作（store からの削除）の後、再び load が走る
        try await favoriteStore.remove(id: 42)
        await model.load()

        // Assert: 削除が isFavorite == false として反映される
        guard case .loaded(let removed) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(removed[0].isFavorite == false)
    }

    // MARK: - ページネーション

    @Test("onLoadMoreで次ページが追加される")
    func loadMoreAppendsNextPage() async {
        // Arrange: hasNextPage=trueの初回検索結果を返す
        let mockSearch = MockSearchRepository()
        let page1Repo = TestData.makeRepository(id: 1, fullName: "page1/repo")
        let page2Repo = TestData.makeRepository(id: 2, fullName: "page2/repo")
        mockSearch.searchResult = .success(
            TestData.makeSearchResult(items: [page1Repo], totalCount: 60, hasNextPage: true)
        )
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "test"
        await model.search()

        // Act: 次ページの結果を設定してonLoadMoreを呼ぶ
        mockSearch.searchResult = .success(
            TestData.makeSearchResult(items: [page2Repo], hasNextPage: false)
        )
        await model.onLoadMore()

        // Assert: 2ページ分のアイテムが表示され、page=2で呼ばれている
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items.count == 2)
        #expect(items[0].fullName == "page1/repo")
        #expect(items[1].fullName == "page2/repo")
        #expect(mockSearch.lastSearchPage == 2)
    }

    // MARK: - スペースのみクエリ

    @Test("スペースのみのクエリはidleにリセットされる")
    func whitespaceOnlyQueryResetsToIdle() async {
        // Arrange: 検索済み状態を作る
        let mockSearch = MockSearchRepository()
        mockSearch.searchResult = .success(TestData.makeSearchResult())
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "swift"
        await model.search()

        // Act: スペースのみ入力
        model.searchQuery = "   "
        await model.search()

        // Assert: idle にリセット
        #expect(model.viewState == .idle)
    }

    // MARK: - ページ追加読み込み失敗

    @Test("ページ追加読み込み失敗時に既存データが維持される")
    func loadMoreFailureKeepsExistingData() async {
        // Arrange: 1ページ目を表示
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 1, fullName: "page1/repo")
        mockSearch.searchResult = .success(
            TestData.makeSearchResult(items: [repo], totalCount: 60, hasNextPage: true)
        )
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "test"
        await model.search()

        // Act: 2ページ目でエラー
        mockSearch.searchResult = .failure(AppError.network)
        await model.onLoadMore()

        // Assert: 1ページ目のデータが維持され、isLoadingMoreもfalseに戻る
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        #expect(items.count == 1)
        #expect(items[0].fullName == "page1/repo")
        #expect(model.isLoadingMore == false)
    }

    // MARK: - お気に入りトグル失敗

    @Test("お気に入り追加失敗時にerrorMessageがセットされる")
    func toggleFavoriteAddFailureShowsError() async {
        // Arrange: 検索結果を表示
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 42)
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo]))
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.shouldThrowOnAdd = true
        let model = SearchModelTests.makeModel(
            searchRepository: mockSearch,
            favoriteRepository: mockFavorite
        )
        model.searchQuery = "test"
        await model.search()

        // Act: お気に入り追加（失敗する）
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        await model.toggleFavorite(items[0])

        // Assert: errorMessageがセットされる
        #expect(model.errorMessage != nil)
        #expect(model.isErrorPresented == true)
    }

    // MARK: - エラーメッセージ dismiss

    @Test("dismissErrorでerrorMessageがnilになる")
    func dismissErrorClearsMessage() async {
        // Arrange: エラー状態を作る
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 42)
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo]))
        let mockFavorite = MockFavoriteRepository()
        mockFavorite.shouldThrowOnAdd = true
        let model = SearchModelTests.makeModel(
            searchRepository: mockSearch,
            favoriteRepository: mockFavorite
        )
        model.searchQuery = "test"
        await model.search()
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state")
            return
        }
        await model.toggleFavorite(items[0])
        #expect(model.errorMessage != nil)

        // Act: エラーを閉じる
        model.dismissError()

        // Assert: errorMessageがクリアされる
        #expect(model.errorMessage == nil)
        #expect(model.isErrorPresented == false)
    }

    // MARK: - リフレッシュ

    @Test("onRefreshで再検索が実行され結果が更新される")
    func onRefreshReloadsData() async {
        // Arrange: 初回検索
        let mockSearch = MockSearchRepository()
        let repo1 = TestData.makeRepository(id: 1, fullName: "old/repo")
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo1]))
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "test"
        await model.search()

        // Act: 新しいデータで再検索
        let repo2 = TestData.makeRepository(id: 2, fullName: "new/repo")
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo2]))
        await model.onRefresh()

        // Assert: 新しいデータに更新
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state after refresh")
            return
        }
        #expect(items.count == 1)
        #expect(items[0].fullName == "new/repo")
    }

    // MARK: - hasNextPage=false時のonLoadMore

    @Test("hasNextPageがfalseの場合onLoadMoreは何もしない")
    func loadMoreDoesNothingWhenNoNextPage() async {
        // Arrange: hasNextPage = false の検索結果
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 1)
        mockSearch.searchResult = .success(
            TestData.makeSearchResult(items: [repo], hasNextPage: false)
        )
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "test"
        await model.search()
        let callCountBeforeLoadMore = mockSearch.searchCallCount

        // Act: hasNextPage=false で onLoadMore を呼ぶ
        await model.onLoadMore()

        // Assert: 追加のAPI呼び出しが発生しない
        #expect(mockSearch.searchCallCount == callCountBeforeLoadMore)
    }

    // MARK: - onLoadMore二重呼び出し防止

    @Test("onLoadMore二重呼び出し時にAPIが1回しか呼ばれない")
    func loadMorePreventsDuplicateCalls() async {
        // Arrange: hasNextPage = true の検索結果
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 1)
        mockSearch.searchResult = .success(
            TestData.makeSearchResult(items: [repo], totalCount: 60, hasNextPage: true)
        )
        let model = SearchModelTests.makeModel(searchRepository: mockSearch)
        model.searchQuery = "test"
        await model.search()
        let callCountAfterSearch = mockSearch.searchCallCount

        // Act: hasNextPage: true の状態で onLoadMore を連続2回呼ぶ（2回目は isLoadingMore=true で無視されるべき）
        let page2Repo = TestData.makeRepository(id: 2)
        mockSearch.searchResult = .success(
            TestData.makeSearchResult(items: [page2Repo], hasNextPage: true)
        )
        async let first: Void = model.onLoadMore()
        async let second: Void = model.onLoadMore()
        _ = await (first, second)

        // Assert: hasNextPage: true のため1回目は API を呼び、2回目は無視されて追加呼び出しは1回だけ
        #expect(mockSearch.searchCallCount == callCountAfterSearch + 1)
    }

    // MARK: - 存在しないIDのtoggleFavorite

    @Test("存在しないIDのtoggleFavoriteは何もしない")
    func toggleFavoriteWithNonExistentIDDoesNothing() async {
        // Arrange: 検索結果を表示
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 1)
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo]))
        let mockFavorite = MockFavoriteRepository()
        let model = SearchModelTests.makeModel(
            searchRepository: mockSearch,
            favoriteRepository: mockFavorite
        )
        model.searchQuery = "test"
        await model.search()

        // Act: allItemsに存在しないIDでtoggle
        let fakeItem = RepositoryDisplayItem(
            repository: TestData.makeRepository(id: 999),
            isFavorite: false
        )
        await model.toggleFavorite(fakeItem)

        // Assert: addもremoveも呼ばれない
        #expect(mockFavorite.addCallCount == 0)
        #expect(mockFavorite.removeCallCount == 0)
    }

    // MARK: - 検索履歴

    @Test("検索成功時に履歴 store に追加される")
    func searchSuccessAddsToHistory() async {
        // Arrange:
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 1)
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo]))
        let mockHistory = MockSearchHistoryStore()
        let model = SearchModelTests.makeModel(
            searchRepository: mockSearch,
            searchHistoryStore: mockHistory
        )

        // Act:
        model.searchQuery = "kotlin"
        await model.search()

        // Assert: 履歴に "kotlin" が追加されている
        #expect(mockHistory.addCallCount == 1)
        #expect(mockHistory.lastAddedQuery == "kotlin")
        #expect(mockHistory.history == ["kotlin"])
    }

    @Test("selectHistory で即時検索が実行される（debounce バイパス）")
    func selectHistoryTriggersImmediateSearch() async {
        // Arrange:
        let mockSearch = MockSearchRepository()
        let repo = TestData.makeRepository(id: 1)
        mockSearch.searchResult = .success(TestData.makeSearchResult(items: [repo]))
        let mockHistory = MockSearchHistoryStore(initialHistory: ["swift", "kotlin"])
        let model = SearchModelTests.makeModel(
            searchRepository: mockSearch,
            searchHistoryStore: mockHistory
        )

        // Act: 履歴から選択
        await model.selectHistory("kotlin")

        // Assert: クエリが反映され、loaded 状態に遷移
        #expect(model.searchQuery == "kotlin")
        guard case .loaded(let items) = model.viewState else {
            Issue.record("Expected loaded state, got \(model.viewState)")
            return
        }
        #expect(items.count == 1)
    }

    @Test("removeHistory で store の remove が呼ばれる")
    func removeHistoryDelegatesToStore() {
        // Arrange:
        let mockHistory = MockSearchHistoryStore(initialHistory: ["a", "b", "c"])
        let model = SearchModelTests.makeModel(searchHistoryStore: mockHistory)

        // Act:
        model.removeHistory("b")

        // Assert:
        #expect(mockHistory.removeCallCount == 1)
        #expect(mockHistory.history == ["a", "c"])
    }

    @Test("clearHistory で store の clear が呼ばれる")
    func clearHistoryDelegatesToStore() {
        // Arrange:
        let mockHistory = MockSearchHistoryStore(initialHistory: ["a", "b"])
        let model = SearchModelTests.makeModel(searchHistoryStore: mockHistory)

        // Act:
        model.clearHistory()

        // Assert:
        #expect(mockHistory.clearCallCount == 1)
        #expect(mockHistory.history.isEmpty)
    }
}

// MARK: - Helper

extension SearchModelTests {
    @MainActor
    fileprivate static func makeModel(
        searchRepository: SearchRepositoryProtocol = MockSearchRepository(),
        favoriteRepository: MockFavoriteRepository = MockFavoriteRepository(),
        // デフォルト引数式は nonisolated で評価されるため、MainActor 隔離の Mock をここで生成できない。nil 既定にして本体で生成する
        searchHistoryStore: (any SearchHistoryStoreProtocol)? = nil
    ) -> SearchModel {
        let favoriteStore = FavoriteStore(favoriteRepository: favoriteRepository)
        return SearchModel(
            searchRepository: searchRepository,
            favoriteStore: favoriteStore,
            searchHistoryStore: searchHistoryStore ?? MockSearchHistoryStore()
        )
    }
}
