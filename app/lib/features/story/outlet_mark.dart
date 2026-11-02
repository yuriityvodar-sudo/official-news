import 'package:flutter/widgets.dart';

import '../../core/story.dart';

/// An outlet's mark: its initials ([outletInitials]) in white on iOS's grey
/// for a contact without a photo, as the app has no colours of the outlets'
/// own. [border], the colour behind it, parts marks that overlap.
class OutletMark extends StatelessWidget {
  const OutletMark(this.outlet, {super.key, required this.size, this.border});

  final String outlet;
  final double size;
  final Color? border;

  static const _grey = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFA5ABB8), Color(0xFF858994)],
  );

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: _grey,
      border: border == null ? null : Border.all(color: border!, width: 1.5),
    ),
    child: Text(
      outletInitials(outlet),
      // A mark, not words to read: the outlet's name is beside it, or in
      // its card's label.
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: size / 2,
        fontWeight: FontWeight.w800,
        height: 1,
        color: const Color(0xFFFFFFFF),
      ),
    ),
  );
}
