import AppKit
import Carbon
import ServiceManagement

/// Each StageKit notice records the page that owns it where it is raised, and the controller the
/// menu-bar panel reads reports that page (#134 review). Guessing from the words sent all of these
/// to Draw; these fail on that version.
final class NoticeOwnerTests: XCTestCase {
    private struct LoginFixtureError: LocalizedError { var errorDescription: String? { "Synthetic login failure" } }
    private struct ScreenshotFixtureError: LocalizedError { var errorDescription: String? { "Synthetic screenshot failure" } }

    /// A disposable coordinator and the controller the panel reads, on a temporary folder only.
    private func withFixture(settingsData: Data? = nil, _ body: @MainActor (AppCoordinator, StageKitController) -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WorkbenchNoticeOwnerTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: root.appendingPathComponent("settings").path)!
        if let settingsData { defaults.set(settingsData, forKey: "preferences.v1") }
        let settings = SettingsStore(defaults: defaults)
        let app = AppCoordinator(settings: settings, archiveURL: root.appendingPathComponent("boards.json"), embedded: true)
        let scenes = DemoScenes(root: root.appendingPathComponent("Scenes"), systemIntegrationEnabled: false)
        app.demoScenes = scenes
        defer { scenes.shutdown() }
        MainActor.assumeIsolated { body(app, StageKitController(coordinator: app)) }
    }

    func testShortcutRecordingNoticesBelongToKeyboard() {
        withFixture { app, stage in
            app.record(Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey)), for: .pen)
            XCTAssertEqual(stage.notice, "Include Control or Option with your shortcut.")
            XCTAssertTrue(stage.noticePage == .keyboard, "A shortcut without Control or Option is Settings › Keyboard's to explain")
            let taken = app.settings.value.shortcut(for: .arrow)
            app.record(Shortcut(keyCode: taken.keyCode, modifiers: taken.modifiers), for: .pen)
            XCTAssertEqual(stage.notice, "That shortcut belongs to \(Action.arrow.title). Choose another combination.")
            XCTAssertTrue(stage.noticePage == .keyboard, "A shortcut another action has is Settings › Keyboard's to explain")
            XCTAssertTrue(stage.notice(on: .keyboard) == stage.notice && stage.notice(on: .draw) == nil, "Keyboard owns it, not Draw")
        }
    }

    func testLoginNoticesBelongToGeneral() {
        withFixture { app, stage in
            app.loginItem = { _ in throw LoginFixtureError() }
            app.setLaunchAtLogin(true)
            XCTAssertEqual(stage.notice, "Login setting could not be changed: Synthetic login failure")
            XCTAssertTrue(stage.noticePage == .general, "Open at login is Settings › General's")
            XCTAssertFalse(app.launchAtLogin)
        }
    }

    func testSavedSettingsNoticesBelongToGeneral() {
        withFixture(settingsData: Data("invalid".utf8)) { app, stage in
            XCTAssertEqual(stage.notice, "Saved settings could not be read. Defaults are in use; the original settings have been preserved.")
            XCTAssertTrue(stage.noticePage == .general, "Saved settings are Settings › General's")
            XCTAssertTrue(stage.notice(on: .general) == stage.notice && stage.notice(on: .draw) == nil, "General owns it, not Draw")
            // A drawing notice raised afterwards is Draw's and comes first; General keeps its own.
            app.copyBoard()
            XCTAssertTrue(stage.noticePage == .draw, "A board that could not be copied is Draw's")
            XCTAssertTrue(stage.notice(on: .general) != nil, "General still shows its saved-settings notice")
            app.clearNotice(); app.settings.clearNotice()
            XCTAssertTrue(stage.notice == nil && stage.noticePage == nil, "Draw's dismiss clears both")
        }
    }

    /// Something that worked is confirmed on its own page and never becomes the panel's orange
    /// problem row (#134 T5, Fit 7). The tone is recorded where each notice is raised, never read
    /// from its words, and a confirmation never stands in front of a live problem.
    func testSuccessesStayOnTheirPageAndNeverHideAProblem() {
        withFixture { app, stage in
            var finish: ((Error?) -> Void)?
            app.screenshotLauncher = { completion in finish = completion }
            func screenshot(closingWith error: Error?) {
                app.openScreenshot()
                XCTAssertTrue(app.screenshotHandoffActive, "Screenshot opened")
                finish?(error)
                let deadline = Date().addingTimeInterval(1)
                while app.screenshotHandoffActive && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                XCTAssertFalse(app.screenshotHandoffActive, "Screenshot closed")
            }
            // (a) Screenshot closing as expected is Draw's quiet confirmation, not a problem.
            screenshot(closingWith: nil)
            XCTAssertTrue(stage.notice == nil && stage.noticePage == nil, "A Screenshot that closed is not a problem: \(stage.notice ?? "nil")")
            XCTAssertTrue(stage.notice(on: .draw)?.hasPrefix("Screenshot closed.") == true, "Draw still confirms it")
            // (d) Draw's confirmation never hides a problem raised after it.
            app.demoScenes.notice = "A scene problem"
            XCTAssertEqual(stage.notice, "A scene problem")
            XCTAssertTrue(stage.noticePage == .present, "The problem's own page, not Draw")
            app.demoScenes.notice = nil
            // (b) Screenshot that could not open stays a Draw problem.
            screenshot(closingWith: ScreenshotFixtureError())
            XCTAssertTrue(stage.notice?.hasPrefix("Screenshot could not open") == true, "\(stage.notice ?? "nil")")
            XCTAssertTrue(stage.noticePage == .draw, "A Screenshot that could not open is Draw's problem")
            // (c) A board that could not be copied is still a Draw problem.
            app.clearNotice()
            app.copyBoard()
            XCTAssertTrue(stage.notice != nil && stage.noticePage == .draw, "No board to copy is Draw's problem")
            app.clearNotice()
            // (e) A scene saved as My device is Present's confirmation; a later notice is a problem again.
            let scenes = app.demoScenes
            let image = FileManager.default.temporaryDirectory.appendingPathComponent("NoticeOwnerScene-" + UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: image) }
            do {
                try SceneLibraryStorage.textLogo("Synthetic scene").write(to: image)
                try scenes.addImage(image)
            } catch { XCTAssertTrue(false, "Synthetic scene: \(error)"); return }
            scenes.saveMyDevice()
            XCTAssertEqual(scenes.notice, "My device saved. Use it in any scene.")
            XCTAssertTrue(stage.notice == nil && stage.noticePage == nil, "My device saved is not a problem: \(stage.notice ?? "nil")")
            XCTAssertEqual(stage.notice(on: .present), "My device saved. Use it in any scene.")
            scenes.notice = "x"
            XCTAssertEqual(stage.notice, "x", "Any other scene notice is a problem")
            XCTAssertTrue(stage.noticePage == .present)
            scenes.notice = nil
            // Persona's confirmations stay on Persona the same way.
            let personas = scenes.personas
            do {
                let group = try personas.createGroup(name: "Synthetic group")
                personas.removeGroup(group)
            } catch { XCTAssertTrue(false, "Synthetic group: \(error)"); return }
            XCTAssertEqual(personas.notice, "Group removed. Its personas, images and scenes are kept.")
            XCTAssertTrue(stage.notice == nil && stage.noticePage == nil, "A removed group is not a problem: \(stage.notice ?? "nil")")
            XCTAssertEqual(stage.notice(on: .persona), "Group removed. Its personas, images and scenes are kept.")
            personas.notice = "y"
            XCTAssertEqual(stage.notice, "y", "Any other Persona notice is a problem")
            XCTAssertTrue(stage.noticePage == .persona)
        }
    }
}
