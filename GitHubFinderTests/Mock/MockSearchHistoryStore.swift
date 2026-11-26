/*
 Abstract:
 SearchHistoryStoreProtocol のテスト用 Mock 実装。
 UserDefaults に依存しない in-memory 実装。本番実装と同じ挙動（重複排除・上限切り詰め・空白トリム）を再現する。
 - addCallCount / lastAddedQuery でテストアサート可能
 - setHistoryForTest() で初期履歴を直接シード可能
 */

import Foundation
import Observation
import GitHubFinderData

@Observable
@MainActor
final class MockSearchHistoryStore: SearchHistoryStoreProtocol {
    private(set) var history: [String] = []

    private(set) var addCallCount = 0
    private(set) var lastAddedQuery: String?
    private(set) var removeCallCount = 0
    private(set) var clearCallCount = 0

    private let maxEntries: Int

    init(maxEntries: Int = 10, initialHistory: [String] = []) {
        self.maxEntries = maxEntries
        self.history = Array(initialHistory.prefix(maxEntries))
    }

    func add(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        addCallCount += 1
        lastAddedQuery = query

        var updated = history.filter { $0 != query }
        updated.insert(query, at: 0)
        if updated.count > maxEntries {
            updated = Array(updated.prefix(maxEntries))
        }
        history = updated
    }

    func remove(_ query: String) {
        removeCallCount += 1
        history.removeAll { $0 == query }
    }

    func clear() {
        clearCallCount += 1
        history = []
    }

    /// テスト用の即時シード（add のロジックを通さず履歴を直接差し込む）
    func setHistoryForTest(_ items: [String]) {
        history = items
    }
}
