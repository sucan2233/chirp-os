import AppKit

/// Handler-only input for native verification. Never posts an event or moves
/// the system pointer. Separate clicks must survive production callback dedup.
enum NativeVerificationInput {
    private static var nextEventNumber:Int64=1000

    static func leftDown(at point:CGPoint)->NSEvent? {
        precondition(Thread.isMainThread)
        guard let event=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,
                                mouseCursorPosition:point,mouseButton:.left) else {return nil}
        precondition(nextEventNumber<Int64.max)
        event.setIntegerValueField(.mouseEventNumber,value:nextEventNumber)
        nextEventNumber+=1
        return NSEvent(cgEvent:event)
    }
}
