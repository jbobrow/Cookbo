import SwiftUI

// MARK: - The fold

/// The iPhone Duo's fold, in the space of the view it was read in.
///
/// Held like a book, the crease is a spine between a left page and a right
/// one. Stood up like a laptop, it's the hinge between a screen and a counter.
/// Either way it's no place to put anything that has to be read whole.
struct Fold: Equatable {
    /// The band the fold takes, margins and all.
    var frame: CGRect

    /// A spine: the crease runs top to bottom.
    var isVertical: Bool { frame.height > frame.width }
}

/// How an iPhone Duo is being held. `.none` on everything that doesn't fold,
/// which is left exactly as it was.
enum DuoPose: Equatable {
    /// A phone, tablet or Mac that doesn't fold.
    case none
    /// Folded shut, on the outer screen: a phone held in one hand, the thumb
    /// along its right-hand edge.
    case closed
    /// Open, on the inner screen: flat, held like a book, or stood up like a
    /// laptop.
    case open
}

// MARK: - The camera band

/// The band down the right-hand edge of the Duo's outer screen, folded shut.
///
/// The system keeps it out of the safe area for the whole height of the
/// glass, though only its top is taken, by the camera. The rest is glass
/// with nothing on it, under the thumb that holds the phone. So the page
/// can be tall or wide:
///
/// - Tall: the page keeps to the safe area, beside the band's buttons.
/// - Wide: the page runs the full width, under them.
///
/// Either way the buttons of a page with a navigation bar stay where they
/// are, in the glass the system stands down the band. A page without one
/// keeps its own rail when tall.
///
/// The choice is kept between launches.
struct CameraStrip: Equatable {
    /// How wide the band is.
    var width: CGFloat
    /// The camera, in global coordinates.
    var occluded: CGRect
    /// Wide: the page runs the full width.
    var expanded: Bool

    /// How far the lens sits from the middle of the band. The system centres
    /// the buttons it stands in the band under the lens, and so does the rail.
    var lensOffset: CGFloat
    /// The height of the lens's middle, in global coordinates, for a row beside it.
    var lensMidY: CGFloat

    /// Tall: the band holds the buttons.
    var rails: Bool { !expanded }
}

extension EnvironmentValues {
    @Entry var duoPose: DuoPose = .none
    /// The camera band on the Duo's outer screen; nil on every other screen.
    @Entry var cameraStrip: CameraStrip? = nil
    /// Switches the outer screen between tall and wide.
    @Entry var toggleCameraStrip: () -> Void = {}

    /// The page is tall on the outer screen, so a page without a navigation
    /// bar stands its buttons in the rail.
    var controlsRailed: Bool { cameraStrip?.rails == true }
}

// MARK: - Reading the glass

extension View {
    /// Reads how an iPhone Duo is held and hands it down the whole app: the
    /// pose, the camera band when it's shut, and the way to switch the band
    /// between tall and wide. Does nothing on anything that doesn't fold.
    func readsDuo() -> some View {
        modifier(DuoReader())
    }
}

private struct DuoReader: ViewModifier {
    static let wideKey = "duoOuterScreenWide"

    @State private var hingePose: DuoPose = .none
    @State private var glass = Glass()
    /// Mirrors the stored choice so switching animates; @AppStorage writes
    /// land outside the withAnimation transaction.
    @State private var wide = UserDefaults.standard.bool(forKey: DuoReader.wideKey)

    /// What the window's geometry says about the glass.
    nonisolated struct Glass: Equatable {
        var hasCrease = false
        var trailingInset: CGFloat = 0
        var camera: CGRect = .zero
        var lensOffset: CGFloat = 0
        var lensMidY: CGFloat = 0
    }

    /// The hinge is asked first. A crease with no word from the hinge still
    /// means glass that folds, and that it's open: shut, the crease isn't on
    /// the screen that's lit.
    private var pose: DuoPose {
        hingePose == .none && glass.hasCrease ? .open : hingePose
    }

    /// Only shut, and only on glass whose trailing inset is a band rather
    /// than a bezel. Turned sideways the band is along the top or bottom, so
    /// there's none.
    private var strip: CameraStrip? {
        guard pose == .closed, glass.trailingInset >= 60 else { return nil }
        return CameraStrip(width: glass.trailingInset, occluded: glass.camera, expanded: wide, lensOffset: glass.lensOffset, lensMidY: glass.lensMidY)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.duoPose, pose)
            .environment(\.cameraStrip, strip)
            .environment(\.toggleCameraStrip, toggle)
            .onGeometryChange(for: Glass.self, of: { Self.read($0) }) { glass = $0 }
            .readsHinge($hingePose)
            #if os(iOS)
            // The clock and signal take a column of their own on this glass,
            // shut or open, that the page and its buttons can use better
            .statusBarHidden(pose != .none)
            .onChange(of: pose, initial: true) { _, now in OrientationLock.duoPoseChanged(now) }
            #endif
    }

    private func toggle() {
        withAnimation(.snappy) { wide.toggle() }
        UserDefaults.standard.set(wide, forKey: Self.wideKey)
    }

    private static func read(_ proxy: GeometryProxy) -> Glass {
        let inset = proxy.safeAreaInsets.trailing
        let band = CGRect(x: proxy.size.width, y: 0, width: inset, height: proxy.size.height)
        // The camera: what's reported taken in the band, or a guess at the
        // top of it
        let regions = proxy.occlusions.filter { $0.intersects(band) }
        let taken = regions.reduce(CGRect.null) { $0.union($1) }
        // The camera's plateau spans the band; the lens is the smallest region
        let lens = regions.min { $0.width * $0.height < $1.width * $1.height }
        let camera = taken.isNull ? CGRect(x: proxy.size.width, y: 0, width: inset, height: 82) : taken
        let origin = proxy.frame(in: .global).origin
        return Glass(hasCrease: proxy.crease != nil,
                     trailingInset: inset,
                     camera: camera.offsetBy(dx: origin.x, dy: origin.y),
                     lensOffset: lens.map { $0.midX - band.midX } ?? 0,
                     lensMidY: (lens?.midY ?? camera.midY) + origin.y)
    }
}

extension View {
    /// Keeps `pose` current with the hinge: shut, open, or not there at all.
    fileprivate func readsHinge(_ pose: Binding<DuoPose>) -> some View {
        modifier(HingeReader(pose: pose))
    }
}

private struct HingeReader: ViewModifier {
    @Binding var pose: DuoPose

    @ViewBuilder
    func body(content: Content) -> some View {
        // The hinge needs the iOS 27.1 SDK, whose SwiftUI is the first at
        // 8.0.85; checking for it keeps the app building with older Xcodes,
        // minus the fold
        #if os(iOS) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                guard let hinge = context.hinge else { pose = .none; return }
                pose = hinge.status == .closed ? .closed : .open
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension GeometryProxy {
    /// Where the fold crosses this view while the glass is bent. Nil opened
    /// flat, and on anything that doesn't fold.
    var fold: Fold? {
        #if os(iOS) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            return reservedRegions(kind: .division)
                .first(where: \.isActive)
                .map { Fold(frame: $0.frame) }
        }
        #endif
        return nil
    }

    /// Where the crease crosses this view, bent or flat. Opened flat it's
    /// still there, for a layout that splits at it either way, though nothing
    /// has to keep clear of it.
    var crease: Fold? {
        #if os(iOS) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            return reservedRegions(kind: .division, options: .includeInactive)
                .first
                .map { Fold(frame: $0.frame) }
        }
        #endif
        return nil
    }

    /// What the glass itself takes out of this view (the Duo's outer camera,
    /// shut), in this view's space. Empty elsewhere.
    var occlusions: [CGRect] {
        #if os(iOS) && canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            return reservedRegions(kind: .occlusion, options: .includeInactive).map(\.frame)
        }
        #endif
        return []
    }

    /// The crease as a spine between two pages: open like a book, with room
    /// for a useful page either side. Nil in any other pose.
    func spine(minimumPage: CGFloat = 300) -> CGRect? {
        guard let crease, crease.isVertical,
              crease.frame.minX >= minimumPage,
              size.width - crease.frame.maxX >= minimumPage else { return nil }
        return crease.frame
    }

    /// The fold of glass stood up like a laptop: a screen above, a counter
    /// below. Nil in any other pose, or when either half is too short to use.
    var laptopFold: CGRect? {
        guard let fold, !fold.isVertical,
              fold.frame.minY >= 240,
              size.height - fold.frame.maxY >= 200 else { return nil }
        return fold.frame
    }
}

extension View {
    /// Centres a dialog on the upright half of glass stood up like a laptop,
    /// rather than on the hinge. `fold` must be in the space this view is
    /// laid out in.
    func centeredAboveFold(_ fold: CGRect?) -> some View {
        modifier(AboveFold(fold: fold))
    }
}

private struct AboveFold: ViewModifier {
    let fold: CGRect?

    func body(content: Content) -> some View {
        if let fold {
            content
                .frame(maxWidth: .infinity, maxHeight: fold.minY)
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            content
        }
    }
}

// MARK: - Tall and wide

extension View {
    /// Makes this a page of the Duo's outer screen, folded shut, whose buttons
    /// are in its navigation bar: the system stands them down the camera band
    /// in glass. Wide, the page runs the full width under the band. Anywhere
    /// else, nothing changes.
    func cameraStripPage() -> some View {
        modifier(CameraStripPage(rail: { EmptyView() }, hasRail: false))
    }

    /// The same for a page with no navigation bar: tall, these buttons stand
    /// in the band beside it. Tall or wide, the way between the two is at the
    /// band's foot, so the page's own buttons must keep clear of it.
    func cameraStripPage<Buttons: View>(@ViewBuilder rail: @escaping () -> Buttons) -> some View {
        modifier(CameraStripPage(rail: rail, hasRail: true))
    }
}

private struct CameraStripPage<Buttons: View>: ViewModifier {
    @Environment(\.cameraStrip) private var strip
    @Environment(\.duoPose) private var pose
    /// Where the page starts, in global coordinates, so the rail can start
    /// below the camera.
    @State private var top: CGFloat = 0
    /// Opened like a book: nothing stands in the band, so the page takes it.
    @State private var isBook = false
    let rail: () -> Buttons
    let hasRail: Bool

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { top = $0 }
            .onGeometryChange(for: Bool.self, of: { $0.spine(minimumPage: 280) != nil }) { isBook = $0 }
            .overlay(alignment: .topTrailing) {
                if hasRail, let strip {
                    CameraStripRail(strip: strip, top: top, buttons: rail)
                        // Tall, the band is past the page's edge; wide, it's
                        // over the page's own
                        .offset(x: (strip.rails ? strip.width : 0) + strip.lensOffset)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea(.container, edges: strip?.expanded == true || isBook ? .trailing : [])
            #if os(iOS)
            // A full-screen cover doesn't take this from the page beneath it
            .statusBarHidden(pose != .none)
            #endif
    }
}

extension View {
    /// Makes this a full-screen cover on the Duo's glass. A cover doesn't take
    /// these from the page beneath it: the clock and signal stay hidden, and
    /// opened up, it has the width they'd have stood in.
    func duoCover() -> some View {
        modifier(DuoCover())
    }
}

private struct DuoCover: ViewModifier {
    @Environment(\.duoPose) private var pose

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(.container, edges: pose == .open ? .trailing : [])
            #if os(iOS)
            .statusBarHidden(pose != .none)
            #endif
    }
}

extension View {
    /// Keeps something out of the camera band when the page is wide: the page
    /// runs the full width, but this stays beside the band's buttons.
    func clearOfCameraStrip(_ strip: CameraStrip?) -> some View {
        padding(.trailing, strip?.expanded == true ? strip!.width : 0)
    }
}

/// The rail: a screen's buttons down the camera band, below the camera, when
/// the page is tall. At its foot, the way between tall and wide.
private struct CameraStripRail<Buttons: View>: View {
    @Environment(\.toggleCameraStrip) private var toggle
    let strip: CameraStrip
    let top: CGFloat
    @ViewBuilder var buttons: Buttons

    var body: some View {
        // A gap between buttons that a thumb feeling its way down the edge
        // of the glass won't cross by accident
        VStack(spacing: 12) {
            if strip.rails { buttons }
            Spacer(minLength: 16)
            RailButton(symbol: CameraStripToggleButton.symbol(expanded: strip.expanded),
                       label: CameraStripToggleButton.label(expanded: strip.expanded),
                       action: toggle)
        }
        .padding(.top, max(12, strip.occluded.maxY + 12 - top))
        .padding(.bottom, 12)
        .frame(width: strip.width)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

extension View {
    /// Glass where the system has it, the size and shape of the buttons it
    /// stands on the Duo's glass itself.
    @ViewBuilder
    func duoGlass() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.fill.tertiary, in: Circle())
        }
    }
}

extension CGFloat {
    /// How far a round button in a corner of the opened screen sits from both
    /// edges. It's where the system puts search, so the corners match each
    /// other and follow the curve of the glass.
    static let duoCorner: CGFloat = 24
}

/// A button in the rail.
struct RailButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .duoGlass()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The way between tall and wide, for a navigation bar. The arrow is the way
/// the page will go: out to the edge of the glass, or back in off the band.
struct CameraStripToggleButton: View {
    @Environment(\.cameraStrip) private var strip
    @Environment(\.toggleCameraStrip) private var toggle

    static func symbol(expanded: Bool) -> String {
        expanded ? "arrow.left.to.line" : "arrow.right.to.line"
    }

    static func label(expanded: Bool) -> String {
        expanded ? "Keep Beside the Camera" : "Use the Full Width"
    }

    var body: some View {
        let expanded = strip?.expanded == true
        Button(action: toggle) {
            Image(systemName: Self.symbol(expanded: expanded))
        }
        .accessibilityLabel(Self.label(expanded: expanded))
    }
}
