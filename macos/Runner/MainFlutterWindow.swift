import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Flutter draws on top of a vibrancy view (the blurred desktop) hosted
    // by a container controller, so mouse events still reach Flutter.
    let container = BlurContainerViewController()
    self.contentViewController = container
    container.addChild(flutterViewController)
    flutterViewController.view.frame = container.view.bounds
    flutterViewController.view.autoresizingMask = [.width, .height]
    container.view.addSubview(flutterViewController.view)

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
    // Content (and the blur) runs under the title bar; Flutter leaves room
    // for the window buttons (macTitleBarHeight in window_chrome.dart).
    self.styleMask.insert(.fullSizeContentView)
    self.titleVisibility = .hidden
    // Solid fallback (Reduced visual effects): the app's background, graphite
    // in dark mode and light grey in light mode (matches hud_theme.dart).
    let solid = NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.067, green: 0.075, blue: 0.090, alpha: 1)
        : NSColor(red: 0.957, green: 0.961, blue: 0.969, alpha: 1)
    }

    // Translucent window: the desktop shows through, blurred, behind the
    // Flutter content (which paints semi-transparent backgrounds).
    flutterViewController.backgroundColor = .clear
    let effect = container.effect
    self.isOpaque = false
    self.backgroundColor = .clear

    func setGlass(_ on: Bool) {
      effect.isHidden = !on
      self.backgroundColor = on ? .clear : solid
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
      } else if call.method == "setGlass" {
        setGlass((call.arguments as? Bool) ?? true)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

/// Root view controller: an `NSVisualEffectView` behind the Flutter view.
class BlurContainerViewController: NSViewController {
  let effect = NSVisualEffectView()

  override func loadView() {
    effect.blendingMode = .behindWindow
    effect.material = .underWindowBackground
    effect.state = .active
    effect.autoresizingMask = [.width, .height]
    view = effect
  }
}
