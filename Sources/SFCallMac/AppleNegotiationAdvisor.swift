#if os(macOS)
import Foundation
import FoundationModels
import SFCallCore

public enum AppleNegotiationAvailability: Equatable, Sendable {
    case available
    case appleIntelligenceNotEnabled
    case modelNotReady
    case deviceNotEligible
    case unavailable

    public var displayText: String {
        switch self {
        case .available: "available"
        case .appleIntelligenceNotEnabled: "Apple Intelligence is disabled"
        case .modelNotReady: "model not ready"
        case .deviceNotEligible: "device not eligible"
        case .unavailable: "unavailable"
        }
    }
}

public enum AppleNegotiationAdvisorError: LocalizedError, Sendable {
    case unavailable(AppleNegotiationAvailability)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let state):
            "Negotiation intelligence unavailable — \(state.displayText)."
        }
    }
}

public final class AppleNegotiationAdvisor: NegotiationAdviceProvider, @unchecked Sendable {
    public init() {}

    public static var availability: AppleNegotiationAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable:
            return .unavailable
        }
    }

    public func advise(for request: ResponseRequest) async throws -> NegotiationAdvice {
        let availability = Self.availability
        guard availability == .available else {
            throw AppleNegotiationAdvisorError.unavailable(availability)
        }

        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: Self.prompt(for: request),
            generating: GeneratedNegotiationAdvice.self
        )
        let generated = response.content

        return NegotiationAdvice(
            translatedClientTextVietnamese: generated.translatedClientTextVietnamese,
            trapDetected: generated.trapDetected,
            riskLevel: generated.riskLevel.domainValue,
            riskReasonVietnamese: generated.riskReasonVietnamese,
            recommendedMoveVietnamese: generated.recommendedMoveVietnamese,
            replyEnglish: generated.replyEnglish,
            replyVietnamese: generated.replyVietnamese,
            confidencePercent: generated.confidencePercent
        )
    }

    private static let instructions = """
    You are a cautious realtime negotiation copilot for a Vietnamese software professional speaking English with a client.
    Use only the facts, requirements, and conversation supplied in the prompt. Never invent price, deadline, approval, scope, capability, evidence, or commitment. If evidence is weak or ambiguous, recommend clarification instead of accusation. Detect supported pressure, ambiguity, contradiction, premature commitment, scope expansion, unfavorable assumptions, and missing information. The English reply MUST be one to three short A2-B1 sentences that are easy to say aloud and MUST NOT create an unverified commitment. Vietnamese fields MUST be natural Vietnamese. Confidence is confidence in the analysis from available evidence, not probability of winning the negotiation.
    """

    private static func prompt(for request: ResponseRequest) -> String {
        let requirements = request.confirmedRequirements.isEmpty
            ? "(none confirmed)"
            : request.confirmedRequirements.map { "- \($0)" }.joined(separator: "\n")
        let facts = request.clientFacts.isEmpty
            ? "(none)"
            : request.clientFacts.map { "- \($0)" }.joined(separator: "\n")
        let turns = request.recentTurns.isEmpty
            ? "(none)"
            : request.recentTurns.map { "\($0.speaker.rawValue.uppercased()): \($0.text)" }.joined(separator: "\n")

        return """
        Analyze the latest CLIENT turn for a live negotiation.

        Latest client statement:
        \(request.clientSaid)

        Confirmed requirements (baseline v\(request.baselineVersion)):
        \(requirements)

        Known client facts:
        \(facts)

        Recent finalized turns:
        \(turns)

        Translate the latest client statement faithfully into Vietnamese, assess negotiation risk only from this evidence, recommend the next move in Vietnamese, and provide a short safe English reply with Vietnamese meaning.
        """
    }
}

@Generable
private enum GeneratedRiskLevel {
    case low
    case medium
    case high

    var domainValue: NegotiationRiskLevel {
        switch self {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }
}

@Generable(description: "Structured negotiation analysis for the latest client statement")
private struct GeneratedNegotiationAdvice {
    @Guide(description: "Faithful Vietnamese translation of only the latest client statement")
    var translatedClientTextVietnamese: String

    @Guide(description: "True only when the supplied evidence supports a negotiation trap or pressure pattern")
    var trapDetected: Bool

    @Guide(description: "Negotiation risk level based only on supplied evidence")
    var riskLevel: GeneratedRiskLevel

    @Guide(description: "Short Vietnamese explanation of the concrete risk or why risk is low")
    var riskReasonVietnamese: String

    @Guide(description: "One concise next negotiation move in Vietnamese")
    var recommendedMoveVietnamese: String

    @Guide(description: "One to three short A2-B1 English sentences to say aloud, with no unverified commitment")
    var replyEnglish: String

    @Guide(description: "Natural Vietnamese meaning of the English reply")
    var replyVietnamese: String

    @Guide(description: "Confidence in this analysis from the supplied evidence, not negotiation success probability", .range(0...100))
    var confidencePercent: Int
}
#endif
