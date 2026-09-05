import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TransactionListViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearanceSetting") private var appearanceSetting: String = "system"
    @AppStorage("accentColorHex") private var accentColorHex: String = "93389F"
    @State private var overallBudgetText: String = ""

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: accentColorHex) },
            set: { accentColorHex = $0.toHex() }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceSetting) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextField("Amount", text: $overallBudgetText)
                        .keyboardType(.decimalPad)
                    Button("Save") {
                        if let value = Double(overallBudgetText) {
                            Task { await viewModel.setOverallBudget(value) }
                        }
                    }
                    .disabled(Double(overallBudgetText) == nil)
                } header: {
                    Text("Overall Monthly Budget")
                } footer: {
                    Text("Get a Discord alert at 80% and 100% of this amount, on top of your per-category budgets.")
                }
                Section("Accent Color") {
                    ColorPicker("App color", selection: accentColorBinding, supportsOpacity: false)
                    Button("Reset to default purple") {
                        accentColorHex = "93389F"
                    }
                }
                Section {
                    NavigationLink("Auto-Categorization Rules") {
                        MerchantRulesView(viewModel: viewModel)
                    }
                } footer: {
                    Text("Automatically categorize transactions from certain people or merchants — e.g. anything from \"Tanvi\" always goes under Friends.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if let budget = viewModel.overallBudget {
                    overallBudgetText = String(format: "%.2f", budget)
                }
            }
        }
    }
}

#Preview {
    SettingsView(viewModel: TransactionListViewModel(repository: MockTransactionRepository(), budgetRepository: MockBudgetRepository(), categoryRepository: MockCategoryRepository(), merchantRuleRepository: MockMerchantRuleRepository()))
}
