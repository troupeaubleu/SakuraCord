import AppKit
import SakuraCordModels

extension NativeTimelineRowPainter {
    private static let unavailableInviteSymbol = NSImage(systemSymbolName: "envelope.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(paletteColors: [.systemRed]))

    static func inviteCard(_ card: NativeTimelineInviteLayout, bubbleRegion: NativeTimelineBubbleRegion? = nil,
                           isHovered: Bool, pressProgress: CGFloat, isModalPreview: Bool = false) {
        if card.content?.activity != nil {
            activityCard(card, bubbleRegion: bubbleRegion, isHovered: isHovered, pressProgress: pressProgress)
            return
        }
        let bubble = card.integratesWithBubble ? bubbleRegion : nil
        let outgoing = bubble?.isOutgoing == true
        let foreground = NativeTimelineBubbleDrawing.foregroundColor(for: bubble)
        let secondary = NativeTimelineBubbleDrawing.secondaryForegroundColor(for: bubble)
        if let bubble {
            bubbleIntegratedSection(card.frame, bubbleRegion: bubble, accentColor: card.content?.brandColor,
                drawsTopSeparator: card.drawsTopSeparator)
        } else {
            // A server card sits on the embed's flat, borderless surface.
            (isModalPreview ? NSColor.windowBackgroundColor : DiscordEmbedPalette.embedFill).setFill()
            NSBezierPath(concentricRoundedRect: card.frame, cornerRadius: isModalPreview ? 0 : NativeTimelineInviteLayout.cornerRadius).fill()
        }
        inviteIdentityMedia(card, bubbleRegion: bubble, isModalPreview: isModalPreview)
        if let avatarFrame = card.inviterAvatarFrame, let url = card.content?.inviter?.avatarURL,
           let image = MediaImageStore.shared.stillImage(for: .media(url, maximumPixelDimension: 32)) {
            drawImage(image, in: avatarFrame, cornerRadius: avatarFrame.width / 2, fillsFrame: true)
        }
        for label in card.labels {
            let color: NSColor = label.overlaysBanner ? .white.withAlphaComponent(label.secondary ? 0.8 : 1)
                : card.isUnavailable && label.bold && !outgoing ? .systemRed : label.secondary ? secondary : foreground
            attributedText(NativeTimelineAttributedTextBox(label.attributedText(color: color)), in: label.frame, model: nil)
        }
        for (index, dot) in card.countDots.enumerated() {
            (index == 0 && card.content?.onlineCount != nil ? NSColor.systemGreen : .white.withAlphaComponent(0.8)).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
        for trait in card.traits {
            foreground.withAlphaComponent(outgoing ? 0.16 : 0.08).setFill()
            NSBezierPath(concentricRoundedRect: trait.frame, cornerRadius: DiscordRichMessageMetrics.cardMediaCornerRadius).fill()
            var textFrame = trait.frame.insetBy(dx: InterfaceScale.metric(8), dy: InterfaceScale.metric(4))
            if trait.value.emoji != nil || trait.value.emojiURL != nil {
                let emojiFrame = CGRect(x: textFrame.minX, y: textFrame.minY + InterfaceScale.metric(2), width: InterfaceScale.metric(16), height: InterfaceScale.metric(16))
                if let url = trait.value.emojiURL, let image = MediaImageStore.shared.stillImage(for: .media(url, maximumPixelDimension: 32)) {
                    drawImage(image, in: emojiFrame, cornerRadius: 0, fillsFrame: false)
                } else if let emoji = trait.value.emoji {
                    let value = NativeEmojiCatalogMetadata.value(forShortcode: emoji) ?? emoji
                    drawImage(ComponentUnicodeEmojiRenderer.image(for: value), in: emojiFrame, cornerRadius: 0, fillsFrame: false)
                }
                textFrame.origin.x += InterfaceScale.metric(20)
                textFrame.size.width -= InterfaceScale.metric(20)
            }
            text(trait.value.label, in: textFrame, font: .interfaceSystemFont(ofSize: 14), color: foreground)
        }
        if card.buttonFrame.height > 0, !isModalPreview {
            gradientButton(
                title: card.buttonTitle, frame: card.buttonFrame,
                isHovered: isHovered && !card.isDisabled,
                pressProgress: card.isDisabled ? 0 : pressProgress,
                colors: [outgoing ? .sakuraCordLabelOnAccentColor : .sakuraCordAccentColor],
                foreground: outgoing ? .sakuraCordAccentColor : .sakuraCordLabelOnAccentColor, isEnabled: !card.isDisabled
            )
        }
    }

    private static func inviteIdentityMedia(
        _ card: NativeTimelineInviteLayout, bubbleRegion bubble: NativeTimelineBubbleRegion?, isModalPreview: Bool
    ) {
        let outgoing = bubble?.isOutgoing == true
        let iconRadius = DiscordRichMessageMetrics.cardMediaCornerRadius
        let iconShape = NSBezierPath(concentricRoundedRect: card.iconFrame, cornerRadius: iconRadius)
        if let invite = card.content {
            // The banner follows the card's top corners, or is rounded as
            // media in a bubble, and fades to dark where the header text sits.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(
                concentricRoundedRect: bubble == nil ? card.frame : card.bannerFrame,
                cornerRadius: bubble != nil ? iconRadius : isModalPreview ? 0 : NativeTimelineInviteLayout.cornerRadius
            ).addClip()
            NSBezierPath(rect: card.bannerFrame).addClip()
            if let url = invite.bannerURL,
               let image = MediaImageStore.shared.stillImage(for: .media(url, maximumPixelDimension: 1_024)) {
                drawImage(image, in: card.bannerFrame, cornerRadius: 0, fillsFrame: true)
            } else {
                inviteGradient(card.gradientColor ?? 0x242424, in: card.bannerFrame)
            }
            let fade = CGRect(x: card.bannerFrame.minX, y: card.iconFrame.minY - InterfaceScale.metric(32),
                              width: card.bannerFrame.width, height: card.bannerFrame.maxY - card.iconFrame.minY + InterfaceScale.metric(32))
            NSGradient(starting: .black.withAlphaComponent(0), ending: .black.withAlphaComponent(0.6))?.draw(in: fade, angle: 90)
            NSGraphicsContext.restoreGraphicsState()
            if let url = invite.iconURL, let image = MediaImageStore.shared.stillImage(for: .media(url, maximumPixelDimension: 128)) {
                NSGraphicsContext.saveGraphicsState()
                iconShape.addClip()
                drawImage(image, in: card.iconFrame, cornerRadius: 0, fillsFrame: true)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor.black.setFill()
                iconShape.fill()
                let initials = invite.name.split(separator: " ").prefix(3).compactMap(\.first).map(String.init).joined()
                text(
                    initials,
                    in: card.iconFrame.insetBy(dx: InterfaceScale.metric(3), dy: (card.iconFrame.height - InterfaceScale.metric(26)) / 2),
                    font: .interfaceSystemFont(ofSize: 20, weight: .semibold),
                    color: .white,
                    alignment: .center
                )
            }
        } else if card.isUnavailable || bubble != nil {
            (outgoing ? NSColor.sakuraCordLabelOnAccentColor.withAlphaComponent(0.14) : NSColor.systemRed.withAlphaComponent(card.isUnavailable ? 0.12 : 0.04)).setFill()
            iconShape.fill()
            if bubble != nil {
                systemSymbol(card.isUnavailable ? "envelope.badge.fill" : card.error == nil ? "clock" : "exclamationmark.circle",
                    in: card.iconFrame, color: outgoing ? .sakuraCordLabelOnAccentColor : card.isUnavailable ? .systemRed : .secondaryLabelColor,
                    inset: InterfaceScale.metric(7))
            } else if let image = unavailableInviteSymbol {
                drawImage(image, in: card.iconFrame.insetBy(dx: InterfaceScale.metric(11), dy: InterfaceScale.metric(11)), cornerRadius: 0, fillsFrame: false)
            }
        }
    }

    /// The first-party profile gradient brightens the preset by 1.75 CIELAB steps (31.5 L*).
    /// Server tag cards pass their own top-left-origin context.
    static func inviteGradient(_ hex: UInt32, in frame: CGRect, context: CGContext? = nil) {
        guard let context = context ?? NSGraphicsContext.current?.cgContext, frame.height > 0 else { return }
        let base = NSColor(hex: hex)
        let bright = NSColor(SakuraCordThemeRGB(base).cielabBrightened(by: 31.5))
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: [bright.cgColor, base.cgColor] as CFArray, locations: [0.2065, 0.8516]) else { return }
        context.saveGState()
        context.clip(to: frame)
        context.translateBy(x: frame.minX + frame.width * 0.501, y: frame.minY + frame.height * 1.2705)
        context.scaleBy(x: frame.width * 1.0543, y: frame.height * 1.2705)
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: 1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }
}
