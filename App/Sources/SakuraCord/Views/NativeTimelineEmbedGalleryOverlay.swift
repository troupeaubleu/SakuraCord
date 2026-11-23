import AppKit
import SakuraCordModels

@MainActor
final class NativeTimelineEmbedGalleryOverlay: NSView {
    private let scrollView = EmbedGalleryScrollView()
    private let documentView = EmbedGalleryDocumentView()
    private let leftButton = EmbedGalleryScrollButton(direction: .left)
    private let rightButton = EmbedGalleryScrollButton(direction: .right)
    private var boundsObserver: NSObjectProtocol?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isApplyingProgrammaticScroll = false
    private let scrollTicker = DisplayLinkTicker()

    private(set) var gallery: NativeTimelineRowLayout.EmbedRegion.Gallery
    private(set) var concealedItemIDs: Set<String>
    var onScrollOffsetChange: ((CGFloat) -> Void)?
    var onOpenItem: ((NativeTimelineRowLayout.EmbedRegion.GalleryItem) -> Void)?
    var onRevealItem: ((String) -> Void)?
    var onContextMenu: ((NativeTimelineRowLayout.EmbedRegion.GalleryItem, NSEvent) -> NSMenu?)?

    override var isFlipped: Bool { true }

    var currentScrollOffsetX: CGFloat {
        scrollView.contentView.bounds.minX
    }

    var scrollProgress: CGFloat {
        let maxOffset = max(0, gallery.contentWidth - bounds.width)
        guard maxOffset > 0.5 else { return 0 }
        return min(max(currentScrollOffsetX / maxOffset, 0), 1)
    }

    func scrollToProgress(_ progress: CGFloat) {
        let maxOffset = max(0, gallery.contentWidth - bounds.width)
        guard maxOffset > 0.5 else { return }
        scrollToOffset(maxOffset * min(max(progress, 0), 1))
    }

    init(
        frame: CGRect,
        gallery: NativeTimelineRowLayout.EmbedRegion.Gallery,
        scrollOffsetX: CGFloat,
        concealedItemIDs: Set<String> = []
    ) {
        self.gallery = gallery
        self.concealedItemIDs = concealedItemIDs
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = gallery.cornerRadius
        layer?.maskedCorners = gallery.maskedCorners

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.timelineScrollViewProvider = { [weak self] in
            self?.superview?.enclosingScrollView
        }
        scrollView.onHorizontalScrollWheel = { [weak self] in
            self?.scrollTicker.stop()
        }
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true

        documentView.onOpenItem = { [weak self] item in self?.onOpenItem?(item) }
        documentView.onRevealItem = { [weak self] itemID in
            self?.onRevealItem?(itemID)
        }
        documentView.onContextMenu = { [weak self] item, event in
            self?.onContextMenu?(item, event)
        }

        leftButton.onPress = { [weak self] in
            self?.stepScroll(direction: -1)
        }
        rightButton.onPress = { [weak self] in
            self?.stepScroll(direction: 1)
        }

        addSubview(scrollView)
        addSubview(leftButton)
        addSubview(rightButton)

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.isApplyingProgrammaticScroll {
                    self.onScrollOffsetChange?(self.scrollView.contentView.bounds.minX)
                }
                self.updateScrollButtons()
            }
        }

        apply(
            gallery: gallery,
            scrollOffsetX: scrollOffsetX,
            concealedItemIDs: concealedItemIDs,
            forceReload: true
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        scrollTicker.stop()
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        layoutScrollButtons()
        updateScrollButtons()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateScrollButtons()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateScrollButtons()
    }

    func update(
        gallery: NativeTimelineRowLayout.EmbedRegion.Gallery,
        scrollOffsetX: CGFloat,
        concealedItemIDs: Set<String> = []
    ) {
        let presentationChanged = self.concealedItemIDs != concealedItemIDs
            || abs(self.gallery.opacity - gallery.opacity) >= 0.01
            || self.gallery.items.count != gallery.items.count
            || abs(self.gallery.viewportFrame.width - gallery.viewportFrame.width) >= 0.5
            || abs(self.gallery.viewportFrame.height - gallery.viewportFrame.height) >= 0.5
            || abs(self.gallery.cornerRadius - gallery.cornerRadius) >= 0.5
            || self.gallery.maskedCorners != gallery.maskedCorners
            || abs(self.gallery.contentWidth - gallery.contentWidth) >= 0.5
            || abs(self.gallery.leadingButtonInset - gallery.leadingButtonInset) >= 0.5
            || abs(self.gallery.trailingButtonInset - gallery.trailingButtonInset) >= 0.5
            || zip(self.gallery.items, gallery.items).contains {
                $0.id != $1.id
                    || $0.frame != $1.frame
                    || $0.mediaKey != $1.mediaKey
                    || $0.isVideo != $1.isVideo
                    || $0.isSpoiler != $1.isSpoiler
            }
        guard presentationChanged else { return }
        apply(
            gallery: gallery,
            scrollOffsetX: scrollOffsetX,
            concealedItemIDs: concealedItemIDs,
            forceReload: true
        )
    }

    func refreshMedia() {
        documentView.needsDisplay = true
    }

    func itemFrameInOverlay(forEmbedID embedID: String) -> CGRect? {
        guard let item = gallery.items.first(where: { $0.id == embedID }) else { return nil }
        let frame = convert(item.frame, from: documentView)
        return frame.intersects(bounds) ? frame : nil
    }

    private func apply(
        gallery: NativeTimelineRowLayout.EmbedRegion.Gallery,
        scrollOffsetX: CGFloat,
        concealedItemIDs: Set<String>,
        forceReload: Bool
    ) {
        self.gallery = gallery
        self.concealedItemIDs = concealedItemIDs
        layer?.cornerRadius = gallery.cornerRadius
        layer?.maskedCorners = gallery.maskedCorners
        if forceReload {
            documentView.frame = CGRect(
                x: 0,
                y: 0,
                width: max(bounds.width, gallery.contentWidth),
                height: max(1, bounds.height)
            )
            documentView.items = gallery.items
            documentView.concealedItemIDs = concealedItemIDs
            documentView.opacity = gallery.opacity
            documentView.needsDisplay = true

            let maxOffset = max(0, gallery.contentWidth - bounds.width)
            let clamped = min(max(0, scrollOffsetX), maxOffset)
            if abs(scrollView.contentView.bounds.minX - clamped) >= 0.5 {
                isApplyingProgrammaticScroll = true
                scrollView.contentView.scroll(to: NSPoint(x: clamped, y: 0))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                isApplyingProgrammaticScroll = false
            }
        }
        layoutScrollButtons()
        updateScrollButtons()
    }

    private func stepScroll(direction: CGFloat) {
        let maxOffset = max(0, gallery.contentWidth - bounds.width)
        guard maxOffset > 0 else { return }
        let startX = scrollView.contentView.bounds.minX
        let step = max(bounds.width * 0.78, InterfaceScale.metric(160))
        let target = min(max(0, startX + direction * step), maxOffset)
        scrollToOffset(target)
    }

    private func scrollToOffset(_ target: CGFloat) {
        let startX = scrollView.contentView.bounds.minX
        guard abs(target - startX) > 0.5 else { return }
        if !AppMotionPolicy.animatesUncategorized || window == nil {
            scrollTicker.stop()
            scrollView.contentView.scroll(to: NSPoint(x: target, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            onScrollOffsetChange?(scrollView.contentView.bounds.minX)
            updateScrollButtons()
            return
        }
        let startTime = ProcessInfo.processInfo.systemUptime
        let duration: TimeInterval = 0.22
        scrollTicker.start(on: self) { [weak self] in
            guard let self else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - startTime
            let raw = min(max(elapsed / duration, 0), 1)
            let eased = 1 - pow(1 - raw, 3)
            let offsetX = startX + (target - startX) * eased
            self.scrollView.contentView.scroll(to: NSPoint(x: offsetX, y: 0))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            if raw >= 1 {
                self.scrollTicker.stop()
            }
        }
    }

    private func layoutScrollButtons() {
        let buttonSize = InterfaceScale.metric(28)
        let inset = InterfaceScale.metric(8)
        let buttonY = ((bounds.height - buttonSize) / 2).rounded()
        leftButton.frame = CGRect(
            x: gallery.leadingButtonInset + inset,
            y: buttonY,
            width: buttonSize,
            height: buttonSize
        )
        let rightX = max(
            leftButton.frame.maxX + inset,
            bounds.width - gallery.trailingButtonInset - inset - buttonSize
        )
        rightButton.frame = CGRect(x: rightX, y: buttonY, width: buttonSize, height: buttonSize)
    }

    private func updateScrollButtons() {
        let currentX = scrollView.contentView.bounds.minX
        let maxX = max(0, gallery.contentWidth - bounds.width)
        leftButton.isHidden = !isHovered || currentX <= 1
        rightButton.isHidden = !isHovered || currentX >= maxX - 1
    }
}

@MainActor
private final class EmbedGalleryScrollView: NSScrollView {
    var timelineScrollViewProvider: (() -> NSScrollView?)?
    var onHorizontalScrollWheel: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            (timelineScrollViewProvider?() ?? nextResponder)?.scrollWheel(with: event)
        } else {
            onHorizontalScrollWheel?()
            super.scrollWheel(with: event)
        }
    }
}

@MainActor
private final class EmbedGalleryDocumentView: NSView {
    var items: [NativeTimelineRowLayout.EmbedRegion.GalleryItem] = [] {
        didSet { updateHoveredSpoiler(at: nil) }
    }
    var concealedItemIDs: Set<String> = []
    var opacity: CGFloat = 1
    var onOpenItem: ((NativeTimelineRowLayout.EmbedRegion.GalleryItem) -> Void)?
    var onRevealItem: ((String) -> Void)?
    var onContextMenu: ((NativeTimelineRowLayout.EmbedRegion.GalleryItem, NSEvent) -> NSMenu?)?

    private var pressedItemID: String?
    private var pressedLocation = CGPoint.zero
    private var hoveredSpoilerItemID: String?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hovered = items.first { $0.frame.contains(point) && concealedItemIDs.contains($0.id) }?.id
        updateHoveredSpoiler(at: hovered)
    }

    override func mouseExited(with event: NSEvent) {
        updateHoveredSpoiler(at: nil)
    }

    private func updateHoveredSpoiler(at nextID: String?) {
        guard hoveredSpoilerItemID != nextID else { return }
        if let previous = hoveredSpoilerItemID,
           let item = items.first(where: { $0.id == previous })
        {
            setNeedsDisplay(item.frame)
        }
        hoveredSpoilerItemID = nextID
        if let nextID,
           let item = items.first(where: { $0.id == nextID })
        {
            setNeedsDisplay(item.frame)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        defer { context?.restoreGState() }
        if opacity < 1 {
            context?.setAlpha(opacity)
            context?.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        for item in items where item.frame.intersects(dirtyRect) {
            let isConcealed = concealedItemIDs.contains(item.id)
            NativeTimelineSpoilerCover.draw(
                covering: isConcealed,
                in: item.frame,
                cornerRadius: item.cornerRadius
            ) {
                NativeTimelineRowPainter.drawMediaSurface(
                    in: item.frame,
                    cornerRadius: item.cornerRadius,
                    backdrop: NativeTimelineSemanticColor.opacity(.secondaryLabelColor, 0.10),
                    image: MediaImageStore.shared.stillImage(for: item.mediaKey),
                    fillsFrame: true,
                    placeholder: item.placeholder,
                    fallbackSymbol: item.isVideo ? ("film", InterfaceScale.metric(30)) : nil,
                    isVideo: item.isVideo
                )
            }
            if isConcealed, hoveredSpoilerItemID == item.id {
                drawSpoilerHoverOverlay(in: item.frame, cornerRadius: item.cornerRadius)
            }
        }
        if opacity < 1 {
            context?.endTransparencyLayer()
        }
    }

    private func drawSpoilerHoverOverlay(in frame: CGRect, cornerRadius: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(concentricRoundedRect: frame, cornerRadius: cornerRadius).addClip()
        SpoilerAppearance.mediaHoverTintColor.setFill()
        frame.fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let pill = NativeTimelineSpoilerCover.pill(in: frame, isHovered: true) else { return }
        SpoilerAppearance.hoveredPillOverlayColor.setFill()
        NSBezierPath(
            roundedRect: pill.frame,
            xRadius: pill.frame.height / 2,
            yRadius: pill.frame.height / 2
        ).fill()
        pill.label.draw(
            in: SpoilerAppearance.labelFrame(
                in: pill.frame,
                measuredLabelHeight: pill.label.size().height
            )
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressedLocation = point
        pressedItemID = items.first(where: { $0.frame.contains(point) })?.id
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedItemID = nil }
        guard let pressedItemID else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - pressedLocation.x
        let dy = point.y - pressedLocation.y
        guard dx * dx + dy * dy <= 36,
              let item = items.first(where: { $0.id == pressedItemID && $0.frame.contains(point) })
        else { return }
        if concealedItemIDs.contains(item.id) {
            onRevealItem?(item.id)
        } else {
            onOpenItem?(item)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let item = items.first(where: { $0.frame.contains(point) }) else {
            return super.menu(for: event)
        }
        return onContextMenu?(item, event) ?? super.menu(for: event)
    }
}

@MainActor
private final class EmbedGalleryScrollButton: NSGlassEffectView {
    enum Direction {
        case left
        case right

        var systemSymbolName: String {
            switch self {
            case .left: "chevron.left"
            case .right: "chevron.right"
            }
        }
    }

    var onPress: (() -> Void)?
    private let button = NSButton()

    init(direction: Direction) {
        super.init(frame: .zero)
        style = .regular
        cornerRadius = InterfaceScale.metric(14)
        effectIsInteractive = true

        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        button.title = ""
        button.image = NSImage(
            systemSymbolName: direction.systemSymbolName,
            accessibilityDescription: direction == .left ? "Previous images" : "Next images"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: InterfaceScale.metric(12), weight: .semibold)
        )
        button.contentTintColor = .labelColor
        button.autoresizingMask = [.width, .height]
        button.target = self
        button.action = #selector(handlePress)
        contentView = button
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        cornerRadius = min(bounds.width, bounds.height) / 2
        button.frame = bounds
    }

    @objc
    private func handlePress() {
        onPress?()
    }
}

extension NativeTimelineEmbedLayout {
    struct HorizontalGalleryEntry {
        let embed: MessageEmbed
        let image: MessageEmbedMedia
        let url: URL
    }

    static func horizontalGalleryHeight(forWidth width: CGFloat) -> CGFloat {
        min(InterfaceScale.metric(220), max(InterfaceScale.metric(120), (width * 0.54).rounded()))
    }

    static func horizontalGallery(
        for region: NativeTimelineRowLayout.EmbedRegion,
        entries: [HorizontalGalleryEntry],
        mediaFrame: CGRect,
        bareLeadingInset: CGFloat = 0,
        leadingButtonInset: CGFloat = 0,
        trailingInset: CGFloat = 0,
        trailingButtonInset: CGFloat = 0
    ) -> NativeTimelineRowLayout.EmbedRegion.Gallery {
        let leadingInset: CGFloat
        let resolvedTrailingInset: CGFloat
        let viewportFrame: CGRect
        let galleryCornerRadius: CGFloat
        let maskedCorners: CACornerMask
        if region.kind == .card {
            // A card's gallery scrolls from the edge of its accent bar.
            let minX = region.frame.minX + DiscordRichMessageMetrics.embedAccentBarWidth
            viewportFrame = CGRect(
                x: minX,
                y: mediaFrame.minY,
                width: max(mediaFrame.width, region.frame.maxX - minX),
                height: mediaFrame.height
            )
            leadingInset = max(0, mediaFrame.minX - minX)
            resolvedTrailingInset = leadingInset
            galleryCornerRadius = 0
            maskedCorners = [
                .layerMinXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMinYCorner,
                .layerMaxXMaxYCorner,
            ]
        } else {
            viewportFrame = mediaFrame
            leadingInset = bareLeadingInset
            resolvedTrailingInset = trailingInset
            galleryCornerRadius = region.mediaCornerRadius
            if region.kind == .bareMedia, bareLeadingInset > 0 || trailingInset > 0 {
                var corners: CACornerMask = []
                if bareLeadingInset <= 0 {
                    corners.insert([.layerMinXMinYCorner, .layerMinXMaxYCorner])
                }
                if trailingInset <= 0 {
                    corners.insert([.layerMaxXMinYCorner, .layerMaxXMaxYCorner])
                }
                maskedCorners = corners
            } else {
                maskedCorners = [
                    .layerMinXMinYCorner,
                    .layerMinXMaxYCorner,
                    .layerMaxXMinYCorner,
                    .layerMaxXMaxYCorner,
                ]
            }
        }
        let tileViewportWidth = region.kind == .bareMedia
            ? max(InterfaceScale.metric(180), mediaFrame.width - bareLeadingInset - resolvedTrailingInset)
            : mediaFrame.width
        let frames = horizontalGalleryFrames(
            medias: entries.map(\.image),
            viewportWidth: tileViewportWidth,
            height: mediaFrame.height,
            spacing: InterfaceScale.metric(4),
            leadingInset: leadingInset
        )
        let items = zip(entries, frames).map { entry, frame in
            NativeTimelineRowLayout.EmbedRegion.GalleryItem(
                id: entry.embed.id,
                frame: frame,
                url: entry.url,
                mediaKey: .media(entry.url),
                placeholder: .init(entry.image),
                cornerRadius: region.mediaCornerRadius,
                accessibilityLabel: entry.image.description ?? entry.embed.title
            )
        }
        let contentWidth = (frames.last?.maxX ?? (leadingInset + tileViewportWidth)) + resolvedTrailingInset
        return NativeTimelineRowLayout.EmbedRegion.Gallery(
            viewportFrame: viewportFrame,
            contentWidth: contentWidth,
            leadingButtonInset: region.kind == .card ? 0 : leadingButtonInset,
            trailingButtonInset: region.kind == .card ? 0 : trailingButtonInset,
            cornerRadius: galleryCornerRadius,
            maskedCorners: maskedCorners,
            items: items
        )
    }

    static func horizontalGalleryFrames(
        medias: [MessageEmbedMedia],
        viewportWidth: CGFloat,
        height: CGFloat,
        spacing: CGFloat,
        leadingInset: CGFloat = 0
    ) -> [CGRect] {
        let aspectRatios: [CGFloat] = medias.map { media in
            if let width = media.width, let mediaHeight = media.height,
               width > 0, mediaHeight > 0
            {
                return CGFloat(width) / CGFloat(mediaHeight)
            }
            return 1
        }
        return horizontalGalleryFrames(
            aspectRatios: aspectRatios,
            viewportWidth: viewportWidth,
            height: height,
            spacing: spacing,
            leadingInset: leadingInset
        )
    }

    static func horizontalGalleryFrames(
        aspectRatios: [CGFloat],
        viewportWidth: CGFloat,
        height: CGFloat,
        spacing: CGFloat,
        leadingInset: CGFloat = 0
    ) -> [CGRect] {
        let minimumTileWidth = InterfaceScale.metric(16)
        let maximumTileWidth = max(
            minimumTileWidth,
            min(viewportWidth, max(InterfaceScale.metric(80), (viewportWidth * 0.78).rounded()))
        )
        var cursorX = leadingInset
        var result: [CGRect] = []
        result.reserveCapacity(aspectRatios.count)
        for aspect in aspectRatios {
            let safeAspect = aspect > 0 ? aspect : 1
            let tileWidth = min(maximumTileWidth, max(minimumTileWidth, (height * safeAspect).rounded()))
            result.append(CGRect(x: cursorX, y: 0, width: tileWidth, height: height))
            cursorX += tileWidth + spacing
        }
        return result
    }
}

@MainActor
final class NativeTimelineGalleryPageIndicatorView: NSView {
    private var itemCount: Int
    private var scrollProgress: CGFloat
    private var pillLayers: [CALayer] = []
    var onSelectProgress: ((CGFloat) -> Void)?

    override var isFlipped: Bool { true }

    init(
        frame: CGRect,
        itemCount: Int,
        scrollProgress: CGFloat
    ) {
        self.itemCount = max(1, itemCount)
        self.scrollProgress = min(max(scrollProgress, 0), 1)
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityRole(.valueIndicator)
        setAccessibilityLabel("Media scroll position")
        updateAccessibilityValue()
        rebuildPillLayers()
        layoutPillLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(itemCount: Int, scrollProgress: CGFloat) {
        let clampedCount = max(1, itemCount)
        let clampedProgress = min(max(scrollProgress, 0), 1)
        let countChanged = self.itemCount != clampedCount
        let progressChanged = abs(self.scrollProgress - clampedProgress) >= 0.0005
        guard countChanged || progressChanged else { return }
        self.itemCount = clampedCount
        self.scrollProgress = clampedProgress
        if countChanged {
            rebuildPillLayers()
        }
        layoutPillLayers()
        updateAccessibilityValue()
    }

    override func layout() {
        super.layout()
        layoutPillLayers()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layoutPillLayers()
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let hitPadding = InterfaceScale.metric(5)
        for (index, item) in pillMetrics().enumerated()
            where item.frame.insetBy(dx: -hitPadding, dy: -hitPadding).contains(local)
        {
            onSelectProgress?(itemCount > 1 ? CGFloat(index) / CGFloat(itemCount - 1) : 0)
            return
        }
        super.mouseDown(with: event)
    }

    private func rebuildPillLayers() {
        pillLayers.forEach { $0.removeFromSuperlayer() }
        pillLayers.removeAll()
        guard itemCount > 1, let rootLayer = layer else { return }
        for _ in 0 ..< itemCount {
            let pill = CALayer()
            rootLayer.addSublayer(pill)
            pillLayers.append(pill)
        }
    }

    private func layoutPillLayers() {
        guard !pillLayers.isEmpty else { return }
        let metrics = pillMetrics()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (index, pill) in pillLayers.enumerated() where metrics.indices.contains(index) {
                let item = metrics[index]
                pill.frame = item.frame
                pill.cornerRadius = item.frame.height / 2
                pill.backgroundColor = NSColor.labelColor.withAlphaComponent(item.alpha).cgColor
            }
            CATransaction.commit()
        }
    }

    private func pillMetrics() -> [(frame: CGRect, alpha: CGFloat)] {
        let pillHeight = InterfaceScale.metric(6)
        let inactiveWidth = InterfaceScale.metric(14)
        let activeWidth = InterfaceScale.metric(28)
        let spacing = InterfaceScale.metric(5)
        let inactiveAlpha: CGFloat = 0.14
        let activeAlpha: CGFloat = 0.45
        let pillY = ((bounds.height - pillHeight) / 2).rounded()
        let continuousPosition = scrollProgress * CGFloat(max(1, itemCount - 1))
        var pillX: CGFloat = 0
        var result: [(frame: CGRect, alpha: CGFloat)] = []
        result.reserveCapacity(itemCount)
        for index in 0 ..< itemCount {
            let weight = max(0, 1 - abs(continuousPosition - CGFloat(index)))
            let width = inactiveWidth + (activeWidth - inactiveWidth) * weight
            let alpha = inactiveAlpha + (activeAlpha - inactiveAlpha) * weight
            result.append((CGRect(x: pillX, y: pillY, width: width, height: pillHeight), alpha))
            pillX += width + spacing
        }
        return result
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue("\(Int((scrollProgress * 100).rounded())) percent")
    }
}

/// Opening, revealing and menus for the items of a scrolling gallery.
extension NativeTimelineCanvasView {
    func openAttachmentGalleryItem(attachmentID: String, rowIdentifier: NativeMessageTimelineItem.Identifier) {
        guard !pointer.overlayBlocksInteractions, !glideBlocksPointer,
              let rowIndex = items.firstIndex(where: { $0.identifier == rowIdentifier }),
              case let .message(row, _, _) = items[rowIndex],
              let attachment = row.message.attachments.first(where: { $0.id == attachmentID })
        else { return }
        _ = activateAttachment(attachment, in: row.message, rowIndex: rowIndex)
    }

    func revealAttachmentGalleryItem(
        attachmentID: String,
        rowIdentifier: NativeMessageTimelineItem.Identifier
    ) {
        guard !pointer.overlayBlocksInteractions, !glideBlocksPointer else { return }
        guard let rowIndex = items.firstIndex(where: { $0.identifier == rowIdentifier }),
              case let .message(row, _, _) = items[rowIndex]
        else { return }
        let revealKey = NativeTimelineComponentRevealKey.attachment(
            messageID: row.id,
            attachmentID: attachmentID
        )
        reveal(revealKey, rowIndex: rowIndex)
    }

    func attachmentGalleryContextMenu(
        forAttachmentID attachmentID: String,
        rowIdentifier: NativeMessageTimelineItem.Identifier
    ) -> NSMenu? {
        guard !pointer.overlayBlocksInteractions, !glideBlocksPointer else { return nil }
        guard let rowIndex = items.firstIndex(where: { $0.identifier == rowIdentifier }),
              case let .message(row, _, _) = items[rowIndex]
        else { return nil }
        let interactionMode = MessageOutboxPresentation.interactionMode(for: row.message)
        guard interactionMode.allowsMessageContextMenu,
              interactionMode.allowsMediaContextMenu,
              let attachment = row.message.attachments.first(where: { $0.id == attachmentID }),
              attachment.mediaKind == .image || attachment.mediaKind == .animatedImage
        else { return nil }
        if attachment.isSpoiler {
            let componentID = NativeTimelineComponentRevealKey.attachmentComponentID(attachment.id)
            guard spoilerRevealStore.isMediaRevealed(
                NativeTimelineComponentRevealKey(
                    messageID: row.message.id,
                    componentID: componentID
                )
            ) else { return nil }
        }
        return MediaImageContextMenuBuilder.make(
            actions: imageContextMenuActions(for: RichMediaItem(attachment))
        )
    }

    func openEmbedGalleryItem(
        _ item: NativeTimelineRowLayout.EmbedRegion.GalleryItem,
        rowIdentifier: NativeMessageTimelineItem.Identifier
    ) {
        guard !pointer.overlayBlocksInteractions, !glideBlocksPointer,
              let rowIndex = items.firstIndex(where: { $0.identifier == rowIdentifier }),
              case let .message(row, _, _) = items[rowIndex]
        else { return }
        if !openEmbedMediaInViewer(id: item.id, message: row.message, rowIndex: rowIndex) {
            NSWorkspace.shared.open(item.url)
        }
    }

    func embedGalleryContextMenu(
        forEmbedID embedID: String,
        rowIdentifier: NativeMessageTimelineItem.Identifier
    ) -> NSMenu? {
        guard !pointer.overlayBlocksInteractions, !glideBlocksPointer else { return nil }
        guard let rowIndex = items.firstIndex(where: { $0.identifier == rowIdentifier }),
              case let .message(row, _, _) = items[rowIndex]
        else { return nil }
        let interactionMode = MessageOutboxPresentation.interactionMode(for: row.message)
        guard interactionMode.allowsMessageContextMenu,
              interactionMode.allowsMediaContextMenu,
              let embed = row.message.embeds.first(where: { $0.id == embedID }),
              let imageItem = RichMediaItem(
                  embed: embed,
                  attachments: row.message.attachments
              ),
              case .image = imageItem.kind
        else { return nil }
        if imageItem.isSpoiler {
            let componentID = NativeTimelineComponentRevealKey.attachmentComponentID(imageItem.id)
            guard spoilerRevealStore.isMediaRevealed(
                NativeTimelineComponentRevealKey(
                    messageID: row.message.id,
                    componentID: componentID
                )
            ) else { return nil }
        }
        return MediaImageContextMenuBuilder.make(
            actions: imageContextMenuActions(for: imageItem)
        )
    }
}

/// Keeps a scrolling gallery's overlay and page indicator over each
/// visible gallery.
extension NativeTimelineCanvasView {
    fileprivate struct DesiredGalleryOverlay {
        let key: EmbedGalleryOverlayKey
        let frame: CGRect
        let gallery: NativeTimelineRowLayout.EmbedRegion.Gallery
        let concealedItemIDs: Set<String>
        let hasUploadRings: Bool
        let pageIndicatorFrame: CGRect?
    }

    func reconcileEmbedGalleryOverlays() {
        let viewport = enclosingScrollView?.documentVisibleRect ?? visibleRect
        guard window != nil,
              viewport.width > 0,
              viewport.height > 0,
              !items.isEmpty,
              !layouts.isEmpty,
              let firstVisibleRow = rowIndex(at: max(0, viewport.minY))
        else {
            removeEmbedGalleryOverlays()
            return
        }

        let desired = desiredEmbedGalleryOverlays(startingAt: firstVisibleRow, viewport: viewport)
        let desiredKeys = Set(desired.map(\.key))
        let desiredIndicatorKeys = Set(desired.compactMap { $0.pageIndicatorFrame != nil ? $0.key : nil })
        for key in Array(embedGalleryOverlays.keys) where !desiredKeys.contains(key) {
            if let overlay = embedGalleryOverlays.removeValue(forKey: key) {
                embedGalleryScrollOffsets[key] = overlay.currentScrollOffsetX
                overlay.removeFromSuperview()
            }
        }
        for key in Array(galleryPageIndicators.keys) where !desiredIndicatorKeys.contains(key) {
            galleryPageIndicators.removeValue(forKey: key)?.removeFromSuperview()
        }

        for item in desired {
            let key = item.key
            let overlay: NativeTimelineEmbedGalleryOverlay
            if let existing = embedGalleryOverlays[key] {
                overlay = existing
                if existing.frame != item.frame {
                    existing.frame = item.frame
                }
                overlay.update(
                    gallery: item.gallery,
                    scrollOffsetX: embedGalleryScrollOffsets[key] ?? existing.currentScrollOffsetX,
                    concealedItemIDs: item.concealedItemIDs
                )
            } else {
                overlay = NativeTimelineEmbedGalleryOverlay(
                    frame: item.frame,
                    gallery: item.gallery,
                    scrollOffsetX: embedGalleryScrollOffsets[key] ?? 0,
                    concealedItemIDs: item.concealedItemIDs
                )
                addSubview(overlay, positioned: .below, relativeTo: mediaViewerHost)
                embedGalleryOverlays[key] = overlay
            }
            configureEmbedGalleryOverlay(overlay, for: item)
            if let indicatorFrame = item.pageIndicatorFrame {
                let indicator: NativeTimelineGalleryPageIndicatorView
                if let existing = galleryPageIndicators[key] {
                    indicator = existing
                    if existing.frame != indicatorFrame {
                        existing.frame = indicatorFrame
                    }
                    existing.update(itemCount: item.gallery.items.count, scrollProgress: overlay.scrollProgress)
                } else {
                    indicator = NativeTimelineGalleryPageIndicatorView(
                        frame: indicatorFrame,
                        itemCount: item.gallery.items.count,
                        scrollProgress: overlay.scrollProgress
                    )
                    addSubview(indicator, positioned: .below, relativeTo: mediaViewerHost)
                    galleryPageIndicators[key] = indicator
                }
                indicator.onSelectProgress = { [weak overlay] progress in
                    overlay?.scrollToProgress(progress)
                }
            }
        }
    }

    private func desiredEmbedGalleryOverlays(
        startingAt firstVisibleRow: Int,
        viewport: CGRect
    ) -> [DesiredGalleryOverlay] {
        var desired: [DesiredGalleryOverlay] = []
        var index = firstVisibleRow
        while items.indices.contains(index),
              layouts.indices.contains(index),
              displayedRowOrigin(at: index) < viewport.maxY
        {
            let identifier = items[index].identifier
            if !hidesRowForSendTransition(identifier),
               case let .message(row, _, _) = items[index]
            {
                let rowOrigin = displayedRowOrigin(at: index)
                let pageIndicator = layouts[index].galleryPageIndicator
                if let gallery = layouts[index].attachmentGallery {
                    let overlayFrame = gallery.viewportFrame.offsetBy(dx: 0, dy: rowOrigin)
                    if overlayFrame.intersects(viewport) {
                        let indicatorFrame = pageIndicator?.scope == .attachments
                            ? pageIndicator?.frame.offsetBy(dx: 0, dy: rowOrigin)
                            : nil
                        desired.append(
                            DesiredGalleryOverlay(
                                key: EmbedGalleryOverlayKey(row: identifier, scope: .attachments),
                                frame: overlayFrame,
                                gallery: gallery,
                                concealedItemIDs: concealedAttachmentGalleryItemIDs(
                                    gallery: gallery,
                                    messageID: row.message.id
                                ),
                                hasUploadRings: !layouts[index].uploadRings.isEmpty,
                                pageIndicatorFrame: indicatorFrame
                            )
                        )
                    }
                }
                let concealedEmbeds = NativeTimelineSpoilerConcealmentPolicy.concealedEmbeds(
                    in: row.message,
                    store: spoilerRevealStore
                )
                for region in layouts[index].embedRegions {
                    guard concealedEmbeds[region.embedID] == nil,
                          let gallery = region.gallery
                    else { continue }
                    let overlayFrame = gallery.viewportFrame.offsetBy(dx: 0, dy: rowOrigin)
                    guard overlayFrame.intersects(viewport) else { continue }
                    let indicatorFrame = pageIndicator?.scope == .embed(region.embedID)
                        ? pageIndicator?.frame.offsetBy(dx: 0, dy: rowOrigin)
                        : nil
                    desired.append(
                        DesiredGalleryOverlay(
                            key: EmbedGalleryOverlayKey(row: identifier, scope: .embed(region.embedID)),
                            frame: overlayFrame,
                            gallery: gallery,
                            concealedItemIDs: [],
                            hasUploadRings: false,
                            pageIndicatorFrame: indicatorFrame
                        )
                    )
                }
            }
            index += 1
        }
        return desired
    }

    private func concealedAttachmentGalleryItemIDs(
        gallery: NativeTimelineRowLayout.EmbedRegion.Gallery,
        messageID: MessageID
    ) -> Set<String> {
        Set(gallery.items.compactMap { item -> String? in
            guard item.isSpoiler,
                  spoilerRevealStore.isConcealed(
                      messageID: messageID,
                      contentID: NativeTimelineComponentRevealKey.attachmentComponentID(item.id),
                      isSpoiler: true
                  )
            else { return nil }
            return item.id
        })
    }

    private func configureEmbedGalleryOverlay(
        _ overlay: NativeTimelineEmbedGalleryOverlay,
        for item: DesiredGalleryOverlay
    ) {
        let key = item.key
        overlay.onScrollOffsetChange = { [weak self, weak overlay] offsetX in
            guard let self else { return }
            self.embedGalleryScrollOffsets[key] = offsetX
            if let overlay {
                self.galleryPageIndicators[key]?.update(
                    itemCount: overlay.gallery.items.count,
                    scrollProgress: overlay.scrollProgress
                )
            }
            if item.hasUploadRings {
                self.reconcileUploadRings()
            }
        }
        switch key.scope {
        case .attachments:
            overlay.onOpenItem = { [weak self] galleryItem in
                self?.openAttachmentGalleryItem(attachmentID: galleryItem.id, rowIdentifier: key.row)
            }
            overlay.onRevealItem = { [weak self] attachmentID in
                self?.revealAttachmentGalleryItem(
                    attachmentID: attachmentID,
                    rowIdentifier: key.row
                )
            }
            overlay.onContextMenu = { [weak self] galleryItem, _ in
                self?.attachmentGalleryContextMenu(
                    forAttachmentID: galleryItem.id,
                    rowIdentifier: key.row
                )
            }
        case .embed:
            overlay.onOpenItem = { [weak self] galleryItem in
                self?.openEmbedGalleryItem(galleryItem, rowIdentifier: key.row)
            }
            overlay.onRevealItem = nil
            overlay.onContextMenu = { [weak self] galleryItem, _ in
                self?.embedGalleryContextMenu(
                    forEmbedID: galleryItem.id,
                    rowIdentifier: key.row
                )
            }
        }
    }

    func positionEmbedGalleryOverlays() {
        var removed: [EmbedGalleryOverlayKey] = []
        for (key, overlay) in embedGalleryOverlays {
            guard let index = items.firstIndex(where: { $0.identifier == key.row }),
                  layouts.indices.contains(index),
                  let gallery: NativeTimelineRowLayout.EmbedRegion.Gallery = switch key.scope {
            case .attachments:
                layouts[index].attachmentGallery
            case let .embed(embedID):
                layouts[index].embedRegions.first(where: { $0.embedID == embedID })?.gallery
            } else {
                embedGalleryScrollOffsets[key] = overlay.currentScrollOffsetX
                overlay.removeFromSuperview()
                removed.append(key)
                continue
            }
            overlay.frame = gallery.viewportFrame.offsetBy(dx: 0, dy: displayedRowOrigin(at: index))
            if let indicator = galleryPageIndicators[key],
               let indicatorFrame = layouts[index].galleryPageIndicator?.frame
            {
                indicator.frame = indicatorFrame.offsetBy(dx: 0, dy: displayedRowOrigin(at: index))
            }
        }
        for key in removed {
            embedGalleryOverlays[key] = nil
            galleryPageIndicators.removeValue(forKey: key)?.removeFromSuperview()
        }
    }

    func refreshEmbedGalleryMedia(for identifiers: Set<NativeMessageTimelineItem.Identifier>) {
        guard !embedGalleryOverlays.isEmpty else { return }
        for (key, overlay) in embedGalleryOverlays where identifiers.contains(key.row) {
            overlay.refreshMedia()
        }
    }

    func removeEmbedGalleryOverlays() {
        for (key, overlay) in embedGalleryOverlays {
            embedGalleryScrollOffsets[key] = overlay.currentScrollOffsetX
            overlay.removeFromSuperview()
        }
        embedGalleryOverlays.removeAll()
        for indicator in galleryPageIndicators.values {
            indicator.removeFromSuperview()
        }
        galleryPageIndicators.removeAll()
    }
}
