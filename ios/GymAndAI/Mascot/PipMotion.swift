import Foundation
import RealityKit

private struct CompanionClip: Decodable {
    let name: String
    let duration: TimeInterval
    let loop: Bool
    let trim_start: TimeInterval
    let trim_end: TimeInterval
}

@MainActor
final class PipMotion {
    private let owner: Entity
    private let clips: [String: (resource: AnimationResource, definition: CompanionClip)]
    private var playback: AnimationPlaybackController?
    private var completion: Task<Void, Never>?
    private var state: MascotState?
    private var reducesMotion = false

    init(character: Entity, companion: CompanionKind) throws {
        guard let owner = Self.animationOwner(in: character),
              let take = owner.availableAnimations.max(by: { $0.definition.duration < $1.definition.duration }),
              let url = Bundle.main.url(forResource: "CompanionClips", withExtension: "json") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let definitions = try JSONDecoder().decode([String: [CompanionClip]].self,
                                                   from: Data(contentsOf: url))
        guard let entries = definitions[companion.rawValue],
              entries.count == MascotState.allCases.count,
              Set(entries.map(\.name)) == Set(MascotState.allCases.map(\.clip)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var clips: [String: (resource: AnimationResource, definition: CompanionClip)] = [:]
        for clip in entries {
            guard clip.duration > 0, clip.trim_start >= 0,
                  clip.trim_end > clip.trim_start, clip.trim_end <= take.definition.duration + 0.04,
                  abs(clip.duration - (clip.trim_end - clip.trim_start)) < 0.04,
                  clip.loop == ["idle", "rest"].contains(clip.name) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let view = AnimationView(source: take.definition, name: clip.name,
                                     trimStart: clip.trim_start, trimEnd: clip.trim_end)
            clips[clip.name] = (try AnimationResource.generate(with: view), clip)
        }
        self.owner = owner
        self.clips = clips
    }

    func configure(state: MascotState, reducesMotion: Bool) {
        guard self.state != state || self.reducesMotion != reducesMotion else { return }
        self.state = state
        self.reducesMotion = reducesMotion
        stop()
        if reducesMotion {
            // Evaluate the neutral frame without advancing the skeletal animation.
            if let idle = clips["idle"] {
                playback = owner.playAnimation(idle.resource, startsPaused: true)
                playback?.time = 0
            }
            return
        }
        play(state.clip)
    }

    func stop() {
        completion?.cancel()
        completion = nil
        playback?.stop()
        playback = nil
    }

    private func play(_ name: String) {
        guard let clip = clips[name] else { return }
        playback = owner.playAnimation(clip.definition.loop ? clip.resource.repeat() : clip.resource,
                                       transitionDuration: 0.15)
        guard !clip.definition.loop else { return }
        completion = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(clip.definition.duration))
                guard !Task.isCancelled, let self, !self.reducesMotion else { return }
                self.playback?.stop()
                self.play("idle")
            } catch { return }
        }
    }

    private static func animationOwner(in entity: Entity) -> Entity? {
        if !entity.availableAnimations.isEmpty { return entity }
        for child in entity.children {
            if let owner = animationOwner(in: child) { return owner }
        }
        return nil
    }
}
