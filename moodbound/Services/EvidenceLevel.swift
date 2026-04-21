import Foundation

// Coarse classification of how much recent evidence the model is working
// from. Used to gate confident-sounding user-facing copy: with fewer than a
// handful of recent check-ins, the underlying point estimates are too noisy
// to phrase as decisive trends ("Pretty turbulent right now"), even though
// the math itself remains valid. Decisions about clinical safety severity
// are NOT gated by this — those must remain honest regardless of N — but
// the surrounding narrative copy is hedged.
enum EvidenceLevel: String, Equatable {
    case insufficient
    case learning
    case established

    // Anchored to the 14-day window most insights operate over. Below 4
    // observations the picture is dominated by a single day's variance;
    // 4–9 is enough to spot directionality but not to make confident
    // claims; 10+ approaches a usable signal.
    static func from(observationCount: Int) -> EvidenceLevel {
        if observationCount < 4 { return .insufficient }
        if observationCount < 10 { return .learning }
        return .established
    }

    var allowsConfidentNarrative: Bool {
        self == .established
    }
}
