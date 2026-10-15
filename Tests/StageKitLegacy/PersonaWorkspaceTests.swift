import AppKit
import SwiftUI

final class PersonaWorkspaceTests {
    private final class Display: PersonaSessionDisplaying {
        func setVoiceRing(_ on: Bool) {}
        func setVoiceColor(_ color: InkColor) {}
        func showVoice(_ frames: [PersonaVoiceFrame]) {}
        var onPlacementChange: ((PersonaOverlayState) -> Void)?
        var onSelection: (() -> Void)?
        var frame: CGRect? = CGRect(x: 0, y: 0, width: 80, height: 120)
        var visible = false
        func show(image: NSImage, name: String, state: PersonaOverlayState, animated: Bool) -> PersonaOverlayState {
            visible = true; return state
        }
        func configure(image: NSImage, name: String, state: PersonaOverlayState) {}
        func hide() { visible = false }
        func shutdown() { visible = false }
    }
    private func fixture() throws -> (URL, PersonaLibrary, UUID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PersonaWorkspace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = try picture(in: root)
        let library = PersonaLibrary(root: root, sessionPanelFactory: { Display() }, sessionHUDEnabled: false)
        let persona = try library.addImage(source, name: "Sample account manager")
        let group = try library.createGroup(name: "Sample group", members: [persona.id])
        try library.saveGroupLayout(group, overlays: [PersonaOverlayItem(personaID: persona.id), PersonaOverlayItem(personaID: persona.id)], publicLabel: "Sample set")
        return (root, library, group)
    }
    private func picture(in root: URL) throws -> URL {
        let image = NSImage(size: CGSize(width: 160, height: 90), flipped: false) { rect in
            NSColor.systemTeal.setFill(); rect.fill(); return true
        }
        let source = root.appendingPathComponent("sample.png")
        try SceneRenderer.png(DemoScene(background: "sample.png"), image: image, size: image.size).write(to: source)
        return source
    }
    func testWorkspaceStartsWithoutDismissalAndPreservesPausedArrangement() throws {
        let (root, library, group) = try fixture()
        defer { library.shutdown(); try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("persona-library.json")
        let before = try Data(contentsOf: manifest)
        var launches = 0
        library.onShow = { launches += 1 }
        var launch = PersonaLibraryLaunchState()
        let result = launch.request(.prepared(groupIDs: [group], softReveal: false), from: .workspace, in: library)
        XCTAssertNotNil(result); try result?.get()
        XCTAssertEqual(library.sessionState.phase, .active)
        XCTAssertTrue(library.toolbarCycle?.isSet == true, "a prepared set uses set switching, never single-card cycling")
        XCTAssertFalse(library.toolbarCycle?.canAdvance ?? true, "one prepared set has no Next set")
        XCTAssertTrue(launch.pending == nil)
        XCTAssertEqual(launches, 1)
        let ids = library.sessionState.instances.map(\.id)
        library.performOverlayAction(.visible(ids[0], false))
        library.performOverlayAction(.position(ids[1], 0.2, 0.8))
        library.performOverlayAction(.locked(ids[1], true))
        let arranged = library.sessionState.instances.map(\.placement)
        try library.togglePersonaVisibility().get()
        XCTAssertEqual(library.sessionState.phase, .paused)
        XCTAssertTrue(library.toolbarCycle == nil, "a hidden set resumes before switching")
        try library.togglePersonaVisibility().get()
        XCTAssertEqual(library.sessionState.phase, .active)
        XCTAssertEqual(library.sessionState.instances.map(\.placement), arranged)
        library.pauseOverlaySession()
        let resumed = launch.request(.resume, from: .workspace, in: library)
        XCTAssertNotNil(resumed); try resumed?.get()
        XCTAssertEqual(library.sessionState.phase, .active)
        XCTAssertEqual(library.sessionState.instances.map(\.id), ids)
        XCTAssertEqual(library.sessionState.instances.map(\.placement), arranged)
        XCTAssertFalse(library.sessionState.instances[0].visible)
        XCTAssertTrue(library.sessionState.instances[1].visible)
        XCTAssertTrue(launch.dismissed(in: library) == nil, "Leaving the workspace cannot replay Start or Resume")
        XCTAssertEqual(launches, 1)
        library.hideOverlay()
        XCTAssertEqual(library.sessionState.phase, .idle)
        XCTAssertTrue(library.sessionState.instances.isEmpty)
        XCTAssertEqual(try Data(contentsOf: manifest), before, "Temporary geometry, hide, resume and End retain the saved library")
    }
    func testWorkspaceSingleCardShowsAndStopsWithoutDismissal() throws {
        let (root, library, _) = try fixture()
        defer { library.shutdown(); try? FileManager.default.removeItem(at: root) }
        library.usesSharedControls = true
        let manifest = root.appendingPathComponent("persona-library.json")
        let before = try Data(contentsOf: manifest)
        var launches = 0
        library.onShow = { launches += 1 }
        var launch = PersonaLibraryLaunchState()
        let result = launch.request(.oneCard, from: .workspace, in: library)
        XCTAssertNotNil(result); try result?.get()
        XCTAssertTrue(library.overlayVisible)
        XCTAssertEqual(library.sessionState.phase, .idle)
        XCTAssertEqual(launches, 1)
        XCTAssertTrue(launch.pending == nil)
        try library.togglePersonaVisibility().get()
        XCTAssertFalse(library.overlayVisible)
        XCTAssertTrue(launch.dismissed(in: library) == nil)
        XCTAssertEqual(launches, 1, "Closing the workspace must not show a card that was hidden")
        try library.togglePersonaVisibility().get()
        XCTAssertTrue(library.overlayVisible)
        XCTAssertEqual(launches, 2)
        library.hideOverlay()
        XCTAssertFalse(library.overlayVisible)
        XCTAssertEqual(try Data(contentsOf: manifest), before)
    }
    func testSheetLaunchWaitsForDismissalAndIsConsumedOnce() throws {
        let (root, library, group) = try fixture()
        defer { library.shutdown(); try? FileManager.default.removeItem(at: root) }
        var launches = 0
        library.onShow = { launches += 1 }
        var launch = PersonaLibraryLaunchState()
        XCTAssertTrue(launch.request(.prepared(groupIDs: [group], softReveal: false), from: .sheet, in: library) == nil)
        XCTAssertEqual(library.sessionState.phase, .idle)
        XCTAssertNotNil(launch.pending)
        try launch.dismissed(in: library)?.get()
        XCTAssertEqual(library.sessionState.phase, .active)
        XCTAssertEqual(launches, 1)
        XCTAssertTrue(launch.pending == nil)
        XCTAssertTrue(launch.dismissed(in: library) == nil)
        XCTAssertEqual(launches, 1)
        library.pauseOverlaySession()
        XCTAssertTrue(launch.request(.resume, from: .sheet, in: library) == nil)
        XCTAssertEqual(library.sessionState.phase, .paused)
        try launch.dismissed(in: library)?.get()
        XCTAssertEqual(library.sessionState.phase, .active)
    }
    func testWorkspaceFailureIsImmediateAndDoesNotReplaceSession() throws {
        let (root, library, group) = try fixture()
        defer { library.shutdown(); try? FileManager.default.removeItem(at: root) }
        try library.startOverlaySession(groupIDs: [group], initialGroupID: group)
        let ids = library.sessionState.instances.map(\.id)
        library.pauseOverlaySession()
        library.mayBeginInteraction = { false }
        XCTAssertThrowsError(try library.togglePersonaVisibility().get())
        XCTAssertEqual(library.sessionState.phase, .paused, "A denied quick resume retains the prepared session")
        library.mayBeginInteraction = { true }
        try library.resumeOverlaySession()
        library.mayBeginInteraction = { false }
        var launch = PersonaLibraryLaunchState()
        for request in [PersonaLibraryLaunchState.Request.oneCard, .prepared(groupIDs: [group], softReveal: false), .resume] {
            let result = launch.request(request, from: .workspace, in: library)
            guard case .failure = result else { XCTAssertTrue(false, "A busy owner must return an immediate failure"); continue }
            XCTAssertTrue(launch.pending == nil)
            XCTAssertEqual(library.sessionState.instances.map(\.id), ids)
            XCTAssertEqual(library.sessionState.phase, .active)
        }
    }
    func testPresentPreviewReservesControlsAndFitsNarrowEditors() {
        for width: CGFloat in [320, 440, 620, 850] {
            for height: CGFloat in [400, 530, 730, 900] {
                for aspect: CGFloat in [0.75, 16 / 9, 2.4] {
                    let size = DemoScenesLayout.previewSize(in: CGSize(width: width, height: height), aspect: aspect)
                    XCTAssertTrue(size.width > 0 && size.height > 0)
                    XCTAssertTrue(size.width <= width - DemoScenesLayout.padding * 2 + 0.001)
                    XCTAssertTrue(size.height <= height * 0.5 + 0.001, "The canvas must leave room for fixed actions and everyday controls")
                    XCTAssertEqual(size.width / size.height, aspect, accuracy: 0.001)
                }
            }
        }
        XCTAssertTrue(DemoScenesLayout.sidebarWidth(in: 834) < DemoScenesLayout.sidebarWidth(in: 1085))
        let fallback = DemoScenesLayout.previewSize(in: CGSize(width: 620, height: 730), aspect: .nan)
        XCTAssertTrue(fallback.width.isFinite && fallback.height.isFinite)
    }

    /// Changing page keeps an unsaved Arrange overlays layout (#340). Each visit hosts a new
    /// workspace page, as the sidebar builds one per route. Persona always comes back on its own
    /// page, with its camera, shown and live panels; Arrange overlays… then opens with the edits,
    /// what is typed there is kept for the next visit, and once nothing is unsaved or the group is
    /// gone, it opens on a saved layout. Only Save layout writes.
    func testChangingPageKeepsAnUnsavedArrangement() throws {
        try MainActor.assumeIsolated {
            let (root, library, group) = try fixture()
            defer { library.shutdown(); try? FileManager.default.removeItem(at: root) }
            func fields(in view: NSView) -> [NSTextField] { ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap { fields(in: $0) } }
            /// Hosts `view` offscreen and returns the public group label field, which only Arrange
            /// overlays shows, after typing `typed` into it.
            func label(in view: AnyView, typing typed: String? = nil) -> String? {
                let size = CGSize(width: 900, height: 900)
                let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
                let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                defer { window.contentView = nil; window.close() }
                func settle() { for _ in 0..<6 { hosting.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.03)) } }
                settle()
                guard let field = fields(in: hosting).first(where: { $0.placeholderString == "Public group label (optional)" }) else { return nil }
                if let typed {
                    field.stringValue = typed
                    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
                    settle()
                }
                return field.stringValue
            }
            /// One visit to Persona: whether it opened on Arrange overlays.
            func visitOpensArrange() -> Bool { label(in: AnyView(PersonaLibraryView(library: library, mode: .workspace))) != nil }
            /// Choosing Arrange overlays… on the page: the view it shows, with its label after typing.
            func arrange(typing typed: String? = nil) -> String? {
                label(in: AnyView(PersonaPresentationPreparation(library: library, onStart: { _, _ in }, onResume: {}, onManageGroups: {},
                                                                onDraftChanged: { _ in })), typing: typed)
            }
            let saved = try contents(of: root)
            XCTAssertFalse(visitOpensArrange(), "With nothing unsaved, Persona opens on its own page")
            let original = library.groups.first { $0.id == group }!
            var moved = original.overlays!; moved[1].placement.x = 0.5; moved[1].visible = false
            let draft = PersonaPresentationDraft(groupID: group, original: original, overlays: moved, publicLabel: "Edited set", selectedID: moved[1].id)
            library.presentationDraft = draft
            XCTAssertFalse(visitOpensArrange(), "An unsaved layout leaves Persona on its own page, where a notice's recovery is")
            XCTAssertEqual(library.presentationDraft, draft, "and keeps waiting")
            XCTAssertEqual(arrange(typing: "Typed set"), "Typed set", "Arrange overlays… opens with the unsaved label")
            XCTAssertEqual(library.presentationDraft?.publicLabel, "Typed set", "and keeps what is typed there")
            XCTAssertFalse(visitOpensArrange(), "The next visit opens on Persona's own page too")
            XCTAssertEqual(arrange(), "Typed set", "and Arrange overlays… still has the typed label")
            XCTAssertEqual(library.presentationDraft?.overlays, moved, "with each overlay as it was moved and hidden")
            XCTAssertEqual(library.presentationDraft?.selectedID, moved[1].id, "and the same overlay selected")

            library.presentationDraft = PersonaPresentationDraft(groupID: group, original: original, overlays: original.overlays!,
                                                                 publicLabel: "Edited set", selectedID: nil)
            XCTAssertEqual(arrange(typing: original.publicLabel), original.publicLabel)
            XCTAssertTrue(library.presentationDraft == nil, "Typing the saved label back leaves nothing unsaved")
            XCTAssertEqual(arrange(), original.publicLabel, "so Arrange overlays… opens on the saved layout")
            XCTAssertTrue(try contents(of: root) == saved, "Keeping a layout across pages writes nothing")

            library.presentationDraft = PersonaPresentationDraft(groupID: group, original: original, overlays: moved,
                                                                 publicLabel: "Edited set", selectedID: nil)
            library.removeGroup(group)
            XCTAssertTrue(arrange() != "Edited set", "A removed group's layout does not come back")
            XCTAssertTrue(library.presentationDraft == nil, "and is dropped")

            // Back, Done, Escape and Manage groups end in the Discard question. Offscreen it cannot be
            // answered, so read its Discard changes action: it drops the kept layout too.
            let view = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Sources/StageKit/PersonaLibraryView.swift"), encoding: .utf8)
            let discard = view.components(separatedBy: "Button(\"Discard changes\", role: .destructive) {").dropFirst().first?
                .components(separatedBy: "Button(\"Keep editing\"").first ?? ""
            XCTAssertTrue(discard.contains("library.presentationDraft = nil"), "Discard changes discards the kept layout too")
        }
    }

    /// Every file under a folder, for checking that nothing in it changed.
    private func contents(of folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let base = folder.resolvingSymlinksInPath().path
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = files?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            result[String(url.resolvingSymlinksInPath().path.dropFirst(base.count))] = try Data(contentsOf: url)
        }
        return result
    }
    /// A Present scene, three saved cards and two groups, with Persona preparing the group of
    /// the first card alone and that card selected.
    private func chooserFixture(in root: URL) throws -> (DemoScenes, UUID, [SavedPersona], UUID) {
        let source = try picture(in: root)
        let scenes = DemoScenes(root: root.appendingPathComponent("Scenes"), systemIntegrationEnabled: false)
        try scenes.addImage(source, name: "Sample scene")
        guard let sceneID = scenes.selectedID else { throw PersonaError.unreadableImage }
        let library = scenes.personas
        let cards = try ["Sample A", "Sample B", "Sample C"].map { try library.addImage(source, name: $0) }
        _ = try library.createGroup(name: "Sample pair", members: [cards[1].id, cards[2].id])
        let onlyA = try library.createGroup(name: "Sample one", members: [cards[0].id])
        library.prepareGroup(onlyA)
        library.selectedID = cards[0].id
        return (scenes, sceneID, cards, onlyA)
    }
    /// Present's Add persona… only selects (#276). It lists every saved card, whatever group
    /// Persona has prepared; showing it writes nothing to Persona's selection, group or library.
    /// Use in scene places the chosen card's own copy, Cancel changes nothing, and Open Persona…
    /// closes it, then opens Persona once.
    func testPresentChooserListsEveryCardAndOnlySelects() throws {
        try MainActor.assumeIsolated {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("PresentChooser-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let (scenes, sceneID, cards, onlyA) = try chooserFixture(in: root)
            defer { scenes.shutdown() }
            let library = scenes.personas
            XCTAssertEqual(library.visibleItems.map(\.id), [cards[0].id], "Persona has prepared the group of A alone")
            let saved = try contents(of: scenes.root)
            var opened = 0
            scenes.onOpenPersonas = { opened += 1 }
            scenes.personaSceneID = sceneID; scenes.choosingPersonas = true

            let chooser = PersonaSceneChooser(model: scenes, sceneID: sceneID)
            XCTAssertEqual(chooser.candidates.map(\.id), cards.map(\.id), "Every saved card, not only the prepared group's")
            let hosting = NSHostingView(rootView: chooser)
            let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 480, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            defer { window.close() }
            for _ in 0..<5 { hosting.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            XCTAssertTrue(library.selectedID == cards[0].id && library.activeGroupID == onlyA, "Showing the chooser keeps Persona's selection and group")
            XCTAssertTrue(try contents(of: scenes.root) == saved, "Showing the chooser writes nothing")

            chooser.cancel()
            XCTAssertFalse(scenes.choosingPersonas, "Cancel closes the chooser")
            XCTAssertTrue(try contents(of: scenes.root) == saved, "Cancel leaves the scene and the library byte for byte")
            XCTAssertTrue(scenes.scenes.first { $0.id == sceneID }?.persona == nil)

            scenes.choosingPersonas = true
            chooser.use(cards[2])
            XCTAssertFalse(scenes.choosingPersonas, "Use in scene closes the chooser")
            let placed = scenes.scenes.first { $0.id == sceneID }?.persona?.image
            XCTAssertTrue(placed != nil && placed != cards[2].image && scenes.personaImage(for: scenes.scenes.first { $0.id == sceneID }!) != nil,
                          "The scene has its own copy of C: \(placed ?? "nil")")
            XCTAssertTrue(library.selectedID == cards[0].id && library.activeGroupID == onlyA, "Placing C keeps Persona's selection and group")
            XCTAssertTrue(try Data(contentsOf: scenes.root.appendingPathComponent("persona-library.json")) == saved["/persona-library.json"],
                          "and its saved library")

            scenes.personaSceneID = sceneID; scenes.choosingPersonas = true
            chooser.openPersona()
            XCTAssertFalse(scenes.choosingPersonas, "Open Persona… closes the chooser")
            XCTAssertEqual(opened, 1, "and opens Persona once")
            // Without a Persona page (the standalone scenes window), it opens the library sheet instead.
            scenes.onOpenPersonas = nil; scenes.onOpen = {}
            scenes.personaSceneID = sceneID; scenes.choosingPersonas = true
            chooser.openPersona()
            XCTAssertTrue(scenes.choosingPersonas && scenes.personaSceneID == nil, "Open Persona… falls back to the library sheet")
            XCTAssertEqual(opened, 1)
        }
    }

    /// Optional offscreen evidence. No app is installed, activated or shown.
    func testOffscreenWorkspaceLayouts() throws {
        guard let output = ProcessInfo.processInfo.environment["WORKBENCH_LAYOUT_EVIDENCE"] else { return }
        try MainActor.assumeIsolated {
            let (root, library, group) = try fixture()
            defer { library.shutdown(); try? FileManager.default.removeItem(at: root) }
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let scenes = DemoScenes(root: root.appendingPathComponent("Scenes"), systemIntegrationEnabled: false)
            defer { scenes.shutdown() }
            scenes.usesSharedControls = true
            try scenes.addImage(root.appendingPathComponent("sample.png"), name: "Sample customer with a deliberately long presentation and device name")
            let persona = try scenes.personas.addImage(root.appendingPathComponent("sample.png"), name: "Sample persona")
            scenes.usePersona(persona, in: scenes.selectedID!)
            for (name, size) in [("present-small", CGSize(width: 834, height: 730)), ("present-normal", CGSize(width: 1085, height: 780)), ("present-narrow", CGSize(width: 620, height: 650))] {
                try render(DemoScenesView(model: scenes), size: size, to: directory.appendingPathComponent(name + ".png"))
            }
            // The phone's status inside the frame and under the preview, from pinned signals; no capture runs offscreen.
            var onUSB = PhoneLinkSignals(); onUSB.usb = [.init(name: "iPhone", kind: .iPhone, productID: 0x12A8)]
            var restricted = PhoneLinkSignals(); restricted.access = .restricted
            var twoScreens = PhoneLinkSignals()
            // Two phone screens: a camera beside one phone is no longer a choice (#285, 7 October 2026).
            twoScreens.sources = [.init(id: "a", name: "Sample iPhone", isScreen: true), .init(id: "b", name: "Sample iPad", isScreen: true)]
            for (name, signals) in [("present-phone-none", PhoneLinkSignals()), ("present-phone-on-usb", onUSB), ("present-phone-restricted", restricted), ("present-phone-choose", twoScreens)] {
                scenes.phoneLink.fixture = signals
                try render(DemoScenesView(model: scenes), size: CGSize(width: 1085, height: 780), to: directory.appendingPathComponent(name + ".png"))
            }
            // The stage itself, windowed size, with the status inside the device frame.
            guard let stageScene = scenes.selected, let stageImage = scenes.image(for: stageScene) else { throw PersonaError.unreadableImage }
            for (name, signals) in [("stage-phone-none", PhoneLinkSignals()), ("stage-phone-choose", twoScreens)] {
                scenes.phoneLink.fixture = signals
                try render(DemoPresentation.offscreenStage(scene: stageScene, image: stageImage, capture: scenes.capture, phoneLink: scenes.phoneLink, root: root.appendingPathComponent("Scenes")),
                           size: CGSize(width: 1100, height: 720), to: directory.appendingPathComponent(name + ".png"))
            }
            scenes.phoneLink.fixture = nil
            for (name, size) in [("persona-small", CGSize(width: 620, height: 650)), ("persona-normal", CGSize(width: 834, height: 730))] {
                try render(PersonaLibraryView(library: library, mode: .workspace), size: size, to: directory.appendingPathComponent(name + ".png"))
            }
            // Back on Persona with an unsaved Arrange overlays layout waiting (#340): one copy moved, the other hidden, the
            // label edited. The page opens as usual; Arrange overlays… brings the layout back, rendered on its own.
            let saved = library.groups.first { $0.id == group }!
            var moved = saved.overlays!; moved[0].placement.x = 0.62; moved[1].visible = false
            library.presentationDraft = PersonaPresentationDraft(groupID: group, original: saved, overlays: moved, publicLabel: "Edited set", selectedID: moved[0].id)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                try render(PersonaLibraryView(library: library, mode: .workspace), size: CGSize(width: 1085, height: 900),
                           to: directory.appendingPathComponent("persona-arrange-kept-" + name + ".png"), appearance: NSAppearance(named: appearance))
                try render(PersonaPresentationPreparation(library: library, onStart: { _, _ in }, onResume: {}, onManageGroups: {}, onDraftChanged: { _ in })
                    .padding(24).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 828, height: 640),
                           to: directory.appendingPathComponent("persona-arrange-kept-open-" + name + ".png"), appearance: NSAppearance(named: appearance))
            }
            library.presentationDraft = nil
            // Present's selection-only chooser, with Persona preparing a group of one card.
            let chooserRoot = root.appendingPathComponent("Chooser")
            try FileManager.default.createDirectory(at: chooserRoot, withIntermediateDirectories: true)
            let (chooserScenes, chooserScene, _, _) = try chooserFixture(in: chooserRoot)
            defer { chooserScenes.shutdown() }
            // A sheet takes its content's height, so render at that height rather than inside a
            // taller frame whose spare space would draw no background.
            let chooserHeight = ceil(NSHostingView(rootView: PersonaSceneChooser(model: chooserScenes, sceneID: chooserScene)).fittingSize.height)
            for (name, appearance) in [("present-persona-chooser-light", NSAppearance.Name.aqua), ("present-persona-chooser-dark", .darkAqua)] {
                try render(PersonaSceneChooser(model: chooserScenes, sceneID: chooserScene), size: CGSize(width: 480, height: chooserHeight),
                           to: directory.appendingPathComponent(name + ".png"), appearance: NSAppearance(named: appearance))
            }
            library.usesSharedControls = true
            try library.startOverlaySession(groupIDs: [group], initialGroupID: group)
            for paused in [false, true] {
                if paused { library.pauseOverlaySession() }
                let name = paused ? "persona-live-set-hidden" : "persona-live-set-active"
                try render(PersonaLibraryView(library: library, mode: .workspace), size: CGSize(width: 620, height: 730),
                    to: directory.appendingPathComponent(name + ".png"))
            }
        }
    }
    @MainActor private func render<V: View>(_ content: V, size: CGSize, to url: URL, appearance: NSAppearance? = nil) throws {
        let hosting = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // Workbench's theme reads its own appearance, chosen here in the argument domain, which is
        // never saved; afterwards it returns to the system's.
        if let appearance {
            window.appearance = appearance
            var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments["appearance"] = appearance.name == .darkAqua ? "Dark" : "Light"
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            WorkbenchSettings.shared.refresh()
        }
        defer {
            if appearance != nil {
                var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
                arguments["appearance"] = nil
                UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
                WorkbenchSettings.shared.refresh()
            }
        }
        window.contentView = hosting
        defer { window.close() }
        hosting.frame = CGRect(origin: .zero, size: size)
        for _ in 0..<10 { hosting.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw PersonaError.unreadableImage }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw PersonaError.unreadableImage }
        try data.write(to: url)
        XCTAssertEqual(hosting.bounds.size, size)
        print("Offscreen layout: " + url.path)
    }
}
