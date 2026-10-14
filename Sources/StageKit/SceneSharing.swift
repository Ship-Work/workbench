import AppKit
import SceneSyncKit

extension DemoScenes {
    func importSceneCopy() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [SceneFile.contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import copy"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        MainActor.assumeIsolated {
            do {
                guard let library = sceneSync?.library else { throw SceneDocumentError.invalid("The scene library is unavailable.") }
                let record = try library.importPackage(SceneFile.read(url))
                query = ""; selectedID = record.id
                confirm("Imported an independent scene. The sender’s copy stays unchanged.")
            } catch { notice = error.localizedDescription }
        }
    }

    func exportSceneCopy() {
        MainActor.assumeIsolated {
            do {
                guard let selected, let library = sceneSync?.library,
                      let record = library.records.first(where: { $0.id == selected.id && !$0.isDeleted }) else {
                    throw SceneDocumentError.invalid("Choose a saved scene to share.")
                }
                let data = try library.package(for: record.scene).encoded()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [SceneFile.contentType]
                panel.nameFieldStringValue = "Workbench scene." + SceneFile.fileExtension
                panel.prompt = "Save copy"
                panel.message = "Includes this scene’s pictures and editable layout. It does not give access to your library."
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try data.write(to: url, options: .atomic)
                confirm("Saved an editable scene copy. Share the file using Finder or your usual app.")
            } catch { notice = error.localizedDescription }
        }
    }
}
