import SwiftUI
import UIKit

// The workout's own screens the page describes (the app's drawing 3): a step of the workout pushed over the list
// (the exercise's intro, a set, the rest, a superset's «straight on»), the summary after a workout, an idle workout —
// and the exercise card's photos. Built from the iPhone's own parts: big numbers in the system's rounded face, a ring
// like the Clock app's timer, the system's check mark symbol.

/// How long the workout has been going, in the top bar of a step («12:34», «1:02:05»).
struct NVClock: View {
    let since: Double
    var label = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.text(max(0, context.date.timeIntervalSince1970 - since / 1000)))
        }
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityIdentifier("nv.clock")
    }

    static func text(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func minutes(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// What to lift in this set: the weight and the reps, big, side by side.
struct NVTargetRow: View {
    let row: NVNode
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            if let cap = row.str("cap") {
                Text(cap).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let weight = row.str("w") {
                    value(weight, unit: row.str("wu"), symbol: "dumbbell.fill", tint: accent)
                    Text("×").font(.title).foregroundStyle(.tertiary)
                }
                value(row.str("r") ?? "", unit: row.str("ru"), symbol: "repeat", tint: .secondary)
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            if let foot = row.str("foot") {
                Text(foot).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let hint = row.str("hint") {
                Text(hint).font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nv.target")
    }

    private func value(_ number: String, unit: String?, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
            Text(number).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
            if let unit { Text(unit).font(.title3.weight(.semibold)).foregroundStyle(.secondary) }
        }
    }
}

/// The rest counting down: a ring that empties and big digits in the middle, like the Clock app's timer; past the
/// end it turns orange and counts on with a minus.
struct NVRingRow: View {
    let row: NVNode
    let accent: Color

    var body: some View {
        let start = row.number("start") ?? 0
        let total = max(1, row.number("sec") ?? 1)
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = total - (context.date.timeIntervalSince1970 * 1000 - start) / 1000
            let over = left < 0
            let fraction = over ? 1 : min(1, max(0, left / total))
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(over ? Color.orange : accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: fraction)
                VStack(spacing: 4) {
                    Text(over ? "−" + NVClock.minutes(-left) : NVClock.minutes(left))
                        .font(.system(size: 60, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(over ? Color.orange : Color.primary)
                    Text(over ? (row.str("over") ?? "") : (row.str("of") ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 236, height: 236)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nv.ring")
    }
}

/// A superset's «straight on»: what's next, big, and how long since the last set.
struct NVTimerRow: View {
    let row: NVNode

    var body: some View {
        let since = row.number("since") ?? 0
        VStack(spacing: 6) {
            Text(row.str("t") ?? "").font(.subheadline).foregroundStyle(.secondary)
            Text(row.str("n") ?? "").font(.title.weight(.bold)).multilineTextAlignment(.center)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text((row.str("cap") ?? "") + NVClock.text(max(0, context.date.timeIntervalSince1970 - since / 1000)))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nv.timer")
    }
}

/// The top of the summary: the system's check mark, the workout done.
struct NVDoneRow: View {
    let row: NVNode
    @State private var shown = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 76))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .symbolEffect(.bounce, value: shown)
            Text(row.str("t") ?? "").font(.title2.weight(.bold)).multilineTextAlignment(.center)
            if let sub = row.str("s") {
                Text(sub).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .onAppear { shown = true }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nv.done")
    }
}

// MARK: - The exercise card's photos

/// The exercise's two positions (one picture: stretch on the left, squeeze on the right): they take turns by
/// themselves; the segmented control shows one of them and stops the turns, the button starts them again.
struct NVPhotoRow: View {
    let row: NVNode
    @ObservedObject var model: NVTabModel
    @State private var frame = 0
    @State private var playing = true

    var body: some View {
        let names = (row.d["names"] as? [String]) ?? ["", ""]
        VStack(spacing: 12) {
            Group {
                if let halves = NVPhotos.halves(key: row.str("key") ?? "", src: row.str("src")) {
                    ZStack {
                        Image(uiImage: halves.0).resizable().scaledToFit().opacity(frame == 0 ? 1 : 0)
                        Image(uiImage: halves.1).resizable().scaledToFit().opacity(frame == 1 ? 1 : 0)
                    }
                    .animation(.easeInOut(duration: 0.35), value: frame)
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { playing.toggle() }
                    .accessibilityLabel((row.str("label") ?? "") + ": " + (names.indices.contains(frame) ? names[frame] : ""))
                } else if let error = row.str("err") {
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.exclamationmark").font(.title).foregroundStyle(.secondary)
                        Text(error).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if let retry = row.str("retry") {
                            Button(row.str("retryT") ?? "") { model.act(retry) }.buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            HStack(spacing: 10) {
                Picker("", selection: Binding(get: { frame }, set: { frame = $0; playing = false })) {
                    Text(names.first ?? "").tag(0)
                    Text(names.count > 1 ? names[1] : "").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button {
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(playing ? (row.str("stop") ?? "") : (row.str("play") ?? ""))
            }
        }
        .padding(.vertical, 6)
        .task(id: playing) {
            while playing && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_700_000_000)
                if playing && !Task.isCancelled { frame = 1 - frame }
            }
        }
        .accessibilityIdentifier("nv.photo")
    }
}

/// The photos the page handed over (as data), cut into their two halves once.
enum NVPhotos {
    private static var cache: [String: (UIImage, UIImage)] = [:]

    static func halves(key: String, src: String?) -> (UIImage, UIImage)? {
        if let hit = cache[key] { return hit }
        guard let src, let comma = src.firstIndex(of: ","),
              let data = Data(base64Encoded: String(src[src.index(after: comma)...])),
              let image = UIImage(data: data), let cg = image.cgImage else { return nil }
        let half = cg.width / 2
        guard half > 0,
              let left = cg.cropping(to: CGRect(x: 0, y: 0, width: half, height: cg.height)),
              let right = cg.cropping(to: CGRect(x: half, y: 0, width: cg.width - half, height: cg.height)) else { return nil }
        let pair = (UIImage(cgImage: left, scale: image.scale, orientation: image.imageOrientation),
                    UIImage(cgImage: right, scale: image.scale, orientation: image.imageOrientation))
        if cache.count > 40 { cache.removeAll() }
        cache[key] = pair
        return pair
    }
}
