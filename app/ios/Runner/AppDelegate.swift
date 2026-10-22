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
