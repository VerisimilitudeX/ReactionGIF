import Foundation

/// The energy the user wants the reaction to land with. Steers the AI's picks
/// and is the core of the app's "it actually reads the room" angle.
///
/// The palette is biased toward subgenres of clowning the most recent sender —
/// that's what 90% of real group-chat reactions look like.
enum Vibe: String, CaseIterable, Identifiable {
    case auto
    case roast
    case doesHeKnow
    case broThinksHesHim
    case howDidHeKnow
    case crashout
    case real

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "✨ Auto"
        case .roast: return "🔥 Roast"
        case .doesHeKnow: return "🤨 Does he know?"
        case .broThinksHesHim: return "🪑 Bro thinks he's him"
        case .howDidHeKnow: return "🤯 How did he know?"
        case .crashout: return "😵‍💫 Crashout"
        case .real: return "🙏 Real"
        }
    }

    /// Injected into the AI prompt to steer the humor.
    var promptHint: String {
        switch self {
        case .auto:
            return """
            Default to clowning the most recent sender — that's what lands \
            in this audience 9/10 times. Only go genuine/wholesome if it's \
            clearly a real moment (loss, achievement, vulnerable share).
            """
        case .roast:
            return """
            Clown whoever sent the most recent message. Target their take, \
            flex, or bit. Reach for templates like "bro thinks he's him", \
            "who invited my man blud", "does he know", "this man yapping". \
            Tease the message, not the person — never punch down at \
            protected traits.
            """
        case .doesHeKnow:
            return """
            They missed something obvious or revealed they're out of the \
            loop. Use the "does he know" / "he doesn't know" family \
            (Rami Malek pointing). The bit: pretend they're missing a \
            massive open secret.
            """
        case .broThinksHesHim:
            return """
            They flexed or made a confident claim that doesn't quite earn \
            it. Roast the unearned confidence with "bro thinks he's him", \
            "who invited my man blud" (NBA bench-warmer), "this man \
            yapping", or "bro really thinks he's [X]".
            """
        case .howDidHeKnow:
            return """
            They said something painfully obvious as if it were profound. \
            React with mock-galaxy-brain awe: "how did he know", "how is \
            bro this smart", "this guy cooked", "bro is a genius". The bit: \
            treat the most basic statement as 5D chess.
            """
        case .crashout:
            return """
            The chat is going off the rails or someone said something \
            unhinged. Respond with full meltdown energy: "crashout", \
            "mental breakdown", "losing it", "crying screaming throwing up".
            """
        case .real:
            return """
            They actually said something real. Validate sincerely: "real", \
            "no fr", "facts", "so true bestie", "we all felt that". This \
            is the rare wholesome lane — use it only when the moment \
            genuinely calls for it.
            """
        }
    }
}
