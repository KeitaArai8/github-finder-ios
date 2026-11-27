/*
 Abstract:
 テスト用の検索リポジトリモック。
 */

import Foundation
import GitHubFinderDomain

final class MockSearchRepository: SearchRepositoryProtocol, @unchecked Sendable {
    var searchResult: Result<SearchResultEntity, Error> = .success(
        SearchResultEntity(
            totalCount: 0,
            items: [],
            hasNextPage: false
        )
    )
    var searchCallCount = 0
    var lastSearchQuery: String?
    var lastSearchPage: Int?

    func search(query: String, page: Int) async throws -> SearchResultEntity {
        // 一度サスペンドして、onLoadMore の2回目の呼び出しが isLoadingMore=true の状態で割り込めるようにする
        // （無いと1回目が完了してしまい二重呼び出し防止のテスト loadMorePreventsDuplicateCalls が成立しない）
        await Task.yield()
        searchCallCount += 1
        lastSearchQuery = query
        lastSearchPage = page
        return try searchResult.get()
    }
}
