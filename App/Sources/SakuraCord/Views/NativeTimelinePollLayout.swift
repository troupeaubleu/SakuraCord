import AppKit
import CoreText
import SakuraCordModels

struct NativeTimelinePollLayout {
    struct Answer {
        let id: Int
        let frame: CGRect
        let textFrame: CGRect
        let barFrame: CGRect
        let emojiFrame: CGRect?
    }
    let frame: CGRect
    let questionFrame: CGRect
    let instructionFrame: CGRect
    let answers: [Answer]
    let votesFrame: CGRect
    let expiryFrame: CGRect
    let revealFrame: CGRect
    let submitFrame: CGRect
    var drawsTopSeparator = false

    static var inset: CGFloat { InterfaceScale.metric(16) }
    static var cornerRadius: CGFloat { DiscordRichMessageMetrics.cardCornerRadius }
    static var answerCornerRadius: CGFloat { DiscordRichMessageMetrics.cardMediaCornerRadius }

    init(poll: MessagePoll, x originX: CGFloat, y originY: CGFloat, width availableWidth: CGFloat, integratesWithBubble: Bool = false) {
        let width = integratesWithBubble ? availableWidth : min(InterfaceScale.metric(456), availableWidth)
        let inset = integratesWithBubble ? 0 : Self.inset
        let inner = max(1, width - inset * 2)
        var cursor = originY + inset
        let questionHeight = Self.height(poll.question, width: inner, font: .interfaceSystemFont(ofSize: 15, weight: .semibold))
        questionFrame = CGRect(x: originX + inset, y: cursor, width: inner, height: questionHeight)
        cursor += questionHeight + InterfaceScale.metric(4)
        instructionFrame = CGRect(x: originX + inset, y: cursor, width: inner, height: poll.isClosed() ? 0 : InterfaceScale.metric(17))
        cursor += instructionFrame.height + InterfaceScale.metric(8)
        // Rows reach past the text so their hover tint frames it; the bar
        // track is always there, so showing results never moves the rows.
        let outset = min(inset, InterfaceScale.metric(8)), padding = InterfaceScale.metric(11)
        let textX = originX + inset
        answers = poll.answers.map { answer in
            let emojiWidth: CGFloat = answer.emoji == nil ? 0 : InterfaceScale.metric(28)
            let textWidth = max(1, inner - emojiWidth - Self.trailingWidth)
            let textHeight = max(InterfaceScale.metric(20), Self.height(answer.text, width: textWidth, font: Self.answerFont))
            let textFrame = CGRect(x: textX + emojiWidth, y: cursor + padding, width: textWidth, height: textHeight)
            let barFrame = CGRect(x: textX, y: textFrame.maxY + InterfaceScale.metric(8), width: inner, height: InterfaceScale.metric(4))
            let rect = CGRect(x: textX - outset, y: cursor, width: inner + outset * 2, height: barFrame.maxY + padding - cursor)
            cursor = rect.maxY
            return Answer(id: answer.id, frame: rect, textFrame: textFrame, barFrame: barFrame,
                          emojiFrame: answer.emoji == nil ? nil : CGRect(x: textX, y: textFrame.minY, width: InterfaceScale.metric(20), height: InterfaceScale.metric(20)))
        }
        cursor += InterfaceScale.metric(12)
        let buttonHeight = NativeTimelineComponentButtonMetrics.height
        let rowHeight = poll.isClosed() ? InterfaceScale.metric(16) : buttonHeight
        let lineY = cursor + (rowHeight - InterfaceScale.metric(16)) / 2
        let votesWidth = min(inner, ceil(NativeTimelineRowLayout.measuredTextWidth(Self.votesTitle(for: poll), font: Self.footerFont)) + 1)
        votesFrame = CGRect(x: textX, y: lineY, width: votesWidth, height: InterfaceScale.metric(16))
        expiryFrame = CGRect(x: votesFrame.maxX, y: lineY, width: max(0, inner - votesWidth), height: InterfaceScale.metric(16))
        let submitWidth = min(InterfaceScale.metric(94), inner * 0.45)
        let revealWidth = min(InterfaceScale.metric(120), max(0, inner - submitWidth - InterfaceScale.metric(6)))
        if !poll.isClosed(), votesWidth + InterfaceScale.metric(96) + revealWidth + submitWidth > inner { cursor += rowHeight + InterfaceScale.metric(8) }
        submitFrame = CGRect(x: textX + inner - submitWidth, y: cursor, width: submitWidth, height: buttonHeight)
        revealFrame = CGRect(x: submitFrame.minX - InterfaceScale.metric(6) - revealWidth, y: cursor, width: revealWidth, height: buttonHeight)
        frame = CGRect(x: originX, y: originY, width: width, height: cursor + rowHeight + inset - originY)
    }

    static var answerFont: NSFont { .interfaceSystemFont(ofSize: 13, weight: .medium) }
    static var footerFont: NSFont { .interfaceSystemFont(ofSize: 12) }
    /// Room right of each answer for a check and its percentage, or the vote indicator.
    private static var trailingWidth: CGFloat { InterfaceScale.metric(72) }

    static func votesTitle(for poll: MessagePoll) -> String {
        poll.results == nil ? "— votes" : "\(poll.totalVotes) \(poll.totalVotes == 1 ? "vote" : "votes")"
    }

    static func resultButtonFrame(in frame: CGRect) -> CGRect {
        let height = NativeTimelineComponentButtonMetrics.height
        return CGRect(x: frame.maxX - resultInset(in: frame) - InterfaceScale.metric(86), y: frame.midY - height / 2, width: InterfaceScale.metric(86), height: height)
    }

    private static func resultInset(in frame: CGRect) -> CGFloat {
        max(0, (frame.height - NativeTimelineComponentButtonMetrics.height) / 2)
    }

    private static func height(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let value = NSAttributedString(string: text, attributes: [.font: font])
        let setter = CTFramesetterCreateWithAttributedString(value)
        return ceil(CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
                     CGSize(width: width, height: .greatestFiniteMagnitude), nil).height)
    }
}

struct NativeTimelinePollPresentation {
    static let voteAnimationDuration: TimeInterval = 0.48
    var selected: Set<Int> = []
    var revealsResults = false
    var hoveredControl: NativeTimelinePollTarget.Control?
    var pressedControl: NativeTimelinePollTarget.Control?
    var fractions: [Int: CGFloat] = [:]

    func showsResults(for poll: MessagePoll) -> Bool {
        revealsResults || poll.isClosed() || !poll.selectedAnswerIDs.isEmpty
    }
}

struct NativeTimelinePollTarget: Equatable {
    enum Control: Equatable { case answer(Int), votes, reveal, submit, original }
    let messageID: MessageID
    let control: Control
}
