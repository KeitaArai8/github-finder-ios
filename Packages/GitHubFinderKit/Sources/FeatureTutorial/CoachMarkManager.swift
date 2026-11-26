/*
 Abstract:
 コーチマーク型チュートリアルのステップ管理と表示制御。
 */

import SwiftUI

@Observable
public final class CoachMarkManager {
    /// チュートリアル進行ステップ。
    /// target の既定隔離が MainActor のため通常は MainActor を継承するが、
    /// `PreferenceKey.defaultValue`（nonisolated コンテキスト）から参照されるため
    /// `nonisolated` 化して隔離を解除する。純粋な値 + 静的文字列のみで MainActor 不要。
    public nonisolated enum Step: Int, CaseIterable, Sendable {
        case searchBar = 0
        case favoriteButton = 1
        case favoriteTab = 2

        public var title: String {
            switch self {
            case .searchBar: String(localized: "検索してみよう", bundle: #bundle)
            case .favoriteButton: String(localized: "お気に入りに追加", bundle: #bundle)
            case .favoriteTab: String(localized: "お気に入り一覧", bundle: #bundle)
            }
        }

        public var description: String {
            switch self {
            case .searchBar: String(localized: "キーワードを入力して\nGitHubリポジトリを検索できます", bundle: #bundle)
            case .favoriteButton: String(localized: "ハートボタンをタップして\nお気に入りに追加しましょう", bundle: #bundle)
            case .favoriteTab: String(localized: "お気に入りタブから\n保存したリポジトリを確認できます", bundle: #bundle)
            }
        }

        public var systemImage: String {
            switch self {
            case .searchBar: "magnifyingglass"
            case .favoriteButton: "heart.fill"
            case .favoriteTab: "star.fill"
            }
        }
    }

    public private(set) var currentStep: Step?
    public private(set) var isActive = false

    private let tutorialDataSource: TutorialLocalDataSource

    public init(tutorialDataSource: TutorialLocalDataSource) {
        self.tutorialDataSource = tutorialDataSource
    }

    public func startIfNeeded() {
        guard !tutorialDataSource.hasCompleted else { return }
        isActive = true
        currentStep = .searchBar
    }

    public func next() {
        guard let current = currentStep else { return }
        let allSteps = Step.allCases
        guard let currentIndex = allSteps.firstIndex(of: current) else { return }

        let nextIndex = allSteps.index(after: currentIndex)
        if nextIndex < allSteps.endIndex {
            currentStep = allSteps[nextIndex]
        } else {
            complete()
        }
    }

    /// 特定の操作（ユーザーの検索、お気に入り登録、タブ切替など）が完了したタイミングで
    /// 次のステップへ進める。現在ステップが一致しないときは何もしない（冪等）。
    public func advance(after step: Step) {
        guard isActive, currentStep == step else { return }
        next()
    }

    public func skip() {
        complete()
    }

    private func complete() {
        currentStep = nil
        isActive = false
        tutorialDataSource.markCompleted()
    }
}
