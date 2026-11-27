// swift-tools-version: 6.2
//
// GitHubFinderKit
// Now in Android (NiA) 風のモジュール分割を iOS で実現するための local Swift Package。
// 倣っているのは core 相当の層（Domain / Data / DesignSystem）と feature を別 target に分ける点。
// 依存の向きは NiA（`:core:domain` が `:core:data` に依存）と異なり、Data が Domain に依存する。
// アプリ本体（Xcode App target）からは複数の library product を import する。
// レイヤ依存:
//   Domain ← Data ← Feature*
//   Domain ← Feature*
//   DesignSystem ← Feature*（DesignSystem は他の target に依存しない）
// FeatureSearch / FeatureFavorite は Domain / Data / DesignSystem に、FeatureSettings / FeatureTutorial は
// DesignSystem だけに依存する。Feature 同士は不参照。
//
// ローカライズ: model 層の String(localized:) は各 target の Resources/Localizable.xcstrings と
// `bundle: #bundle` で解決する。
// view 層（Text / Button / Label 等）も同じ target のカタログで、`Text("…", bundle: #bundle)` や
//   `LocalizedStringResource("…", bundle: #bundle)` を使って解決する。
//   App target（GitHubFinder/・FavoriteWidget/）専用の文言だけが App 側のカタログに残る。

import PackageDescription

let package = Package(
    name: "GitHubFinderKit",
    defaultLocalization: "ja",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(name: "GitHubFinderDomain", targets: ["GitHubFinderDomain"]),
        .library(name: "GitHubFinderData", targets: ["GitHubFinderData"]),
        .library(name: "GitHubFinderDesignSystem", targets: ["GitHubFinderDesignSystem"]),
        .library(name: "FeatureSearch", targets: ["FeatureSearch"]),
        .library(name: "FeatureFavorite", targets: ["FeatureFavorite"]),
        .library(name: "FeatureSettings", targets: ["FeatureSettings"]),
        .library(name: "FeatureTutorial", targets: ["FeatureTutorial"]),
    ],
    targets: [
        // MARK: - Core layers
        .target(
            name: "GitHubFinderDomain",
            path: "Sources/GitHubFinderDomain",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ],
        ),
        .target(
            name: "GitHubFinderData",
            dependencies: ["GitHubFinderDomain"],
            path: "Sources/GitHubFinderData",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ],
        ),
        .target(
            name: "GitHubFinderDesignSystem",
            path: "Sources/GitHubFinderDesignSystem",
            resources: [.process("Resources")],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ],
        ),

        // MARK: - Feature layers
        .target(
            name: "FeatureSearch",
            dependencies: [
                "GitHubFinderDomain",
                "GitHubFinderData",
                "GitHubFinderDesignSystem",
            ],
            path: "Sources/FeatureSearch",
            resources: [.process("Resources")],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ],
        ),
        .target(
            name: "FeatureFavorite",
            dependencies: [
                "GitHubFinderDomain",
                "GitHubFinderData",
                "GitHubFinderDesignSystem",
            ],
            path: "Sources/FeatureFavorite",
            resources: [.process("Resources")],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ],
        ),
        .target(
            name: "FeatureSettings",
            dependencies: [
                "GitHubFinderDesignSystem",
            ],
            path: "Sources/FeatureSettings",
            resources: [.process("Resources")],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ],
        ),
        .target(
            name: "FeatureTutorial",
            dependencies: [
                "GitHubFinderDesignSystem",
            ],
            path: "Sources/FeatureTutorial",
            resources: [.process("Resources")],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ],
        ),

        // MARK: - Tests
        .testTarget(
            name: "GitHubFinderKitTests",
            dependencies: [
                "GitHubFinderDomain",
                "GitHubFinderData",
                "GitHubFinderDesignSystem",
                "FeatureSearch",
                "FeatureFavorite",
            ],
            path: "Tests/GitHubFinderKitTests",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ],
        ),
    ]
)
