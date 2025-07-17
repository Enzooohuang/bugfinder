import SwiftUI

enum FilterType: String, CaseIterable {
    case normal = "Normal"
    case general = "General"
    case edge = "Edge"
    case light = "Light"
    case dark = "Dark"
    case brown = "Brown"
    case golden = "Gold"
    case gray = "Gray"
}

struct ContentView: View {
    @StateObject private var permissionManager = CameraPermissionManager()
    @State private var selectedFilter: FilterType = .general // Default filter
    @State private var zoomFactor: CGFloat = 2.0 // Default zoom
    @State private var isFlashlightOn: Bool = false
    @State private var useFrontCamera: Bool = false
    @State private var isFrozen: Bool = false
    @State private var isSwitchingCamera: Bool = false
    @State private var showingNotificationSettings: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if permissionManager.isAuthorized {
                CameraContainerView(selectedFilter: $selectedFilter, zoomFactor: $zoomFactor, isFlashlightOn: $isFlashlightOn, useFrontCamera: $useFrontCamera, isFrozen: $isFrozen, isSwitchingCamera: $isSwitchingCamera)
                    .edgesIgnoringSafeArea(.all)
                
                // Notification Settings Button - Top Right Corner
                VStack {
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            showingNotificationSettings = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 44, height: 44)
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "bell")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.top, 30)
                        .padding(.trailing, 20)
                    }
                    
                    Spacer()
                }

                VStack(spacing: 12) {
                    // Zoom selector (only show for back camera)
                    if !useFrontCamera {
                        HStack(spacing: 16) {
                            ForEach([1.0, 2.0], id: \.self) { zoom in
                                ZoomOptionView(
                                    zoom: zoom,
                                    isSelected: zoomFactor == zoom,
                                    isDisabled: isFrozen || isSwitchingCamera
                                ) {
                                    if !isFrozen && !isSwitchingCamera {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            zoomFactor = zoom
                                        }
                                    }
                                }
                            }
                        }
                        .allowsHitTesting(true)
                        .contentShape(Rectangle())
                        .transition(.opacity)
                        
                        // Add a little vertical space between zoom and filter selector
                        Spacer().frame(height: 2)
                    }
                    
                    // Filter selector UI
                    VStack(spacing: 0) {
                        VStack(spacing: 16) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(FilterType.allCases, id: \.self) { filter in
                                        FilterOptionView(
                                            filter: filter,
                                            isSelected: filter == selectedFilter,
                                            isDisabled: isFrozen || isSwitchingCamera
                                        ) {
                                            if !isFrozen && !isSwitchingCamera {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    selectedFilter = filter
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 20)
                                .padding(.horizontal, 20)
                            }
                            
                            // Bottom control buttons inside filter block
                            HStack {
                                // Camera flip button (left of center)
                                Button(action: {
                                    if !isFrozen && !isSwitchingCamera {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            useFrontCamera.toggle()
                                        }
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill((isFrozen || isSwitchingCamera) ? Color.gray.opacity(0.1) : Color.white.opacity(0.2))
                                            .frame(width: 44, height: 44)
                                        Circle()
                                            .stroke((isFrozen || isSwitchingCamera) ? Color.gray.opacity(0.3) : Color.white.opacity(0.5), lineWidth: 2)
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor((isFrozen || isSwitchingCamera) ? Color.gray.opacity(0.5) : .white)
                                    }
                                }
                                .disabled(isFrozen || isSwitchingCamera)
                                .scaleEffect((!isFrozen && !isSwitchingCamera && useFrontCamera) ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: useFrontCamera)
                                
                                Spacer()
                                
                                // Freeze button (center)
                                Button(action: {
                                    if !isSwitchingCamera {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            isFrozen.toggle()
                                        }
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(isSwitchingCamera ? Color.gray.opacity(0.1) : 
                                                  (isFrozen ? Color.yellow.opacity(0.3) : Color.white.opacity(0.2)))
                                            .frame(width: 60, height: 60)
                                        Circle()
                                            .stroke(isSwitchingCamera ? Color.gray.opacity(0.3) : 
                                                   (isFrozen ? Color.yellow : Color.white.opacity(0.5)), lineWidth: 2)
                                            .frame(width: 60, height: 60)
                                        Image(systemName: isFrozen ? "play.fill" : "pause.fill")
                                            .font(.system(size: 24, weight: .medium))
                                            .foregroundColor(isSwitchingCamera ? Color.gray.opacity(0.5) : 
                                                           (isFrozen ? .yellow : .white))
                                    }
                                }
                                .disabled(isSwitchingCamera)
                                .scaleEffect((!isSwitchingCamera && isFrozen) ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFrozen)
                                
                                Spacer()
                                
                                // Flashlight button (right of center)
                                Button(action: {
                                    if !useFrontCamera && !isFrozen && !isSwitchingCamera {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            isFlashlightOn.toggle()
                                        }
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill((useFrontCamera || isFrozen || isSwitchingCamera) ? Color.gray.opacity(0.1) : 
                                                  (isFlashlightOn ? Color.yellow.opacity(0.3) : Color.white.opacity(0.2)))
                                            .frame(width: 44, height: 44)
                                        Circle()
                                            .stroke((useFrontCamera || isFrozen || isSwitchingCamera) ? Color.gray.opacity(0.3) : 
                                                   (isFlashlightOn ? Color.yellow : Color.white.opacity(0.5)), lineWidth: 2)
                                            .frame(width: 44, height: 44)
                                        Image(systemName: isFlashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor((useFrontCamera || isFrozen || isSwitchingCamera) ? Color.gray.opacity(0.5) : 
                                                           (isFlashlightOn ? .yellow : .white))
                                    }
                                }
                                .disabled(useFrontCamera || isFrozen || isSwitchingCamera)
                                .scaleEffect((!useFrontCamera && !isFrozen && !isSwitchingCamera && isFlashlightOn) ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFlashlightOn)
                            }
                            .padding(.horizontal, 20)
                        }
                        .allowsHitTesting(true)
                        .contentShape(Rectangle())
                        .padding(.bottom, 20)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.6),
                                        Color.black.opacity(0.4)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
                .padding(.bottom, 0) // Remove extra bottom padding from outer VStack
            } else {
                Text("Please grant camera permission to use this feature.")
                    .padding()
            }
        }
        .onAppear {
            permissionManager.checkPermission()
        }
        .alert(isPresented: $permissionManager.showSettingsAlert) {
            Alert(
                title: Text("Camera Permission Required"),
                message: Text("Please go to system settings to enable camera access."),
                primaryButton: .default(Text("Open Settings"), action: {
                    permissionManager.openSettings()
                }),
                secondaryButton: .cancel(Text("Cancel"))
            )
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NotificationSettingsView()
        }
    }
}

// Zoom option preview view
struct ZoomOptionView: View {
    let zoom: CGFloat
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: isDisabled ? 
                            [Color.gray.opacity(0.1), Color.gray.opacity(0.05)] :
                            (isSelected ? 
                                [Color.yellow.opacity(0.3), Color.cyan.opacity(0.2)] :
                                [Color.white.opacity(0.1), Color.white.opacity(0.05)]
                            )
                        ),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)   
            
            Circle()
                .stroke(
                    isDisabled ? Color.gray.opacity(0.3) :
                    (isSelected ? Color.yellow : Color.white.opacity(0.3)),
                    lineWidth: isSelected ? 2 : 1
                )
                .frame(width: 32, height: 32)
            
            // Zoom text
            Text("\(Int(zoom))x")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(isDisabled ? Color.gray.opacity(0.5) :
                               (isSelected ? .yellow : .white.opacity(0.9)))
        }
        .scaleEffect((!isDisabled && isSelected) ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onTapGesture {
            onTap()
        }
        .allowsHitTesting(true)
        .contentShape(Circle())
    }
}

// Filter option preview view
struct FilterOptionView: View {
    let filter: FilterType
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // Filter preview circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: isDisabled ?
                                [Color.gray.opacity(0.1), Color.gray.opacity(0.05)] :
                                (isSelected ? 
                                    [Color.yellow.opacity(0.3), Color.orange.opacity(0.2)] :
                                    [Color.white.opacity(0.1), Color.white.opacity(0.05)]
                                )
                            ),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Circle()
                    .stroke(
                        isDisabled ? Color.gray.opacity(0.3) :
                        (isSelected ? Color.yellow : Color.white.opacity(0.3)),
                        lineWidth: isSelected ? 2 : 1
                    )
                    .frame(width: 50, height: 50)
                
                // Filter preview image
                Image(filterImageName(for: filter))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .opacity(isDisabled ? 0.5 : 1.0)
            }
                    .scaleEffect((!isDisabled && isSelected) ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        
        // Filter name
        Text(filter.rawValue)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(isDisabled ? Color.gray.opacity(0.5) :
                           (isSelected ? .yellow : .white.opacity(0.9)))
            .lineLimit(1)
    }
    .onTapGesture {
        onTap()
    }
    .allowsHitTesting(true)
    .contentShape(Rectangle())
    }
    
    // Get the corresponding image name for each filter type
    private func filterImageName(for filter: FilterType) -> String {
        switch filter {
        case .normal:
            return "normal"
        case .general:
            return "inverted"
        case .light:
            return "light"
        case .dark:
            return "dark"
        case .brown:
            return "brown"
        case .golden:
            return "gold"
        case .gray:
            return "gray"
        case .edge:
            return "edge"
        }
    }
}
