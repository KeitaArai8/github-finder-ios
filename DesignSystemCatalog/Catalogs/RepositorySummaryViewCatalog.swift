/*
 Abstract:
 RepositorySummaryView の表示確認カタログ。
 description・language の有無による見た目の違いを並べる。
 */

import SwiftUI
import GitHubFinderDesignSystem

struct RepositorySummaryViewCatalog: View {
    var body: some View {
        List {
            Section("description・language あり") {
                RepositorySummaryView(
                    fullName: "apple/swift",
                    description: "The Swift Programming Language",
                    starCount: 67_000,
                    language: "C++",
                    ownerAvatarURL: nil
                )
            }
            Section("description なし") {
                RepositorySummaryView(
                    fullName: "owner/no-description",
                    description: nil,
                    starCount: 12,
                    language: "Swift",
                    ownerAvatarURL: nil
                )
            }
            Section("language なし") {
                RepositorySummaryView(
                    fullName: "owner/no-language",
                    description: "language が無いリポジトリ",
                    starCount: 3,
                    language: nil,
                    ownerAvatarURL: nil
                )
            }
        }
        .navigationTitle("RepositorySummaryView")
    }
}

#Preview {
    NavigationStack { RepositorySummaryViewCatalog() }
}
