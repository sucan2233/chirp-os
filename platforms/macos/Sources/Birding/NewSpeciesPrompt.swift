import AppKit
import BirdingCore

extension DesktopController {
    /// Kept for existing launch callers. Pending species are presented in
    /// Settings, never in a recurring startup modal and never auto-allocated.
    func promptNewSpecies() {
        settingsWindow?.refreshNewSpeciesNotice()
    }
}
