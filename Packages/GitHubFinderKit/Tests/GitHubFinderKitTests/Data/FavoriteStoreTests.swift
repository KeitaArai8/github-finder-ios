/*
 Abstract:
 FavoriteStore の変更通知（onFavoritesChanged）の呼び出しを検証する単体テスト。
 */

import Testing
import GitHubFinderDomain
@testable import GitHubFinderData

@Suite("FavoriteStore")
@MainActor
struct FavoriteStoreTests {

    @Test("追加と削除が保存されるたびに onFavoritesChanged が呼ばれる")
    func addAndRemoveNotifyChange() async throws {
        // Arrange: 呼び出し回数を数えるコールバックを渡した Store
        var changeCount = 0
        let store = FavoriteStore(
            favoriteRepository: MockFavoriteRepository(),
            onFavoritesChanged: { changeCount += 1 }
        )

        // Act: 1 件追加して、同じものを削除
        try await store.add(TestData.makeRepository(id: 1))
        try await store.remove(id: 1)

        // Assert: 追加と削除で 1 回ずつ呼ばれる
        #expect(changeCount == 2)
    }

    @Test("追加が失敗したときは onFavoritesChanged を呼ばない")
    func failedAddDoesNotNotifyChange() async {
        // Arrange: add が失敗するリポジトリ
        var changeCount = 0
        let repository = MockFavoriteRepository()
        repository.shouldThrowOnAdd = true
        let store = FavoriteStore(
            favoriteRepository: repository,
            onFavoritesChanged: { changeCount += 1 }
        )

        // Act: 追加を試みる（失敗する）
        try? await store.add(TestData.makeRepository(id: 1))

        // Assert: 保存されていないので呼ばれない
        #expect(changeCount == 0)
    }
}
