//
//  PointCloudViewer.swift
//  PointCloudLIDAR
//
//  Created by Alex Giger on 10/6/25.
//

import SwiftUI
import SceneKit
internal import ARKit

struct PointCloudViewer: View {
    @ObservedObject var arManager: ARManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var sceneView = SCNView()
    @State private var cameraNode = SCNNode()
    @State private var pointGeometryNode = SCNNode()
    @State private var pointCount = 0
    
    // Camera controls
    @State private var isRotating = false
    @State private var rotationX: Float = -45 // Better downward viewing angle
    @State private var rotationY: Float = 45 // Start with a slight angle to the side
    @State private var zoom: Float = 1.5 // Start slightly zoomed in
    @State private var panOffset = SCNVector3(0, 0, 0)
    
    // Display options
    @State private var pointSize: CGFloat = 4
    @State private var showWireframe = false
    @State private var colorMode: ColorMode = .original
    @State private var showingSettings = false
    
    // Measurement functionality
    @State private var isMeasurementMode = false
    @State private var selectedPoints: [SCNVector3] = []
    @State private var measurementNodes: [SCNNode] = []
    @State private var measuredDistance: Float? = nil
    
    enum ColorMode: String, CaseIterable {
        case original = "Original"
        case depth = "Depth-Based"
        case height = "Height-Based"
        
        var systemImage: String {
            switch self {
            case .original: return "camera.fill"
            case .depth: return "ruler.fill"
            case .height: return "arrow.up.and.down"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // SceneKit View
                SceneKitView(
                    sceneView: sceneView,
                    cameraNode: cameraNode,
                    pointGeometryNode: pointGeometryNode,
                    arManager: arManager,
                    rotationX: $rotationX,
                    rotationY: $rotationY,
                    zoom: $zoom,
                    panOffset: $panOffset,
                    isMeasurementMode: $isMeasurementMode,
                    onPointSelected: handlePointSelection
                )
                .ignoresSafeArea()
                
                // Controls overlay
                VStack {
                    // Top info bar
                    HStack {
                        // Exit button
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.black.opacity(0.7))
                                .cornerRadius(15)
                        }
                        
                        Spacer()
                        
                        Text("Points: \(pointCount, format: .number)")
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.7))
                            .cornerRadius(15)
                        
                        // Measurement info
                        if isMeasurementMode {
                            VStack {
                                Text("Measurement Mode")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                                
                                if selectedPoints.count == 1 {
                                    Text("Select second point")
                                        .font(.caption2)
                                        .foregroundColor(.yellow)
                                } else if let distance = measuredDistance {
                                    Text("Distance: \(formatDistance(distance))")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.7))
                            .cornerRadius(15)
                        }
                        
                        Spacer()
                        
                        // Settings button
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.black.opacity(0.7))
                                .cornerRadius(15)
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Bottom controls
                    VStack(spacing: 15) {
                        // Camera controls
                        HStack(spacing: 20) {
                            // Measurement mode toggle
                            Button(action: toggleMeasurementMode) {
                                Image(systemName: isMeasurementMode ? "ruler.fill" : "ruler")
                                    .font(.title2)
                                    .foregroundColor(isMeasurementMode ? .yellow : .white)
                                    .padding(12)
                                    .background(.black.opacity(0.7))
                                    .cornerRadius(20)
                            }
                            
                            // Reset view button
                            Button(action: resetCamera) {
                                Image(systemName: "viewfinder")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(.black.opacity(0.7))
                                    .cornerRadius(20)
                            }
                            
                            // Color mode selector
                            Button(action: nextColorMode) {
                                HStack(spacing: 8) {
                                    Image(systemName: colorMode.systemImage)
                                    Text(colorMode.rawValue)
                                        .font(.caption)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.7))
                                .cornerRadius(15)
                            }
                            
                            // Auto-rotate toggle
                            Button(action: { isRotating.toggle() }) {
                                Image(systemName: isRotating ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(isRotating ? .orange : .white)
                                    .padding(12)
                                    .background(.black.opacity(0.7))
                                    .cornerRadius(20)
                            }
                            
                            // Clear measurements button (only show in measurement mode)
                            if isMeasurementMode && !selectedPoints.isEmpty {
                                Button(action: clearMeasurements) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                        .padding(12)
                                        .background(.black.opacity(0.7))
                                        .cornerRadius(20)
                                }
                            }
                        }
                        
                        // Zoom slider
                        HStack {
                            Image(systemName: "minus.magnifyingglass")
                                .foregroundColor(.white)
                            
                            Slider(value: $zoom, in: 0.1...5.0, step: 0.1)
                                .tint(.white)
                            
                            Image(systemName: "plus.magnifyingglass")
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.7))
                        .cornerRadius(15)
                        .padding(.horizontal)
                    }
                    .padding(.bottom)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                setupScene()
                updateGeometry()
                updatePointCount()
            }
            .onChange(of: zoom) { updateCameraPosition() }
            .onChange(of: colorMode) { updateGeometry() }
            .onChange(of: pointSize) { updateGeometry() }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    pointSize: $pointSize,
                    showWireframe: $showWireframe,
                    colorMode: $colorMode
                )
            }
        }
    }
    
    private func setupScene() {
        // Create scene
        let scene = SCNScene()
        sceneView.scene = scene
        sceneView.backgroundColor = UIColor.black
        sceneView.allowsCameraControl = false // We'll handle camera controls manually
        
        // Setup camera
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 75 // Wider field of view for better point cloud viewing
        cameraNode.camera?.zNear = 0.01 // Allow closer viewing
        cameraNode.camera?.zFar = 100.0 // Allow further viewing
        scene.rootNode.addChildNode(cameraNode)
        
        // Set initial camera position
        updateCameraPosition()
        
        // Add lighting
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 300
        scene.rootNode.addChildNode(ambientLight)
        
        // Add point geometry node
        scene.rootNode.addChildNode(pointGeometryNode)
        
        // Start auto-rotation if enabled
        startAutoRotation()
    }
    
    private func updateGeometry() {
        Task {
            let allVertices = await arManager.pointCloudProvider.vertices.values
            let verticesArray = Array(allVertices)
            
            await MainActor.run {
                self.pointCount = verticesArray.count
                
                guard !verticesArray.isEmpty else { return }
                
                // Create geometry
                let positions = verticesArray.map { $0.position }
                let vertexSource = SCNGeometrySource(vertices: positions)
                
                // Create colors based on selected mode
                let colors = generateColors(for: verticesArray, mode: colorMode)
                let colorData = Data(bytes: colors, count: MemoryLayout<simd_float4>.size * colors.count)
                let colorSource = SCNGeometrySource(
                    data: colorData,
                    semantic: .color,
                    vectorCount: colors.count,
                    usesFloatComponents: true,
                    componentsPerVector: 4,
                    bytesPerComponent: MemoryLayout<Float>.size,
                    dataOffset: 0,
                    dataStride: MemoryLayout<simd_float4>.size
                )
                
                // Create geometry element
                let pointIndices: [UInt32] = Array(0..<UInt32(verticesArray.count))
                let element = SCNGeometryElement(indices: pointIndices, primitiveType: .point)
                element.maximumPointScreenSpaceRadius = pointSize
                element.minimumPointScreenSpaceRadius = max(1, pointSize / 4)
                
                // Create final geometry
                let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
                
                // Configure material
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.isDoubleSided = true
                if showWireframe {
                    material.fillMode = .lines
                }
                geometry.materials = [material]
                
                pointGeometryNode.geometry = geometry
            }
        }
    }
    
    private func generateColors(for vertices: [PointCloud.Vertex], mode: ColorMode) -> [simd_float4] {
        switch mode {
        case .original:
            return vertices.map { $0.color }
            
        case .depth:
            // Color by distance from origin
            let distances = vertices.map { sqrt($0.position.x * $0.position.x + $0.position.y * $0.position.y + $0.position.z * $0.position.z) }
            let minDist = distances.min() ?? 0
            let maxDist = distances.max() ?? 1
            let range = maxDist - minDist
            
            return distances.map { distance in
                let normalized = range > 0 ? (distance - minDist) / range : 0
                return depthColor(for: normalized)
            }
            
        case .height:
            // Color by Y position (height)
            let yPositions = vertices.map { $0.position.y }
            let minY = yPositions.min() ?? 0
            let maxY = yPositions.max() ?? 1
            let range = maxY - minY
            
            return yPositions.map { y in
                let normalized = range > 0 ? (y - minY) / range : 0
                return heightColor(for: normalized)
            }
        }
    }
    
    private func depthColor(for normalized: Float) -> simd_float4 {
        // Blue to red gradient for depth
        let r = normalized
        let b = 1.0 - normalized
        return simd_float4(r, 0.2, b, 1.0)
    }
    
    private func heightColor(for normalized: Float) -> simd_float4 {
        // Blue (low) to green (middle) to red (high)
        if normalized < 0.5 {
            let t = normalized * 2
            return simd_float4(0, t, 1 - t, 1.0)
        } else {
            let t = (normalized - 0.5) * 2
            return simd_float4(t, 1 - t, 0, 1.0)
        }
    }
    
    private func updateCameraPosition() {
        let distance = Float(3.0) / zoom
        
        // Convert rotations to radians
        let rotXRad = rotationX * .pi / 180
        let rotYRad = rotationY * .pi / 180
        
        // Calculate spherical coordinates for camera position
        let x = distance * cos(rotXRad) * sin(rotYRad)
        let y = distance * sin(rotXRad)
        let z = distance * cos(rotXRad) * cos(rotYRad)
        
        cameraNode.position = SCNVector3(
            x + panOffset.x,
            y + panOffset.y,
            z + panOffset.z
        )
        
        // Look at the center point (adjusted by pan offset)
        cameraNode.look(at: SCNVector3(panOffset.x, panOffset.y, panOffset.z))
    }
    
    private func resetCamera() {
        withAnimation(.easeOut(duration: 0.5)) {
            rotationX = -45
            rotationY = 45
            zoom = 1.5
            panOffset = SCNVector3(0, 0, 0)
        }
        updateCameraPosition()
    }
    
    private func nextColorMode() {
        let currentIndex = ColorMode.allCases.firstIndex(of: colorMode) ?? 0
        let nextIndex = (currentIndex + 1) % ColorMode.allCases.count
        colorMode = ColorMode.allCases[nextIndex]
    }
    
    private func updatePointCount() {
        Task {
            let count = await arManager.pointCloudProvider.vertices.count
            await MainActor.run {
                self.pointCount = count
            }
        }
    }
    
    private func startAutoRotation() {
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            guard isRotating else { return }
            rotationY += 1
            if rotationY >= 360 { rotationY = 0 }
            updateCameraPosition()
        }
    }
    
    // MARK: - Measurement Functions
    
    private func toggleMeasurementMode() {
        isMeasurementMode.toggle()
        if !isMeasurementMode {
            clearMeasurements()
        }
    }
    
    private func handlePointSelection(_ point: SCNVector3) {
        guard isMeasurementMode else { return }
        
        if selectedPoints.count >= 2 {
            // Start new measurement
            clearMeasurements()
        }
        
        selectedPoints.append(point)
        addPointMarker(at: point)
        
        if selectedPoints.count == 2 {
            calculateAndDisplayDistance()
        }
    }
    
    private func addPointMarker(at position: SCNVector3) {
        let sphere = SCNSphere(radius: 0.02)
        let material = SCNMaterial()
        material.diffuse.contents = selectedPoints.count == 1 ? UIColor.yellow : UIColor.green
        material.lightingModel = .constant
        sphere.materials = [material]
        
        let markerNode = SCNNode(geometry: sphere)
        markerNode.position = position
        
        measurementNodes.append(markerNode)
        sceneView.scene?.rootNode.addChildNode(markerNode)
    }
    
    private func calculateAndDisplayDistance() {
        guard selectedPoints.count == 2 else { return }
        
        let point1 = selectedPoints[0]
        let point2 = selectedPoints[1]
        
        // Calculate Euclidean distance
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        let dz = point2.z - point1.z
        let distance = sqrt(dx*dx + dy*dy + dz*dz)
        
        measuredDistance = distance
        
        // Add line between points
        addLineBetweenPoints(point1, point2)
        
        // Add distance label
        addDistanceLabel(at: midpoint(point1, point2), distance: distance)
    }
    
    private func addLineBetweenPoints(_ point1: SCNVector3, _ point2: SCNVector3) {
        let indices: [UInt32] = [0, 1]
        let source = SCNGeometrySource(vertices: [point1, point2])
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.cyan
        material.lightingModel = .constant
        geometry.materials = [material]
        
        let lineNode = SCNNode(geometry: geometry)
        measurementNodes.append(lineNode)
        sceneView.scene?.rootNode.addChildNode(lineNode)
    }
    
    private func addDistanceLabel(at position: SCNVector3, distance: Float) {
        let text = SCNText(string: formatDistance(distance), extrusionDepth: 0.001)
        text.font = UIFont.systemFont(ofSize: 0.1)
        text.flatness = 0.1
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .constant
        text.materials = [material]
        
        let textNode = SCNNode(geometry: text)
        textNode.position = position
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)
        
        // Make text face camera
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = [.Y]
        textNode.constraints = [billboardConstraint]
        
        measurementNodes.append(textNode)
        sceneView.scene?.rootNode.addChildNode(textNode)
    }
    
    private func midpoint(_ point1: SCNVector3, _ point2: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            (point1.x + point2.x) / 2,
            (point1.y + point2.y) / 2,
            (point1.z + point2.z) / 2
        )
    }
    
    private func formatDistance(_ distance: Float) -> String {
        if distance < 1.0 {
            return String(format: "%.1f cm", distance * 100)
        } else {
            return String(format: "%.2f m", distance)
        }
    }
    
    private func clearMeasurements() {
        selectedPoints.removeAll()
        measuredDistance = nil
        
        // Remove all measurement nodes from scene
        for node in measurementNodes {
            node.removeFromParentNode()
        }
        measurementNodes.removeAll()
    }
}

struct SceneKitView: UIViewRepresentable {
    let sceneView: SCNView
    let cameraNode: SCNNode
    let pointGeometryNode: SCNNode
    let arManager: ARManager
    
    @Binding var rotationX: Float
    @Binding var rotationY: Float
    @Binding var zoom: Float
    @Binding var panOffset: SCNVector3
    @Binding var isMeasurementMode: Bool
    
    let onPointSelected: (SCNVector3) -> Void
    
    func makeUIView(context: Context) -> SCNView {
        let coordinator = context.coordinator
        
        // Add gesture recognizers
        let panGesture = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinchGesture = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        let tapGesture = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        
        // Configure tap gesture to work with pan
        tapGesture.numberOfTapsRequired = 1
        panGesture.require(toFail: tapGesture)
        
        sceneView.addGestureRecognizer(panGesture)
        sceneView.addGestureRecognizer(pinchGesture)
        sceneView.addGestureRecognizer(tapGesture)
        
        return sceneView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        updateCameraPosition()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func updateCameraPosition() {
        let distance = Float(3.0) / zoom
        
        // Convert rotations to radians
        let rotXRad = rotationX * .pi / 180
        let rotYRad = rotationY * .pi / 180
        
        // Calculate spherical coordinates for camera position
        let x = distance * cos(rotXRad) * sin(rotYRad)
        let y = distance * sin(rotXRad)
        let z = distance * cos(rotXRad) * cos(rotYRad)
        
        cameraNode.position = SCNVector3(
            x + panOffset.x,
            y + panOffset.y,
            z + panOffset.z
        )
        
        // Look at the center point (adjusted by pan offset)
        cameraNode.look(at: SCNVector3(panOffset.x, panOffset.y, panOffset.z))
    }
    
    class Coordinator: NSObject {
        var parent: SceneKitView
        
        init(_ parent: SceneKitView) {
            self.parent = parent
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard !parent.isMeasurementMode else { return }
            
            let translation = gesture.translation(in: gesture.view)
            let sensitivity: Float = 0.5
            
            parent.rotationY += Float(translation.x) * sensitivity
            parent.rotationX -= Float(translation.y) * sensitivity
            
            // Clamp X rotation to prevent flipping
            parent.rotationX = max(-90, min(90, parent.rotationX))
            
            parent.updateCameraPosition()
            gesture.setTranslation(.zero, in: gesture.view)
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard !parent.isMeasurementMode else { return }
            
            let scale = Float(gesture.scale)
            parent.zoom *= scale
            parent.zoom = max(0.1, min(5.0, parent.zoom))
            
            parent.updateCameraPosition()
            gesture.scale = 1.0
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard parent.isMeasurementMode else { return }
            
            let location = gesture.location(in: parent.sceneView)
            
            // Use a simpler approach - find closest point from the original vertex data
            Task {
                if let closestPoint = await findClosestPointFromVertexData(to: location) {
                    await MainActor.run {
                        parent.onPointSelected(closestPoint)
                    }
                }
            }
        }
        
        private func findClosestPointFromVertexData(to screenPoint: CGPoint) async -> SCNVector3? {
            // Access the original vertex data from ARManager
            let vertices = await parent.arManager.pointCloudProvider.vertices.values
            let verticesArray = Array(vertices)
            
            var closestPoint: SCNVector3?
            var closestDistance: Float = Float.greatestFiniteMagnitude
            
            // Check points within a reasonable radius
            let searchRadius: Float = 50.0 // pixels
            
            for vertex in verticesArray {
                let worldPosition = vertex.position
                let screenPosition = parent.sceneView.projectPoint(worldPosition)
                
                let dx = Float(screenPoint.x) - screenPosition.x
                let dy = Float(screenPoint.y) - screenPosition.y
                let screenDistance = sqrt(dx*dx + dy*dy)
                
                if screenDistance < searchRadius && screenDistance < closestDistance {
                    closestDistance = screenDistance
                    closestPoint = worldPosition
                }
            }
            
            return closestPoint
        }
    }
}

struct SettingsView: View {
    @Binding var pointSize: CGFloat
    @Binding var showWireframe: Bool
    @Binding var colorMode: PointCloudViewer.ColorMode
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section("Display") {
                    HStack {
                        Text("Point Size")
                        Spacer()
                        Slider(value: $pointSize, in: 1...20, step: 1) {
                            Text("Point Size")
                        }
                        Text("\(Int(pointSize))")
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("Wireframe Mode", isOn: $showWireframe)
                }
                
                Section("Color Mode") {
                    ForEach(PointCloudViewer.ColorMode.allCases, id: \.self) { mode in
                        HStack {
                            Image(systemName: mode.systemImage)
                                .foregroundColor(colorMode == mode ? .blue : .secondary)
                            Text(mode.rawValue)
                            Spacer()
                            if colorMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            colorMode = mode
                        }
                    }
                }
                
                Section("Instructions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Navigation:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("• Drag to rotate the point cloud")
                        Text("• Pinch to zoom in/out")
                        Text("• Use the zoom slider for precise control")
                        Text("• Tap the viewfinder icon to reset camera")
                        Text("• Toggle auto-rotation with the play button")
                        
                        Text("\nMeasurement Mode:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("• Tap the ruler icon to enable measurement mode")
                        Text("• Tap on a point in the cloud to select it")
                        Text("• Tap a second point to measure distance")
                        Text("• Clear measurements with the X button")
                        Text("• Exit measurement mode to resume navigation")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Viewer Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

#Preview {
    PointCloudViewer(arManager: ARManager())
}
