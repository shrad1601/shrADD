import SwiftUI

private enum RootTab: Hashable {
    case transactions, categories, income, compare
}

struct RootTabView: View {
    @StateObject private var viewModel = TransactionListViewModel()
    @AppStorage("appearanceSetting") private var appearanceSetting: String = "system"
    @AppStorage("accentColorHex") private var accentColorHex: String = "93389F"
    // Explicit, app-owned selection instead of letting TabView track it
    // internally — without this, presenting a system UI over a tab (Face ID's
    // prompt, in particular) could silently bounce the selection back to the
    // first tab once the prompt dismissed.
    @State private var selectedTab: RootTab = .transactions

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
        TabView(selection: $selectedTab) {
            TransactionListView(viewModel: viewModel)
                .tabItem { Label("Transactions", systemImage: "list.bullet") }
                .tag(RootTab.transactions)

            CategoryBreakdownView(viewModel: viewModel)
                .tabItem { Label("Categories", systemImage: "chart.pie") }
                .tag(RootTab.categories)

            IncomeListView(viewModel: viewModel)
                .tabItem { Label("Income", systemImage: "arrow.down.circle") }
                .tag(RootTab.income)

            CompareView(viewModel: viewModel)
                .tabItem { Label("Compare", systemImage: "arrow.left.arrow.right.circle") }
                .tag(RootTab.compare)
        }
        .tint(Color(hex: accentColorHex))
        .preferredColorScheme(preferredScheme)
    }
}

#Preview {
    RootTabView()
}
