import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// iOS-style press feedback: the child shrinks and dims slightly while held,
/// then springs back. Replaces Material ripples on cards and covers.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = .97,
    this.pressedOpacity = .82,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final double pressedOpacity;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final pressed = enabled && _pressed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: pressed ? widget.pressedScale : 1,
        duration: reduced
            ? Duration.zero
            : Duration(milliseconds: pressed ? 90 : 260),
        curve: pressed ? Curves.easeOut : Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: pressed ? widget.pressedOpacity : 1,
          duration: reduced
              ? Duration.zero
              : Duration(milliseconds: pressed ? 60 : 200),
          child: widget.child,
        ),
      ),
    );
  }
}
