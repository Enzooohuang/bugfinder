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
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Navigation separator
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1)
                            .edgesIgnoringSafeArea(.horizontal)
                        
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
                                    .onChange(of: notificationManager.isNotificationsEnabled) { _, enabled in
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
                                                    },
                                                    onUpdate: { updatedTime in
                                                        notificationManager.updateNotificationTime(at: index, newTime: updatedTime)
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
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
    let onUpdate: (NotificationTime) -> Void
    
    @State private var isExpanded = false
    @State private var editingTime = Date()
    @State private var selectedWeekdays: Set<Int> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(time.displayString)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(time.weekdaysString)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .font(.caption)
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onDelete()
                        }
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.title3)
                    }
                }
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }
            
            // Expanded content
            if isExpanded {
                VStack(spacing: 16) {
                    Divider()
                        .background(Color.white.opacity(0.2))
                    
                    // Time picker
                    VStack(spacing: 8) {
                        Text("Time")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        DatePicker(
                            "Time",
                            selection: $editingTime,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(CompactDatePickerStyle())
                        .labelsHidden()
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    
                    // Day selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Days of the week")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                            ForEach(1...7, id: \.self) { weekday in
                                WeekdayToggle(
                                    weekday: weekday,
                                    isSelected: selectedWeekdays.contains(weekday)
                                ) {
                                    if selectedWeekdays.contains(weekday) {
                                        selectedWeekdays.remove(weekday)
                                    } else {
                                        selectedWeekdays.insert(weekday)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Save button
                    Button(action: {
                        let calendar = Calendar.current
                        let hour = calendar.component(.hour, from: editingTime)
                        let minute = calendar.component(.minute, from: editingTime)
                        
                        let updatedTime = NotificationTime(
                            hour: hour,
                            minute: minute,
                            weekdays: selectedWeekdays.isEmpty ? Set(1...7) : selectedWeekdays
                        )
                        
                        onUpdate(updatedTime)
                        
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded = false
                        }
                    }) {
                        Text("Save Changes")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.yellow)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selectedWeekdays.isEmpty)
                    .opacity(selectedWeekdays.isEmpty ? 0.5 : 1.0)
                }
                .padding()
                .clipped()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            // Initialize editing state with current values
            editingTime = Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
            selectedWeekdays = time.weekdays
        }
        .onChange(of: time.id) { _, _ in
            // Update editing state when time data changes
            editingTime = Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
            selectedWeekdays = time.weekdays
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                // Reset editing state when expanding
                editingTime = Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
                selectedWeekdays = time.weekdays
            }
        }
    }
}

struct WeekdayToggle: View {
    let weekday: Int
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            Text(NotificationTime.shortWeekdayName(for: weekday))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .black : .gray)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.yellow : Color.white.opacity(0.1))
                )
        }
        .buttonStyle(PlainButtonStyle())
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