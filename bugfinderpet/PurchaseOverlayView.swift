import SwiftUI

struct PurchaseOverlayView: View {
    @StateObject private var purchaseManager = InAppPurchaseManager.shared
    @StateObject private var trialManager = TrialManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var showingFeatures = false
    
    let onDebugTrigger: (() -> Void)?
    
    init(onDebugTrigger: (() -> Void)? = nil) {
        self.onDebugTrigger = onDebugTrigger
    }
    
    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)
                        .onLongPressGesture(minimumDuration: 2.0) {
                            onDebugTrigger?()
                        }
                    
                    Text("Unlock Full Access")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    if trialManager.isTrialExpired {
                        Text("Your 5-minute trial has ended")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    } else {
                        VStack(spacing: 4) {
                            Text("Trial time remaining:")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Text(trialManager.getFormattedTimeRemaining())
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.yellow)
                        }
                    }
                }
                
                // Features list
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "camera.fill", title: "Unlimited Camera Access", description: "Use all filters without time limits")
                    FeatureRow(icon: "wand.and.stars", title: "All Premium Filters", description: "Access to all current and future filters")
                    FeatureRow(icon: "infinity", title: "Lifetime Access", description: "One-time purchase, no subscriptions")
                }
                .padding(.horizontal)
                
                // Purchase button
                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await purchaseManager.purchaseLifetimeAccess()
                        }
                    }) {
                        HStack {
                            if purchaseManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "crown.fill")
                                    .font(.title3)
                            }
                            
                            Text("Get Lifetime Access")
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Text(purchaseManager.getFormattedPrice())
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.yellow, Color.orange]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }
                    .disabled(purchaseManager.isLoading)
                    
                    // Restore purchases button
                    Button(action: {
                        Task {
                            await purchaseManager.restorePurchases()
                        }
                    }) {
                        Text("Restore Purchases")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .disabled(purchaseManager.isLoading)
                }
                .padding(.horizontal)
                
                // Error message
                if let errorMessage = purchaseManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Close button (only if trial not expired)
                if !trialManager.isTrialExpired {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Continue Trial")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
        }
        .onAppear {
            Task {
                await purchaseManager.loadProducts()
            }
        }
        .onChange(of: purchaseManager.isPurchased) { _, isPurchased in
            if isPurchased {
                dismiss()
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.yellow)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
}

#Preview {
    PurchaseOverlayView()
}