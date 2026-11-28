import CoreGraphics
import Foundation

@main struct ApplyStateTests {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard let dataArgument = args.firstIndex(of: "--data-dir"), dataArgument + 1 < args.count else {
            preconditionFailure("Run with an isolated test data directory")
        }
        let studio = Studio()
        var theme = Profile(name: "Test")
        theme.slots[0].asset = "assets/test.ani"
        studio.library.profiles = [theme]
        studio.library.selected = theme.id
        precondition(studio.canApply)
        studio.activeApplication = theme
        precondition(studio.isApplied && !studio.canApply)
        studio.library.english = true
        studio.library.profiles[0].name = "Renamed"
        precondition(studio.isApplied, "Language and name do not change cursor settings")
        studio.library.profiles[0].slots[0].size = 48
        precondition(!studio.isApplied && studio.canApply)
        studio.library.profiles[0].slots = theme.slots
        precondition(studio.isApplied, "Returning to applied settings needs no reapply")
        precondition(studio.profile?.whiteOutline == nil, "Existing themes start with the outline off")
        studio.setWhiteOutline(true)
        precondition(studio.profile?.whiteOutline == true && studio.canApply)
        let saved = try JSONDecoder().decode(Library.self, from: Data(contentsOf: studio.root.appendingPathComponent("library.json")))
        precondition(saved.profiles[0].whiteOutline == true)
        studio.role = "text"
        precondition(studio.profile?.whiteOutline == true, "The outline applies across modes")
        studio.setWhiteOutline(false)
        precondition(studio.isApplied && !studio.canApply)
        studio.library.profiles[0].slots[0].hotspot = [0.2, 0.3]
        precondition(studio.canApply)
        studio.library.profiles[0].slots = theme.slots
        studio.library.profiles[0].slots[0].asset = "assets/replacement.ani"
        precondition(studio.canApply)
        studio.library.profiles[0].slots[0] = Slot(role: "arrow")
        precondition(!studio.canApply && !studio.isApplied)
        studio.library.profiles[0] = theme
        studio.activeApplication = nil
        precondition(studio.canApply, "Native reset or system restore invalidates applied state")
        studio.busy = true
        precondition(!studio.canApply)
        print("PASS: apply state, edits, white outline, reverted edits, empty theme, language, reset and busy state")
        testOutlineCache()
    }

    static func testOutlineCache() {
        let cache = PreviewOutlineCache()
        let original = cursorBitmap(width: 2, height: 3)!.makeImage()!
        func frame(_ source: String, index: Int = 0, width: Int = 2, density: Int = 1) -> CGImage {
            cache.image(original, source: source, frame: index, width: width, height: 3, density: density)!
        }

        let arrow = frame("previews/arrow")
        let pointing = frame("previews/pointing")
        precondition(arrow !== pointing, "A different source needs its own outlined image")
        precondition(frame("previews/arrow") === arrow && frame("previews/pointing") === pointing,
                     "Previously displayed frames survive mode and theme switches")
        precondition(frame("previews/arrow", index: 1) !== arrow)
        precondition(frame("previews/arrow", width: 4).width == 6)
        precondition(frame("previews/arrow", density: 2).width == 6)
        print("PASS: outlined frames are reused by source, frame, size and display density")
    }
}
