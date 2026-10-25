import UIKit
import AudioToolbox

/// Click-wheel tick feedback. Ported from the web iPod's ClickSoundPlayer:
/// clicks are queued 50 ms apart and dropped once 150 ms are already queued,
/// so a fast spin produces a steady clicker instead of a pile-up.
/// Each queued click also fires a haptic tap.
@MainActor
final class Feedback {
    static let shared = Feedback()
    private let tickGen = UIImpactFeedbackGenerator(style: .rigid)
    private let pressGen = UIImpactFeedbackGenerator(style: .medium)
    private var clickID: SystemSoundID = 0
    private var nextSlot: CFTimeInterval = 0

    static let spacing = 0.05      // Wr
    static let maxQueued = 0.15    // jr

    private init() {
        if let url = Bundle.main.url(forResource: "click", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(url as CFURL, &clickID)
        }
        tickGen.prepare(); pressGen.prepare()
    }

    /// One wheel step (`count` steps at once, e.g. accelerated scrolling).
    func tick(clicker: Bool, haptics: Bool, count: Int = 1) {
        guard clicker || haptics else { return }
        for _ in 0..<max(1, count) {
            let now = CACurrentMediaTime()
            if nextSlot - now >= Feedback.maxQueued { return }
            let start = max(now, nextSlot)
            nextSlot = start + Feedback.spacing
            let delay = start - now
            if delay < 0.002 { fire(clicker: clicker, haptics: haptics) }
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.fire(clicker: clicker, haptics: haptics)
                }
            }
        }
    }

    /// Haptic-only tick (seeking is silent on the web iPod).
    func silentTick(haptics: Bool) {
        guard haptics else { return }
        tickGen.impactOccurred(intensity: 0.45); tickGen.prepare()
    }

    private func fire(clicker: Bool, haptics: Bool) {
        if haptics { tickGen.impactOccurred(intensity: 0.6); tickGen.prepare() }
        if clicker, clickID != 0 { AudioServicesPlaySystemSound(clickID) }
    }

    func press(clicker: Bool, haptics: Bool) {
        if haptics { pressGen.impactOccurred(intensity: 0.8); pressGen.prepare() }
        if clicker, clickID != 0 { AudioServicesPlaySystemSound(clickID) }
    }
}
