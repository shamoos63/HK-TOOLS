import Cocoa
import FlutterMacOS
import macos_window_utils

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // macos_window_utils (used by flutter_acrylic) hosts the Flutter view on
    // top of an NSVisualEffectView; Window.setEffect(WindowEffect.sidebar)
    // from Dart picks its material. Flutter paints the sidebar transparent
    // and the main panel solid.
    let macOSWindowUtilsViewController = MacOSWindowUtilsViewController()
    self.contentViewController = macOSWindowUtilsViewController

    // Dense layout: open large, never shrink below the sidebar + tables.
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

    // Native canvas must not block the effect behind Flutter.
    self.isOpaque = false
    self.backgroundColor = .clear
    // Content runs under the title bar so the traffic lights sit inside the
    // translucent sidebar (Flutter leaves room: macTitleBarInset).
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    MainFlutterWindowManipulator.start(mainFlutterWindow: self)

    let flutterViewController = macOSWindowUtilsViewController.flutterViewController
    flutterViewController.backgroundColor = .clear

    // Settings › Appearance can force light / dark; "system" follows macOS.
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
