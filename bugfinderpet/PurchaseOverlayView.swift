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
            
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 20) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)
                        .onLongPressGesture(minimumDuration: 2.0) {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                onDebugTrigger?()
                            }
                        }
                    
                    Text("Protect Your Pet")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    if trialManager.isTrialExpired {
                        Text("Continue protecting your pet's health")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 8) {
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
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "camera.fill", title: "Unlimited Detection", description: "Find fleas, ticks & insects")
                    FeatureRow(icon: "wand.and.stars", title: "Advanced Filters", description: "Better visual detection")
                    FeatureRow(icon: "infinity", title: "Lifetime Access", description: "One-time purchase forever")
                }
                .padding(.horizontal, 24)
                
                // Purchase button
                VStack(spacing: 16) {
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
                            
                            Text("Protect Forever")
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Text(purchaseManager.getFormattedPrice())
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.yellow, Color.orange]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(18)
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
                .padding(.horizontal, 24)
                
                // Error message
                if let errorMessage = purchaseManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
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
            .padding(32)
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
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.yellow)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PurchaseOverlayView()
}