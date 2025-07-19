import Foundation
import SwiftUI
import UIKit

@MainActor
class TrialManager: ObservableObject {
    static let shared = TrialManager()
    
    @Published var totalUsageTime: TimeInterval = 0
    @Published var currentSessionTime: TimeInterval = 0
    @Published var isTrialExpired: Bool = false
    @Published var timeRemaining: TimeInterval = 0
    @Published var isOnPausingPage: Bool = false // Track if user is on purchase/notification page
    
    private let trialDuration: TimeInterval = 5 * 60 // 5 minutes in seconds
    private let usageKey = "total_usage_time"
    private let firstLaunchKey = "first_launch_date"
    
    private var sessionStartTime: Date?
    private var timer: Timer?
    
    // Non-isolated copies for deinit access
    private var backupTotalUsageTime: TimeInterval = 0
    private var backupSessionStartTime: Date?
    
    init() {
        loadUsageData()
        updateTrialStatus()
        setupAppLifecycleObservers()
    }
    
    /// Load saved usage data from UserDefaults
    private func loadUsageData() {
        totalUsageTime = UserDefaults.standard.double(forKey: usageKey)
        backupTotalUsageTime = totalUsageTime // Keep non-isolated copy
        
        // Set first launch date if not already set
        if UserDefaults.standard.object(forKey: firstLaunchKey) == nil {
            UserDefaults.standard.set(Date(), forKey: firstLaunchKey)
        }
    }
    
    /// Update trial status and remaining time
    private func updateTrialStatus() {
        timeRemaining = max(0, trialDuration - totalUsageTime)
        isTrialExpired = totalUsageTime >= trialDuration
    }
    
    /// Setup app lifecycle observers
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.endSession()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.endSession()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Only restart if we're not purchased, trial hasn't expired, and not on a pausing page
                guard let self = self, 
                      !InAppPurchaseManager.shared.isPurchased, 
                      self.canUseApp(),
                      !self.isOnPausingPage else { return }
                self.startSession()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveCurrentSession()
            }
        }
    }
    
    /// Save current session progress without ending the session
    private func saveCurrentSession() {
        guard let startTime = sessionStartTime else { return }
        
        let sessionDuration = Date().timeIntervalSince(startTime)
        let updatedTotalTime = totalUsageTime + sessionDuration
        
        // Save to UserDefaults
        UserDefaults.standard.set(updatedTotalTime, forKey: usageKey)
        
        print("💾 Saved trial progress: \(Int(updatedTotalTime)) seconds")
    }
    
    /// Start tracking usage time
    func startSession() {
        guard !InAppPurchaseManager.shared.isPurchased else { return }
        guard !isTrialExpired else { return }
        
        // Reload usage data to get latest saved state
        loadUsageData()
        updateTrialStatus()
        
        // Check again if trial expired after loading
        guard !isTrialExpired else { return }
        
        sessionStartTime = Date()
        backupSessionStartTime = sessionStartTime // Keep non-isolated copy
        currentSessionTime = 0
        
        print("▶️ Session started. Previous usage: \(Int(totalUsageTime)) seconds")
        
        // Start timer to update current session time every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSessionTime()
            }
        }
    }
    
    /// Stop tracking usage time
    func endSession() {
        timer?.invalidate()
        timer = nil
        
        guard let startTime = sessionStartTime else { return }
        
        let sessionDuration = Date().timeIntervalSince(startTime)
        totalUsageTime += sessionDuration
        backupTotalUsageTime = totalUsageTime // Update non-isolated copy
        currentSessionTime = 0
        sessionStartTime = nil
        backupSessionStartTime = nil // Update non-isolated copy
        
        // Save to UserDefaults
        UserDefaults.standard.set(totalUsageTime, forKey: usageKey)
        
        updateTrialStatus()
        
        print("⏹️ Session ended. Total usage: \(Int(totalUsageTime)) seconds")
    }
    
    /// Update current session time
    private func updateSessionTime() {
        guard let startTime = sessionStartTime else { return }
        
        currentSessionTime = Date().timeIntervalSince(startTime)
        let totalCurrentUsage = totalUsageTime + currentSessionTime
        
        timeRemaining = max(0, trialDuration - totalCurrentUsage)
        
        // Check if trial expired during this session
        if totalCurrentUsage >= trialDuration && !isTrialExpired {
            isTrialExpired = true
            endSession()
        }
    }
    
    /// Get formatted time remaining string
    func getFormattedTimeRemaining() -> String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Get formatted total usage time string
    func getFormattedTotalUsage() -> String {
        let minutes = Int(totalUsageTime) / 60
        let seconds = Int(totalUsageTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Check if user can use the app (either purchased or trial not expired)
    func canUseApp() -> Bool {
        return InAppPurchaseManager.shared.isPurchased || !isTrialExpired
    }
    
    /// Set whether user is on a page that should pause the timer
    func setIsOnPausingPage(_ isPausing: Bool) {
        isOnPausingPage = isPausing
    }
    
    /// Reset trial (for testing purposes - remove in production)
    func resetTrial() {
        UserDefaults.standard.removeObject(forKey: usageKey)
        UserDefaults.standard.removeObject(forKey: firstLaunchKey)
        UserDefaults.standard.removeObject(forKey: "lifetime_purchased")
        
        totalUsageTime = 0
        currentSessionTime = 0
        isTrialExpired = false
        isOnPausingPage = false
        
        InAppPurchaseManager.shared.isPurchased = false
        
        updateTrialStatus()
    }
    
    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        
        // Save any current session before deallocation using non-isolated copies
        if let startTime = backupSessionStartTime {
            let sessionDuration = Date().timeIntervalSince(startTime)
            let updatedTotalTime = backupTotalUsageTime + sessionDuration
            
            // Direct UserDefaults save since we can't call main actor methods in deinit
            UserDefaults.standard.set(updatedTotalTime, forKey: usageKey)
            print("💾 Saved trial progress in deinit: \(Int(updatedTotalTime)) seconds")
        }
    }
}