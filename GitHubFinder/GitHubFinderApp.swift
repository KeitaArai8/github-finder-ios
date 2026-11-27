/*
 Abstract:
 アプリケーションのエントリポイント。DI の組み立てと SwiftData 設定を行う。
 GitHubFinderKit local Swift Package（Domain / Data / DesignSystem / Feature*）から
 必要なプロダクトを import して composition root を構築する。
 */

import SwiftUI
import SwiftData
import WidgetKit
import GitHubFinderData
import FeatureSearch
import FeatureFavorite
import FeatureTutorial

@main
struct GitHubFinderApp: App {
    @State private var searchModel: SearchModel
    @State private var favoriteModel: FavoriteModel
    @State private var coachMarkManager: CoachMarkManager
    @State private var networkMonitor: NetworkMonitor

    init() {
        // DB — App Group経由でWidgetと共有するコンテナ
        // App Groupエンタイトルメントの未設定は開発時のみ発生するため、ここは致命エラーとして扱う
        let container: ModelContainer
        do {
            container = try AppGroupContainer.makeModelContainer()
        } catch {
            fatalError(
                "Failed to create App Group ModelContainer. Check entitlements for \(AppGroupContainer.identifier): \(error)"
            )
        }

        // DataSources
        let remoteDataSource = GitHubRemoteDataSource()
        let cacheDataSource = SearchCacheDataSource()
        let favoriteLocalDataSource = FavoriteLocalDataSource(modelContainer: container)
        let tutorialDataSource = TutorialLocalDataSource()

        // Repositories
        let searchRepository = SearchRepositoryImpl(
            remoteDataSource: remoteDataSource,
            cacheDataSource: cacheDataSource
        )
        let favoriteRepository = FavoriteRepositoryImpl(
            localDataSource: favoriteLocalDataSource
        )

        // Shared Stores
        let favoriteStore = FavoriteStore(
            favoriteRepository: favoriteRepository,
            // お気に入りの変更をウィジェットへ即時反映する（次回の定期更新を待たない）
            onFavoritesChanged: {
                WidgetCenter.shared.reloadTimelines(ofKind: AppGroupContainer.favoriteWidgetKind)
            }
        )
        let searchHistoryStore = SearchHistoryStore()

        // Models (State Holders)
        self.searchModel = SearchModel(
            searchRepository: searchRepository,
            favoriteStore: favoriteStore,
            searchHistoryStore: searchHistoryStore
        )
        self.favoriteModel = FavoriteModel(
            favoriteStore: favoriteStore
        )
        self.coachMarkManager = CoachMarkManager(
            tutorialDataSource: tutorialDataSource
        )

        // Network 監視（購読は AppRootView の .task で開始する）
        self.networkMonitor = NetworkMonitor()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                searchModel: searchModel,
                favoriteModel: favoriteModel,
                coachMarkManager: coachMarkManager,
                networkMonitor: networkMonitor
            )
        }
    }
}
