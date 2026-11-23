import AppKit
import SakuraCordModels

extension NativeTimelineRowPainter {
    static func pollSurface(in frame: CGRect) {
        // Polls sit on the embed's flat, borderless surface.
        DiscordEmbedPalette.embedFill.setFill()
        NSBezierPath(concentricRoundedRect: frame, cornerRadius: NativeTimelinePollLayout.cornerRadius).fill()
    }

    static func pollButton(_ title: String, in frame: CGRect, control: NativeTimelinePollTarget.Control,
                           state: NativeTimelinePollPresentation, isEnabled: Bool = true, isProminent: Bool = false,
                           bubbleRegion: NativeTimelineBubbleRegion? = nil) {
        let outgoing = bubbleRegion?.isOutgoing == true
        gradientButton(title: title, frame: frame, isHovered: isEnabled && state.hoveredControl == control,
                        pressProgress: state.pressedControl == control ? 1 : 0,
                        colors: [outgoing ? .sakuraCordLabelOnAccentColor.withAlphaComponent(isProminent ? 1 : 0.16) : isProminent ? .sakuraCordAccentColor : .controlColor],
                        foreground: outgoing ? (isProminent ? .sakuraCordAccentColor : .sakuraCordLabelOnAccentColor) : isProminent ? .sakuraCordLabelOnAccentColor : .labelColor, isEnabled: isEnabled)
    }

    static func drawPoll(_ input: NativeTimelineMessageDrawInput) {
        guard let poll = input.row.message.poll, let layout = input.layout.pollLayout else { return }
        let state = input.pollPresentation
        let bubble = input.layout.bubbleRegion
        if let bubble {
            bubbleIntegratedSection(layout.frame, bubbleRegion: bubble, accentColor: nil,
                drawsTopSeparator: layout.drawsTopSeparator)
        } else {
            pollSurface(in: layout.frame)
        }
        text(poll.question, in: layout.questionFrame, font: .interfaceSystemFont(ofSize: 15, weight: .semibold),
             color: NativeTimelineBubbleDrawing.foregroundColor(for: bubble), lineBreakMode: .byWordWrapping)
        text(poll.isClosed() ? "" : poll.allowsMultipleAnswers ? "Select one or more answers" : "Select one answer",
             in: layout.instructionFrame, font: .interfaceSystemFont(ofSize: 12), color: NativeTimelineBubbleDrawing.secondaryForegroundColor(for: bubble))
        for region in layout.answers {
            guard let answer = poll.answers.first(where: { $0.id == region.id }) else { continue }
            drawPollAnswer(answer, region: region, poll: poll, state: state, bubbleRegion: bubble,
                           hasAnimatedEmojiOverlay: input.animatedOverlayRoles.contains(.pollAnswer(answer.id)))
        }
        drawPollFooter(poll, layout: layout, state: state,
                       isConfirmed: input.row.message.outboxState == .confirmed,
                       canVote: input.model?.canUpdatePollVote(on: input.row.message, removing: !poll.selectedAnswerIDs.isEmpty) != false, bubbleRegion: bubble)
    }

    private static func drawPollAnswer(_ answer: PollAnswer, region: NativeTimelinePollLayout.Answer,
                                       poll: MessagePoll, state: NativeTimelinePollPresentation, bubbleRegion: NativeTimelineBubbleRegion?,
                                       hasAnimatedEmojiOverlay: Bool) {
        let results = state.showsResults(for: poll)
        let selected = results ? poll.selectedAnswerIDs.contains(answer.id) : state.selected.contains(answer.id)
        let highestCount = poll.results?.answerCounts.map(\.count).max() ?? 0
        let winner = poll.isClosed() && highestCount > 0 && poll.count(for: answer.id) == highestCount
        let outgoing = bubbleRegion?.isOutgoing == true
        let foreground = NativeTimelineBubbleDrawing.foregroundColor(for: bubbleRegion)
        let accent = outgoing ? NSColor.sakuraCordLabelOnAccentColor : .sakuraCordAccentColor
        if state.hoveredControl == .answer(answer.id) {
            foreground.withAlphaComponent(outgoing ? 0.12 : 0.06).setFill()
            NSBezierPath(concentricRoundedRect: region.frame, cornerRadius: NativeTimelinePollLayout.answerCornerRadius).fill()
        }
        let radius = region.barFrame.height / 2
        foreground.withAlphaComponent(outgoing ? 0.18 : 0.10).setFill()
        NSBezierPath(roundedRect: region.barFrame, xRadius: radius, yRadius: radius).fill()
        if !hasAnimatedEmojiOverlay { drawPollEmoji(answer.emoji, frame: region.emojiFrame) }
        text(answer.text, in: region.textFrame, font: NativeTimelinePollLayout.answerFont, color: foreground, lineBreakMode: .byWordWrapping)
        let mark = CGRect(x: region.barFrame.maxX - InterfaceScale.metric(18), y: region.textFrame.minY + InterfaceScale.metric(1),
                          width: InterfaceScale.metric(18), height: InterfaceScale.metric(18))
        if results {
            let fraction = min(1, max(0, state.fractions[answer.id] ?? CGFloat(poll.fraction(for: answer.id))))
            if fraction > 0 {
                ((selected || winner) ? accent : foreground.withAlphaComponent(0.35)).setFill()
                let bar = CGRect(x: region.barFrame.minX, y: region.barFrame.minY,
                                 width: max(region.barFrame.height, region.barFrame.width * fraction), height: region.barFrame.height)
                NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()
            }
            let percentage = poll.results == nil ? "—" : "\(Int((poll.fraction(for: answer.id) * 100).rounded()))%"
            let font = NSFont.interfaceSystemFont(ofSize: 13, weight: .semibold)
            let percentageWidth = ceil(NativeTimelineRowLayout.measuredTextWidth(percentage, font: font)) + 1
            let percentageFrame = CGRect(x: region.barFrame.maxX - percentageWidth, y: region.textFrame.minY,
                                         width: percentageWidth, height: InterfaceScale.metric(20))
            text(percentage, in: percentageFrame, font: font, color: foreground, alignment: .right)
            if selected {
                systemSymbol("checkmark.circle", in: mark.offsetBy(dx: percentageFrame.minX - InterfaceScale.metric(6) - mark.maxX, dy: 0),
                             color: foreground, inset: 0)
            }
        } else if selected {
            systemSymbol(poll.allowsMultipleAnswers ? "checkmark.square" : "checkmark.circle", in: mark, color: foreground, inset: 0)
        } else {
            let indicatorRadius = poll.allowsMultipleAnswers ? InterfaceScale.metric(5) : mark.width / 2
            let indicator = NSBezierPath(roundedRect: mark.insetBy(dx: 0.75, dy: 0.75), xRadius: indicatorRadius, yRadius: indicatorRadius)
            NativeTimelineBubbleDrawing.secondaryForegroundColor(for: bubbleRegion).setStroke()
            indicator.lineWidth = 1.5
            indicator.stroke()
        }
    }

    private static func drawPollEmoji(_ emoji: EmojiReference?, frame: CGRect?) {
        guard let emoji, let frame else { return }
        if let key = MediaImageKey.emoji(emoji), let image = MediaImageStore.shared.stillImage(for: key) {
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else if emoji.id == nil {
            text(emoji.name, in: frame, font: .interfaceSystemFont(ofSize: 20), color: .labelColor, lineBreakMode: .byClipping)
        }
    }

    private static func drawPollFooter(_ poll: MessagePoll, layout: NativeTimelinePollLayout,
                                       state: NativeTimelinePollPresentation, isConfirmed: Bool, canVote: Bool,
                                       bubbleRegion: NativeTimelineBubbleRegion?) {
        let results = state.showsResults(for: poll)
        let secondary = NativeTimelineBubbleDrawing.secondaryForegroundColor(for: bubbleRegion)
        text(NativeTimelinePollLayout.votesTitle(for: poll), in: layout.votesFrame, font: NativeTimelinePollLayout.footerFont,
             color: state.hoveredControl == .votes ? NativeTimelineBubbleDrawing.foregroundColor(for: bubbleRegion) : secondary)
        let remaining = max(0, Int((poll.expiry?.timeIntervalSinceNow ?? 0) / 60))
        let time = poll.isClosed() ? "Final results" : remaining >= 1440 ? "\(remaining / 1440)d left" : remaining >= 60 ? "\(remaining / 60)h left" : "\(max(1, remaining))m left"
        text(" · \(time)", in: layout.expiryFrame, font: NativeTimelinePollLayout.footerFont, color: secondary)
        guard !poll.isClosed(), isConfirmed else { return }
        if poll.selectedAnswerIDs.isEmpty {
            pollButton(results ? "Back to vote" : "Show results", in: layout.revealFrame, control: .reveal, state: state, bubbleRegion: bubbleRegion)
        }
        if !results || !poll.selectedAnswerIDs.isEmpty {
            let removing = !poll.selectedAnswerIDs.isEmpty
            let enabled = canVote && (removing || !state.selected.isEmpty)
            pollButton(removing ? "Remove Vote" : "Vote",
                       in: layout.submitFrame, control: .submit, state: state, isEnabled: enabled, isProminent: !removing, bubbleRegion: bubbleRegion)
        }
    }
}
