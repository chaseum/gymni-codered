import Combine
import Foundation
import RealityKit

@MainActor
final class PipAssetLibrary {
    static let shared = PipAssetLibrary()
    private var assetTasks: [CompanionKind: Task<Entity, Error>] = [:]
    private var lightingTask: Task<EnvironmentResource, Error>?

    func character(_ companion: CompanionKind) async throws -> Entity {
        if assetTasks[companion] == nil {
            assetTasks[companion] = Task {
                if #available(iOS 18, *) {
                    return try await Entity(named: companion.resource, in: .main)
                }
                for try await entity in Entity.loadAsync(named: companion.resource, in: .main).values {
                    return entity
                }
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        guard let assetTask = assetTasks[companion] else { throw CocoaError(.fileNoSuchFile) }
        return try await assetTask.value.clone(recursive: true)
    }

    func lighting() async throws -> EnvironmentResource {
        if lightingTask == nil {
            lightingTask = Task {
                if #available(iOS 18, *) {
                    return try await EnvironmentResource(named: "PipStudio", in: .main)
                }
                for try await lighting in EnvironmentResource.loadAsync(named: "PipStudio", in: .main).values {
                    return lighting
                }
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        guard let lightingTask else { throw CocoaError(.fileNoSuchFile) }
        return try await lightingTask.value
    }
}
