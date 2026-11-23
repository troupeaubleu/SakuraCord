import SakuraCordModels
import SwiftUI

struct GuildIconView: View {
    let name: String
    let iconURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    var animates = true
    var isSelected = false
    var loadsImage = true
    let morphsInFolder: Bool
    let morphID: GuildID?
    let maximumPixelDimension: Int?
    @Environment(\.colorScheme) private var colorScheme

    init(
        name: String,
        iconURL: URL?,
        size: CGFloat,
        cornerRadius: CGFloat,
        animates: Bool = true,
        isSelected: Bool = false,
        loadsImage: Bool = true,
        morphsInFolder: Bool = false,
        morphID: GuildID? = nil,
        maximumPixelDimension: Int? = nil
    ) {
        self.name = name
        self.iconURL = iconURL
        self.size = size
        self.cornerRadius = cornerRadius
        self.animates = animates
        self.isSelected = isSelected
        self.loadsImage = loadsImage
        self.morphsInFolder = morphsInFolder
        self.morphID = morphID
        self.maximumPixelDimension = maximumPixelDimension
    }

    var body: some View {
        ZStack {
            if let iconURL {
                if loadsImage {
                    StaticRemoteImage(
                        url: iconURL,
                        maximumPixelDimension: requestedPixelDimension,
                        retriesFailedLoads: true
                    )
                    if animates,
                       UserAvatarPresentation
                        .shouldDecodeAnimation(for: iconURL)
                    {
                        AnimatedRemoteImage(
                            url: iconURL,
                            maximumPixelDimension: requestedPixelDimension
                        )
                        .transition(.identity)
                    }
                } else {
                    Color.clear
                }
            } else {
                iconShape
                    .fill(fallbackBackground)
                Text(initials)
                    .font(.system(size: size * 0.43, weight: .medium))
                    .foregroundStyle(isSelected ? .white : fallbackForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .clipShape(iconShape)
        .modifier(ServerFolderIconMorph(isEnabled: morphsInFolder, guildID: morphID))
        .frame(width: size, height: size)
        .accessibilityLabel(name.isEmpty ? "Unnamed Server" : name)
    }

    private var iconShape: GuildIconShape {
        GuildIconShape(cornerRadius: cornerRadius)
    }

    private var requestedPixelDimension: Int {
        max(1, maximumPixelDimension ?? Int((size * 2).rounded(.up)))
    }

    private var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        if words.count > 1 {
            return String(words.prefix(3).compactMap(\.first))
        }
        return words.first.map { String($0.prefix(2)) } ?? "?"
    }

    private var fallbackBackground: Color {
        if isSelected { return Color(hex: 0x6D7EEE) }
        return Color.secondary.opacity(0.16)
    }

    private var fallbackForeground: Color {
        Color(hex: colorScheme == .dark ? 0xF2F2F4 : 0x3C3D42)
    }
}

/// A rounded square with continuous corners that becomes an exact circle at
/// half its side. A folder's collapsed previews are circles and its open
/// icons rounded squares, and one shape whose radius animates morphs between
/// them; swapping a circle for a rounded rectangle jumped mid-animation.
nonisolated struct GuildIconShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let halfSide = min(rect.width, rect.height) / 2
        let radius = min(max(0, cornerRadius), halfSide)
        guard radius > 0 else { return Path(rect) }
        // Figma's corner smoothing, at the 60 % that matches Apple's
        // continuous corners, spends the room left beside each corner and
        // so runs out as the radius reaches half the side.
        let smoothing = min(0.6, halfSide / radius - 1)
        let cornerLength = min((1 + smoothing) * radius, halfSide)
        let arcAngle = CGFloat.pi / 2 * (1 - smoothing)
        let arcSpan = sin(arcAngle / 2) * radius * 2.squareRoot()
        let beta = CGFloat.pi / 4 * smoothing
        let handle = radius * tan((CGFloat.pi / 2 - arcAngle) / 4) * cos(beta)
        let offset = handle * tan(beta)
        let curveStep = (cornerLength - arcSpan - handle - offset) / 3
        // The arc's centre lies on the corner's diagonal, `radius` from both ends.
        let centerDepth = offset + arcSpan / 2 + (2 * radius * radius - arcSpan * arcSpan).squareRoot() / 2

        // Each corner, clockwise, with the direction of the edge running into
        // it; the edge leaving it turns a quarter clockwise from that.
        let corners: [(CGPoint, CGVector)] = [
            (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 1, dy: 0)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 0, dy: 1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: -1, dy: 0)),
            (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 0, dy: -1)),
        ]
        var path = Path()
        for (corner, along) in corners {
            let across = CGVector(dx: -along.dy, dy: along.dx)
            // A point `distance` along the incoming edge from where the corner
            // starts and `depth` in toward the shape.
            func point(_ distance: CGFloat, _ depth: CGFloat) -> CGPoint {
                let fromCorner = distance - cornerLength
                return CGPoint(
                    x: corner.x + along.dx * fromCorner + across.dx * depth,
                    y: corner.y + along.dy * fromCorner + across.dy * depth
                )
            }
            let curveEnd = curveStep * 3 + handle
            if path.isEmpty { path.move(to: point(0, 0)) } else { path.addLine(to: point(0, 0)) }
            path.addCurve(to: point(curveEnd, offset), control1: point(curveStep * 2, 0), control2: point(curveStep * 3, 0))
            // The arc between the two curves, as one cubic: it spans at most 90°.
            let arcHandle = 4 / 3 * tan(arcAngle / 4) * radius
            let center = point(cornerLength - centerDepth, centerDepth)
            let arcStart = point(curveEnd, offset)
            let arcEnd = point(cornerLength - offset, cornerLength - curveEnd)
            func tangent(at end: CGPoint, toward other: CGPoint) -> CGVector {
                let radial = CGVector(dx: end.x - center.x, dy: end.y - center.y)
                var tangent = CGVector(dx: -radial.dy / radius, dy: radial.dx / radius)
                if tangent.dx * (other.x - end.x) + tangent.dy * (other.y - end.y) < 0 {
                    tangent = CGVector(dx: -tangent.dx, dy: -tangent.dy)
                }
                return tangent
            }
            let startTangent = tangent(at: arcStart, toward: arcEnd)
            let endTangent = tangent(at: arcEnd, toward: arcStart)
            path.addCurve(
                to: arcEnd,
                control1: CGPoint(x: arcStart.x + startTangent.dx * arcHandle, y: arcStart.y + startTangent.dy * arcHandle),
                control2: CGPoint(x: arcEnd.x + endTangent.dx * arcHandle, y: arcEnd.y + endTangent.dy * arcHandle)
            )
            path.addCurve(
                to: point(cornerLength, cornerLength),
                control1: point(cornerLength, cornerLength - curveStep * 3),
                control2: point(cornerLength, cornerLength - curveStep * 2)
            )
        }
        path.closeSubpath()
        return path
    }
}
