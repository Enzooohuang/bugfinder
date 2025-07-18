import SwiftUI

// MARK: - Debug Settings View (Remove in production)
struct DebugSettingsView: View {
    @StateObject private var trialManager = TrialManager.shared
    @StateObject private var purchaseManager = InAppPurchaseManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Trial Information") {
                    HStack {
                        Text("Total Usage Time")
                        Spacer()
                        Text(trialManager.getFormattedTotalUsage())
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Time Remaining")
                        Spacer()
                        Text(trialManager.getFormattedTimeRemaining())
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Trial Expired")
                        Spacer()
                        Text(trialManager.isTrialExpired ? "Yes" : "No")
                            .foregroundColor(trialManager.isTrialExpired ? .red : .green)
                    }
                }
                
                Section("Purchase Information") {
                    HStack {
                        Text("Lifetime Purchased")
                        Spacer()
                        Text(purchaseManager.isPurchased ? "Yes" : "No")
                            .foregroundColor(purchaseManager.isPurchased ? .green : .red)
                    }
                }
                
                Section("Debug Actions") {
                    Button("Reset Trial") {
                        trialManager.resetTrial()
                    }
                    .foregroundColor(.red)
                    
                    Button("Simulate Purchase") {
                        purchaseManager.isPurchased = true
                        UserDefaults.standard.set(true, forKey: "lifetime_purchased")
                    }
                    .foregroundColor(.blue)
                }
                
                Section("Notes") {
                    Text("⚠️ This debug view should be removed in production builds. Use it only for testing the trial and purchase flow.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .navigationTitle("Debug Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DebugSettingsView()
}