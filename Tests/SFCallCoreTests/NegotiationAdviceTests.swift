import XCTest
@testable import SFCallCore

final class NegotiationAdviceTests: XCTestCase {
    func testAdvicePreservesFieldsAndClampsConfidenceAboveRange() {
        let advice = NegotiationAdvice(
            translatedClientTextVietnamese: "Khách muốn giao vào thứ Sáu.",
            trapDetected: true,
            riskLevel: .high,
            riskReasonVietnamese: "Đang yêu cầu cam kết trước khi chốt phạm vi.",
            recommendedMoveVietnamese: "Chốt phạm vi và tiêu chí nghiệm thu trước.",
            replyEnglish: "Let me confirm the scope first. Then I can confirm the timeline.",
            replyVietnamese: "Hãy để tôi xác nhận phạm vi trước. Sau đó tôi có thể xác nhận tiến độ.",
            confidencePercent: 140
        )

        XCTAssertEqual(advice.translatedClientTextVietnamese, "Khách muốn giao vào thứ Sáu.")
        XCTAssertTrue(advice.trapDetected)
        XCTAssertEqual(advice.riskLevel, .high)
        XCTAssertEqual(advice.riskReasonVietnamese, "Đang yêu cầu cam kết trước khi chốt phạm vi.")
        XCTAssertEqual(advice.recommendedMoveVietnamese, "Chốt phạm vi và tiêu chí nghiệm thu trước.")
        XCTAssertEqual(advice.replyEnglish, "Let me confirm the scope first. Then I can confirm the timeline.")
        XCTAssertEqual(advice.replyVietnamese, "Hãy để tôi xác nhận phạm vi trước. Sau đó tôi có thể xác nhận tiến độ.")
        XCTAssertEqual(advice.confidencePercent, 100)
    }

    func testAdviceClampsNegativeConfidenceToZero() {
        let advice = NegotiationAdvice(
            translatedClientTextVietnamese: "",
            trapDetected: false,
            riskLevel: .low,
            riskReasonVietnamese: "",
            recommendedMoveVietnamese: "Hỏi lại để làm rõ.",
            replyEnglish: "Could you clarify that point?",
            replyVietnamese: "Bạn có thể làm rõ điểm đó không?",
            confidencePercent: -7
        )

        XCTAssertEqual(advice.confidencePercent, 0)
    }
}
