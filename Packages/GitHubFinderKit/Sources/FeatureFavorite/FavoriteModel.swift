/*
 Abstract:
 お気に入り一覧の状態管理を担当するState Holder。
 通常表示モードと編集モード（複数選択→一括削除）を切り替える。
 ソート・言語フィルタはメモリ保持（永続化なし）。生データは favoriteStore.favorites のまま保持し、
 displayedFavorites で表示順を導出する。
 */

import Foundation
import os
import GitHubFinderDomain
import GitHubFinderData
import GitHubFinderDesignSystem

/// お気に入り一覧の並び替え基準
public enum FavoriteSortKey: String, CaseIterable, Identifiable {
    case savedAtDesc      // 保存が新しい順（デフォルト）
    case starCountDesc    // ⭐ が多い順
    case fullNameAsc      // リポジトリ名 A→Z

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .savedAtDesc:   return String(localized: "新しい順", bundle: #bundle)
        case .starCountDesc: return String(localized: "Star が多い順", bundle: #bundle)
        case .fullNameAsc:   return String(localized: "名前順 (A→Z)", bundle: #bundle)
        }
    }
}

@Observable
public final class FavoriteModel {
    /// 画面のフェーズ。保存せず、読み込みの事実（`hasStartedLoading` / `hasLoaded`）と
    /// 共有 Store の `favorites` から都度導出する（元データのコピーを持たないため同期処理が要らない）
    public var viewState: ViewState<[FavoriteEntity]> {
        guard hasStartedLoading else { return .idle }
        guard hasLoaded else { return .loading }
        let rawFavorites = favoriteStore.favorites
        guard !rawFavorites.isEmpty else { return .empty }
        return .loaded(applySortAndFilter(rawFavorites))
    }
    public private(set) var errorMessage: String?
    /// エラーアラートの表示フラグ（`.alert(isPresented:)` に直接バインドする）。文言は errorMessage を使う
    public var isErrorPresented = false

    /// 初回の load を開始したか（開始前は .idle）
    private var hasStartedLoading = false
    /// 初回の load が完了したか（完了までは .loading）
    private var hasLoaded = false

    /// 編集モード（複数選択可能）中かどうか。お気に入りが 0 件のときは編集モードとして扱わない
    public var isEditMode: Bool {
        isEditModeRequested && !favoriteStore.favorites.isEmpty
    }
    /// 編集モード中に選択されているお気に入りID。現在のお気に入りに存在しない ID は除く
    public var selectedIDs: Set<Int> {
        guard isEditMode else { return [] }
        return storedSelectedIDs.intersection(favoriteStore.favoriteIDs)
    }
    private var isEditModeRequested = false
    private var storedSelectedIDs: Set<Int> = []
    /// 一括削除の確認ダイアログ表示フラグ
    public var isDeleteConfirmationPresented: Bool = false

    /// 並び替え基準（メモリ保持。アプリ再起動でリセット）
    public private(set) var sortKey: FavoriteSortKey = .savedAtDesc
    /// 言語フィルタ（nil = フィルタ無し）
    /// 現在のお気に入りに存在しない言語が指定されている場合は nil（フィルタ無し）として扱う
    public var filterLanguage: String? {
        guard let language = storedFilterLanguage,
              favoriteStore.favorites.contains(where: { $0.language == language }) else { return nil }
        return language
    }
    private var storedFilterLanguage: String?

    private let favoriteStore: FavoriteStore

    public init(favoriteStore: FavoriteStore) {
        self.favoriteStore = favoriteStore
    }

    // MARK: - User Events (Normal Mode)

    /// 画面表示時の読み込み（View の `.task` から呼ぶ）
    public func load() async {
        hasStartedLoading = true

        await favoriteStore.refresh()
        hasLoaded = true
        resetStaleSelectionState()
    }

    public func onRefresh() async {
        await load()
    }

    public func removeFavorite(_ favorite: FavoriteEntity) async {
        do {
            try await favoriteStore.remove(id: favorite.id)
            Logger.favorite.info("Favorite removed: id=\(favorite.id, privacy: .public)")
            resetStaleSelectionState()
        } catch {
            Logger.favorite.error("Favorite remove failed: id=\(favorite.id, privacy: .public), error=\(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "お気に入りの削除に失敗しました", bundle: #bundle)
            isErrorPresented = true
        }
    }

    public func dismissError() {
        errorMessage = nil
        isErrorPresented = false
    }

    // MARK: - User Events (Sort & Filter)

    public func setSortKey(_ key: FavoriteSortKey) {
        sortKey = key
    }

    /// 言語フィルタを設定（nil でクリア）
    public func setFilterLanguage(_ language: String?) {
        // 現在のお気に入りに存在しない言語は受け付けない（フィルタ無しとして扱う）
        if let language, !favoriteStore.favorites.contains(where: { $0.language == language }) {
            storedFilterLanguage = nil
        } else {
            storedFilterLanguage = language
        }
    }

    // MARK: - User Events (Edit Mode)

    public func enterEditMode() {
        guard case .loaded = viewState else { return }
        isEditModeRequested = true
        storedSelectedIDs = []
    }

    public func exitEditMode() {
        isEditModeRequested = false
        storedSelectedIDs = []
    }

    public func toggleSelection(id: Int) {
        if storedSelectedIDs.contains(id) {
            storedSelectedIDs.remove(id)
        } else {
            storedSelectedIDs.insert(id)
        }
    }

    public func selectAll() {
        guard case .loaded(let items) = viewState else { return }
        storedSelectedIDs = Set(items.map(\.id))
    }

    public func deselectAll() {
        storedSelectedIDs = []
    }

    /// 表示中（フィルタ後）のお気に入りすべてが選択済みかどうか。
    /// 「全選択 ⇔ 全解除」トグルボタンのラベル切り替えに使う。iOS Photos.app の defacto。
    public var isAllSelected: Bool {
        guard case .loaded(let items) = viewState, !items.isEmpty else { return false }
        return Set(items.map(\.id)) == selectedIDs
    }

    /// 全選択⇔全解除のトグル。Passive View 原則に従い、判定ロジックは Model 側に集約する。
    public func toggleSelectAll() {
        if isAllSelected {
            deselectAll()
        } else {
            selectAll()
        }
    }

    /// 編集モード TopBar 左に出すボタンのタイトル。
    /// View は状態を表示するだけの Passive View に保つため、条件による文言の出し分けは Model が持つ。
    public var selectAllButtonTitle: String {
        isAllSelected ? String(localized: "全解除", bundle: #bundle) : String(localized: "全選択", bundle: #bundle)
    }

    public func requestRemoveSelected() {
        guard !selectedIDs.isEmpty else { return }
        isDeleteConfirmationPresented = true
    }

    public func confirmRemoveSelected() async {
        isDeleteConfirmationPresented = false
        let idsToRemove = selectedIDs
        guard !idsToRemove.isEmpty else { return }

        Logger.favorite.info("Bulk delete started: count=\(idsToRemove.count)")
        do {
            for id in idsToRemove {
                try await favoriteStore.remove(id: id)
            }
            Logger.favorite.info("Bulk delete succeeded: count=\(idsToRemove.count)")
            storedSelectedIDs = []
            resetStaleSelectionState()
        } catch {
            Logger.favorite.error("Bulk delete failed: error=\(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "お気に入りの削除に失敗しました", bundle: #bundle)
            isErrorPresented = true
        }
    }

    // MARK: - Private

    /// お気に入りが変わったあとのイベント処理で、無効になった編集・フィルタ状態を実際に捨てる。
    /// 読み取り側（`isEditMode` / `selectedIDs` / `filterLanguage`）でも無効値は除くが、
    /// ここで捨てないと、お気に入りが再び増えたときに編集モードやフィルタが勝手に復活してしまう
    private func resetStaleSelectionState() {
        let rawFavorites = favoriteStore.favorites
        if rawFavorites.isEmpty {
            isEditModeRequested = false
            storedSelectedIDs = []
        }
        if let language = storedFilterLanguage,
           !rawFavorites.contains(where: { $0.language == language }) {
            storedFilterLanguage = nil
        }
    }

    /// 生のお気に入りに sortKey/filterLanguage を適用した表示用配列を返す
    private func applySortAndFilter(_ favorites: [FavoriteEntity]) -> [FavoriteEntity] {
        let filtered: [FavoriteEntity]
        if let language = filterLanguage {
            filtered = favorites.filter { $0.language == language }
        } else {
            filtered = favorites
        }

        switch sortKey {
        case .savedAtDesc:
            return filtered.sorted { $0.savedAt > $1.savedAt }
        case .starCountDesc:
            return filtered.sorted { $0.starCount > $1.starCount }
        case .fullNameAsc:
            return filtered.sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
        }
    }

    /// 言語フィルタの選択肢（生のお気に入りから抽出した重複なし、ソート済み）
    public var availableLanguages: [String] {
        Set(favoriteStore.favorites.compactMap(\.language))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    #if DEBUG
    /// Preview 用: viewState の元になる事実だけを注入する。
    /// 一覧そのもの（loaded / empty）は Preview 側が favoriteStore に仕込んだデータを load() が読み込んで決まる
    public func _setPreviewState(
        hasStartedLoading: Bool,
        hasLoaded: Bool,
        isEditMode: Bool = false,
        selectedIDs: Set<Int> = [],
        sortKey: FavoriteSortKey = .savedAtDesc,
        filterLanguage: String? = nil
    ) {
        self.hasStartedLoading = hasStartedLoading
        self.hasLoaded = hasLoaded
        self.isEditModeRequested = isEditMode
        self.storedSelectedIDs = selectedIDs
        self.sortKey = sortKey
        self.storedFilterLanguage = filterLanguage
    }
    #endif
}
