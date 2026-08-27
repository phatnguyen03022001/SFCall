import Foundation

public enum NegotiationRiskLevel: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct NegotiationAdvice: Equatable, Codable, Sendable {
    public let translatedClientTextVietnamese: String
    public let trapDetected: Bool
    public let riskLevel: NegotiationRiskLevel
    public let riskReasonVietnamese: String
    public let recommendedMoveVietnamese: String
    public let replyEnglish: String
    public let replyVietnamese: String
    public let confidencePercent: Int

    public init(
        translatedClientTextVietnamese: String,
        trapDetected: Bool,
        riskLevel: NegotiationRiskLevel,
        riskReasonVietnamese: String,
        recommendedMoveVietnamese: String,
        replyEnglish: String,
        replyVietnamese: String,
        confidencePercent: Int
    ) {
        self.translatedClientTextVietnamese = translatedClientTextVietnamese
        self.trapDetected = trapDetected
        self.riskLevel = riskLevel
        self.riskReasonVietnamese = riskReasonVietnamese
        self.recommendedMoveVietnamese = recommendedMoveVietnamese
        self.replyEnglish = replyEnglish
        self.replyVietnamese = replyVietnamese
        self.confidencePercent = min(100, max(0, confidencePercent))
    }
}

public protocol NegotiationAdviceProvider: Sendable {
    func advise(for request: ResponseRequest) async throws -> NegotiationAdvice
}
