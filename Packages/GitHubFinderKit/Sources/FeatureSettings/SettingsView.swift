/*
 Abstract:
 アプリの設定画面。法的情報とバージョン情報を表示。
 */

import SwiftUI
import GitHubFinderDesignSystem

public struct SettingsView: View {
    @State private var safariDestination: SafariDestination?

    private let privacyPolicyURL = URL(string: "https://www.apple.com/legal/privacy/")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/")!

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section(LocalizedStringResource("法的情報", bundle: #bundle)) {
                    Button {
                        safariDestination = SafariDestination(url: privacyPolicyURL)
                    } label: {
                        Label(LocalizedStringResource("プライバシーポリシー", bundle: #bundle), systemImage: "hand.raised")
                    }

                    Button {
                        safariDestination = SafariDestination(url: termsURL)
                    } label: {
                        Label(LocalizedStringResource("利用規約", bundle: #bundle), systemImage: "doc.text")
                    }
                }

                Section(LocalizedStringResource("アプリ情報", bundle: #bundle)) {
                    HStack {
                        Text("バージョン", bundle: #bundle)
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(Color.Content.secondary)
                    }
                }
            }
            .navigationTitle(LocalizedStringResource("設定", bundle: #bundle))
            .sheet(item: $safariDestination) { destination in
                SafariView(url: destination.url)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
