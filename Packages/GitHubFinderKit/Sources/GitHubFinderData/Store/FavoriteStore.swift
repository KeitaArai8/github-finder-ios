/*
 Abstract:
 お気に入り状態を一元管理する共有ストア。SearchModel と FavoriteModel の両方がこのストアを参照する。
 NiA の `:core:data` における `FavoriteStore` 同等の役割。
 */

import Foundation
import GitHubFinderDomain

@Observable
@MainActor
public final class FavoriteStore {
    public private(set) var favoriteIDs: Set<Int> = []
    public private(set) var favorites: [FavoriteEntity] = []
    /// 直近の `refresh()` が失敗したか。失敗しても `favorites` は前回の内容を保つ
    public private(set) var hasRefreshFailed = false

    private let favoriteRepository: FavoriteRepositoryProtocol
    /// お気に入りの追加・削除が保存されたあとに呼ぶ。ウィジェットの更新など、Data 層の外の後処理を
    /// composition root から渡す（Data 層が WidgetKit に依存しないようにするため）
    private let onFavoritesChanged: @MainActor () -> Void

    public init(
        favoriteRepository: FavoriteRepositoryProtocol,
        onFavoritesChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.favoriteRepository = favoriteRepository
        self.onFavoritesChanged = onFavoritesChanged
    }

    public func refresh() async {
        do {
            favorites = try await favoriteRepository.getAll()
            favoriteIDs = Set(favorites.map(\.id))
            hasRefreshFailed = false
        } catch {
            // リフレッシュ失敗時は現在の状態を維持し、失敗したことだけを記録する
            hasRefreshFailed = true
        }
    }

    public func add(_ repository: RepositoryEntity) async throws {
        try await favoriteRepository.add(repository)
        await refresh()
        onFavoritesChanged()
    }

    public func remove(id: Int) async throws {
        try await favoriteRepository.remove(id: id)
        await refresh()
        onFavoritesChanged()
    }

    public func contains(id: Int) -> Bool {
        favoriteIDs.contains(id)
    }
}
