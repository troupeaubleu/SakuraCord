import AppKit
import SakuraCordModels

extension NativeMessageTimelineCoordinator {
    func refreshServerInvites(_ reference: ServerInviteReference?) {
        guard let canvas, let scrollView, layoutWidth > 0 else { return }
        relayRows(
            where: { item in
                guard let row = item.messageRow, !row.serverInvites.isEmpty || row.message.hasActivityInstance else { return false }
                return reference.map { row.serverInvites.contains($0) } ?? true
            },
            on: canvas, in: scrollView,
            layout: { layout(for: $0, width: layoutWidth) }
        )
    }
}

extension NativeTimelineCanvasView {
    func activateInvite(_ card: NativeTimelineInviteLayout, message: Message) {
        guard let model else { return }
        if let instanceID = card.content?.activityInstanceID {
            guard !card.isDisabled else { return }
            model.startAccountChildTask(account: model.accountSession()) { model, _ in
                await model.joinActivityInstance(instanceID, from: message)
            }
            return
        }
        guard let reference = card.reference else { return }
        guard !card.isDisabled else { return }
        if let invite = card.invite, invite.activity != nil, model.presentationGuild(invite.guildID) != nil {
            model.startAccountChildTask(account: model.accountSession()) { model, _ in
                await model.joinActivityInvite(invite)
            }
            return
        }
        if card.invite?.unsupportedJoinReason != nil,
           card.invite.flatMap({ model.serverRailGuildsByID[$0.guildID] }) == nil {
            NSWorkspace.shared.open(reference.url)
            return
        }
        let session = model.accountSession()
        model.startAccountChildTask(account: session) { model, _ in
            _ = await model.activateServerInvite(reference, messageID: message.id)
        }
    }

    func appendInviteAccessibility(message: Message, to children: inout [Any], layout: NativeTimelineRowLayout,
                                   rowIndex: Int, parent: NSAccessibilityElement) {
        for card in layout.inviteRegions {
            let group = accessibilityElement(role: .group,
                label: (card.content?.activity == nil ? "Server invite. " : "Activity. ") + card.accessibilityLabel,
                frame: accessibilityChildFrame(card.frame, rowIndex: rowIndex), parent: parent)
            var controls: [Any] = []
            if card.buttonFrame.height > 0 {
                let button = accessibilityElement(role: .button, label: card.buttonTitle,
                    frame: accessibilityChildFrame(card.buttonFrame, rowIndex: rowIndex), parent: group) { [weak self] in
                    guard !card.isDisabled else { return false }
                    self?.activateInvite(card, message: message)
                    return true
                }
                button.setAccessibilityEnabled(!card.isDisabled)
                controls.append(button)
            }
            group.setAccessibilityChildren(controls)
            children.append(group)
        }
    }
}
