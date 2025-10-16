import SwiftUI

struct UIViewWrapper<V: UIView>: UIViewRepresentable {
    
    let view: UIView
    
    func makeUIView(context: Context) -> some UIView { view }
    func updateUIView(_ uiView: UIViewType, context: Context) { }
}

@main
struct PointCloudLIDARApp: App {
    
    @StateObject var arManager = ARManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView(arManager: arManager)
        }
    }
}

struct ContentView: View {
    @ObservedObject var arManager: ARManager
    @State private var showingPointCloudViewer = false
    @State private var pointCount = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            UIViewWrapper(view: arManager.sceneView).ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Point count display
                HStack {
                    Spacer()
                    Text("Points: \(pointCount, format: .number)")
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.7))
                        .cornerRadius(15)
                    Spacer()
                }
                
                HStack(spacing: 30) {
                    // Clear button
                    Button {
                        Task {
                            await arManager.pointCloudProvider.clear()
                            await updatePointCount()
                        }
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .foregroundStyle(.red, .white)
                    }
                    
                    // Capture/Stop button
                    Button {
                        arManager.isCapturing.toggle()
                    } label: {
                        Image(systemName: arManager.isCapturing ?
                                          "stop.circle.fill" :
                                          "play.circle.fill")
                            .foregroundStyle(arManager.isCapturing ? .red : .green, .white)
                    }
                    
                    // View point cloud button
                    Button {
                        showingPointCloudViewer = true
                    } label: {
                        Image(systemName: "view.3d")
                            .foregroundStyle(.purple, .white)
                    }
                    
                    // Export button
                    ShareLink(item: PLYFile(pointCloudProvider: arManager.pointCloudProvider),
                                            preview: SharePreview("exported.ply")) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .foregroundStyle(.blue, .white)
                    }
                }
                .font(.system(size: 50))
            }
            .padding(25)
        }
        .fullScreenCover(isPresented: $showingPointCloudViewer) {
            PointCloudViewer(arManager: arManager)
        }
        .task {
            // Update point count periodically
            while !Task.isCancelled {
                await updatePointCount()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    
    private func updatePointCount() async {
        let count = await arManager.pointCloudProvider.vertices.count
        await MainActor.run {
            self.pointCount = count
        }
    }
}
