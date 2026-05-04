import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import 'key_button.dart';

class Numpad extends StatelessWidget {
  final void Function(String key) onKey;
  const Numpad({super.key, required this.onKey});

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final cells = <_Cell>[
      _Cell.digit('1'), _Cell.digit('2'), _Cell.digit('3'),
      _Cell.digit('4'), _Cell.digit('5'), _Cell.digit('6'),
      _Cell.digit('7'), _Cell.digit('8'), _Cell.digit('9'),
      _Cell.symbol('STAR', '*'),
      _Cell.digit('0'),
      _Cell.icon('DEL', Icons.backspace_outlined),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.sunken,
        borderRadius: BorderRadius.circular(28),
      ),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.4,
        children: [
          for (final c in cells)
            KeyButton(
              radius: BorderRadius.circular(16),
              onPressed: () => onKey(c.key),
              textStyle: GoogleFonts.dmMono(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: c.muted ? p.muted : p.ink,
              ),
              child: c.icon != null
                  ? Icon(c.icon, size: 22, color: p.muted)
                  : Text(c.label!),
            ),
        ],
      ),
    );
  }
}

class _Cell {
  final String key;
  final String? label;
  final IconData? icon;
  final bool muted;
  _Cell._(this.key, this.label, this.icon, this.muted);

  factory _Cell.digit(String s) => _Cell._(s, s, null, false);
  factory _Cell.symbol(String key, String label) => _Cell._(key, label, null, true);
  factory _Cell.icon(String key, IconData ic) => _Cell._(key, null, ic, true);
}
