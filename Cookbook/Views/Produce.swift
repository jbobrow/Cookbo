import SwiftUI

/// The hand-drawn produce from cookbo.app, drawn like the app icon. They drop
/// in beside things and rock when tapped, the same as on the website.
enum Produce: String, CaseIterable {
    case lemon, carrot, tomato, garlic, eggplant, broccoli
    case avocado, strawberry, mushroom, radish, peapod, corn

    var image: Image { Image("Produce/\(rawValue)") }

    /// Height next to text, in ems, so each piece looks its own size beside
    /// the others (a pea pod is slimmer than a head of broccoli).
    var height: CGFloat {
        switch self {
        case .lemon: 0.62
        case .carrot: 0.6
        case .tomato: 0.84
        case .garlic: 0.86
        case .eggplant: 0.64
        case .broccoli: 0.9
        case .avocado: 0.9
        case .strawberry: 0.76
        case .mushroom: 0.8
        case .radish: 0.9
        case .peapod: 0.5
        case .corn: 0.56
        }
    }

    /// The width of the drawing over its height.
    var aspectRatio: CGFloat {
        switch self {
        case .lemon: 64.0 / 44
        case .carrot: 96.0 / 40
        case .tomato: 64.0 / 60
        case .garlic: 52.0 / 60
        case .eggplant: 84.0 / 44
        case .broccoli: 56.0 / 60
        case .avocado: 52.0 / 62
        case .strawberry: 52.0 / 58
        case .mushroom: 56.0 / 58
        case .radish: 50.0 / 62
        case .peapod: 90.0 / 40
        case .corn: 92.0 / 44
        }
    }

    /// How far it's turned as it falls, and how it comes to rest, in degrees.
    var spin: Double {
        switch self {
        case .lemon: -28
        case .carrot: 32
        case .tomato: -40
        case .garlic: 26
        case .eggplant: -36
        case .broccoli: 30
        case .avocado: -30
        case .strawberry: 34
        case .mushroom: -26
        case .radish: 28
        case .peapod: -34
        case .corn: 30
        }
    }

    var rest: Double {
        switch self {
        case .lemon: -7
        case .carrot: 5
        case .tomato: 0
        case .garlic: 3
        case .eggplant: -6
        case .broccoli: -3
        case .avocado: -4
        case .strawberry: 5
        case .mushroom: 3
        case .radish: -5
        case .peapod: -5
        case .corn: 4
        }
    }

    /// The long pieces, which rock a little less and a little slower, as if
    /// heavier. A side gets at most one, so every handful fits.
    var isLong: Bool { [.carrot, .eggplant, .peapod, .corn].contains(self) }

    /// Two different handfuls of `count` pieces, one for each side of a title.
    static func handfuls(of count: Int) -> (left: [Produce], right: [Produce]) {
        var pool = allCases.shuffled()
        func pick() -> [Produce] {
            var side: [Produce] = []
            for piece in pool where side.count < count {
                if piece.isLong && side.contains(where: \.isLong) { continue }
                side.append(piece)
            }
            pool.removeAll { side.contains($0) }
            return side
        }
        return (pick(), pick())
    }
}

/// One piece of produce. It drops in whenever `dropped` turns true, and rocks
/// where it sits when tapped, tipping toward the side that was poked.
struct ProduceView: View {
    let produce: Produce
    /// Height in points of a piece one em tall; each piece scales from this.
    let em: CGFloat
    var delay: Double = 0
    /// Drops in when this turns true, so a piece on a page that isn't showing
    /// yet waits to be seen.
    var dropped = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion: Motion = .drop
    @State private var trigger = 0
    @State private var visible = false
    @State private var push: Double = 1
    @State private var swing: Double = 1

    private enum Motion { case drop, rock }

    private struct Pose {
        var y: CGFloat = 0
        var angle: Double
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var opacity: Double = 1
    }

    private var height: CGFloat { em * produce.height }

    var body: some View {
        produce.image
            .resizable()
            .aspectRatio(produce.aspectRatio, contentMode: .fit)
            .frame(width: height * produce.aspectRatio, height: height)
            .keyframeAnimator(initialValue: Pose(angle: produce.rest), trigger: trigger) { content, pose in
                content
                    .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
                    .rotationEffect(.degrees(pose.angle), anchor: .bottom)
                    .offset(y: pose.y)
                    .opacity(pose.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.y) { yFrames }
                KeyframeTrack(\.angle) { angleFrames }
                KeyframeTrack(\.scaleX) { scaleFrames(squash: [1.1, 0.96, 1.04]) }
                KeyframeTrack(\.scaleY) { scaleFrames(squash: [0.8, 1.05, 0.95]) }
                KeyframeTrack(\.opacity) { opacityFrames }
            }
            .opacity(visible ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard visible, !reduceMotion else { return }
                push = location.x < height * produce.aspectRatio / 2 ? -1 : 1
                // No two rocks alike
                swing = Double.random(in: 0.55...1.35) * (produce.isLong ? 0.75 : 1)
                motion = .rock
                trigger += 1
            }
            .onAppear { if dropped { drop() } }
            .onChange(of: dropped) { _, isDropped in
                if isDropped { drop() }
            }
            .accessibilityHidden(true)
    }

    private func drop() {
        visible = true
        guard !reduceMotion else { return }
        motion = .drop
        trigger += 1
    }

    // A drop falls from above turning, lands with a squash, hops once and
    // settles, timed like the website's `drop` keyframes. A rock only tips
    // it back and forth.

    private static let dropTime = 0.95
    private var rockTime: Double { produce.isLong ? 1.0 : 0.8 }

    @KeyframeTrackContentBuilder<CGFloat>
    private var yFrames: some KeyframeTrackContent<CGFloat> {
        let total = Self.dropTime
        if motion == .drop {
            MoveKeyframe(-260)
            LinearKeyframe(-260, duration: delay)
            CubicKeyframe(0, duration: total * 0.52)
            CubicKeyframe(-height * 0.14, duration: total * 0.16)
            CubicKeyframe(0, duration: total * 0.14)
            LinearKeyframe(0, duration: total * 0.18)
        } else {
            LinearKeyframe(0, duration: rockTime)
        }
    }

    @KeyframeTrackContentBuilder<Double>
    private var angleFrames: some KeyframeTrackContent<Double> {
        let total = Self.dropTime
        let rest = produce.rest
        let tip = push * swing
        if motion == .drop {
            MoveKeyframe(produce.spin)
            LinearKeyframe(produce.spin, duration: delay)
            CubicKeyframe(rest * 0.5, duration: total * 0.52)
            CubicKeyframe(rest * 1.4, duration: total * 0.16)
            CubicKeyframe(rest, duration: total * 0.14)
            LinearKeyframe(rest, duration: total * 0.18)
        } else {
            CubicKeyframe(rest + 9 * tip, duration: rockTime * 0.18)
            CubicKeyframe(rest - 7 * tip, duration: rockTime * 0.2)
            CubicKeyframe(rest + 4 * tip, duration: rockTime * 0.2)
            CubicKeyframe(rest - 1.5 * tip, duration: rockTime * 0.2)
            CubicKeyframe(rest, duration: rockTime * 0.22)
        }
    }

    /// The squash on landing, the stretch of the hop, and the settle.
    @KeyframeTrackContentBuilder<CGFloat>
    private func scaleFrames(squash: [CGFloat]) -> some KeyframeTrackContent<CGFloat> {
        let total = Self.dropTime
        if motion == .drop {
            MoveKeyframe(1)
            LinearKeyframe(1, duration: delay + total * 0.4)
            CubicKeyframe(squash[0], duration: total * 0.12)
            CubicKeyframe(squash[1], duration: total * 0.16)
            CubicKeyframe(squash[2], duration: total * 0.14)
            CubicKeyframe(1, duration: total * 0.18)
        } else {
            LinearKeyframe(1, duration: rockTime)
        }
    }

    @KeyframeTrackContentBuilder<Double>
    private var opacityFrames: some KeyframeTrackContent<Double> {
        if motion == .drop {
            MoveKeyframe(0)
            LinearKeyframe(0, duration: delay)
            LinearKeyframe(1, duration: Self.dropTime * 0.06)
        } else {
            LinearKeyframe(1, duration: rockTime)
        }
    }
}

/// A word with a handful of produce on either side, sitting on its baseline,
/// as in the website's title.
struct ProduceTitle: View {
    let title: String
    let fontSize: CGFloat
    /// Pieces a side. Two fit beside "Cookbo" on the narrowest phone.
    var perSide = 3
    var dropped = true

    @State private var handfuls = Produce.handfuls(of: 3)

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: fontSize * 0.14) {
            side(Array(handfuls.left.prefix(perSide)), delays: [0.30, 0.16, 0.04], alignment: .trailing)
            Text(title)
                .font(.system(size: fontSize, weight: .bold))
                .fixedSize()
            side(Array(handfuls.right.prefix(perSide)), delays: [0.10, 0.24, 0.36], alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }

    /// Both sides take the same width, so the title stays centered whatever
    /// lands beside it. The pieces nearest the title land first.
    private func side(_ pieces: [Produce], delays: [Double], alignment: Alignment) -> some View {
        HStack(alignment: .bottom, spacing: -fontSize * 0.1) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                // The left side's nearest piece is its last, so it takes the
                // last delays
                let delay = alignment == .trailing ? delays[delays.count - pieces.count + index] : delays[index]
                ProduceView(produce: piece, em: fontSize, delay: delay, dropped: dropped)
            }
        }
        .frame(width: fontSize * (perSide == 3 ? 3.2 : 2.1), alignment: alignment)
        .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
    }
}

#Preview {
    VStack(spacing: 40) {
        ProduceTitle(title: "Cookbo", fontSize: 44)
        ProduceTitle(title: "Cookbo", fontSize: 34, perSide: 2)
        HStack(alignment: .bottom) {
            ForEach(Produce.allCases, id: \.self) { ProduceView(produce: $0, em: 40) }
        }
    }
    .padding()
}
