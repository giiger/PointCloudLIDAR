// ARManager.swift

import Foundation
internal import ARKit
import SceneKit
internal import Combine

/// ARManager - manages ARSCNView, ARSession and geometry rendering.
/// Implemented as an actor-like concurrency-safe manager using an actor for PointCloud.
/// For easier UIKit interop we use a regular class for ARSession delegate responsibilities
/// while keeping point cloud processing inside an actor (PointCloud).
final class ARManager: NSObject, ARSessionDelegate, ObservableObject {

    // Publicly exposed view to be bridged into SwiftUI
    @MainActor public let sceneView = ARSCNView()

    // Geometry node used to display point cloud
    @MainActor private let geometryNode = SCNNode()

    // Point cloud actor instance
    public let pointCloudProvider = PointCloud.shared

    // Processing flags
    @MainActor private var isProcessing = false
    @MainActor @Published public var isCapturing = false

    override init() {
        super.init()

        // Configure sceneView & session
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true

        // Setup a small point cloud node
        sceneView.scene.rootNode.addChildNode(geometryNode)

        // start session with sceneDepth semantics for LiDAR devices
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .sceneDepth
        sceneView.session.run(configuration)
    }

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // offload processing to an async task
        Task { await process(frame: frame) }
    }

    // Toggle capturing
    func toggleCapturing() async {
        await MainActor.run {
            self.isCapturing.toggle()
        }
    }

    // Frame processing entry - skips frames while processing
    @MainActor
    private func process(frame: ARFrame) async {
        guard !isProcessing && isCapturing else { return }
        isProcessing = true

        // Delegate heavy work to PointCloud actor
        await pointCloudProvider.process(frame: frame)

        // Update SceneKit geometry with new vertices
        await updateGeometry()

        isProcessing = false
    }

    // Create/update SCNGeometry from point cloud vertices (renders every 10th point)
    func updateGeometry() async {
        // Capture vertices snapshot from actor
        let vertices = await pointCloudProvider.vertices.values.enumerated().filter { index, _ in
            index % 10 == 9
        }.map { $0.element }

        guard !vertices.isEmpty else {
            await MainActor.run {
                geometryNode.geometry = nil
            }
            return
        }

        // Create vertex source
        let positions = vertices.map { $0.position }
        let vertexSource = SCNGeometrySource(vertices: positions)

        // Create color data (SIMD4<Float> -> 4 floats)
        var colorArray: [Float] = []
        colorArray.reserveCapacity(vertices.count * 4)
        for v in vertices {
            colorArray.append(v.color.x)
            colorArray.append(v.color.y)
            colorArray.append(v.color.z)
            colorArray.append(v.color.w)
        }
        let colorData = Data(bytes: colorArray, count: MemoryLayout<Float>.size * colorArray.count)

        let colorSource = SCNGeometrySource(data: colorData,
                                            semantic: .color,
                                            vectorCount: vertices.count,
                                            usesFloatComponents: true,
                                            componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<Float>.size,
                                            dataOffset: 0,
                                            dataStride: MemoryLayout<Float>.size * 4)

        // Indices
        var pointIndices = [UInt32]()
        pointIndices.reserveCapacity(vertices.count)
        for i in 0..<vertices.count {
            pointIndices.append(UInt32(i))
        }

        let element = SCNGeometryElement(indices: pointIndices, primitiveType: .point)
        element.maximumPointScreenSpaceRadius = 15

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        geometry.firstMaterial?.isDoubleSided = true
        geometry.firstMaterial?.lightingModel = .constant

        await MainActor.run {
            geometryNode.geometry = geometry
        }
    }
}
