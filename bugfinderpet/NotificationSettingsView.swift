import SwiftUI

struct NotificationSettingsView: View {
    @StateObject private var notificationManager = NotificationManager()
    @Environment(\.presentationMode) var presentationMode
    @State private var showingTimePicker = false
    @State private var selectedTime = Date()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 40))
                            .foregroundColor(.yellow)
                        
                        Text("Bug Check Notifications")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Set when you want to be reminded to check for bugs")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Enable/Disable Toggle
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Notifications")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text("Receive daily reminders to check for bugs")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $notificationManager.isNotificationsEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: .yellow))
                                .fixedSize()
                                .onChange(of: notificationManager.isNotificationsEnabled) { enabled in
                                    if enabled {
                                        notificationManager.requestNotificationPermission()
                                    }
                                }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                        )
                        
                        // Notification Times Section
                        if notificationManager.isNotificationsEnabled {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text("Notification Times")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        selectedTime = Date()
                                        showingTimePicker = true
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.yellow)
                                    }
                                }
                                
                                if notificationManager.notificationTimes.isEmpty {
                                    Text("No notification times set")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 20)
                                } else {
                                    LazyVStack(spacing: 8) {
                                        ForEach(notificationManager.notificationTimes.indices, id: \.self) { index in
                                            NotificationTimeRow(
                                                time: notificationManager.notificationTimes[index],
                                                onDelete: {
                                                    notificationManager.removeNotificationTime(at: index)
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.1))
                            )
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.yellow)
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingTimePicker) {
            TimePickerSheet(
                selectedTime: $selectedTime,
                onSave: { time in
                    let calendar = Calendar.current
                    let hour = calendar.component(.hour, from: time)
                    let minute = calendar.component(.minute, from: time)
                    notificationManager.addNotificationTime(NotificationTime(hour: hour, minute: minute))
                }
            )
        }
    }
}

struct NotificationTimeRow: View {
    let time: NotificationTime
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(time.displayString)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Daily reminder")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.title3)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
}

struct TimePickerSheet: View {
    @Binding var selectedTime: Date
    @Environment(\.presentationMode) var presentationMode
    let onSave: (Date) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 30) {
                    Text("Select Notification Time")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    DatePicker(
                        "Time",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(WheelDatePickerStyle())
                    .labelsHidden()
                    .colorScheme(.dark)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onSave(selectedTime)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.yellow)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    NotificationSettingsView()
}