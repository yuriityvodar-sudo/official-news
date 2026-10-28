import 'package:flutter/cupertino.dart';

/// The AI chat's and its paywall's colours (#146): the Garnet red, deep enough
/// for white words on a button; a lighter one for words on a dark page. The
/// Seal look's green joins it with the looks (#176).
class ChatStyle {
  ChatStyle._(this.fill, this.ink);

  factory ChatStyle.of(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return ChatStyle._(
      const Color(0xFFC41230),
      dark ? const Color(0xFFFF5A72) : const Color(0xFFC41230),
    );
  }

  /// A button's and the reader's bubble's colour, under white words.
  final Color fill;

  /// Words and icons in the colour, on the page.
  final Color ink;
}
