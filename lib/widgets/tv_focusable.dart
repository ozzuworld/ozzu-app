import 'package:flutter/material.dart';

/// A widget that makes any child focusable and works across all platforms.
///
/// On touch devices (phones/tablets):
/// - Works exactly like a normal tap target
/// - No visual focus indicators
/// - Touch ripple effects work normally
///
/// On TV/Keyboard devices:
/// - Responds to D-pad/arrow key navigation
/// - Shows visual focus indicator (border + scale)
/// - SELECT/Enter key activates onTap
class TVFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final double focusScale;
  final Color focusBorderColor;
  final double focusBorderWidth;
  final BorderRadius? borderRadius;

  const TVFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.autofocus = false,
    this.focusScale = 1.05,
    this.focusBorderColor = Colors.white,
    this.focusBorderWidth = 3.0,
    this.borderRadius,
  });

  @override
  State<TVFocusable> createState() => _TVFocusableState();
}

class _TVFocusableState extends State<TVFocusable> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (hasFocus) {
        setState(() => _isFocused = hasFocus);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_isFocused ? widget.focusScale : 1.0),
        decoration: BoxDecoration(
          border: _isFocused
              ? Border.all(
                  color: widget.focusBorderColor,
                  width: widget.focusBorderWidth,
                )
              : null,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: widget.focusBorderColor.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A specialized version for content cards (movies, TV shows, etc.)
class TVFocusableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus;
  final double width;
  final double height;

  const TVFocusableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.autofocus = false,
    this.width = 120,
    this.height = 180,
  });

  @override
  State<TVFocusableCard> createState() => _TVFocusableCardState();
}

class _TVFocusableCardState extends State<TVFocusableCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (hasFocus) {
        setState(() => _isFocused = hasFocus);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_isFocused ? 1.08 : 1.0),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            border: _isFocused
                ? Border.all(
                    color: Colors.white,
                    width: 3.0,
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.5),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A focusable button optimized for circular/icon buttons
class TVFocusableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final double size;
  final bool isCircular;

  const TVFocusableButton({
    super.key,
    required this.child,
    this.onTap,
    this.autofocus = false,
    this.size = 150,
    this.isCircular = true,
  });

  @override
  State<TVFocusableButton> createState() => _TVFocusableButtonState();
}

class _TVFocusableButtonState extends State<TVFocusableButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = widget.isCircular
        ? BorderRadius.circular(widget.size / 2)
        : BorderRadius.circular(12);

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (hasFocus) {
        setState(() => _isFocused = hasFocus);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_isFocused ? 1.1 : 1.0),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            border: _isFocused
                ? Border.all(
                    color: Colors.blueAccent,
                    width: 4.0,
                  )
                : null,
            borderRadius: borderRadius,
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.blueAccent.withOpacity(0.6),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: borderRadius,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
