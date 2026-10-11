import Foundation
import RealityKit

@MainActor
final class PipMotion {
    private let root: Entity
    private let body: Entity
    private let orbit: Entity
    private let arm: Entity
    private let rootPose: Transform
    private let bodyPose: Transform
    private let orbitPose: Transform
    private let armPose: Transform
    private var state = MascotState.idle
    private var elapsed: Float = 0
    private var reducesMotion = false

    init(root: Entity, character: Entity) throws {
        guard let body = character.findEntity(named: "Body"),
              let orbit = character.findEntity(named: "Orbit"),
              let arm = character.findEntity(named: "RightArm") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.root = root
        self.body = body
        self.orbit = orbit
        self.arm = arm
        rootPose = root.transform
        bodyPose = body.transform
        orbitPose = orbit.transform
        armPose = arm.transform
    }

    func setState(_ state: MascotState) {
        guard self.state != state else { return }
        self.state = state
        elapsed = 0
        applyPose()
    }

    func setReducedMotion(_ reducesMotion: Bool) {
        self.reducesMotion = reducesMotion
        if reducesMotion { restorePose() }
    }

    func advance(by seconds: TimeInterval) {
        guard !reducesMotion else { return }
        elapsed += Float(seconds)
        applyPose()
    }

    private func applyPose() {
        guard !reducesMotion else { return }
        restorePose()
        switch state {
        case .idle:
            root.position.y += 0.025 * sin(elapsed * 1.8)
            spinOrbit(speed: 0.18)
        case .coaching:
            root.position.y += 0.018 * sin(elapsed * 3)
            body.orientation = bodyPose.rotation * simd_quatf(angle: 0.07 * sin(elapsed * 4), axis: [1, 0, 0])
            arm.orientation = armPose.rotation * simd_quatf(angle: 0.20 * sin(elapsed * 4), axis: [0, 1, 0])
            spinOrbit(speed: 0.4)
        case .celebrate:
            guard elapsed < 1.6 else {
                root.position.y += 0.025 * sin(elapsed * 1.8)
                spinOrbit(speed: 0.18)
                return
            }
            let progress = min(elapsed / 1.6, 1)
            root.position.y += 0.12 * abs(sin(progress * .pi * 2)) * (1 - progress)
            arm.orientation = armPose.rotation * simd_quatf(angle: -0.5 * sin(progress * .pi), axis: [0, 1, 0])
            spinOrbit(speed: 0.8)
        case .rest:
            root.position.y -= 0.025
            body.orientation = bodyPose.rotation * simd_quatf(angle: -0.06, axis: [1, 0, 0])
            root.position.y += 0.008 * sin(elapsed * 0.9)
            spinOrbit(speed: 0.06)
        }
    }

    private func spinOrbit(speed: Float) {
        orbit.orientation = simd_quatf(angle: elapsed * speed, axis: [0, 0, 1]) * orbitPose.rotation
    }

    private func restorePose() {
        root.transform = rootPose
        body.transform = bodyPose
        orbit.transform = orbitPose
        arm.transform = armPose
    }
}
