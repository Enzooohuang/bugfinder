import SwiftUI
import UserNotifications

struct NotificationTime {
    let hour: Int
    let minute: Int
    
    var displayString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
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
        guard let data = UserDefaults.standard.data(forKey: "notificationTimes"),
              let timeData = try? JSONDecoder().decode([[String: Int]].self, from: data) else {
            return []
        }
        
        return timeData.compactMap { dict in
            guard let hour = dict["hour"], let minute = dict["minute"] else { return nil }
            return NotificationTime(hour: hour, minute: minute)
        }
    }
    
    private func saveNotificationTimes() {
        let timeData = notificationTimes.map { ["hour": $0.hour, "minute": $0.minute] }
        if let data = try? JSONEncoder().encode(timeData) {
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
        
        for (index, time) in notificationTimes.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Bug Check Reminder"
            content.body = "Time to check for bugs with your pet detective!"
            content.sound = .default
            
            var dateComponents = DateComponents()
            dateComponents.hour = time.hour
            dateComponents.minute = time.minute
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "bugcheck_\(index)", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request)
        }
    }
}