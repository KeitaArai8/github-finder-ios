/*
 Abstract:
 お気に入りリポジトリの一覧画面。
 通常モード: スワイプ削除 / 行タップでGitHubページを開く
 編集モード: 複数選択 → 一括削除（確認ダイアログ付き）
 */

import SwiftUI
import GitHubFinderDomain
import GitHubFinderData
import GitHubFinderDesignSystem

public struct FavoriteListView: View {
    @Bindable var model: FavoriteModel
    @State private var safariDestination: SafariDestination?

    public init(model: FavoriteModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            contentView
                .navigationTitle(navigationTitle)
                .toolbar { toolbarContent }
                .task {
                    await model.load()
                }
                .alert(Text("エラー", bundle: #bundle), isPresented: $model.isErrorPresented) {
                    Button(LocalizedStringResource("OK", bundle: #bundle)) { model.dismissError() }
                } message: {
                    Text(model.errorMessage ?? "")
                }
                .confirmationDialog(
                    LocalizedStringResource(
                        "\(model.selectedIDs.count)件のお気に入りを削除しますか？",
                        bundle: #bundle
                    ),
                    isPresented: $model.isDeleteConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    Button(LocalizedStringResource("削除", bundle: #bundle), role: .destructive) {
                        Task { await model.confirmRemoveSelected() }
                    }
                    Button(LocalizedStringResource("キャンセル", bundle: #bundle), role: .cancel) {}
                } message: {
                    Text("この操作は取り消せません。", bundle: #bundle)
                }
                .sheet(item: $safariDestination) { destination in
                    SafariView(url: destination.url)
                }
        }
    }

    private var navigationTitle: LocalizedStringResource {
        model.isEditMode
            ? LocalizedStringResource("\(model.selectedIDs.count)件選択", bundle: #bundle)
            : LocalizedStringResource("お気に入り", bundle: #bundle)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 通常モード時: 右 = ソートメニュー + 編集ボタン（Android と並び順を統一）
        // 編集モード時: 左 = 全選択 / 右 = 削除(N) + 完了
        // ※ Android 側と同じく TopBar に集約。bottomBar は TabView 内の NavigationStack だと
        //   タブバーと衝突して表示されない SwiftUI の挙動があるため避けて TopBar に統一する。
        if case .loaded = model.viewState {
            if model.isEditMode {
                editModeToolbarContent
            } else {
                normalModeToolbarContent
            }
        }
    }

    @ToolbarContentBuilder
    private var normalModeToolbarContent: some ToolbarContent {
        // [sortMenu | 編集] の並び（Android の actions と同一順）。
        // 別々の ToolbarItem + 固定スペーサーにして、iOS 26 の Liquid Glass 上で
        // 「ソート」と「編集」を別のグラスとして分ける（同一グループだと 1 枚に融合する）。
        ToolbarItem(placement: .topBarTrailing) {
            sortMenu
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button(LocalizedStringResource("編集", bundle: #bundle)) {
                model.enterEditMode()
            }
        }
    }

    @ToolbarContentBuilder
    private var editModeToolbarContent: some ToolbarContent {
        // 全選択 ⇔ 全解除トグルを左に配置（iOS Photos.app と同じパターン）。
        // ラベル文言・状態判定は Model に集約しているため、View 側に if/三項演算子は書かない。
        ToolbarItem(placement: .topBarLeading) {
            Button(model.selectAllButtonTitle) {
                model.toggleSelectAll()
            }
        }
        // 削除(N) と 完了 は右に並べ、固定スペーサーで別のグラスに分ける。
        // 完了は確定操作なので role: .confirm（システムが強調スタイルで描く）。
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .destructive) {
                model.requestRemoveSelected()
            } label: {
                Text("削除(\(model.selectedIDs.count))", bundle: #bundle)
            }
            .disabled(model.selectedIDs.isEmpty)
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button(LocalizedStringResource("完了", bundle: #bundle), role: .confirm) {
                model.exitEditMode()
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker(LocalizedStringResource("並び替え", bundle: #bundle), selection: Binding(
                get: { model.sortKey },
                set: { model.setSortKey($0) }
            )) {
                ForEach(FavoriteSortKey.allCases) { key in
                    Text(key.displayName).tag(key)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .accessibilityLabel(Text("並び替え", bundle: #bundle))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch model.viewState {
        case .idle, .loading:
            ProgressView { Text("読み込み中...", bundle: #bundle) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let favorites):
            favoriteList(favorites)

        case .empty:
            ContentUnavailableView(
                label: {
                    Label(
                        LocalizedStringResource("お気に入りがありません", bundle: #bundle),
                        systemImage: "heart.slash"
                    )
                },
                description: { Text("検索画面からリポジトリを\nお気に入りに追加しましょう", bundle: #bundle) }
            )

        case .error(let message):
            ErrorView(message: message) {
                Task { await model.onRefresh() }
            }
        }
    }

    private func favoriteList(_ favorites: [FavoriteEntity]) -> some View {
        // selectedIDs は読むたびに導出されるため、行ごとに読まず 1 回だけ読む
        let selectedIDs = model.selectedIDs
        return VStack(spacing: 0) {
            // 編集モード中はフィルタ操作も誤動作しがちなので非表示
            if !model.isEditMode {
                languageFilterBar
            }
            List {
                ForEach(favorites) { favorite in
                    favoriteRowButton(favorite, isSelected: selectedIDs.contains(favorite.id))
                }
                .onDelete(perform: model.isEditMode ? nil : { indexSet in
                    let targets = indexSet.map { favorites[$0] }
                    Task {
                        for favorite in targets {
                            await model.removeFavorite(favorite)
                        }
                    }
                })
            }
            .listStyle(.plain)
            .refreshable {
                await model.onRefresh()
            }
            .overlay {
                // フィルタ後に該当0件の場合のメッセージ
                if favorites.isEmpty {
                    ContentUnavailableView(
                        label: {
                            Label(
                                LocalizedStringResource("該当するリポジトリがありません", bundle: #bundle),
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                        },
                        description: { Text("フィルタを変更してください", bundle: #bundle) }
                    )
                }
            }
        }
    }

    private func favoriteRowButton(_ favorite: FavoriteEntity, isSelected: Bool) -> some View {
        Button {
            if model.isEditMode {
                model.toggleSelection(id: favorite.id)
            } else {
                safariDestination = makeGitHubURL(fullName: favorite.fullName)
                    .map(SafariDestination.init(url:))
            }
        } label: {
            FavoriteRow(
                favorite: favorite,
                isEditMode: model.isEditMode,
                isSelected: isSelected
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 通常モード時のみシェア可能（編集モード中は contextMenu 衝突回避）
        .modifier(FavoriteRowShareModifier(
            favorite: favorite,
            isEditMode: model.isEditMode
        ))
    }

    @ViewBuilder
    private var languageFilterBar: some View {
        let languages = model.availableLanguages
        // filterLanguage は読むたびに導出されるため、チップごとに読まず 1 回だけ読む
        let filterLanguage = model.filterLanguage
        if !languages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.spacing100) {
                    FilterChip(
                        label: Text("すべて", bundle: #bundle),
                        isSelected: filterLanguage == nil,
                        action: { model.setFilterLanguage(nil) }
                    )
                    ForEach(languages, id: \.self) { language in
                        FilterChip(
                            label: Text(verbatim: language),
                            isSelected: filterLanguage == language,
                            action: {
                                // 同じチップをタップで選択解除（トグル動作）
                                model.setFilterLanguage(filterLanguage == language ? nil : language)
                            }
                        )
                    }
                }
                .padding(.horizontal, Spacing.spacing200)
                .padding(.vertical, Spacing.spacing100)
            }
            .background(Color.Background.primary)
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    /// 固定文言（カタログで翻訳）と言語名（翻訳しない）を同じ型で受けるため `Text` で受け取る。
    let label: Text
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.appBodyMedium)
                .padding(.horizontal, Spacing.spacing150)
                .padding(.vertical, Spacing.spacing50 + 2) // 6pt: 50 と 100 の中間
                .background(
                    Capsule()
                        .fill(isSelected ? Color.Content.accent : Color.Border.subtle)
                )
                .foregroundStyle(isSelected ? Color.Content.inverse : Color.Content.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Share Modifier

/// 行に GitHub URL のシェアを提供する Menu/contextMenu を付与する。
/// 編集モード中は誤操作防止のため何も付けない。
private struct FavoriteRowShareModifier: ViewModifier {
    let favorite: FavoriteEntity
    let isEditMode: Bool

    func body(content: Content) -> some View {
        if isEditMode {
            content
        } else {
            content
                .contextMenu {
                    if let url = makeGitHubURL(fullName: favorite.fullName) {
                        ShareLink(item: url) {
                            Label(
                                LocalizedStringResource("リポジトリをシェア", bundle: #bundle),
                                systemImage: "square.and.arrow.up"
                            )
                        }
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if let url = makeGitHubURL(fullName: favorite.fullName) {
                        ShareLink(item: url) {
                            Label(
                                LocalizedStringResource("シェア", bundle: #bundle),
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .tint(Color.Content.accent)
                    }
                }
        }
    }
}

// MARK: - Favorite Row

private struct FavoriteRow: View {
    let favorite: FavoriteEntity
    let isEditMode: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.spacing150) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.Content.accent : Color.Content.tertiary)
                    .accessibilityLabel(isSelected
                        ? Text("選択済み", bundle: #bundle)
                        : Text("未選択", bundle: #bundle)
                    )
            }
            RepositorySummaryView(
                fullName: favorite.fullName,
                description: favorite.description,
                starCount: favorite.starCount,
                language: favorite.language,
                ownerAvatarURL: favorite.ownerAvatarURL
            )
        }
        .padding(.vertical, Spacing.spacing50)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isEditMode
            ? Text("ダブルタップで選択/解除", bundle: #bundle)
            : Text("ダブルタップで GitHub ページを開く", bundle: #bundle)
        )
    }
}

// MARK: - Previews

#if DEBUG

/// 一覧は viewState ではなく favoriteStore の中身から導出されるため、Preview 用 Repository に仕込んで View の `.task` の load で読み込ませる。
/// 一覧の内容は `.task` が `load()` を実行した後に現れるため、Loaded / Edit Mode の Preview の最初の 1 フレームは空になる
private func makePreviewFavoriteModel(
    favorites: [FavoriteEntity] = [],
    isLoading: Bool = false,
    isEditMode: Bool = false,
    selectedIDs: Set<Int> = []
) -> FavoriteModel {
    let repository = PreviewFavoriteRepository(favorites: favorites, neverCompletes: isLoading)
    let model = FavoriteModel(favoriteStore: FavoriteStore(favoriteRepository: repository))
    model._setPreviewState(
        hasStartedLoading: true,
        hasLoaded: !isLoading,
        isEditMode: isEditMode,
        selectedIDs: selectedIDs
    )
    return model
}

private func makePreviewFavorites() -> [FavoriteEntity] {
    [
        FavoriteEntity(
            id: 1,
            fullName: "apple/swift",
            description: "The Swift Programming Language",
            starCount: 67_000,
            language: "C++",
            ownerAvatarURL: nil,
            savedAt: .now
        ),
        FavoriteEntity(
            id: 2,
            fullName: "pointfreeco/swift-composable-architecture",
            description: "A library for building applications in a consistent and understandable way",
            starCount: 13_000,
            language: "Swift",
            ownerAvatarURL: nil,
            savedAt: .now
        ),
        FavoriteEntity(
            id: 3,
            fullName: "Alamofire/Alamofire",
            description: "Elegant HTTP Networking",
            starCount: 41_000,
            language: "Swift",
            ownerAvatarURL: nil,
            savedAt: .now
        ),
    ]
}

#Preview("Loaded") {
    FavoriteListView(model: makePreviewFavoriteModel(favorites: makePreviewFavorites()))
}

#Preview("Edit Mode（2件選択中）") {
    FavoriteListView(model: makePreviewFavoriteModel(
        favorites: makePreviewFavorites(),
        isEditMode: true,
        selectedIDs: [1, 2]
    ))
}

#Preview("Empty") {
    FavoriteListView(model: makePreviewFavoriteModel())
}

#Preview("Loading") {
    FavoriteListView(model: makePreviewFavoriteModel(isLoading: true))
}

// MARK: - Preview 専用 Repository

private nonisolated final class PreviewFavoriteRepository: FavoriteRepositoryProtocol {
    let favorites: [FavoriteEntity]
    /// true の間は getAll が完了しない（Loading の Preview 用）
    let neverCompletes: Bool

    init(favorites: [FavoriteEntity], neverCompletes: Bool) {
        self.favorites = favorites
        self.neverCompletes = neverCompletes
    }

    func getAll() async throws -> [FavoriteEntity] {
        if neverCompletes { try await Task.sleep(for: .seconds(3600)) }
        return favorites
    }
    func add(_ repository: RepositoryEntity) async throws {}
    func remove(id: Int) async throws {}
}

#endif
