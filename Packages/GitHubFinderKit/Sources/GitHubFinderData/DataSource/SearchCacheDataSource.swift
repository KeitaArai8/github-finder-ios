/*
 Abstract:
 検索結果のメモリキャッシュを管理するデータソース。
 */

import GitHubFinderDomain

public actor SearchCacheDataSource {
    private var cache: [String: SearchResultEntity] = [:]

    public init() {}

    public func get(query: String, page: Int) -> SearchResultEntity? {
        cache[cacheKey(query: query, page: page)]
    }

    public func set(
        query: String,
        page: Int,
        result: SearchResultEntity
    ) {
        cache[cacheKey(query: query, page: page)] = result
    }

    /// 指定クエリの全ページを破棄する
    public func removeAll(query: String) {
        let prefix = cacheKeyPrefix(query: query)
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
    }

    private func cacheKey(query: String, page: Int) -> String {
        "\(cacheKeyPrefix(query: query))\(page)"
    }

    /// ページ番号を除いたキーの先頭部分。区切りは改行（検索語に含まれない文字）にして、
    /// `a` と `a:1` のように検索語が別のキーの先頭と一致して誤って破棄されるのを防ぐ
    private func cacheKeyPrefix(query: String) -> String {
        "\(query.lowercased())\n"
    }
}
