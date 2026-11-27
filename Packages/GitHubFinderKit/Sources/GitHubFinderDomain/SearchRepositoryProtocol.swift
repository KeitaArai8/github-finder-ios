/*
 Abstract:
 リポジトリ検索のデータアクセス契約。
 */

public protocol SearchRepositoryProtocol: Sendable {
    /// - Parameter forceRefresh: true のときはキャッシュを使わずに取得し直す（引っ張って更新・再試行用）
    func search(
        query: String,
        page: Int,
        forceRefresh: Bool
    ) async throws -> SearchResultEntity
}
