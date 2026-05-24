import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Make Flutter content use the full window (no extra top bar strip)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true
    self.toolbar = nil

    // Rounded app content corners (window content)
    self.isOpaque = false
    self.backgroundColor = .clear
    if let contentView = self.contentView {
      contentView.wantsLayer = true
      contentView.layer?.cornerRadius = 14
      contentView.layer?.masksToBounds = true
    }

    if #available(macOS 11.0, *) {
      self.toolbarStyle = .unifiedCompact
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Set initial window size (larger for better experience on macOS)
    self.setContentSize(NSSize(width: 1800, height: 1200))
    
    // Set minimum window size
    self.minSize = NSSize(width: 1600, height: 1000)
    // Optional: Center window on launch
    self.center()

    super.awakeFromNib()
  }
}
