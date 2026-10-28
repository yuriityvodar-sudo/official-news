import Flutter
import UIKit
import firebase_messaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Push (#62): with UIScene, plugins register after this returns, but iOS needs
    // the notification delegate before launch ends, or the tap that started the
    // app is lost (firebase_messaging's own instructions for UIScene apps).
    FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The Liquid Glass surface behind the feed's settings gear (#66).
    engineBridge.pluginRegistry
      .registrar(forPlugin: "official_news/glass")?
      .register(GlassViewFactory(), withId: "official_news/glass")
    // iOS's own pull-down menus for the feed's filter chips (#141).
    if let menus = engineBridge.pluginRegistry.registrar(forPlugin: "official_news/menu") {
      menus.register(MenuViewFactory(messenger: menus.messenger()), withId: "official_news/menu")
    }
  }
}

/// A round Liquid Glass surface (iOS 26, Yurii, 20 Oct) behind the feed's
/// settings gear. Flutter draws the icon and takes the tap; this view only
/// draws the glass, over whatever Flutter has under it. On iOS before 26 it
/// draws the plain grey circle the button had (the app runs from iOS 15).
class GlassViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return GlassView(frame: frame)
  }
}

class GlassView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    // Taps fall through to Flutter's button (PlatformViewHitTestBehavior.transparent).
    container.isUserInteractionEnabled = false
    if #available(iOS 26.0, *) {
      let glass = UIGlassEffect()
      glass.isInteractive = false
      let effect = UIVisualEffectView(effect: glass)
      effect.frame = container.bounds
      effect.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      effect.cornerConfiguration = .capsule()
      container.addSubview(effect)
    } else {
      let circle = CircleView(frame: container.bounds)
      circle.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      container.addSubview(circle)
    }
    super.init()
  }

  func view() -> UIView { container }
}

/// The plain circle, iOS 15 to 18: the system's secondary fill, as the
/// Flutter button drew (surfaceContainerHighest), round at any size.
class CircleView: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .secondarySystemFill
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = min(bounds.width, bounds.height) / 2
  }
}

/// A clear button over a filter chip that opens iOS's own pull-down menu
/// (#141): Liquid Glass from iOS 26, the system's animation and haptics.
/// Flutter draws the chip under it and sends the items; the chosen item goes
/// back as [section, row] on the channel `official_news/menu_<id>`.
class MenuViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    MenuView(
      frame: frame,
      channel: FlutterMethodChannel(
        name: "official_news/menu_\(viewId)", binaryMessenger: messenger),
      arguments: args as? [String: Any] ?? [:])
  }
}

class MenuView: NSObject, FlutterPlatformView {
  private let button: UIButton
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, arguments: [String: Any]) {
    self.channel = channel
    button = UIButton(type: .custom)
    button.frame = frame
    button.backgroundColor = .clear
    button.showsMenuAsPrimaryAction = true
    button.accessibilityLabel = arguments["label"] as? String
    super.init()
    let sections = arguments["sections"] as? [[[String: Any]]] ?? []
    // Each group of items inline, with the system's wide divider between.
    let groups = sections.enumerated().map { section, items in
      UIMenu(
        title: "", options: .displayInline,
        children: items.enumerated().map { row, item in
          UIAction(
            title: item["title"] as? String ?? "",
            image: (item["symbol"] as? String).flatMap { UIImage(systemName: $0) },
            state: item["selected"] as? Bool == true ? .on : .off
          ) { [weak self] _ in
            self?.channel.invokeMethod("select", arguments: [section, row])
          }
        })
    }
    button.menu = UIMenu(title: "", children: groups)
  }

  func view() -> UIView { button }
}
