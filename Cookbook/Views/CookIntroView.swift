import SwiftUI

/// The two screens before step 1 of a fresh cook: the whole cook at a
/// glance, then the knife work to do before the heat goes on.
struct CookIntroView: View {
    enum Page {
        case overview
        case prep
    }

    let page: Page
    let overview: CookOverview
    /// The on-device model is still working out the overview.
    var overviewLoading = false
    let prepTasks: [PrepTask]
    @Binding var prepped: Set<Int>
    let accentColor: Color
    let isLandscape: Bool
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(page == .overview ? (overviewLoading ? " " : overview.totalLabel) : "Cut these first")
                .font(.system(size: isLandscape ? 26 : 30, weight: .bold))
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)

            Group {
                switch page {
                case .overview:
                    if overviewLoading {
                        // Wait for the finished overview rather than show it changing
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Planning your cook…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                    } else {
                        CookOverviewTimeline(overview: overview, accentColor: accentColor, isLandscape: isLandscape)
                            .transition(.opacity)
                    }
                case .prep: prepList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            buttons
        }
    }

    // MARK: - Prep

    @ViewBuilder
    private var prepList: some View {
        if isLandscape {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3), spacing: 14) {
                    ForEach(prepTasks.indices, id: \.self) { index in
                        prepCard(index)
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(prepTasks.indices, id: \.self) { index in
                        prepRow(index)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func prepCard(_ index: Int) -> some View {
        let task = prepTasks[index]
        let done = prepped.contains(index)
        return Button { toggle(index) } label: {
            VStack(alignment: .leading, spacing: 10) {
                checkCircle(done, size: 28)
                Text(task.title)
                    .font(.system(size: 19, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(task.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(done ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title), \(task.detail)")
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    private func prepRow(_ index: Int) -> some View {
        let task = prepTasks[index]
        let done = prepped.contains(index)
        return Button { toggle(index) } label: {
            HStack(spacing: 14) {
                checkCircle(done, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 20, weight: .bold))
                    Text(task.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(done ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title), \(task.detail)")
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    private func checkCircle(_ done: Bool, size: CGFloat) -> some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size))
            .foregroundColor(done ? .green : .gray)
            .contentTransition(.identity)
    }

    private func toggle(_ index: Int) {
        if prepped.contains(index) { prepped.remove(index) } else { prepped.insert(index) }
    }

    // MARK: - Buttons

    private var nextLabel: String {
        page == .overview && !prepTasks.isEmpty ? "Prep" : "Start Cooking"
    }

    private var nextButton: some View {
        Button(action: onNext) {
            HStack(spacing: 6) {
                Text(nextLabel)
                Image(systemName: "chevron.right")
            }
            .font(.title3.weight(.bold))
            .foregroundColor(.white)
            .frame(maxWidth: isLandscape ? nil : .infinity, minHeight: 56)
            .frame(minWidth: isLandscape ? 220 : nil)
            .padding(.horizontal, 24)
            .background(accentColor, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.rightArrow, modifiers: [])
    }

    @ViewBuilder
    private var backButton: some View {
        let first = page == .overview
        Button(action: onBack) {
            if isLandscape {
                Label("Back", systemImage: "chevron.left")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(.fill.tertiary, in: Capsule())
                    .contentShape(Capsule())
            } else {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .background(.fill.tertiary, in: Circle())
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.leftArrow, modifiers: [])
        .disabled(first)
        .opacity(first ? 0.35 : 1)
        .accessibilityLabel("Back")
    }

    @ViewBuilder
    private var skipButton: some View {
        if page == .overview {
            Button("Skip to Step 1", action: onSkip)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if isLandscape {
            HStack(spacing: 16) {
                backButton
                Spacer(minLength: 0)
                skipButton
                nextButton
            }
        } else {
            VStack(spacing: 4) {
                skipButton
                HStack(spacing: 12) {
                    backButton
                    nextButton
                }
            }
        }
    }
}

/// Bars in lanes, one word and a time each, sized by how long they take.
/// Left to right in landscape; top to bottom in portrait.
struct CookOverviewTimeline: View {
    let overview: CookOverview
    let accentColor: Color
    let isLandscape: Bool

    private let gap: CGFloat = 5
    private let laneGap: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let frames = blockFrames(in: geometry.size)
            ZStack(alignment: .topLeading) {
                ForEach(overview.blocks.indices, id: \.self) { index in
                    if let frame = frames[index] {
                        block(overview.blocks[index], in: frame)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: isLandscape ? .leading : .topLeading)
        }
        .padding(.vertical, isLandscape ? 0 : 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Overview")
    }

    private func block(_ block: CookOverview.Block, in frame: CGRect) -> some View {
        let fill: Color = switch block.kind {
        case .prep: .orange
        case .cook: accentColor
        case .alongside: .cyan
        }
        let ink: Color = block.kind == .alongside ? Color(red: 0, green: 0.13, blue: 0.18) : .white
        let alignment: HorizontalAlignment = (isLandscape || block.lane > 0) ? .center : .leading
        return VStack(alignment: alignment, spacing: 1) {
            Text(block.word)
                .font(.system(size: 16, weight: .bold))
            // A squeezed block keeps its word and drops the time
            if (isLandscape ? frame.width : frame.height) >= (isLandscape ? 54 : 40) {
                Text(block.timeLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.75)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundColor(ink)
        .padding(.horizontal, alignment == .leading ? 16 : 6)
        .frame(width: frame.width, height: frame.height, alignment: Alignment(horizontal: alignment, vertical: .center))
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .offset(x: frame.minX, y: frame.minY)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(block.step.map { "Step \($0 + 1), \(block.word), \(block.timeLabel)" } ?? "\(block.word), \(block.timeLabel)")
    }

    /// Where each block goes. The main lane is laid out along time; the other
    /// lanes line up with it.
    private func blockFrames(in size: CGSize) -> [CGRect?] {
        let lanes = overview.laneCount
        let mainIndices = overview.blocks.indices.filter { overview.blocks[$0].lane == 0 }
            .sorted { overview.blocks[$0].start < overview.blocks[$1].start }
        let minimum: (CookOverview.Block) -> Double = { block in
            if self.isLandscape {
                return max(Double(block.word.count) * 16 * 0.62, Double(block.timeLabel.count) * 13 * 0.55) + 20
            }
            return 46
        }

        let length = Double(isLandscape ? size.width : size.height)
        let (spans, position) = CookIntroPlanner.layout(
            main: mainIndices.map { (overview.blocks[$0].start, overview.blocks[$0].end, minimum(overview.blocks[$0])) },
            length: length, gap: Double(gap)
        )

        // Across the lanes: equal heights in landscape; in portrait the main
        // lane is the widest column
        let laneSize: CGFloat
        let mainSize: CGFloat
        if isLandscape {
            laneSize = min(56, (size.height - laneGap * CGFloat(lanes - 1)) / CGFloat(lanes))
            mainSize = laneSize
        } else {
            mainSize = lanes > 1 ? size.width * 0.5 : size.width
            laneSize = lanes > 1 ? (size.width - mainSize - laneGap * CGFloat(lanes - 1)) / CGFloat(lanes - 1) : 0
        }
        let crossOffset: (Int) -> CGFloat = { lane in
            if self.isLandscape {
                let total = laneSize * CGFloat(lanes) + self.laneGap * CGFloat(lanes - 1)
                return (size.height - total) / 2 + CGFloat(lane) * (laneSize + self.laneGap)
            }
            return lane == 0 ? 0 : mainSize + self.laneGap + CGFloat(lane - 1) * (laneSize + self.laneGap)
        }

        var frames = [CGRect?](repeating: nil, count: overview.blocks.count)
        for (order, index) in mainIndices.enumerated() {
            let (from, to) = spans[order]
            frames[index] = rect(along: from, length: to - from, across: crossOffset(0), thickness: mainSize)
        }
        var laneEnds: [Int: Double] = [:]
        for index in overview.blocks.indices where overview.blocks[index].lane > 0 {
            let block = overview.blocks[index]
            let from = max(position(block.start), (laneEnds[block.lane] ?? -.infinity) + Double(gap))
            let span = max(position(block.end) - position(block.start) - Double(gap), minimum(block))
            laneEnds[block.lane] = from + span
            frames[index] = rect(along: from, length: span, across: crossOffset(block.lane), thickness: laneSize)
        }
        return frames
    }

    private func rect(along: Double, length: Double, across: CGFloat, thickness: CGFloat) -> CGRect {
        isLandscape
            ? CGRect(x: along, y: Double(across), width: length, height: Double(thickness))
            : CGRect(x: Double(across), y: along, width: Double(thickness), height: length)
    }
}
