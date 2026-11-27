/*
 Abstract:
 検索・お気に入り・設定の3タブを提供するメインタブ画面。
 */

import SwiftUI
import FeatureSearch
import FeatureFavorite
import FeatureSettings

struct MainTabView: View {
    let searchModel: SearchModel
    let favoriteModel: FavoriteModel

    var body: some View {
        TabView {
            Tab(
                "検索",
                systemImage: "magnifyingglass",
                role: .search
            ) {
                SearchView(model: searchModel)
            }

            Tab("お気に入り", systemImage: "heart.fill") {
                FavoriteListView(model: favoriteModel)
            }

            Tab("設定", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
