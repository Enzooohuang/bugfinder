import SwiftUI
import UserNotifications

struct NotificationTime: Codable {
    let id: UUID
    let hour: Int
    let minute: Int
    let weekdays: Set<Int> // 1 = Sunday, 2 = Monday, ..., 7 = Saturday
    
    init(hour: Int, minute: Int, weekdays: Set<Int> = Set(1...7)) {
        self.id = UUID()
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
    }
    
    var displayString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
    
    var weekdaysString: String {
        if weekdays.count == 7 {
            return "Daily"
        } else if weekdays.count == 5 && weekdays.isSubset(of: Set(2...6)) {
            return "Weekdays"
        } else if weekdays.count == 2 && weekdays.isSubset(of: Set([1, 7])) {
            return "Weekends"
        } else {
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let selectedDays = weekdays.sorted().map { dayNames[$0 - 1] }
            return selectedDays.joined(separator: ", ")
        }
    }
    
    static func weekdayName(for weekday: Int) -> String {
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return dayNames[weekday - 1]
    }
    
    static func shortWeekdayName(for weekday: Int) -> String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return dayNames[weekday - 1]
    }
}

class NotificationManager: ObservableObject {
    @Published var isNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isNotificationsEnabled, forKey: "notificationsEnabled")
        }
    }
    
    @Published var notificationTimes: [NotificationTime] {
        didSet {
            saveNotificationTimes()
        }
    }
    
    init() {
        self.isNotificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        self.notificationTimes = NotificationManager.loadNotificationTimes()
        
        if notificationTimes.isEmpty {
            notificationTimes = [
                NotificationTime(hour: 9, minute: 0),
                NotificationTime(hour: 18, minute: 0)
            ]
        }
    }
    
    private static func loadNotificationTimes() -> [NotificationTime] {
        guard let data = UserDefaults.standard.data(forKey: "notificationTimes") else {
            return []
        }
        
        // Try to decode new format first
        if let times = try? JSONDecoder().decode([NotificationTime].self, from: data) {
            return times
        }
        
        // Fallback to old format for migration
        if let timeData = try? JSONDecoder().decode([[String: Int]].self, from: data) {
            return timeData.compactMap { dict in
                guard let hour = dict["hour"], let minute = dict["minute"] else { return nil }
                return NotificationTime(hour: hour, minute: minute, weekdays: Set(1...7))
            }
        }
        
        return []
    }
    
    private func saveNotificationTimes() {
        if let data = try? JSONEncoder().encode(notificationTimes) {
            UserDefaults.standard.set(data, forKey: "notificationTimes")
        }
    }
    
    func addNotificationTime(_ time: NotificationTime) {
        notificationTimes.append(time)
        scheduleNotifications()
    }
    
    func removeNotificationTime(at index: Int) {
        guard index < notificationTimes.count else { return }
        notificationTimes.remove(at: index)
        scheduleNotifications()
    }
    
    func updateNotificationTime(at index: Int, newTime: NotificationTime) {
        guard index < notificationTimes.count else { return }
        notificationTimes[index] = newTime
        scheduleNotifications()
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    self.scheduleNotifications()
                }
            }
        }
    }
    
    private func scheduleNotifications() {
        guard isNotificationsEnabled else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }
        
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        for (timeIndex, time) in notificationTimes.enumerated() {
            for weekday in time.weekdays {
                let content = UNMutableNotificationContent()
                content.title = "Post-Walk Bug Check"
                content.body = "Did you walk your pet recently? Check for fleas and ticks! 🐕"
                content.sound = .default
                
                var dateComponents = DateComponents()
                dateComponents.hour = time.hour
                dateComponents.minute = time.minute
                dateComponents.weekday = weekday
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "bugcheck_\(timeIndex)_\(weekday)", 
                    content: content, 
                    trigger: trigger
                )
                
                UNUserNotificationCenter.current().add(request)
            }
        }
    }
}