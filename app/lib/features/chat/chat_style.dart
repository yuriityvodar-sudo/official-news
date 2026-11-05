import 'package:flutter/cupertino.dart';

import '../../core/feed_design.dart';
import '../feed/feed_look.dart' show feedDesign;

/// The AI chat's and its paywall's colours (#146): the Seal look's green when
/// the feed is in it, otherwise the Garnet red, both deep enough for white
/// words on a button; a lighter one for words on a dark page.
class ChatStyle {
  ChatStyle._(this.fill, this.ink, this.cover);

  factory ChatStyle.of(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return feedDesign.value == FeedDesign.seal
        ? ChatStyle._(
            const Color(0xFF0E7A5E),
            dark ? const Color(0xFF3DD4A3) : const Color(0xFF0E7A5E),
            const [Color(0xFF0E7A5E), Color(0xFF0A5C47), Color(0xFF053A2C)],
          )
        : ChatStyle._(
            const Color(0xFFC41230),
            dark ? const Color(0xFFFF5A72) : const Color(0xFFC41230),
            const [Color(0xFFC41230), Color(0xFF9E0E27), Color(0xFF670A1A)],
          );
  }

  /// A button's and the reader's bubble's colour, under white words.
  final Color fill;

  /// Words and icons in the colour, on the page.
  final Color ink;

  /// The chat's cover, deepening, the same in both themes, under white words.
  final List<Color> cover;
}
