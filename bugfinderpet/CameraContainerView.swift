import SwiftUI
import MetalKit

struct CameraContainerView: UIViewRepresentable {
    @Binding var selectedFilter: FilterType
    @Binding var zoomFactor: CGFloat
    @Binding var isFlashlightOn: Bool
    @Binding var useFrontCamera: Bool
    @Binding var isFrozen: Bool
    @Binding var isSwitchingCamera: Bool

    class Coordinator {
        var processor: NativeCameraProcessor?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView(frame: .zero)
        let processor = NativeCameraProcessor(selectedFilter: selectedFilter)
        processor.zoomFactor = zoomFactor
        processor.isFlashlightOn = isFlashlightOn
        processor.useFrontCamera = useFrontCamera
        processor.isFrozen = isFrozen
        processor.onSwitchingStateChanged = { switching in
            DispatchQueue.main.async {
                self.isSwitchingCamera = switching
            }
        }
        context.coordinator.processor = processor

        let metalView = processor.metalView
        metalView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: containerView.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            metalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.processor?.selectedFilter = selectedFilter
        context.coordinator.processor?.zoomFactor = zoomFactor
        context.coordinator.processor?.isFlashlightOn = isFlashlightOn
        context.coordinator.processor?.useFrontCamera = useFrontCamera
        context.coordinator.processor?.isFrozen = isFrozen
    }
}
