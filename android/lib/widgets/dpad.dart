import 'package:flutter/material.dart';

import '../main.dart';
import 'key_button.dart';

class Dpad extends StatelessWidget {
  final void Function(String key) onKey;
  const Dpad({super.key, required this.onKey});

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 28.0; // outer breathing room inside the plate
        const gap = 14.0;     // gap between cells
        const minBox = 280.0;
        const maxBox = 360.0;

        // pick the largest plate that fits the parent
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxBox;
        final boxSize = available.clamp(minBox, maxBox);

        // 3 cells across with 2 inter-cell gaps inside the padded inner box
        final inner = boxSize - padding * 2;
        final cellSize = (inner - gap * 2) / 3;

        Widget row(List<Widget> children) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                SizedBox(width: cellSize, height: cellSize, child: children[i]),
              ],
            ],
          );
        }

        Widget spacer() => SizedBox(width: cellSize, height: cellSize);

        return Center(
          child: Container(
            width: boxSize,
            height: boxSize,
            padding: const EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: p.sunken,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                row([spacer(), _arrow(context, 'UP', Icons.keyboard_arrow_up_rounded), spacer()]),
                SizedBox(height: gap),
                row([
                  _arrow(context, 'LEFT', Icons.keyboard_arrow_left_rounded),
                  _ok(context),
                  _arrow(context, 'RIGHT', Icons.keyboard_arrow_right_rounded),
                ]),
                SizedBox(height: gap),
                row([spacer(), _arrow(context, 'DOWN', Icons.keyboard_arrow_down_rounded), spacer()]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _arrow(BuildContext context, String key, IconData icon) {
    return KeyButton(
      onPressed: () => onKey(key),
      radius: BorderRadius.circular(22),
      child: Icon(icon, size: 38),
    );
  }

  Widget _ok(BuildContext context) {
    return KeyButton(
      primary: true,
      onPressed: () => onKey('OK'),
      radius: BorderRadius.circular(999),
      textStyle: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
      child: const Text('OK'),
    );
  }
}
