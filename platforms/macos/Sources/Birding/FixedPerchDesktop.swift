import AppKit
import ColorSync
import BirdingCore

extension DesktopController {
    var fixedPerchDisplayIDs:[String] {
        NSScreen.screens.map {screen in
            guard let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let reference=CGDisplayCreateUUIDFromDisplayID(number.uint32Value) else {return ""}
            return CFUUIDCreateString(nil,reference.takeRetainedValue()) as String
        }
    }
}
