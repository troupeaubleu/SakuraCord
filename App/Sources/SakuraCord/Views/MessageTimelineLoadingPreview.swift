import AppKit
import SwiftUI

/// A conversation's stand-in while its first messages load: messages laid
/// out as the timeline lays them out, too blurred to read, which the real
/// messages come into focus over.
struct MessageTimelineLoadingPreview: View {
    var bottomContentInset: CGFloat = 0

    var body: some View {
        Representable(bottomInset: bottomContentInset + MessageTimelineLoadingPreviewView.messageSpacing)
            // The timeline runs beneath the translucent toolbar; so does its stand-in.
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
    }

    private struct Representable: NSViewRepresentable {
        let bottomInset: CGFloat

        func makeNSView(context _: Context) -> MessageTimelineLoadingPreviewView {
            MessageTimelineLoadingPreviewView(frame: .zero)
        }

        func updateNSView(_ view: MessageTimelineLoadingPreviewView, context _: Context) {
            view.bottomInset = bottomInset
        }
    }
}

/// Draws the stand-in's messages from the bottom up, repeating them as far
/// as the view reaches. The timeline's history placeholder covers only what
/// is on screen of a far taller region; `bottomOffset` keeps its messages
/// anchored to that region's bottom so they scroll with the timeline.
final class MessageTimelineLoadingPreviewView: NSView {
    static var blurRadius: CGFloat { InterfaceScale.metric(14) }
    static var messageSpacing: CGFloat { InterfaceScale.metric(16) }

    /// The space below the newest message.
    var bottomInset: CGFloat = 0 {
        didSet { if bottomInset != oldValue { needsDisplay = true } }
    }

    /// How far below this view the stand-in's bottom edge lies.
    var bottomOffset: CGFloat = 0 {
        didSet { if bottomOffset != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.filters = [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: Self.blurRadius])].compactMap(\.self)
        alphaValue = 0.6
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Loading messages")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    override func hitTest(_: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let samples = PreviewMessage.samples
        let period = samples.reduce(0) { $0 + $1.height + Self.messageSpacing }
        var bottom = bounds.maxY + bottomOffset - bottomInset
        // Skip whole repeats below what this view shows.
        if bottom > bounds.maxY + period {
            bottom -= ((bottom - bounds.maxY) / period).rounded(.down) * period
        }
        let textWidth = min(
            InterfaceScale.metric(560),
            max(InterfaceScale.metric(120), bounds.width - PreviewMessage.textX - MessageRowLayoutMetrics.avatarColumnGap * 2)
        )
        // Newest at the bottom, so each group's head sits above its continuations.
        var index = samples.count - 1
        while bottom > bounds.minY {
            let message = samples[index]
            let top = bottom - message.height
            if top < dirtyRect.maxY, bottom > dirtyRect.minY {
                message.draw(atTop: top, textWidth: textWidth)
            }
            bottom = top - Self.messageSpacing
            index = (index + samples.count - 1) % samples.count
        }
    }
}

/// One fake message, drawn as shapes where text, avatar and media would be.
private struct PreviewMessage {
    /// Grouped under the message before, without its own avatar and name.
    var continuesGroup = false
    var nameWidth: CGFloat = 0
    /// Each line's share of the text column.
    let lines: [CGFloat]
    var imageSize: CGSize?

    static let samples: [Self] = [
        .init(nameWidth: 96, lines: [0.82, 0.46]),
        .init(continuesGroup: true, lines: [0.64]),
        .init(nameWidth: 128, lines: [0.38], imageSize: CGSize(width: 260, height: 150)),
        .init(nameWidth: 82, lines: [0.9, 0.74, 0.3]),
        .init(continuesGroup: true, lines: [0.52]),
        .init(nameWidth: 112, lines: [0.7]),
        .init(nameWidth: 90, lines: [0.86, 0.58]),
        .init(continuesGroup: true, lines: [0.4]),
    ]

    static var textX: CGFloat {
        MessageRowLayoutMetrics.horizontalInset + MessageRowLayoutMetrics.avatarDiameter + MessageRowLayoutMetrics.avatarColumnGap
    }

    private static var itemSpacing: CGFloat { InterfaceScale.metric(9) }
    private static var headerTop: CGFloat { InterfaceScale.metric(3) }
    private static var nameHeight: CGFloat { InterfaceScale.metric(11) }
    private static var lineHeight: CGFloat { InterfaceScale.metric(10) }

    /// The header, lines and image, top to bottom, as heights.
    private var items: [CGFloat] {
        (continuesGroup ? [] : [Self.nameHeight]) + lines.map { _ in Self.lineHeight }
            + [imageSize.map { InterfaceScale.metric($0.height) }].compactMap(\.self)
    }

    var height: CGFloat {
        let content = (continuesGroup ? 0 : Self.headerTop)
            + items.reduce(0, +) + Self.itemSpacing * CGFloat(items.count - 1)
        return continuesGroup ? content : max(MessageRowLayoutMetrics.avatarDiameter, content)
    }

    func draw(atTop top: CGFloat, textWidth: CGFloat) {
        var originY = top
        if !continuesGroup {
            NSColor.labelColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(ovalIn: CGRect(
                x: MessageRowLayoutMetrics.horizontalInset,
                y: top,
                width: MessageRowLayoutMetrics.avatarDiameter,
                height: MessageRowLayoutMetrics.avatarDiameter
            )).fill()
            originY += Self.headerTop
            Self.bar(
                CGRect(x: Self.textX, y: originY, width: InterfaceScale.metric(nameWidth), height: Self.nameHeight),
                color: NSColor.labelColor.withAlphaComponent(0.7)
            )
            let timestampHeight = InterfaceScale.metric(8)
            Self.bar(
                CGRect(
                    x: Self.textX + InterfaceScale.metric(nameWidth + 8),
                    y: originY + (Self.nameHeight - timestampHeight) / 2,
                    width: InterfaceScale.metric(44),
                    height: timestampHeight
                ),
                color: NSColor.secondaryLabelColor.withAlphaComponent(0.5)
            )
            originY += Self.nameHeight + Self.itemSpacing
        }
        for fraction in lines {
            Self.bar(
                CGRect(x: Self.textX, y: originY, width: textWidth * fraction, height: Self.lineHeight),
                color: NSColor.labelColor.withAlphaComponent(0.55)
            )
            originY += Self.lineHeight + Self.itemSpacing
        }
        if let imageSize {
            NSColor.labelColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(
                roundedRect: CGRect(
                    x: Self.textX,
                    y: originY,
                    width: min(InterfaceScale.metric(imageSize.width), textWidth),
                    height: InterfaceScale.metric(imageSize.height)
                ),
                xRadius: InterfaceScale.metric(8),
                yRadius: InterfaceScale.metric(8)
            ).fill()
        }
    }

    private static func bar(_ frame: CGRect, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
    }
}
