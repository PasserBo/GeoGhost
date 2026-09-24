import PhotosUI
import SwiftData
import SwiftUI

/// Full-screen capture flow: camera → segmentation editor → save.
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @State private var model = CaptureFlowModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var isCapturing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.stage {
            case .camera:
                cameraStage
            case .analyzing:
                analyzingStage
            case .editing:
                SegmentationEditorView(model: model)
            case .manualCrop:
                if let image = model.fullImage {
                    ManualCropView(image: image, canGoBack: model.analysis != nil) { rect in
                        model.finishManualCrop(normalizedRect: rect)
                    } onBack: {
                        model.backToAutomatic()
                    } onCancel: {
                        model.reset()
                    }
                }
            case .failed(let message):
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Something went wrong", message: LocalizedStringResource(stringLiteral: message),
                               action: (label: "Try again", run: { model.reset() }))
                    .foregroundStyle(.white)
            }
        }
        .statusBarHidden(model.stage == .camera)
        .sheet(isPresented: Bindable(model).showSaveSheet) {
            if let cutout = model.cutout {
                SaveArtworkSheet(model: model, cutout: cutout) {
                    dismiss()
                }
                .interactiveDismissDisabled()
            }
        }
        .onAppear { services.location.start() }
        .onDisappear { services.location.stop(); services.camera.stop() }
        .onChange(of: model.stage) { _, new in
            if new == .camera { Task { await services.camera.start() } } else { services.camera.stop() }
        }
        .task { await services.camera.start() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                defer { pickerItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.receiveImportedPhoto(data)
                } else {
                    errorMessage = String(localized: "That photo could not be loaded.")
                }
            }
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Camera

    @ViewBuilder private var cameraStage: some View {
        let camera = services.camera
        ZStack {
            switch camera.state {
            case .running, .configuring, .idle:
                CameraPreviewView(session: camera.session) { devicePoint in camera.focus(atDevicePoint: devicePoint) }
                    .ignoresSafeArea()
                    .gesture(MagnifyGesture().onChanged { v in camera.setZoom(v.magnification * camera.zoomFactor) })
                if camera.state != .running {
                    ProgressView().tint(.white)
                }
            case .denied:
                cameraUnavailable(title: "Camera access is off", message: "Allow camera access in Settings, or import a photo from your library.", showsSettings: true)
            case .unavailable(let reason):
                cameraUnavailable(title: "Camera unavailable", message: LocalizedStringResource(stringLiteral: reason), showsSettings: false)
            }

            VStack {
                topBar
                Spacer()
                locationPill
                bottomBar
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            Spacer()
            if services.camera.isFlashAvailable {
                Button {
                    services.camera.flashMode = services.camera.flashMode == .off ? .auto : .off
                } label: {
                    Image(systemName: services.camera.flashMode == .off ? "bolt.slash" : "bolt.badge.automatic")
                        .font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var locationPill: some View {
        let loc = services.location
        return Group {
            if loc.isDenied {
                Label("Location off — pieces will be saved without a place", systemImage: "location.slash")
            } else if let fix = loc.usableFix {
                Label("±\(Int(fix.horizontalAccuracy)) m", systemImage: "location.fill")
            } else {
                Label("Finding your location…", systemImage: "location")
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
        .foregroundStyle(.white)
        .padding(.bottom, 12)
    }

    private var bottomBar: some View {
        HStack {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Import from library")
            Spacer()
            Button { Task { await shutter() } } label: {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 82, height: 82)
                    Circle().fill(.white).frame(width: 68, height: 68).scaleEffect(isCapturing ? 0.85 : 1)
                }
            }
            .disabled(!services.camera.isRunning || isCapturing)
            .accessibilityLabel("Take photo")
            Spacer()
            Color.clear.frame(width: 56, height: 56)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func cameraUnavailable(title: LocalizedStringResource, message: LocalizedStringResource, showsSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.slash").font(.system(size: 40)).foregroundStyle(.white.opacity(0.7))
            Text(title).font(.display(20)).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            if showsSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url).fontWeight(.semibold)
            }
        }
        .padding(32)
    }

    private func shutter() async {
        isCapturing = true
        defer { isCapturing = false }
        let sensor = services.location.metadataSnapshot()
        do {
            let data = try await services.camera.capturePhoto(metadata: sensor)
            model.receiveCameraPhoto(data, sensor: sensor)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var analyzingStage: some View {
        ZStack {
            if let data = model.originalData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFit().ignoresSafeArea().blur(radius: 6).opacity(0.6)
            }
            VStack(spacing: 12) {
                ProgressView().tint(.white).controlSize(.large)
                Text("Finding the piece…").font(.headline).foregroundStyle(.white)
            }
        }
    }
}
