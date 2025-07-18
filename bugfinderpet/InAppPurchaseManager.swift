import Foundation
import StoreKit
import SwiftUI

@MainActor
class InAppPurchaseManager: NSObject, ObservableObject {
    static let shared = InAppPurchaseManager()
    
    @Published var isPurchased = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var products: [Product] = []
    
    private let productID = "com.bugfinder.lifetime" // Replace with your actual product ID
    
    override init() {
        super.init()
        checkPurchaseStatus()
    }
    
    /// Check if user has already purchased the lifetime access
    func checkPurchaseStatus() {
        isPurchased = UserDefaults.standard.bool(forKey: "lifetime_purchased")
    }
    
    /// Load available products from App Store
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let products = try await Product.products(for: [productID])
            self.products = products
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("❌ Failed to load products: \(error)")
        }
        
        isLoading = false
    }
    
    /// Purchase the lifetime access
    func purchaseLifetimeAccess() async {
        guard let product = products.first else {
            errorMessage = "Product not available"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // Transaction is verified, grant access
                    await completeTransaction(transaction)
                    isPurchased = true
                    UserDefaults.standard.set(true, forKey: "lifetime_purchased")
                    print("✅ Purchase successful and verified")
                    
                case .unverified(_, let error):
                    errorMessage = "Purchase verification failed: \(error.localizedDescription)"
                    print("❌ Purchase verification failed: \(error)")
                }
                
            case .userCancelled:
                print("ℹ️ User cancelled purchase")
                
            case .pending:
                print("ℹ️ Purchase is pending")
                
            @unknown default:
                errorMessage = "Unknown purchase result"
                print("❌ Unknown purchase result")
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            print("❌ Purchase failed: \(error)")
        }
        
        isLoading = false
    }
    
    /// Restore previous purchases
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await AppStore.sync()
            
            for await result in StoreKit.Transaction.currentEntitlements {
                switch result {
                case .verified(let transaction):
                    if transaction.productID == productID {
                        isPurchased = true
                        UserDefaults.standard.set(true, forKey: "lifetime_purchased")
                        print("✅ Restored purchase for product: \(transaction.productID)")
                    }
                    
                case .unverified(_, let error):
                    print("❌ Unverified transaction during restore: \(error)")
                }
            }
            
            if !isPurchased {
                errorMessage = "No previous purchases found"
            }
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            print("❌ Failed to restore purchases: \(error)")
        }
        
        isLoading = false
    }
    
    /// Complete the transaction
    private func completeTransaction(_ transaction: StoreKit.Transaction) async {
        // Finish the transaction
        await transaction.finish()
    }
    
    func getFormattedPrice() -> String {
        guard let product = products.first else { return "$1.99" }
        return product.displayPrice
    }
}