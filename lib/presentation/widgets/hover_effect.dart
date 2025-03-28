import 'package:flutter/material.dart';

/// Виджет, добавляющий размытый эффект при наведении
/// Этот класс можно поместить в lib/presentation/widgets/ и использовать во всем приложении
class BlurredHover extends StatefulWidget {
  final Widget child;
  final Color hoverColor;
  final double blurRadius;
  final double spreadRadius;
  final BorderRadius borderRadius;
  final Duration duration;
  final double elevationDelta;

  const BlurredHover({
    Key? key,
    required this.child,
    this.hoverColor = const Color(0xFFC60E7A),
    this.blurRadius = 12.0,
    this.spreadRadius = -2.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(12.0)),
    this.duration = const Duration(milliseconds: 150),
    this.elevationDelta = 1.0,
  }) : super(key: key);

  @override
  State<BlurredHover> createState() => _BlurredHoverState();
}

class _BlurredHoverState extends State<BlurredHover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: widget.duration,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: _isHovered ? [
            BoxShadow(
              color: widget.hoverColor.withOpacity(0.08),
              blurRadius: widget.blurRadius,
              spreadRadius: widget.spreadRadius,
            ),
          ] : [],
        ),
        child: widget.child,
      ),
    );
  }
}