# GitHubFinder (iOS)

GitHubのリポジトリをキーワードで検索し、お気に入りに保存できるiOSアプリです。2026 年時点のデファクトスタンダード（SwiftUI + `@Observable` + SwiftData + Swift Testing + WidgetKit）に準拠した学習サンプル実装です。

デファクトスタンダードに準拠したうえで、個人のコーディング規約（引数の改行、関数の長さ、デザイントークンの徹底、stack の `spacing` の明示など）も適用しています。これらは個人の規約であり、Apple や Swift.org の公式な推奨ではありません。

## 技術スタック

| 項目 | 選定 |
|------|------|
| UI | SwiftUI |
| 状態管理 | `@Observable` + 軽量UDF |
| 永続化 | SwiftData（App Group 共有コンテナ） |
| ネットワーク | URLSession (async/await) |
| DI | init ベース |
| テスト | Swift Testing + XCUITest |
| Widget | WidgetKit + TimelineProvider |
| 最小OS | iOS 26+ |
| Swift | Swift 6 言語モード（Xcode 27 / Swift 6.4） |

## アーキテクチャ

[Android公式アーキテクチャガイド](https://developer.android.com/topic/architecture)の設計思想を共通基盤とし、iOS のフレームワークで実現しています。

### 設計原則

| 原則 | 説明 |
|------|------|
| **UDF** | データは Data→UI へ流れ、イベントは UI→Data へ流れる |
| **SSOT** | お気に入り→SwiftData、検索結果→API+メモリキャッシュ |
| **不変データの公開** | State Holder (Model) のみが状態を更新 |
| **関心の分離** | View は表示のみ、ロジックは Model に集約 |
| **テスタビリティ** | protocol ベースの DI でモック差し替え可能 |

### レイヤー構成

```
┌─────────────────────────────────┐
│         UI Layer                │
│  View (SwiftUI) ← 表示のみ      │
│  Model (@Observable) ← UDF     │
└──────────────┬──────────────────┘
               ↓
┌─────────────────────────────────┐
│         Data Layer              │
│  Repository ← DataSource統合    │
│  ├── RemoteDataSource (API)     │
│  ├── LocalDataSource (SwiftData)│
│  └── CacheDataSource (メモリ)   │
└─────────────────────────────────┘
```

Domain Layer（UseCase）は設けていません。このアプリの規模では不要と判断しました（Android公式でもオプションと明記）。

### DataSource の分離

Android公式に従い、各DataSourceは**単一のデータソースのみ**を処理します。

| DataSource | 責務 | データソース |
|-----------|------|------------|
| `GitHubRemoteDataSource` | GitHub API 通信のみ（struct） | URLSession |
| `FavoriteLocalDataSource` | お気に入り CRUD のみ | SwiftData (`@ModelActor`, async throws) |
| `SearchCacheDataSource` | 検索結果のメモリキャッシュ | Dictionary (actor) |
| `TutorialLocalDataSource` | チュートリアルフラグ管理 | UserDefaults |

`TutorialLocalDataSource` だけは Repository を挟まず、`CoachMarkManager` が直接保持します。`UserDefaults` の Bool を 1 つ読み書きするだけで、統合する DataSource もエラー変換も無いためです（`SearchHistoryStore` が `UserDefaults` を直接扱うのと同じ判断です）。Tutorial 機能でしか使わないので `FeatureTutorial` に置いています。

`SearchRepositoryImpl` はリモートとキャッシュの 2 つの DataSource を統合し、エラー変換とキャッシュ制御を行います。`FavoriteRepositoryImpl` は `FavoriteLocalDataSource` へそのまま委譲します（エラーは変換しません）。

### SSOT（単一信頼源）

| データ | SSOT | 理由 |
|--------|------|------|
| お気に入り | SwiftData (App Group 共有) | アプリ終了後も保持。アプリと Widget で同じファイルを参照 |
| 検索結果 | API + メモリキャッシュ | API が正。キャッシュはアプリ起動中のみ |
| チュートリアル表示済み | UserDefaults | ローカルフラグ |

### お気に入り設計（Passive View + SSOT）

Entity にフラグを持たせず、Model 内で表示用構造体 `RepositoryDisplayItem` に変換して公開します。View は受け取った値をそのまま表示するだけです。

```
SearchModel（内部）
├── allItems: [RepositoryEntity]       ← API から取得した生データ
└── favoriteStore: FavoriteStore       ← お気に入り ID を保持する共有 Store（追加・削除・読み込みのたびに DB から取り直す）

SearchModel（公開）
└── viewState: ViewState<[RepositoryDisplayItem]>  ← 上の 2 つから都度導出する。View はこれを表示するだけ
```

### エラーハンドリング

```
DataSource → 生の例外を throw
    ↓
Repository → SearchRepositoryImpl は catch して AppError に変換（FavoriteRepositoryImpl は変換せずそのまま throw）
    ↓
Model → AppError を ViewState.error に反映
    ↓
View → エラーメッセージ + リトライボタン表示
```

### ViewState（5状態）

| 状態 | 意味 |
|------|------|
| `idle` | 初期状態 |
| `loading` | データ取得中 |
| `loaded(data)` | データあり |
| `empty` | 取得成功だがデータなし |
| `error(message)` | 失敗 |

### DesignSystem トークン

`GitHubFinderDesignSystem` は単なる UI コンポーネント置き場ではなく、**セマンティック・トークン**を提供する真のデザインシステム。各 View はハードコードされた `16` / `Color.gray` / `.font(.headline)` を直接使わず、**必ずトークンを経由**する。

例外として、対応するトークンが無い値は View に直接書いている（トークンは増やしていない）: アイコンの `.font(.title3)`、チュートリアルの暗転 `Color.black.opacity(0.75)`・パルスリングの `Color.white`・吹き出しの `Color.blue`、チュートリアルのモック UI の `Color.gray`、10pt / 6pt / 2pt の間隔、14pt / 10pt の角丸、要素の位置・サイズの数値。`FavoriteWidget` は DesignSystem を import していないため、システムのフォントと色を直接指定している。

| トークン | 場所 | 例 |
|---------|------|-----|
| `Spacing` | `Tokens/Spacing.swift` | `Spacing.spacing100` (8pt), `Spacing.spacing200` (16pt) ... 8pt グリッドベース |
| `Radius` | `Tokens/Radius.swift` | `Radius.radius50` (4pt), `Radius.radius100` (8pt), `Radius.radiusFull` |
| `Color` | `Tokens/AppColor.swift` | `Color.Background.primary`, `Color.Content.secondary`, `Color.Brand.favorite` 等のセマンティック分類 |
| `Font` | `Tokens/AppFont.swift` | `.appTitleSmall`, `.appBodyMedium`, `.appLabelMedium`（Dynamic Type 追従） |

```swift
// ❌ ハードコード
HStack(spacing: 12) {
    Image(systemName: "heart.fill").foregroundStyle(.red)
    Text("お気に入り").font(.subheadline)
}
.padding(.horizontal, 16)
.background(Color(.systemBackground))

// ✅ トークン経由
HStack(spacing: Spacing.spacing150) {
    Image(systemName: "heart.fill").foregroundStyle(Color.Brand.favorite)
    Text("お気に入り").font(.appBodyMedium)
}
.padding(.horizontal, Spacing.spacing200)
.background(Color.Background.primary)
```

**メリット**:
- デザイン変更（spacing 体系の変更、ブランドカラー変更等）を**一箇所で吸収**できる
- トークン名が役割（intent）を表すため、コードを読むだけで設計意図がわかる
- ダークモード対応はセマンティックカラーが自動でハンドリング
- Dynamic Type にも自動追従

**確認**: `DesignSystemCatalog` ターゲットを起動すると、Tokens セクション（Spacing / Radius / AppColor / AppFont）でビジュアル一覧 + 実サイズが確認できる。

### App Group 共有コンテナ

アプリ本体と Widget Extension が SwiftData を共有するため、App Group 配下の SQLite ファイルを両ターゲットから参照します。

```swift
AppGroupContainer.makeModelContainer() throws -> ModelContainer
  → FileManager.containerURL(forSecurityApplicationGroupIdentifier:)
  → ModelConfiguration(url: storeURL)
```

失敗時の扱い:
- アプリ本体: `fatalError` で明確な診断（開発時の設定不備を即座に検知）
- Widget: `try?` で空状態にフォールバック（クラッシュ防止）

### オフライン検知（NetworkMonitor）

`NWPathMonitor` をラップした `@Observable` クラスで、`isConnected` を MainActor で公開:

```swift
@Observable @MainActor
final class NetworkMonitor {
    private(set) var isConnected: Bool = true
    // start() が NWPathMonitor の AsyncSequence を購読して接続状態を更新する
    // （View の `.task` から呼ぶ。View の消滅で Task がキャンセルされ購読も止まる）
}
```

`AppRootView` でメイン画面に `safeAreaBar(edge: .top)` として差し込み、トランジションで切替（バナーの分だけコンテンツが下がる）:

```swift
MainTabView(...)
    .safeAreaBar(edge: .top) {
        if !networkMonitor.isConnected {
            OfflineBanner()
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
```

### 構造化ログ（os.Logger）

`subsystem = "com.example.GitHubFinder"` + 機能別 category で分類:

| Category | 用途 |
|---|---|
| `search` | 検索 / API 呼び出し |
| `favorite` | お気に入り CRUD |
| `network` | 接続状態変化 |

```swift
Logger.search.info("Search succeeded: count=\(count), totalCount=\(total)")
Logger.search.error("Search failed: \(error.localizedDescription, privacy: .public)")
```

**Console.app** から `subsystem == "com.example.GitHubFinder"` でフィルタ表示可能。

### 検索の debounce（`.task(id:)`）

`SearchView` が `.task(id: model.searchQuery)` で 500ms 待ってから（空クエリは待たずに即リセット）`model.search()` を呼ぶ。入力が変わると前のタスクが自動キャンセルされるため、手動の Task 管理や Clock 抽象化は不要。`SearchModel.search()` は async メソッドなので、テストでは直接 `await` できる。

## ディレクトリ構成（NiA 風モジュール分割）

Now in Android（NiA）に倣い、ローカル Swift Package `GitHubFinderKit` で物理的にレイヤー分割している。
App ターゲットは composition root のみ（3 ファイル）に保ち、ロジック・UI はすべてパッケージ側に集約。
Feature 同士は直接参照不可で、コンパイル時に依存方向の不正を検出できる。

```
GitHubFinder/
├── GitHubFinder.xcodeproj
├── GitHubFinder/                              ← App ターゲット（composition root のみ）
│   ├── GitHubFinderApp.swift                  ← @main + DI 組み立て
│   └── Presentation/App/
│       ├── AppRootView.swift                  ← Tutorial/MainTabView + OfflineBanner 切替
│       └── MainTabView.swift                  ← 検索/お気に入り/設定の 3 タブ
│
├── FavoriteWidget/                            ← Widget Extension（別ターゲット）
│   ├── FavoriteWidget.swift                   ← TimelineProvider + WidgetView
│   ├── FavoriteWidgetBundle.swift
│   └── Localizable.xcstrings
│
├── DesignSystemCatalog/                       ← DesignSystem のカタログアプリ（別ターゲット）
├── GitHubFinderUITests/                       ← XCUITest
│
└── Packages/GitHubFinderKit/                  ← Local Swift Package（7 target + テスト 1 target）
    ├── Package.swift
    ├── Tests/GitHubFinderKitTests/            ← Swift Testing の単体テスト（アプリを起動せずに実行）
    └── Sources/
        ├── GitHubFinderDomain/                ← Entity / Repository protocol / AppError / AppLogger /
        │                                        GitHubURL（依存なし）
        ├── GitHubFinderData/                  ← Repository Impl / DataSource (Remote/Local/Cache)
        │                                        DTO / DB / NetworkMonitor / FavoriteStore /
        │                                        SearchHistoryStore + Protocol / AppGroupContainer
        │                                        （依存: Domain）
        ├── GitHubFinderDesignSystem/          ← Tokens (Spacing / Radius / AppColor / AppFont) /
        │                                        ViewState / ErrorView / OfflineBanner /
        │                                        RepositorySummaryView / SafariView（依存なし）
        ├── FeatureSearch/                     ← SearchModel + SearchView + RepositoryDisplayItem
        │                                        （依存: Domain, Data, DesignSystem）
        ├── FeatureFavorite/                   ← FavoriteModel + FavoriteListView
        │                                        （依存: Domain, Data, DesignSystem）
        ├── FeatureSettings/                   ← SettingsView（依存: DesignSystem）
        └── FeatureTutorial/                   ← CoachMarkManager / CoachMarkOverlay /
                                                 CoachMarkPreferenceKey / TutorialScreen /
                                                 PulseEffect / View+ReverseMask /
                                                 TutorialLocalDataSource（依存: DesignSystem）
```

### モジュール依存グラフ

```
   Domain (entities, protocols, errors, logger)        DesignSystem (tokens, 共通 UI)
      ▲              ▲                                        ▲
      │              │                                        │
    Data             │                                        │
      ▲              │                                        │
      └──────┬───────┘                                        │
             │                                                │
   FeatureSearch / FeatureFavorite ───────────────────────────┤
                                                              │
   FeatureSettings / FeatureTutorial ─────────────────────────┘

   App target（composition root）は Data と DesignSystem、4 つの Feature を組み立てる
```

DesignSystem は Domain を含むどの target にも依存しません（トークンと、primitive な値だけを受け取る共通 UI）。`SafariView` は 3 つの画面が共有する UI のラッパーなので DesignSystem に置いています。

| ターゲット | 依存先 |
|---|---|
| `GitHubFinder.app` | Data, DesignSystem, FeatureSearch, FeatureFavorite, FeatureSettings, FeatureTutorial |
| `FavoriteWidgetExtension.appex` | Domain, Data |
| `GitHubFinderKitTests`（パッケージのテスト） | Domain, Data, DesignSystem, FeatureSearch, FeatureFavorite |
| `DesignSystemCatalog.app` | DesignSystem |

## DI の流れ

```
GitHubFinderApp.init()
├── ModelContainer (App Group 共有)
├── DataSources
│   ├── GitHubRemoteDataSource()
│   ├── SearchCacheDataSource()
│   ├── FavoriteLocalDataSource(modelContainer:)
│   └── TutorialLocalDataSource()
├── Repositories
│   ├── SearchRepositoryImpl(remote:, cache:)
│   └── FavoriteRepositoryImpl(local:)
├── Shared Stores
│   ├── FavoriteStore(favoriteRepository:, onFavoritesChanged:)  ← 変更時にウィジェットを更新する処理を渡す
│   └── SearchHistoryStore()
├── Models (State Holders)
│   ├── SearchModel(searchRepository:, favoriteStore:, searchHistoryStore:)
│   ├── FavoriteModel(favoriteStore:)
│   └── CoachMarkManager(tutorialDataSource:)
└── NetworkMonitor()
```

## 機能一覧

### メイン機能

| 機能 | 説明 |
|------|------|
| キーワード検索 | デバウンス付き（500ms）、GitHub API |
| **検索履歴** | 直近10件を `UserDefaults` に永続化、Idle 時に履歴一覧 / 行タップで即時再検索 / 行末の X ボタンで個別削除 / 全消去 |
| 無限スクロール | ページネーション対応（末尾3件手前でプリフェッチ） |
| お気に入り登録/解除 | ハートボタン、SwiftData 永続化 |
| お気に入り一覧 | スワイプ削除 / 行タップで GitHub ページを SafariView で開く |
| **ソート（メモリ保持）** | 保存が新しい順 / Star 多い順 / 名前 A→Z（ToolbarItem の Menu Picker） |
| **言語フィルタ（メモリ保持）** | 登録済み言語を Chip で動的提示、トグルで絞り込み・解除（フィルタ中の言語が消失すると自動クリア） |
| **シェア** | `ShareLink`（iOS 16+）で GitHub URL をシェア（検索結果は contextMenu、お気に入りは contextMenu + leading swipe action） |
| **一括選択削除** | 編集モードで複数選択 → 確認ダイアログ → 一括削除 |
| メモリキャッシュ | 検索結果をアプリ起動中キャッシュ |
| プルリフレッシュ | 検索・お気に入り両画面 |
| **オフライン検知** | `NWPathMonitor` で接続状態を監視、切断時に画面上部にバナー表示 |
| **構造化ログ** | `os.Logger` で subsystem + category 別にイベントを記録（Console.app から検索可） |
| チュートリアル | **スポットライト型専用画面**（TutorialScreen）、初回起動時のみ |
| 設定画面 | プライバシーポリシー/利用規約（SFSafariViewController） |
| ダークモード | システム設定追従 |
| エラーハンドリング | 5分類（Network/RateLimit/Server/Decode/Unknown）+ リトライ |

### ホームウィジェット

| 項目 | 内容 |
|------|------|
| 機能 | お気に入り上位5件をホーム画面に表示 |
| サイズ | Small (1件) / Medium (3件) / Large (5件) |
| データ取得 | App Group 経由で SwiftData を直接読む |
| 更新頻度 | 1時間ごと（TimelineProvider .after policy）。アプリでお気に入りを追加・削除したときは即時に更新 |
| タップ動作 | アプリ起動 |

### チュートリアル（スポットライト型）

専用の `TutorialScreen` でモック UI を組み、実際のアプリ UI と同じレイアウトに `coachMarkAnchor` を付与してスポットライトを当てます。本機能実装には一切影響しません。

| ステップ | 操作 |
|---------|------|
| 1. 検索バー | モック TextField タップで次へ |
| 2. お気に入りボタン | モックハートタップで次へ |
| 3. お気に入りタブ | モックタブタップで完了 |

## セキュリティ

| 項目 | 対応 |
|------|------|
| ATS | デフォルト有効（HTTPS 強制） |
| URL 構築 | `URLComponents` で path を自動 percent-encode（[GitHubURL.swift](Packages/GitHubFinderKit/Sources/GitHubFinderDomain/GitHubURL.swift)） |
| App Group | メインアプリ・Widget 両方で `group.com.example.GitHubFinder` を設定 |
| データ保護 | 公開リポジトリ情報のみ保存。認証情報なし |
| SQL インジェクション | SwiftData Predicate（`#Predicate` マクロ）で型安全 |

## テスト

### Unit Tests（Swift Testing）

`GitHubFinderKit` パッケージのテストターゲット `GitHubFinderKitTests` にあります。アプリを起動せずに実行できます。

```bash
cd Packages/GitHubFinderKit
xcodebuild test -scheme GitHubFinderKit-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

Xcode では `Packages/GitHubFinderKit` を開いて `GitHubFinderKit-Package` スキームでテストします。`GitHubFinder.xcodeproj` の `GitHubFinder` スキームのテストは UI テストだけです。

| 層 | テストファイル |
|---|---|
| Presentation | SearchModelTests, FavoriteModelTests |
| Data/Store | SearchHistoryStoreTests, FavoriteStoreTests |
| Data/Cache | SearchCacheDataSourceTests |
| Data/Local | FavoriteLocalDataSourceTests（SwiftData in-memory）, FavoriteSchemaTests |
| Data/Remote | GitHubRemoteDataSourceTests（URLProtocol モック） |
| Data/Repository | SearchRepositoryImplTests, FavoriteRepositoryImplTests |

### UI Tests（XCUITest）

- 起動時のタブバー表示と初期画面の確認
- 3タブ間の遷移（検索 → お気に入り → 設定 → 検索）

### テスト手法のハイライト

- `MockURLProtocol` によるネットワークモック
- SwiftData `ModelConfiguration(isStoredInMemoryOnly: true)` でハーメティックな DB テスト
- Model の非同期メソッドを直接 `await`（debounce は View の `.task(id:)` が担うため Model 側は待機不要）
- `// Arrange:` / `// Act:` / `// Assert:` の AAA コメント必須

## セットアップ

1. Xcode 27+ で `GitHubFinder.xcodeproj` を開く
2. シミュレータを選択して Run

### Widget の動作確認

1. アプリ起動 → 検索 → お気に入りを数件登録
2. ホーム画面長押し → **+** → 「GitHubFinder」を検索 → 配置

### Widget と共有するコード

Widget Extension は `GitHubFinderKit` パッケージの `GitHubFinderData` / `GitHubFinderDomain` をリンクして App Group の SwiftData を読むため、個別ファイルの Target Membership 設定は不要。

### スキーマと文言

- SwiftData のモデル `FavoriteRecord` は `FavoriteSchemaV1`（`VersionedSchema`）の入れ子型で、将来のスキーマ変更は `FavoriteMigrationPlan` にステージを足して移行する。エンティティ名 `FavoriteRecord` は共有ストアのキーなので、テストで固定している。
- 文言は各パッケージ target と Widget がそれぞれ `Localizable.xcstrings` を持ち（`Text(..., bundle: #bundle)` で参照）、App 側のカタログは App ターゲットのコードで使う文字列だけを持つ。

GitHub API は認証なし（Rate Limit: 10 req/min）で動作します。

## 命名規則

| 種類 | 命名 |
|------|------|
| Entity | `〇〇Entity` |
| DTO | `〇〇DTO` |
| SwiftData Model | `〇〇Record` |
| Repository protocol | `〇〇RepositoryProtocol` |
| Repository 実装 | `〇〇RepositoryImpl` |
| DataSource | `〇〇RemoteDataSource` / `〇〇LocalDataSource` / `〇〇CacheDataSource` |
| Model (State Holder) | `〇〇Model` |
| View | `〇〇View` |

## Android版

同一仕様の Android 版が [KeitaArai8/github-finder-android](https://github.com/KeitaArai8/github-finder-android) にあります。設計思想・機能は共通で、技術スタックのみが異なります。

## オープンソース利用について

### ライセンス
[MIT License](./LICENSE) で公開しています。

### フォーク時の識別子置換

このリポジトリをフォークして利用する場合、以下の識別子を**自身のものに変更してください**:

| 項目 | サンプル値 | 変更先の例 |
|---|---|---|
| Bundle Identifier | `com.k-arai.GitHubFinder` | `com.yourdomain.GitHubFinder` |
| App Group | `group.com.example.GitHubFinder` | `group.com.yourdomain.GitHubFinder` |
| Widget Bundle ID | `com.k-arai.GitHubFinder.FavoriteWidget` | 同上 + Widget サフィックス |
| Team ID / Signing | 未設定（`DEVELOPMENT_TEAM` は空） | Xcode の **Signing & Capabilities** で設定 |

#### 変更箇所

1. **Xcode プロジェクト設定**
   - Targets → `GitHubFinder` / `FavoriteWidgetExtension` の **Bundle Identifier**
   - **Signing & Capabilities** タブの **App Groups**
2. **エンタイトルメント ファイル**
   - `GitHubFinder/GitHubFinder.entitlements`
   - `FavoriteWidgetExtension.entitlements`
3. **ソースコード**
   - [`AppGroupContainer.swift`](Packages/GitHubFinderKit/Sources/GitHubFinderData/AppGroup/AppGroupContainer.swift) の `identifier` 定数

### GitHub 商標について

本アプリは GitHub Inc. と無関係な学習用サンプルです。アプリ名・アイコンに公式 GitHub の商標を使用していません。

### GitHub API 利用について

[GitHub REST API Terms of Use](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) に準拠してください。このアプリが使う検索 API の認証なしのレートリミットは **10 req/min** です。

### セキュリティ

脆弱性を発見された場合は [SECURITY.md](./SECURITY.md) を参照してください。

### 免責事項

本アプリは**学習・教育目的のサンプル実装**です。本番環境での利用は自己責任でお願いします。Apple 公式サンプル相当の品質を目指していますが、特定用途への適合性を保証するものではありません。
