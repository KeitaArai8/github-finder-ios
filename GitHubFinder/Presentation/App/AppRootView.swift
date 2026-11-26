/*
 Abstract:
 アプリのルートView。チュートリアル表示判定とメイン画面の切替を行う。
 チュートリアルが有効な間はTutorialScreen（専用モック画面）を表示し、
 完了・スキップ後に本物のMainTabViewへ遷移する。
 オフライン時はアプリ最上部に OfflineBanner を safeAreaBar として差し込む。
 */

import SwiftUI
import GitHubFinderData
import GitHubFinderDesignSystem
import FeatureSearch
import FeatureFavorite
import FeatureTutorial

struct AppRootView: View {
    let searchModel: SearchModel
    let favoriteModel: FavoriteModel
    let coachMarkManager: CoachMarkManager
    let networkMonitor: NetworkMonitor

    var body: some View {
        Group {
            if coachMarkManager.isActive {
                TutorialScreen(coachMarkManager: coachMarkManager)
            } else {
                // safeAreaBar はメイン画面だけに掛ける。チュートリアルまで包むと、バーのホストが
                // 上端の帯のタップを奪い、スキップボタンが反応しなくなる（チュートリアルはモック UI でバナー不要）
                MainTabView(
                    searchModel: searchModel,
                    favoriteModel: favoriteModel
                )
                // バナーの分だけコンテンツが下へ押し下げられ、スクロールエッジ効果も追従する
                .safeAreaBar(edge: .top) {
                    if !networkMonitor.isConnected {
                        OfflineBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: networkMonitor.isConnected)
        .task {
            coachMarkManager.startIfNeeded()
        }
        .task {
            await networkMonitor.start()
        }
    }
}
