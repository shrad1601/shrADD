import SwiftUI

struct RootTabView: View {
    @StateObject private var viewModel = TransactionListViewModel()
    @AppStorage("appearanceSetting") private var appearanceSetting: String = "system"
    @AppStorage("accentColorHex") private var accentColorHex: String = "93389F"

    private var preferredScheme: ColorScheme? {
        switch appearanceSetting {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    init() {
        UITabBar.appearance().unselectedItemTintColor = .init(Palette.mutedText)
    }

    var body: some View {
        TabView {
            TransactionListView(viewModel: viewModel)
                .tabItem { Label("Transactions", systemImage: "list.bullet") }

            CategoryBreakdownView(viewModel: viewModel)
                .tabItem { Label("Categories", systemImage: "chart.pie") }

            IncomeListView(viewModel: viewModel)
                .tabItem { Label("Income", systemImage: "arrow.down.circle") }

            CompareView(viewModel: viewModel)
                .tabItem { Label("Compare", systemImage: "arrow.left.arrow.right.circle") }
        }
        .tint(Color(hex: accentColorHex))
        .preferredColorScheme(preferredScheme)
    }
}

#Preview {
    RootTabView()
}
