import Foundation

/// 0.3.0 removed the CTC glossary helper (Parakeet CTC 110M), which was off by default and could only be
/// turned on in the Debug menu. Whoever had it on has its model folder (about 100 MB) in FluidAudio's folder:
/// it is deleted once, on the first launch after the update, and the old `glossaryHelper` preference goes with it.
/// Nothing else is touched: not the speech model, not the glossary, not the replacements.
enum RetiredGlossaryHelper {
    static let preferenceKey = "glossaryHelper"
    static let folderName = "parakeet-ctc-110m-coreml"

    /// Where FluidAudio put the helper: `<Application Support>/FluidAudio/Models/parakeet-ctc-110m-coreml`.
    static func folder(applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent("FluidAudio/Models", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// Deletes the folder if it exists and removes the preference if it is set. Returns what it did, for the log.
    @discardableResult
    static func cleanUp(applicationSupport: URL, defaults: UserDefaults, fileManager: FileManager = .default) -> Result {
        var result = Result()
        let folder = folder(applicationSupport: applicationSupport)
        if fileManager.fileExists(atPath: folder.path) {
            do {
                try fileManager.removeItem(at: folder)
                result.deletedFolder = true
            } catch {
                result.error = error.localizedDescription
            }
        }
        if defaults.object(forKey: preferenceKey) != nil {
            defaults.removeObject(forKey: preferenceKey)
            result.removedPreference = true
        }
        return result
    }

    struct Result: Equatable {
        var deletedFolder = false
        var removedPreference = false
        var error: String?
    }

    /// At launch: quietly, with one line in the log only when something was removed.
    static func runAtLaunch() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let result = cleanUp(applicationSupport: support, defaults: AppDefaults.standard)
        if let error = result.error {
            Log.models.error("Removing the old glossary helper failed: \(error, privacy: .public)")
        } else if result.deletedFolder || result.removedPreference {
            Log.models.notice("Removed the old glossary helper (folder: \(result.deletedFolder ? "deleted" : "none"), preference: \(result.removedPreference ? "removed" : "none"))")
        }
    }
}
