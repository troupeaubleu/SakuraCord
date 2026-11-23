import AppKit
import CoreText
import SakuraCordModels

struct NativeServerCardContent {
    let guildID: GuildID?
    let name: String
    let iconURL: URL?
    /// The server's 16:9 banner, where one is known.
    var bannerURL: URL?
    let inviter: User?
    let brandColor: UInt32?
    let description: String?
    let traits: [ServerInvite.Trait]
    let memberCount: Int?
    let onlineCount: Int?
    var activity: ServerInvite.Activity?
    /// Server name shown beside an Activity's voice channel.
    let guildName: String
    /// The running instance an application's launch message offers to join.
    var activityInstanceID: String?

    init(invite: ServerInvite) {
        guildID = invite.guildID
        activity = invite.activity
        guildName = invite.name
        name = invite.activity?.name ?? invite.name
        iconURL = invite.activity?.iconURL ?? invite.iconURL
        inviter = invite.inviter
        brandColor = invite.brandColor
        description = invite.description
        traits = invite.traits
        memberCount = invite.memberCount
        onlineCount = invite.onlineCount
    }

    /// The card an application posts when someone launches its Activity.
    init(activityMessage message: Message) {
        guildID = message.guildID
        activityInstanceID = message.activityInstanceID
        activity = ServerInvite.Activity(
            applicationID: ApplicationID(rawValue: message.author.id.rawValue), name: message.author.displayName,
            iconURL: message.author.avatarURL
        )
        guildName = ""
        name = message.author.displayName
        iconURL = message.author.avatarURL
        inviter = message.interactionMetadata?.user
        brandColor = nil
        description = nil
        traits = []
        memberCount = nil
        onlineCount = nil
    }

    init(profile: GuildProfile, iconURL: URL?, adaptiveColor: UInt32? = nil) {
        guildID = profile.id
        activity = nil
        guildName = profile.name
        name = profile.name
        self.iconURL = iconURL
        bannerURL = profile.bannerURL
        inviter = nil
        brandColor = profile.brandColor ?? adaptiveColor
        description = profile.description
        traits = profile.traits.map { .init(label: $0.label, emoji: $0.emojiName, emojiURL: $0.emojiURL) }
        memberCount = profile.memberCount
        onlineCount = profile.onlineCount
    }
}

struct NativeTimelineInviteLayout {
    /// Server cards share the embed card's shape.
    static var cornerRadius: CGFloat { DiscordRichMessageMetrics.cardCornerRadius }
    private static var spacing: CGFloat { InterfaceScale.metric(12) }

    struct Label {
        var text: String
        var frame: CGRect
        var size: CGFloat = 14
        var bold = false
        var secondary = false
        var lineHeight: CGFloat = 20
        /// Set on the banner, where text is white over its fade.
        var overlaysBanner = false

        func attributedText(color: NSColor) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = InterfaceScale.metric(lineHeight)
            paragraph.maximumLineHeight = InterfaceScale.metric(lineHeight)
            paragraph.lineBreakMode = .byWordWrapping
            return NSAttributedString(string: text, attributes: [
                .font: NSFont.interfaceSystemFont(ofSize: size, weight: bold ? .semibold : .regular),
                .foregroundColor: color, .paragraphStyle: paragraph
            ])
        }
    }
    struct Trait {
        var value: ServerInvite.Trait
        var frame: CGRect
    }
    let reference: ServerInviteReference?
    let componentID: String
    let frame: CGRect
    let bannerFrame: CGRect
    let iconFrame: CGRect
    let inviterAvatarFrame: CGRect?
    let gradientColor: UInt32?
    let countDots: [CGRect]
    let labels: [Label]
    let traits: [Trait]
    let buttonFrame: CGRect
    let invite: ServerInvite?
    let content: NativeServerCardContent?
    let buttonTitle: String
    let isDisabled: Bool
    let isUnavailable: Bool
    let error: String?
    let integratesWithBubble: Bool
    var drawsTopSeparator = false
    /// The speaker before an Activity card's channel line.
    var symbolFrame: CGRect?
    /// Faces of the people in the Activity, as Discord stacks them.
    var playerAvatars: [(frame: CGRect, url: URL?)] = []

    var accessibilityLabel: String {
        (labels.map(\.text) + (content?.traits.map(\.label) ?? [])).joined(separator: ". ")
    }

    init(reference: ServerInviteReference? = nil, index: Int, origin: CGPoint, maximumWidth: CGFloat,
         source: AppModel?, isOwnMessage: Bool, fillsWidth: Bool = false, preview: NativeServerCardContent? = nil,
         integratesWithBubble: Bool = false) {
        self.reference = reference
        self.integratesWithBubble = integratesWithBubble
        componentID = "server-invite:\(index):\(reference?.code ?? preview?.guildID?.description ?? "")"
        let entry = reference.flatMap { source?.inviteEntry(for: $0) }
        invite = entry?.isUnavailable == true ? nil : entry?.invite
        content = preview ?? invite.map(NativeServerCardContent.init)
        gradientColor = content?.brandColor ?? entry?.adaptiveColor
        isUnavailable = entry?.isUnavailable == true
        error = entry?.error ?? invite.flatMap {
            source?.presentationGuild($0.guildID) == nil ? $0.unsupportedJoinReason : nil
        }
        (buttonTitle, isDisabled) = Self.action(for: invite, entry: entry, source: source)
        let width = fillsWidth || integratesWithBubble ? maximumWidth : min(InterfaceScale.metric(360), maximumWidth)
        let inset = integratesWithBubble ? 0 : InterfaceScale.metric(16)
        let originX = origin.x + inset, inner = max(1, width - inset * 2)
        var labels: [Label] = []
        var traits: [Trait] = []
        var inviterAvatar: CGRect?
        var countDots: [CGRect] = []
        var cursor = origin.y + inset
        let showsButton = preview == nil && !isUnavailable
        let buttonWidth = showsButton ? Self.buttonWidth(buttonTitle, maximum: inner) : 0
        if let invite = content {
            // The banner is the card's header: a 5:2 crop of the 16:9 image
            // carries the server's identity and the button along its faded lower edge.
            bannerFrame = CGRect(x: origin.x, y: origin.y, width: width, height: (width * 2 / 5).rounded())
            let padding = Self.spacing, iconSize = InterfaceScale.metric(48)
            iconFrame = CGRect(x: origin.x + padding, y: bannerFrame.maxY - padding - iconSize, width: iconSize, height: iconSize)
            buttonFrame = CGRect(x: bannerFrame.maxX - padding - buttonWidth, y: iconFrame.midY - Self.buttonHeight / 2,
                                 width: buttonWidth, height: showsButton ? Self.buttonHeight : 0)
            let headerX = iconFrame.maxX + Self.spacing
            let headerWidth = max(1, bannerFrame.maxX - padding - headerX - (showsButton ? buttonWidth + Self.spacing : 0))
            let nameHeight = Self.height(invite.name, width: headerWidth, size: 16, bold: true, lineHeight: 22)
            let countsHeight = invite.onlineCount == nil && invite.memberCount == nil ? 0 : InterfaceScale.metric(18)
            cursor = (iconFrame.midY - (nameHeight + countsHeight) / 2).rounded()
            labels.append(.init(text: invite.name, frame: CGRect(x: headerX, y: cursor, width: headerWidth, height: nameHeight),
                                size: 16, bold: true, lineHeight: 22, overlaysBanner: true))
            cursor += nameHeight
            Self.appendCounts(invite, originX: headerX, width: headerWidth, cursor: &cursor, labels: &labels, dots: &countDots)
            cursor = bannerFrame.maxY + max(0, inset - Self.spacing)
            if let description = invite.description, !description.isEmpty {
                cursor += Self.spacing
                let height = Self.height(description, width: inner, size: 14)
                labels.append(.init(text: description, frame: CGRect(x: originX, y: cursor, width: inner, height: height)))
                cursor += height
            }
            if !invite.traits.isEmpty {
                cursor += Self.spacing
                traits = Self.arrangeTraits(invite.traits, origin: CGPoint(x: originX, y: cursor), width: inner)
                cursor = traits.map(\.frame.maxY).max() ?? cursor
            }
            if self.invite != nil, let error {
                cursor += Self.spacing
                let height = Self.height(error, width: inner, size: 13)
                labels.append(.init(text: error, frame: CGRect(x: originX, y: cursor, width: inner, height: height), size: 13))
                cursor += height
            }
            inviterAvatar = Self.appendFooter(invite, currentUserID: source?.currentUserID, originX: originX, width: inner,
                                              cursor: &cursor, labels: &labels)
        } else {
            let title = isUnavailable ? "Invalid Invite" : entry?.error == nil ? "Loading invite…" : "Invite unavailable"
            let detail = isUnavailable ? (isOwnMessage ? "Try sending a new invite" : "Ask for a new invite") : entry?.error
            if !integratesWithBubble {
                labels.append(.init(text: isOwnMessage ? "You sent an invite, but" : "You've been invited, but",
                                    frame: CGRect(x: originX, y: cursor, width: inner, height: InterfaceScale.metric(20)), secondary: true))
                cursor += InterfaceScale.metric(28)
            }
            let iconSize = InterfaceScale.metric(integratesWithBubble ? 32 : 48)
            iconFrame = CGRect(x: originX, y: cursor, width: iconSize, height: iconSize)
            let detailX = isUnavailable || integratesWithBubble ? iconFrame.maxX + InterfaceScale.metric(12) : originX
            let detailWidth = max(1, originX + inner - detailX)
            labels.append(.init(text: title, frame: CGRect(x: detailX, y: cursor, width: detailWidth, height: InterfaceScale.metric(22)), size: 16, bold: true))
            cursor += InterfaceScale.metric(26)
            if let detail {
                let height = Self.height(detail, width: detailWidth, size: 14)
                labels.append(.init(text: detail, frame: CGRect(x: detailX, y: cursor, width: detailWidth, height: height), secondary: true))
                cursor += height
            }
            if isUnavailable || integratesWithBubble { cursor = max(cursor, iconFrame.maxY) }
            bannerFrame = .zero
            buttonFrame = CGRect(x: originX, y: cursor + Self.spacing, width: buttonWidth, height: showsButton ? Self.buttonHeight : 0)
            if showsButton { cursor = buttonFrame.maxY }
        }
        frame = CGRect(x: origin.x, y: origin.y, width: width, height: cursor + inset - origin.y)
        inviterAvatarFrame = inviterAvatar
        self.countDots = countDots
        self.labels = labels
        self.traits = traits
    }

    private static var buttonHeight: CGFloat { InterfaceScale.metric(32) }

    /// The accented pill fits its title, with room for the rounded ends.
    private static func buttonWidth(_ title: String, maximum: CGFloat) -> CGFloat {
        min(maximum, max(
            InterfaceScale.metric(80),
            ceil(NativeTimelineRowLayout.measuredTextWidth(title, font: NativeTimelineComponentButtonMetrics.font) + buttonHeight)
        ))
    }

    private static func appendCounts(_ invite: NativeServerCardContent, originX: CGFloat, width: CGFloat, cursor: inout CGFloat,
                                     labels: inout [Label], dots: inout [CGRect]) {
        var countX = originX
        for count in [invite.onlineCount.map { "\($0.formatted()) Online" },
                      invite.memberCount.map { "\($0.formatted()) \($0 == 1 ? "Member" : "Members")" }].compactMap(\.self) {
            dots.append(CGRect(x: countX, y: cursor + InterfaceScale.metric(5), width: InterfaceScale.metric(8), height: InterfaceScale.metric(8)))
            let textWidth = ceil((count as NSString).size(withAttributes: [.font: NSFont.interfaceSystemFont(ofSize: 13)]).width)
            let labelX = countX + InterfaceScale.metric(12)
            labels.append(.init(
                text: count,
                frame: CGRect(x: labelX, y: cursor, width: max(1, min(textWidth + 1, originX + width - labelX)), height: InterfaceScale.metric(18)),
                size: 13, secondary: true, lineHeight: 18, overlaysBanner: true
            ))
            countX += textWidth + InterfaceScale.metric(20)
        }
        if countX > originX { cursor += InterfaceScale.metric(18) }
    }

    /// Who sent the invite and when the server began, in small print at the end.
    private static func appendFooter(_ invite: NativeServerCardContent, currentUserID: UserID?, originX: CGFloat, width: CGFloat,
                                     cursor: inout CGFloat, labels: inout [Label]) -> CGRect? {
        let sender = invite.inviter.map { $0.id == currentUserID ? "You sent this invite" : "\($0.displayName) invited you" }
        let founded = invite.guildID.map { "Est. \($0.createdAt.formatted(.dateTime.month(.abbreviated).year()))" }
        let text = [sender, founded].compactMap(\.self).joined(separator: " · ")
        guard !text.isEmpty else { return nil }
        cursor += spacing
        let avatarSize = InterfaceScale.metric(16)
        let textX = originX + (sender == nil ? 0 : avatarSize + InterfaceScale.metric(6))
        let textHeight = height(text, width: max(1, originX + width - textX), size: 13, lineHeight: 18)
        labels.append(.init(text: text, frame: CGRect(x: textX, y: cursor, width: max(1, originX + width - textX), height: textHeight),
                            size: 13, secondary: true, lineHeight: 18))
        defer { cursor += textHeight }
        return sender == nil ? nil : CGRect(x: originX, y: cursor + InterfaceScale.metric(1), width: avatarSize, height: avatarSize)
    }

    static func action(for invite: ServerInvite?, entry: ServerInvitePresentationStore.Entry?,
                       content: NativeServerCardContent? = nil, source: AppModel?) -> (String, Bool) {
        if let instanceID = content?.activityInstanceID { return source?.activityInstanceAction(instanceID) ?? ("Join", true) }
        if let invite, invite.activity != nil, let source, source.presentationGuild(invite.guildID) != nil {
            if source.isInActivityInvite(invite) { return ("Joined", true) }
            let label = source.activityPlayers(reference: invite.reference, instanceID: nil).isEmpty ? "Play" : "Join"
            return (label, source.activityInviteChannel(invite) == nil)
        }
        if let invite, source?.isLeavingInviteGuild(invite.guildID) == true { return ("Leaving…", true) }
        if let invite, source?.isJoiningInviteGuild(invite.guildID) == true { return ("Joining…", true) }
        if let member = invite.flatMap({ source?.presentationGuild($0.guildID) }) {
            return (member.isUnavailable ? "Server unavailable" : "Go to Server", member.isUnavailable)
        }
        if invite?.unsupportedJoinReason != nil { return ("Open in Discord", false) }
        if invite?.requiresApplication == true { return ("Apply to Join", false) }
        return (invite != nil ? "Join Server" : entry?.error != nil ? "Try Again" : "Loading…",
                entry?.isLoading != false && invite == nil)
    }

    private static func arrangeTraits(_ values: [ServerInvite.Trait], origin: CGPoint, width: CGFloat) -> [Trait] {
        var regions: [Trait] = []
        var cursorX = origin.x
        var cursorY = origin.y
        let traitHeight = InterfaceScale.metric(28)
        let gap = InterfaceScale.metric(4)
        for trait in values.prefix(5) {
            let labelWidth = (trait.label as NSString).size(withAttributes: [.font: NSFont.interfaceSystemFont(ofSize: 14)]).width
            let traitWidth = min(width, ceil(labelWidth) + InterfaceScale.metric(16) + (trait.emoji != nil || trait.emojiURL != nil ? InterfaceScale.metric(20) : 0))
            if cursorX + traitWidth > origin.x + width, cursorX > origin.x { cursorX = origin.x; cursorY += traitHeight + gap }
            regions.append(.init(value: trait, frame: CGRect(x: cursorX, y: cursorY, width: traitWidth, height: traitHeight)))
            cursorX += traitWidth + gap
        }
        return regions
    }

    static func height(_ text: String, width: CGFloat, size: CGFloat, bold: Bool = false, lineHeight: CGFloat = 20) -> CGFloat {
        let value = Label(text: text, frame: .zero, size: size, bold: bold, lineHeight: lineHeight).attributedText(color: .labelColor)
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(value), CFRange(), nil,
                                                                  CGSize(width: width, height: .greatestFiniteMagnitude), nil).height
        let line = InterfaceScale.metric(lineHeight)
        return max(line, ceil(measured / line) * line)
    }
}
