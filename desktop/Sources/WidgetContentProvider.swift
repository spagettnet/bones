import AppKit

@MainActor
protocol WidgetContentProvider {
    var preferredSize: NSSize { get }
    func makeView(frame: NSRect) -> NSView
}
