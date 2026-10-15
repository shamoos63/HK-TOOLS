import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Dense HUD layout: open large, never shrink below the sidebar + tables.
    let size = NSSize(width: 1480, height: 920)
    if let screen = NSScreen.main?.visibleFrame {
      let w = min(size.width, screen.width - 40)
      let h = min(size.height, screen.height - 40)
      self.setFrame(
        NSRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h),
        display: true)
    }
    self.contentMinSize = NSSize(width: 1180, height: 720)
    self.title = "HK Tools"
    self.titlebarAppearsTransparent = true
    self.backgroundColor = NSColor(red: 0.043, green: 0.059, blue: 0.098, alpha: 1)
    self.appearance = NSAppearance(named: .darkAqua)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
