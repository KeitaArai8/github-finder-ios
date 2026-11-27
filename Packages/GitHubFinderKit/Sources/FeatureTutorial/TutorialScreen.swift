/*
 Abstract:
 初回起動時に表示するチュートリアル専用画面。
 SearchView のレイアウトをモックで再現し、各UIに .coachMarkAnchor を付与する。
 本機能側の実装には一切手を入れず、チュートリアル進行は TutorialScreen 内の
 モック操作（TextField タップ・ハートタップ・タブタップ）から発火させる。
 */

import SwiftUI
import GitHubFinderDesignSystem

public struct TutorialScreen: View {
    @Bindable var coachMarkManager: CoachMarkManager

    @State private var coachMarkFrames: [CoachMarkManager.Step: CGRect] = [:]

    private let mockRepo = MockRepository(
        fullName: "apple/swift",
        description: "The Swift Programming Language",
        starCount: 67_000,
        language: "C++"
    )

    public init(coachMarkManager: CoachMarkManager) {
        self.coachMarkManager = coachMarkManager
    }

    public var body: some View {
        ZStack {
            Color.Background.primary.ignoresSafeArea()

            VStack(spacing: 0) {
                headerTitle
                mockSearchBar
                mockRepositoryRow
                    .padding(.top, Spacing.spacing300)
                Spacer()
                mockTabBar
            }

            if let step = coachMarkManager.currentStep {
                CoachMarkOverlay(
                    step: step,
                    frames: coachMarkFrames,
                    onNext: { coachMarkManager.next() },
                    onSkip: { coachMarkManager.skip() }
                )
            }
        }
        .onPreferenceChange(CoachMarkFramePreferenceKey.self) { frames in
            coachMarkFrames = frames
        }
    }

    // MARK: - Mock UI

    private var headerTitle: some View {
        HStack(spacing: 0) {
            Text("検索", bundle: #bundle)
                .font(.appTitleLarge)
            Spacer()
        }
        .padding(.horizontal, Spacing.spacing200)
        .padding(.top, Spacing.spacing200)
    }

    private var mockSearchBar: some View {
        HStack(spacing: Spacing.spacing100) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("リポジトリを検索", bundle: #bundle)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.spacing150)
        .padding(.vertical, 10)
        .background(Color.Background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, Spacing.spacing200)
        .padding(.top, Spacing.spacing200)
        .coachMarkAnchor(for: .searchBar)
        .contentShape(Rectangle())
        .onTapGesture {
            coachMarkManager.advance(after: .searchBar)
        }
    }

    private var mockRepositoryRow: some View {
        HStack(alignment: .top, spacing: Spacing.spacing150) {
            Color.gray.opacity(0.25)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: Radius.radius100))

            VStack(alignment: .leading, spacing: Spacing.spacing50) {
                Text(mockRepo.fullName)
                    .font(.appTitleSmall)
                Text(mockRepo.description)
                    .font(.appBodyMedium)
                    .foregroundStyle(.secondary)
                HStack(spacing: Spacing.spacing150) {
                    Label("\(mockRepo.starCount)", systemImage: "star.fill")
                        .foregroundStyle(Color.Brand.star)
                    Text(mockRepo.language)
                        .foregroundStyle(.secondary)
                }
                .font(.appLabelMedium)
            }

            Spacer()

            Button {
                coachMarkManager.advance(after: .favoriteButton)
            } label: {
                Image(systemName: "heart")
                    .font(.title3)
                    .foregroundStyle(.gray)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .coachMarkAnchor(for: .favoriteButton)
        }
        .padding(.horizontal, Spacing.spacing200)
    }

    private var mockTabBar: some View {
        // 実機の iOS 26 タブバーと同じ並び: お気に入り・設定が 1 つのカプセル、検索（role: .search）は右端に独立した丸
        GlassEffectContainer(spacing: Spacing.spacing100) {
            HStack(spacing: Spacing.spacing100) {
                HStack(spacing: 0) {
                    tabItem(
                        systemImage: "heart.fill",
                        label: LocalizedStringResource("お気に入り", bundle: #bundle),
                        isSelected: false
                    ) {
                        coachMarkManager.advance(after: .favoriteTab)
                    }
                    .coachMarkAnchor(for: .favoriteTab)

                    tabItem(
                        systemImage: "gearshape",
                        label: LocalizedStringResource("設定", bundle: #bundle),
                        isSelected: false
                    ) {}
                }
                .frame(height: 56)
                // iOS 26 のタブバーは画面下端に浮くガラスのカプセル。material の帯ではなく同じ見た目に揃える
                .glassEffect(.regular, in: .capsule)

                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(Color.Content.accent)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular, in: .circle)
                    .accessibilityLabel(Text("検索", bundle: #bundle))
            }
        }
        .padding(.horizontal, Spacing.spacing200)
        .padding(.bottom, Spacing.spacing100)
    }

    private func tabItem(
        systemImage: String,
        label: LocalizedStringResource,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.appBodyLarge)
                Text(label)
                    .font(.appLabelSmall)
            }
            .foregroundStyle(isSelected ? Color.Content.accent : Color.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mock Data

    private struct MockRepository {
        let fullName: String
        let description: String
        let starCount: Int
        let language: String
    }
}
