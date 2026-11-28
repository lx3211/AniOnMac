import SwiftUI
import AppKit
import UniformTypeIdentifiers

@_silgen_name("MeowHoverCursor") func MeowHoverCursor(_ inside: Int32)
// AppKit owns cursor updates separately from SwiftUI's visual hover state.
struct SecondaryCopy: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
    }
}
struct ButtonCursorRegion: NSViewRepresentable {
    var enabled: Bool
    func makeNSView(context: Context) -> Region { Region() }
    func updateNSView(_ view: Region, context: Context) {
        if view.enabled != enabled {
            view.enabled = enabled
            view.window?.invalidateCursorRects(for: view)
        }
    }
    final class RegisteredHand: NSCursor {
        override func set() { MeowHoverCursor(1) }
    }
    final class Region: NSView {
        var enabled = true
        private let hand = RegisteredHand(image: NSCursor.pointingHand.image, hotSpot: NSCursor.pointingHand.hotSpot)
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func resetCursorRects() {
            if enabled { addCursorRect(visibleRect, cursor: hand) }
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .cursorUpdate, .mouseEnteredAndExited], owner: self, userInfo: nil))
        }
        override func cursorUpdate(with event: NSEvent) { if enabled { hand.set() } }
        override func mouseEntered(with event: NSEvent) { if enabled { hand.set() } }
        override func mouseExited(with event: NSEvent) { MeowHoverCursor(0) }
    }
}
struct SmallActionStyle: ButtonStyle {
    var primary = false
    var row = false
    var selected = false
    var borderless = false
    func makeBody(configuration: Configuration) -> some View {
        Action(configuration: configuration, primary: primary, row: row, selected: selected, borderless: borderless)
    }
    struct Action: View {
        let configuration: ButtonStyle.Configuration
        let primary: Bool
        let row: Bool
        let selected: Bool
        let borderless: Bool
        @State private var hovered = false
        @Environment(\.isEnabled) var enabled
        @Environment(\.accessibilityReduceMotion) var reduceMotion
        var pressed: Bool { enabled && configuration.isPressed }
        var fill: Color {
            if pressed { return primary ? Color(red: 0.65, green: 0.29, blue: 0.08) : Color(red: 0.96, green: 0.68, blue: 0.39) }
            if hovered && enabled { return primary ? accent.opacity(0.85) : apricot }
            return primary ? accent : (selected ? apricot.opacity(0.65) : (borderless ? Color.clear : Color.white))
        }
        var body: some View {
            configuration.label
                .padding(.horizontal, row ? 0 : 9).padding(.vertical, row ? 0 : 5)
                .foregroundStyle(primary ? Color.white : ink)
                .background(fill, in: RoundedRectangle(cornerRadius: row ? 10 : 6))
                .overlay(RoundedRectangle(cornerRadius: row ? 10 : 6)
                    .stroke(accent.opacity(borderless ? 0 : (pressed ? 0.95 : (hovered && enabled ? 0.7 : 0.25))), lineWidth: pressed ? 1.5 : 1))
                .shadow(color: .black.opacity(borderless || pressed ? 0 : (hovered && enabled ? 0.10 : 0.04)), radius: 2, y: pressed ? 0 : 1)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: pressed)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
                .background(ButtonCursorRegion(enabled: enabled))
                .onHover { inside in hovered = inside }
                .onChange(of: enabled) { if !enabled && hovered { MeowHoverCursor(0) } }
                .onDisappear { if hovered { MeowHoverCursor(0) } }
        }
    }
}

struct CursorPreview: View {
    let asset: PreviewAsset
    let size: Double
    var hotspot: [Double]?
    var mark = false
    var markerColor = accent
    var outline: (source: String, cache: PreviewOutlineCache)?
    var update: (([Double]) -> Void)?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let info = asset.info
        let maximum = info.aligned_canvas_px.max()!
        let w = size * info.aligned_canvas_px[0] / maximum
        let h = size * info.aligned_canvas_px[1] / maximum
        let density = displayScale >= 2 ? 2 : 1
        let pixelWidth = max(1, Int((w * Double(density)).rounded()))
        let pixelHeight = max(1, Int((h * Double(density)).rounded()))
        let padding = Double(CursorOutline.widthInPoints)
        let hot = hotspot ?? [info.hotspot_points[0] / (128 * info.aligned_canvas_px[0] / maximum), info.hotspot_points[1] / (128 * info.aligned_canvas_px[1] / maximum)]
        TimelineView(.animation(minimumInterval: max(0.016, info.frame_duration_seconds))) { time in
            let steps = info.playback_frames
            let step = Int(time.date.timeIntervalSinceReferenceDate / max(0.016, info.frame_duration_seconds)) % steps.count
            let frame = steps[step]
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: w, height: h).background {
                    if let outline, let image = outline.cache.image(asset.frames[frame], source: outline.source, frame: frame,
                                                                    width: pixelWidth, height: pixelHeight, density: density) {
                        Image(decorative: image, scale: CGFloat(density)).resizable().interpolation(.high)
                            .frame(width: w + 2 * padding, height: h + 2 * padding)
                    } else {
                        Image(decorative: asset.frames[frame], scale: 1).resizable().interpolation(.high).frame(width: w, height: h)
                    }
                }
                if mark {
                    Path { p in
                        let x = hot[0] * w, y = hot[1] * h
                        p.move(to: CGPoint(x: x - 5, y: y)); p.addLine(to: CGPoint(x: x + 5, y: y))
                        p.move(to: CGPoint(x: x, y: y - 5)); p.addLine(to: CGPoint(x: x, y: y + 5))
                    }.stroke(markerColor, lineWidth: 1)
                }
            }.frame(width: w, height: h).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    update?([min(0.999999, max(0, value.location.x / w)), min(0.999999, max(0, value.location.y / h))])
                })
        }
    }
}

struct ContentView: View {
    @StateObject var studio = Studio()
    @State var path = ""
    @State var targeted = false
    @State var showHotspot = true
    @State var darkPreview = false
    @State var confirmDelete = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                header
                rolePicker
                ScrollView {
                    if let slot = studio.slot { editor(slot) }
                }
                footer
            }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.98, green: 0.98, blue: 0.97))
        }.foregroundStyle(ink).tint(accent).preferredColorScheme(.light)
            .frame(minWidth: 1060, minHeight: 780)
            .disabled(studio.busy || !studio.ready)
            .overlay { if studio.busy { VStack(spacing: 12) { ProgressView(); Text(studio.t("processing")) }.padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
            .alert(studio.t("errorTitle"), isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) {
                Button(studio.t("ok")) { studio.error = nil }
            } message: { Text(studio.t("errorDetail") + "\n\n" + (studio.error ?? "")) }
            .alert(studio.t("deleteTitle"), isPresented: $confirmDelete) {
                Button(studio.t("cancel"), role: .cancel) {}
                Button(studio.t("delete"), role: .destructive) { studio.remove() }
            } message: { Text(studio.t("deleteMessage")) }
            .onChange(of: studio.role) { path = "" }
            .onChange(of: studio.library.selected) { path = "" }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.rays").font(.title).foregroundStyle(accent)
                Text("AniOnMac").font(.title3.bold())
            }.padding(.top, 14)
            Text(studio.t("myThemes")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(studio.library.profiles) { p in themeRow(p) }
                }
            }
            Button { studio.add(copy: false) } label: { Label(studio.t("addTheme"), systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(SmallActionStyle()).controlSize(.large)
            HStack {
                Button(studio.t("duplicate")) { studio.add(copy: true) }.buttonStyle(SmallActionStyle())
                Spacer()
                Button { confirmDelete = true } label: { Image(systemName: "trash") }.buttonStyle(SmallActionStyle())
                    .disabled(studio.library.profiles.count < 2).help(studio.t("delete"))
            }
            Divider()
            Button { studio.restoreNative() } label: {
                Label(studio.t("nativeReset"), systemImage: "arrow.counterclockwise.circle")
                    .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).contentShape(Rectangle())
            }.buttonStyle(SmallActionStyle(row: true))
            Divider()
            Label(studio.t("autoSave"), systemImage: "checkmark.circle").modifier(SecondaryCopy())
            Text(studio.t("copyHint")).modifier(SecondaryCopy()).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(width: 210).frame(maxHeight: .infinity).background(cream)
    }
    func themeRow(_ p: Profile) -> some View {
        Button { studio.select(p.id) } label: {
            HStack(spacing: 10) {
                if let slot = p.slots.first(where: { !$0.preview.isEmpty }), let asset = studio.cache[slot.preview] {
                    CursorPreview(asset: asset, size: 28).allowsHitTesting(false).frame(width: 34, height: 34)
                } else { Image(systemName: "cursorarrow").frame(width: 34, height: 34) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name.isEmpty ? studio.t("untitled") : p.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text("\(p.slots.filter { !$0.asset.isEmpty }.count) / 4 · " + studio.t("modes")).modifier(SecondaryCopy())
                }
                Spacer(minLength: 0)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(SmallActionStyle(row: true, selected: p.id == studio.library.selected, borderless: true)).frame(maxWidth: .infinity)
    }
    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(studio.t("themeName"), text: Binding(get: { studio.profile?.name ?? "" }, set: { studio.rename($0) }))
                    .font(.system(size: 26, weight: .semibold)).textFieldStyle(.plain).accessibilityLabel(studio.t("themeName"))
                Text(studio.t("subtitle")).font(.callout).foregroundStyle(.secondary)
            }
            Button(studio.library.english ? "中文版" : "English version") { studio.toggleLanguage() }.buttonStyle(SmallActionStyle())
        }
    }
    var rolePicker: some View {
        HStack(spacing: 8) {
            ForEach(roles, id: \.self) { role in
                Button { studio.role = role } label: {
                    HStack(spacing: 8) {
                        Group {
                            if let slot = studio.profile?.slots.first(where: { $0.role == role }), let asset = studio.cache[slot.preview] {
                                CursorPreview(asset: asset, size: 28).allowsHitTesting(false)
                            } else {
                                Image(systemName: symbols[role]!)
                            }
                        }.frame(width: 32, height: 32).accessibilityHidden(true)
                        Text(studio.t(role))
                    }.font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 9).contentShape(Rectangle())
                }.buttonStyle(SmallActionStyle(row: true, selected: studio.role == role, borderless: true))
            }
        }
    }
    func editor(_ slot: Slot) -> some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(studio.t("importHeading")).font(.caption.weight(.semibold)).foregroundStyle(accent)
                    Spacer()
                    if !slot.asset.isEmpty { Button(studio.t("clearMode")) { studio.clearSlot() }.buttonStyle(SmallActionStyle()).font(.caption) }
                }
                dropZone(slot)
                HStack {
                    TextField(studio.t("pathPlaceholder"), text: $path).textFieldStyle(.roundedBorder).onSubmit { importPath() }
                    Button(studio.t("import")) { importPath() }.buttonStyle(SmallActionStyle()).disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Divider()
                HStack {
                    Text(studio.t("sizeHeading")).font(.caption.weight(.semibold)).foregroundStyle(accent)
                    Spacer(); Text("\(Int(slot.size)) pt").monospacedDigit()
                }
                Slider(value: Binding(get: { studio.slot?.size ?? 32 }, set: { studio.size($0) }), in: 8...128, step: 1).accessibilityLabel(studio.t("sizeHeading"))
                HStack(spacing: 12) {
                    Button(studio.t("resetSize")) { studio.size(32) }
                    Button(studio.t("allSizes")) { studio.allSizes() }
                }.buttonStyle(SmallActionStyle()).font(.caption)
                Divider()
                hotspotEditor(slot)
                if slot.role == "pointing" { Text(studio.t("pointingHint")).modifier(SecondaryCopy()) }
            }.frame(maxWidth: .infinity)
            previewPanel(slot).frame(maxWidth: .infinity)
        }.padding(22).background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
    }
    func dropZone(_ slot: Slot) -> some View {
        VStack(spacing: 9) {
            Image(systemName: "square.and.arrow.down").font(.system(size: 25, weight: .light)).foregroundStyle(accent)
            Text(studio.t("dropHint")).font(.system(size: 14, weight: .medium))
            Text(slot.filename.isEmpty ? studio.t("animationHint") : slot.filename).modifier(SecondaryCopy()).lineLimit(2)
            Button(studio.t("chooseFile")) { studio.chooseFile() }.buttonStyle(SmallActionStyle()).controlSize(.large)
        }.frame(maxWidth: .infinity).frame(height: 155).background(targeted ? apricot.opacity(0.6) : cream, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    if let url { Task { @MainActor in studio.importFile(url) } }
                }
                return true
            }
    }
    func hotspotEditor(_ slot: Slot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(studio.t("hotspotHeading")).font(.caption.weight(.semibold)).foregroundStyle(accent)
                Spacer(); Button(studio.t("resetHotspot")) { studio.setHotspot(nil) }.buttonStyle(SmallActionStyle()).font(.caption)
            }
            HStack {
                ForEach(0..<2, id: \.self) { axis in
                    Text(axis == 0 ? "X" : "Y").font(.caption)
                    TextField("0", value: hotspotBinding(slot, axis), format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder).accessibilityLabel(axis == 0 ? "Hotspot X" : "Hotspot Y")
                }
                Text("pt").modifier(SecondaryCopy())
            }.disabled(slot.asset.isEmpty)
            Text(studio.t("hotspotHint")).modifier(SecondaryCopy()).fixedSize(horizontal: false, vertical: true)
        }
    }
    func hotspotBinding(_ slot: Slot, _ axis: Int) -> Binding<Double> {
        let info = studio.cache[slot.preview]?.info
        let dimensions = info?.aligned_canvas_px ?? [1, 1]
        let length = slot.size * dimensions[axis] / dimensions.max()!
        return Binding(get: { studio.hotNormalized(studio.slot ?? slot)[axis] * length }, set: { value in
            guard value.isFinite else { return }
            var hot = studio.hotNormalized(studio.slot ?? slot); hot[axis] = value / length; studio.setHotspot(hot)
        })
    }
    func previewPanel(_ slot: Slot) -> some View {
        let appearanceAction = studio.t(darkPreview ? "lightPreview" : "darkPreview")
        let themeHasOutline = studio.profile?.whiteOutline == true
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(studio.t("preview")).font(.headline)
                Button { darkPreview.toggle() } label: { Image(systemName: "circle.lefthalf.filled") }
                    .buttonStyle(SmallActionStyle(selected: darkPreview, borderless: true))
                    .help(appearanceAction)
                    .accessibilityLabel(appearanceAction)
                Spacer()
                Text(studio.t("actualSize")).font(.caption).foregroundStyle(accent).padding(7).background(cream, in: Capsule())
            }
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(darkPreview ? Color.black : Color.white)
                if let asset = studio.cache[slot.preview] {
                    CursorPreview(asset: asset, size: slot.size, hotspot: studio.hotNormalized(slot), mark: showHotspot,
                                  markerColor: darkPreview ? apricot : accent,
                                  outline: themeHasOutline ? (source: slot.preview, cache: studio.outlineCache) : nil,
                                  update: { studio.setHotspot($0) })
                } else {
                    Text(studio.t("noCursor")).font(.callout).foregroundStyle(darkPreview ? Color.white.opacity(0.7) : Color.secondary)
                }
            }.frame(height: 310).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.12)))
            HStack(spacing: 18) {
                Toggle(studio.t("showHotspot"), isOn: $showHotspot)
                Toggle(studio.t("whiteOutline"), isOn: Binding(get: { studio.profile?.whiteOutline == true }, set: { studio.setWhiteOutline($0) }))
            }.toggleStyle(.checkbox).font(.caption)
            Text(studio.t("previewHint") + "\n" + studio.t("markerHint")).modifier(SecondaryCopy()).fixedSize(horizontal: false, vertical: true)
        }
    }
    func importPath() {
        var input = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.hasPrefix("\"") && input.hasSuffix("\"") { input = String(input.dropFirst().dropLast()) }
        let url = input.hasPrefix("file://") ? URL(string: input) : URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
        if let url { studio.importFile(url) }
    }
    var footer: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 14) {
                Text(studio.t(studio.status)).modifier(SecondaryCopy()).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Button(studio.t("undo")) { studio.restore() }.buttonStyle(SmallActionStyle()).disabled(!studio.canUndo).controlSize(.large)
                Button { studio.apply() } label: { Label(studio.t(studio.isApplied ? "alreadyApplied" : "apply"), systemImage: "checkmark").padding(.horizontal, 8) }
                    .buttonStyle(SmallActionStyle(primary: true)).controlSize(.large).disabled(!studio.canApply)
            }
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text(verbatim: "v\(version)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.51, green: 0.29, blue: 0.12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(apricot.opacity(0.55), in: Capsule())
                    .offset(y: 6)
            }
        }
    }
}

@main struct CursorApp: App {
    var body: some Scene {
        Window("AniOnMac", id: "main") { ContentView() }.defaultSize(width: 1160, height: 900)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
