/*
 Abstract:
 キーワード検索の状態管理を担当するState Holder。UDFパターンで実装。
 */

import Foundation
import os
import GitHubFinderDomain
import GitHubFinderData
import GitHubFinderDesignSystem

@Observable
public final class SearchModel {
    /// 画面のフェーズ。保存せず、検索の事実（`isSearching` / `searchError` / `lastSearchedQuery`）と
    /// 元データ（`allItems`・共有 Store の `favoriteStore`）から都度導出する。
    /// お気に入り済みかは Store の値を導出時に結合する（行にコピーして持たない）
    public var viewState: ViewState<[RepositoryDisplayItem]> {
        if isSearching { return .loading }
        if let searchError { return .error(searchError) }
        if !allItems.isEmpty {
            return .loaded(allItems.map { repo in
                RepositoryDisplayItem(
                    repository: repo,
                    isFavorite: favoriteStore.contains(id: repo.id)
                )
            })
        }
        // 検索が一度も実行されていない（初回起動など）間は .idle。.empty は「検索した結果 0 件」専用
        return lastSearchedQuery == nil ? .idle : .empty
    }
    public private(set) var errorMessage: String?
    /// エラーアラートの表示フラグ（`.alert(isPresented:)` に直接バインドする）。文言は errorMessage を使う
    public var isErrorPresented = false
    public var searchQuery = ""

    private var currentPage = 1
    private var hasNextPage = false
    /// 直近に検索を開始したクエリ。同じクエリでの再実行（タブ復帰で .task が再走した場合など）を避けるために保持する
    private var lastSearchedQuery: String?
    private var allItems: [RepositoryEntity] = []
    /// 1 ページ目の検索を実行中か（キャンセルされた検索は次の検索かリセットまで true のまま残る）
    private var isSearching = false
    /// 直近の検索が失敗したときのエラー文言
    private var searchError: String?
    public private(set) var isLoadingMore = false

    private let searchRepository: SearchRepositoryProtocol
    private let favoriteStore: FavoriteStore
    /// 検索履歴 Store（protocol 依存。本番は SearchHistoryStore、テストは MockSearchHistoryStore）
    public let searchHistoryStore: any SearchHistoryStoreProtocol

    public init(
        searchRepository: SearchRepositoryProtocol,
        favoriteStore: FavoriteStore,
        searchHistoryStore: any SearchHistoryStoreProtocol
    ) {
        self.searchRepository = searchRepository
        self.favoriteStore = favoriteStore
        self.searchHistoryStore = searchHistoryStore
    }

    /// 履歴選択：クエリを反映し即時検索（debounce バイパス）
    public func selectHistory(_ query: String) async {
        searchQuery = query
        await performSearch()
    }

    /// 単一履歴エントリの削除
    public func removeHistory(_ query: String) {
        searchHistoryStore.remove(query)
    }

    /// 履歴を全消去
    public func clearHistory() {
        searchHistoryStore.clear()
    }

    // MARK: - User Events

    /// 現在の searchQuery で検索する。debounce は呼び出し側（View の `.task(id:)`）が担う。
    /// 空クエリは結果をリセットし、検索済みと同じクエリは再検索しない。
    public func search() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            if lastSearchedQuery != nil { resetSearch() }
            return
        }
        // タブ復帰などで `.task(id:)` が再走しても同じクエリを再検索しない（完了しなかった検索・失敗した検索は nil に戻す）
        guard searchQuery != lastSearchedQuery else { return }
        await performSearch()
    }

    public func onRefresh() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        currentPage = 1
        allItems = []
        await performSearch(forceRefresh: true)
    }

    public func onLoadMore() async {
        guard hasNextPage, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await loadNextPage()
    }

    public func toggleFavorite(_ item: RepositoryDisplayItem) async {
        guard let repository = allItems.first(where: { $0.id == item.id }) else { return }
        await performToggleFavorite(repository)
    }

    /// 画面表示時のお気に入り状態の再取得（View の `.task` から呼ぶ）
    public func load() async {
        await favoriteStore.refresh()
    }

    public func dismissError() {
        errorMessage = nil
        isErrorPresented = false
    }

    // MARK: - Private

    private func performSearch(forceRefresh: Bool = false) async {
        isSearching = true
        searchError = nil
        currentPage = 1
        allItems = []
        lastSearchedQuery = searchQuery

        Logger.search.info("Search started: query=\(self.searchQuery), page=1")
        do {
            let result = try await searchRepository.search(
                query: searchQuery,
                page: 1,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else {
                lastSearchedQuery = nil
                return
            }

            allItems = result.items
            hasNextPage = result.hasNextPage
            await favoriteStore.refresh()

            Logger.search.info(
                "Search succeeded: count=\(result.items.count), totalCount=\(result.totalCount), hasNextPage=\(result.hasNextPage)"
            )

            // 結果が 0 件でも「ユーザが意図して入力した検索語」であることに変わりはないので履歴に残す
            searchHistoryStore.add(searchQuery)

            isSearching = false
            // 遅れて失敗した古い検索が書いた searchError を、新しい検索の成功で確実に消す
            searchError = nil
        } catch {
            handleSearchFailure(error)
        }
    }

    private func handleSearchFailure(_ error: any Error) {
        // 完了していない検索（キャンセル・失敗）は「検索済み」にしない
        // （同じクエリへ戻したり再入力したり、タブ復帰したときに再検索できるように）
        lastSearchedQuery = nil
        if error is CancellationError || Task.isCancelled {
            Logger.search.debug("Search cancelled: query=\(self.searchQuery)")
            return
        }
        Logger.search.error("Search failed: \(String(describing: error), privacy: .public)")
        isSearching = false
        searchError = error.localizedDescription
    }

    private func loadNextPage() async {
        // 検索ボックスの入力中の文字列（searchQuery）ではなく、表示中の一覧を取得したクエリで続きを取る
        guard let query = lastSearchedQuery else { return }
        let nextPage = currentPage + 1

        do {
            let result = try await searchRepository.search(
                query: query,
                page: nextPage,
                forceRefresh: false
            )
            guard !Task.isCancelled else { return }
            // 取得中に別の検索が始まっていたら、古い一覧の続きは捨てる
            guard query == lastSearchedQuery else { return }

            currentPage = nextPage
            allItems.append(contentsOf: result.items)
            hasNextPage = result.hasNextPage
        } catch is CancellationError {
            return
        } catch {
            // ページ追加読み込み失敗は既存データを維持
        }
    }

    private func performToggleFavorite(_ repository: RepositoryEntity) async {
        do {
            if favoriteStore.contains(id: repository.id) {
                try await favoriteStore.remove(id: repository.id)
            } else {
                try await favoriteStore.add(repository)
            }
        } catch {
            errorMessage = String(localized: "お気に入りの更新に失敗しました", bundle: #bundle)
            isErrorPresented = true
        }
    }

    private func resetSearch() {
        allItems = []
        currentPage = 1
        hasNextPage = false
        lastSearchedQuery = nil
        isSearching = false
        searchError = nil
    }

    #if DEBUG
    /// Preview 用: viewState の元になる事実だけを注入する。
    /// View の `.task(id:)` が走っても検索済み扱いが保たれるよう、検索済みのクエリも合わせて入れる
    func _setPreviewState(_ state: ViewState<[RepositoryDisplayItem]>) {
        searchQuery = "preview"
        lastSearchedQuery = "preview"
        isSearching = false
        searchError = nil
        allItems = []
        switch state {
        case .idle:
            searchQuery = ""
            lastSearchedQuery = nil
        case .loading:
            isSearching = true
        case .loaded(let items):
            allItems = items.map {
                RepositoryEntity(
                    id: $0.id,
                    fullName: $0.fullName,
                    description: $0.description,
                    starCount: $0.starCount,
                    language: $0.language,
                    ownerAvatarURL: $0.ownerAvatarURL
                )
            }
        case .empty:
            break
        case .error(let message):
            searchError = message
        }
    }
    #endif
}
