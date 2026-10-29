import Flutter
import SwiftUI
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
    // The Garnet and Seal looks' pills in Liquid Glass (#166).
    if let pills = engineBridge.pluginRegistry.registrar(forPlugin: "official_news/pills") {
      pills.register(PillsViewFactory(messenger: pills.messenger()), withId: "official_news/pills")
    }
    // The phone's Region setting, for For you (#170).
    if let region = engineBridge.pluginRegistry.registrar(forPlugin: "official_news/region") {
      FlutterMethodChannel(name: "official_news/region", binaryMessenger: region.messenger())
        .setMethodCallHandler { _, result in result(AppDelegate.phoneRegion()) }
    }
  }

  /// The country of iOS Settings → General → Language & Region → Region
  /// (#170). Flutter's locale is the first preferred language instead, whose
  /// region can be another: "en-GB" on a phone set to Germany (Yurii, #201).
  static func phoneRegion() -> String? {
    if #available(iOS 16, *) { return Locale.current.region?.identifier }
    // iOS 15: a region set apart from the language is the identifier's "rg"
    // keyword ("en_GB@rg=dezzzz"), else its own region.
    let id = Locale.current.identifier
    if let range = id.range(of: "rg=") {
      return String(id[range.upperBound...].prefix(2)).uppercased()
    }
    return Locale.current.regionCode
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

/// The Garnet and Seal looks' pills, drawn by iOS (Roman, 27 Oct, #166): what
/// the feed shows (For you, The whole world, the topics) as a row of SwiftUI
/// buttons in Liquid Glass from iOS 26, the chosen one a drop of the look's
/// colour that flows to the pill tapped; the system's translucent material
/// before iOS 26. Flutter sends the pills, the chosen one, the colour and
/// light or dark (`update`); a tap goes back as `select` with the pill's id
/// (`pill-for-you`, `pill-world`, `pill-topic-economy`), and where the row
/// rests once swiped as `scrolled` (iOS 26), on the channel
/// `official_news/pills_<id>`.
class PillsViewFactory: NSObject, FlutterPlatformViewFactory {
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
    PillsView(
      frame: frame,
      channel: FlutterMethodChannel(
        name: "official_news/pills_\(viewId)", binaryMessenger: messenger),
      arguments: args as? [String: Any] ?? [:])
  }
}

class PillsView: NSObject, FlutterPlatformView {
  private let model: PillsModel
  private let host: UIHostingController<PillsRow>
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, arguments: [String: Any]) {
    let model = PillsModel()
    model.update(arguments, animated: false)
    self.model = model
    self.channel = channel
    host = UIHostingController(rootView: PillsRow(model: model))
    super.init()
    model.onSelect = { [weak self] id in
      self?.channel.invokeMethod("select", arguments: id)
    }
    model.onScroll = { [weak self] offset in
      self?.channel.invokeMethod("scrolled", arguments: Double(offset))
    }
    host.view.frame = frame
    host.view.backgroundColor = .clear
    host.overrideUserInterfaceStyle = model.dark ? .dark : .light
    // The same row takes every change, so the drop flows instead of a new row appearing.
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update", let args = call.arguments as? [String: Any], let self {
        self.model.update(args, animated: true)
        self.host.overrideUserInterfaceStyle = self.model.dark ? .dark : .light
      }
      result(nil)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { host.view }
}

final class PillsModel: ObservableObject {
  struct Pill: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
  }

  @Published var pills: [Pill] = []
  @Published var chosen = ""
  @Published var tint = Color.accentColor
  @Published var dark = false
  var onSelect: (String) -> Void = { _ in }
  var onScroll: (CGFloat) -> Void = { _ in }

  /// How far the row is swiped, told to Flutter once it rests: Flutter's own
  /// row, shown while an article grows out of its card, stands the same.
  var offset: CGFloat = 0

  /// How the drop moves: a spring that settles with a little give, as iOS's
  /// own selections do.
  static let flow = Animation.spring(response: 0.48, dampingFraction: 0.74)

  func update(_ args: [String: Any], animated: Bool) {
    let pills = (args["pills"] as? [[String: Any]] ?? []).map {
      Pill(
        id: $0["id"] as? String ?? "",
        title: $0["title"] as? String ?? "",
        symbol: $0["symbol"] as? String ?? "")
    }
    if pills != self.pills { self.pills = pills }
    tint = Color(uiColor: UIColor(argb: args["tint"] as? Int ?? 0))
    dark = args["dark"] as? Bool ?? false
    let chosen = args["chosen"] as? String ?? ""
    guard chosen != self.chosen else { return }
    if animated {
      withAnimation(Self.flow) { self.chosen = chosen }
    } else {
      self.chosen = chosen
    }
  }

  /// The tap's haptic comes from Flutter, as for every other way to choose what
  /// the feed shows.
  func tap(_ id: String) {
    guard id != chosen else { return }
    withAnimation(Self.flow) { chosen = id }
    onSelect(id)
  }
}

struct PillsRow: View {
  @ObservedObject var model: PillsModel

  /// The pills in Flutter's row (58 points at the usual text size, taller as
  /// the text grows), where Flutter's own pills are, with room under them
  /// for the glass's shadow.
  static let insets = EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16)

  var body: some View {
    Group {
      if #available(iOS 26.0, *) {
        GlassPills(model: model)
      } else {
        MaterialPills(model: model)
      }
    }
    .environment(\.colorScheme, model.dark ? .dark : .light)
    .ignoresSafeArea()
  }
}

/// A pill's icon and name, white on the chosen one's colour. At least 36
/// points high, and growing with the reader's text size as Flutter's pills
/// do (Yurii, #210): the subheadline is 15 points at the usual size.
struct PillLabel: View {
  let pill: PillsModel.Pill
  let chosen: Bool

  var body: some View {
    HStack(spacing: 6) {
      // VoiceOver reads the name alone.
      Image(systemName: pill.symbol).accessibilityHidden(true)
      Text(pill.title).lineLimit(1)
    }
    .font(.subheadline.weight(.semibold))
    .foregroundColor(chosen ? .white : .primary)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .frame(minHeight: 36)
    .contentShape(Capsule())
  }
}

/// iOS 26: every pill is Liquid Glass; the chosen one's glass is tinted and
/// keeps one id, so iOS flows it from pill to pill, merging with the glass it
/// passes, as its own tab bars and segmented controls do.
@available(iOS 26.0, *)
struct GlassPills: View {
  @ObservedObject var model: PillsModel
  @Namespace private var glass

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        GlassEffectContainer(spacing: 4) {
          HStack(spacing: 8) {
            ForEach(model.pills) { pill in
              let chosen = pill.id == model.chosen
              Button {
                model.tap(pill.id)
              } label: {
                PillLabel(pill: pill, chosen: chosen)
              }
              .buttonStyle(.plain)
              .glassEffect(
                chosen ? .regular.tint(model.tint).interactive() : .regular.interactive(),
                in: Capsule()
              )
              .glassEffectID(chosen ? "chosen" : pill.id, in: glass)
              .accessibilityAddTraits(chosen ? .isSelected : [])
              .id(pill.id)
            }
          }
          .padding(PillsRow.insets)
        }
      }
      .scrollClipDisabled()
      .onAppear { proxy.scrollTo(model.chosen, anchor: .center) }
      .onChange(of: model.chosen) { _, id in
        withAnimation(PillsModel.flow) { proxy.scrollTo(id, anchor: .center) }
      }
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        geometry.contentOffset.x + geometry.contentInsets.leading
      } action: { _, offset in
        model.offset = offset
      }
      .onScrollPhaseChange { _, phase in
        if phase == .idle { model.onScroll(model.offset) }
      }
    }
  }
}

/// Before iOS 26: the system's translucent material, and a drop of the colour
/// that slides to the chosen pill.
struct MaterialPills: View {
  @ObservedObject var model: PillsModel
  @Namespace private var drop

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(model.pills) { pill in
            let chosen = pill.id == model.chosen
            Button {
              model.tap(pill.id)
            } label: {
              PillLabel(pill: pill, chosen: chosen)
            }
            .buttonStyle(.plain)
            .background(
              ZStack {
                Capsule().fill(.ultraThinMaterial)
                if chosen {
                  Capsule().fill(model.tint).matchedGeometryEffect(id: "drop", in: drop)
                }
              }
            )
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .id(pill.id)
          }
        }
        .padding(PillsRow.insets)
      }
      .onAppear { proxy.scrollTo(model.chosen, anchor: .center) }
      .onChange(of: model.chosen) { id in
        withAnimation(PillsModel.flow) { proxy.scrollTo(id, anchor: .center) }
      }
    }
  }
}

extension UIColor {
  /// A colour as Flutter's `Color.toARGB32()` writes it.
  convenience init(argb: Int) {
    self.init(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }
}
