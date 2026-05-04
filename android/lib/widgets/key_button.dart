import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';

/// Rounded, slightly elevated key. Soft drop shadow on light, subtle border
/// on dark. Press: scale-down + shadow recedes (button "settles").
class KeyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final bool primary;
  final double? size;
  final BorderRadius? radius;
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;

  const KeyButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.primary = false,
    this.size,
    this.radius,
    this.padding,
    this.textStyle,
  });

  @override
  State<KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<KeyButton> {
  bool _pressed = false;

  void _down(_) {
    setState(() => _pressed = true);
    HapticFeedback.lightImpact();
  }

  void _up(_) {
    if (_pressed) {
      setState(() => _pressed = false);
      widget.onPressed();
    }
  }

  void _cancel() => setState(() => _pressed = false);

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = widget.radius ?? BorderRadius.circular(18);

    final Color bg;
    final Color fg;
    final Border? border;

    if (widget.primary) {
      bg = _pressed ? Color.lerp(p.accent, p.ink, 0.15)! : p.accent;
      fg = p.onAccent;
      border = null;
    } else {
      bg = _pressed ? p.sunken : p.card;
      fg = p.ink;
      border = isDark ? Border.all(color: p.line, width: 1) : null;
    }

    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: (_) => _cancel(),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: widget.size,
          height: widget.size,
          padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            border: border,
            boxShadow: _pressed ? null : dpadrShadows(context, depth: widget.primary ? 0.6 : 0.4),
          ),
          alignment: Alignment.center,
          child: DefaultTextStyle.merge(
            style: (widget.textStyle ?? Theme.of(context).textTheme.titleMedium)?.copyWith(color: fg),
            child: IconTheme(data: IconThemeData(color: fg, size: 24), child: widget.child),
          ),
        ),
      ),
    );
  }
}
