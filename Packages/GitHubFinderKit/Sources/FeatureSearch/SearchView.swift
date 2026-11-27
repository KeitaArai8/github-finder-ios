/*
 Abstract:
 リポジトリ検索画面。キーワード入力、検索結果一覧、お気に入りトグルを提供。
 */

import SwiftUI
import GitHubFinderDomain
import GitHubFinderData
import GitHubFinderDesignSystem

public struct SearchView: View {
    @Bindable var model: SearchModel
    @State private var safariDestination: SafariDestination?

    /// 検索履歴行の削除（X）ボタンの一辺（pt）。アイコンの周囲にタップ領域を確保する。
    private static let historyDeleteButtonSide: CGFloat = 36

    public init(model: SearchModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            contentView
                .navigationTitle(LocalizedStringResource("検索", bundle: #bundle))
                .searchable(
                    text: $model.searchQuery,
                    prompt: Text("リポジトリを検索", bundle: #bundle)
                )
                // 入力が変わるたびに前のタスクがキャンセルされ、500ms 無入力が続いたときだけ検索する（debounce）
                .task(id: model.searchQuery) {
                    // 空クエリは待たずに即リセットする（debounce は検索を始める入力にだけ適用）
                    if !model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    guard !Task.isCancelled else { return }
                    await model.search()
                }
                .task {
                    await model.load()
                }
                .alert(Text("エラー", bundle: #bundle), isPresented: $model.isErrorPresented) {
                    Button(LocalizedStringResource("OK", bundle: #bundle)) { model.dismissError() }
                } message: {
                    Text(model.errorMessage ?? "")
                }
                .sheet(item: $safariDestination) { destination in
                    SafariView(url: destination.url)
                }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch model.viewState {
        case .idle:
            // 履歴がある場合は履歴一覧を、無ければ初期メッセージを表示
            if model.searchHistoryStore.history.isEmpty {
                ContentUnavailableView(
                    label: {
                        Label(
                            LocalizedStringResource("リポジトリを検索", bundle: #bundle),
                            systemImage: "magnifyingglass"
                        )
                    },
                    description: { Text("キーワードを入力して\nGitHubリポジトリを探しましょう", bundle: #bundle) }
                )
            } else {
                searchHistoryList
            }

        case .loading:
            ProgressView { Text("検索中...", bundle: #bundle) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let items):
            repositoryList(items)

        case .empty:
            ContentUnavailableView(
                label: {
                    Label(
                        LocalizedStringResource("結果が見つかりません", bundle: #bundle),
                        systemImage: "magnifyingglass"
                    )
                },
                description: { Text("別のキーワードで検索してみてください", bundle: #bundle) }
            )

        case .error(let message):
            ErrorView(message: message) {
                Task { await model.onRefresh() }
            }
        }
    }

    // MARK: - Search History

    private var searchHistoryList: some View {
        List {
            Section {
                ForEach(model.searchHistoryStore.history, id: \.self) { query in
                    searchHistoryRow(query)
                }
            } header: {
                searchHistoryHeader
            }
        }
        .listStyle(.plain)
    }

    /// 行タップで再検索 / 行末 X タップで個別削除（Android と統一）。
    /// swipeActions ではなく trailing X icon を採用しているのは、検索履歴の業界 defacto
    /// (Google / YouTube / Chrome 等) に従い、可視性と 1-tap 完結を優先するため。
    ///
    /// 構造: 「行タップ用 Button」と「X 削除 Button」を並列に配置し、
    ///       両方を `.buttonStyle(.plain)` で SwiftUI に「独立した tap 領域」と認識させる。
    ///       VoiceOver でも 2 つの操作要素として個別フォーカスされる。
    private func searchHistoryRow(_ query: String) -> some View {
        HStack(spacing: 0) {
            Button {
                Task { await model.selectHistory(query) }
            } label: {
                HStack(spacing: Spacing.spacing150) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Color.Content.secondary)
                    Text(query)
                        .foregroundStyle(Color.Content.primary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(query)
            .accessibilityHint(Text("ダブルタップでこのキーワードを再検索", bundle: #bundle))

            Button {
                model.removeHistory(query)
            } label: {
                Image(systemName: "xmark")
                    .font(.appLabelMedium)
                    .foregroundStyle(Color.Content.tertiary)
                    .frame(
                        width: Self.historyDeleteButtonSide,
                        height: Self.historyDeleteButtonSide
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(query) を履歴から削除", bundle: #bundle))
        }
    }

    private var searchHistoryHeader: some View {
        HStack(spacing: 0) {
            Text("最近の検索", bundle: #bundle)
            Spacer()
            Button(LocalizedStringResource("すべて消去", bundle: #bundle), role: .destructive) {
                model.clearHistory()
            }
            .font(.appLabelMedium)
            .textCase(nil)
        }
    }

    // MARK: - Repository List

    private func repositoryList(_ items: [RepositoryDisplayItem]) -> some View {
        List {
            ForEach(items) { item in
                repositoryRow(item, in: items)
            }

            if model.isLoadingMore {
                HStack(spacing: 0) {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await model.onRefresh()
        }
    }

    private func repositoryRow(
        _ item: RepositoryDisplayItem,
        in items: [RepositoryDisplayItem]
    ) -> some View {
        RepositoryRow(
            item: item,
            onOpen: {
                safariDestination = makeGitHubURL(fullName: item.fullName)
                    .map(SafariDestination.init(url:))
            },
            onFavoriteTap: { Task { await model.toggleFavorite(item) } }
        )
        .contextMenu {
            if let url = makeGitHubURL(fullName: item.fullName) {
                ShareLink(item: url) {
                    Label(
                        LocalizedStringResource("リポジトリをシェア", bundle: #bundle),
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
        }
        .onAppear {
            if items.suffix(3).contains(where: { $0.id == item.id }) {
                Task { await model.onLoadMore() }
            }
        }
    }
}

// MARK: - Repository Row

private struct RepositoryRow: View {
    let item: RepositoryDisplayItem
    let onOpen: () -> Void
    let onFavoriteTap: () -> Void

    var body: some View {
        // 「リポジトリを開く Button」と「お気に入り Button」を並列に配置する（検索履歴行と同じ構造）。
        // 入れ子にせず独立した tap 領域にすることで、タップが衝突せず VoiceOver でも別々のボタンとして読まれる。
        HStack(spacing: Spacing.spacing150) {
            Button(action: onOpen) {
                HStack(spacing: Spacing.spacing150) {
                    RepositorySummaryView(
                        fullName: item.fullName,
                        description: item.description,
                        starCount: item.starCount,
                        language: item.language,
                        ownerAvatarURL: item.ownerAvatarURL
                    )
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            favoriteButton
        }
        .padding(.vertical, Spacing.spacing50)
    }

    private var favoriteButton: some View {
        Button(action: onFavoriteTap) {
            Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(item.isFavorite ? Color.Brand.favorite : Color.Content.tertiary)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isFavorite
            ? Text(
                "お気に入りから削除",
                bundle: #bundle,
                comment: "Accessibility label when the repository is currently a favorite"
            )
            : Text(
                "お気に入りに追加",
                bundle: #bundle,
                comment: "Accessibility label when the repository is not a favorite yet"
            )
        )
        .accessibilityHint(Text(
            "ダブルタップで切り替え",
            bundle: #bundle,
            comment: "Accessibility hint for favorite toggle"
        ))
    }
}

// MARK: - Previews

#if DEBUG

private func makePreviewSearchModel(
    state: ViewState<[RepositoryDisplayItem]>,
    history: [String] = []
) -> SearchModel {
    // Preview 専用 UserDefaults。本番の検索履歴を汚染しないよう Suite 名を分離する
    let suite = "preview.search.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suite) ?? .standard
    let historyStore = SearchHistoryStore(userDefaults: userDefaults)
    // history を逆順に追加（add は先頭挿入なので最終的にこの順番になるよう）
    history.reversed().forEach { historyStore.add($0) }

    let model = SearchModel(
        searchRepository: PreviewSearchRepository(),
        favoriteStore: FavoriteStore(favoriteRepository: PreviewFavoriteRepository()),
        searchHistoryStore: historyStore
    )
    model._setPreviewState(state)
    return model
}

private func makePreviewItem(
    id: Int,
    fullName: String,
    star: Int,
    language: String? = "Swift"
) -> RepositoryDisplayItem {
    RepositoryDisplayItem(
        repository: RepositoryEntity(
            id: id,
            fullName: fullName,
            description: "Sample repository description",
            starCount: star,
            language: language,
            ownerAvatarURL: nil
        ),
        isFavorite: false
    )
}

#Preview("Idle（初期状態・履歴なし）") {
    SearchView(model: makePreviewSearchModel(state: .idle))
}

#Preview("Idle（履歴あり）") {
    SearchView(model: makePreviewSearchModel(
        state: .idle,
        history: ["swift", "compose", "kotlin", "tca", "jetpack"]
    ))
}

#Preview("Loaded") {
    SearchView(model: makePreviewSearchModel(state: .loaded([
        makePreviewItem(
            id: 1,
            fullName: "apple/swift",
            star: 67_000,
            language: "C++"
        ),
        makePreviewItem(
            id: 2,
            fullName: "pointfreeco/swift-composable-architecture",
            star: 13_000
        ),
        makePreviewItem(
            id: 3,
            fullName: "Alamofire/Alamofire",
            star: 41_000
        ),
    ])))
}

#Preview("Loading") {
    SearchView(model: makePreviewSearchModel(state: .loading))
}

#Preview("Empty") {
    SearchView(model: makePreviewSearchModel(state: .empty))
}

#Preview("Error") {
    SearchView(model: makePreviewSearchModel(state: .error("ネットワークに接続できません")))
}

// MARK: - Preview 専用 Repository

private nonisolated final class PreviewSearchRepository: SearchRepositoryProtocol {
    func search(query: String, page: Int) async throws -> SearchResultEntity {
        SearchResultEntity(
            totalCount: 0,
            items: [],
            hasNextPage: false
        )
    }
}

private nonisolated final class PreviewFavoriteRepository: FavoriteRepositoryProtocol {
    func getAll() async throws -> [FavoriteEntity] { [] }
    func add(_ repository: RepositoryEntity) async throws {}
    func remove(id: Int) async throws {}
}

#endif
