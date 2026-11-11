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
    // Title bar takes the app's background: graphite in dark mode, light grey
    // in light mode (matches HudPalette in hud_theme.dart).
    self.backgroundColor = NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.067, green: 0.075, blue: 0.090, alpha: 1)
        : NSColor(red: 0.957, green: 0.961, blue: 0.969, alpha: 1)
    }

    // The app picks light / dark (Settings › Appearance); "system" follows
    // macOS. Without this the title bar would not follow an override.
    let channel = FlutterMethodChannel(
      name: "hk_tools/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "setAppearance" {
        switch call.arguments as? String {
        case "light": self?.appearance = NSAppearance(named: .aqua)
        case "dark": self?.appearance = NSAppearance(named: .darkAqua)
        default: self?.appearance = nil
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
