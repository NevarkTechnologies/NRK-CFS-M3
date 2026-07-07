import 'package:flutter/material.dart';

class SmoothMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final double gap;
  final double pixelsPerSecond;

  const SmoothMarqueeText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.gap = 36,
    this.pixelsPerSecond = 28,
  });

  @override
  State<SmoothMarqueeText> createState() => _SmoothMarqueeTextState();
}

class _SmoothMarqueeTextState extends State<SmoothMarqueeText> {
  final ScrollController _controller = ScrollController();
  bool _started = false;

  @override
  void didUpdateWidget(covariant SmoothMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _started = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _overflows(double maxWidth, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width > maxWidth;
  }

  void _startLoop(double distance) {
    if (_started || distance <= 0) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      while (mounted && _controller.hasClients) {
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted || !_controller.hasClients) return;
        final duration = Duration(
          milliseconds: ((distance / widget.pixelsPerSecond) * 1000).round(),
        );
        await _controller.animateTo(
          distance,
          duration: duration,
          curve: Curves.linear,
        );
        if (!mounted || !_controller.hasClients) return;
        _controller.jumpTo(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_overflows(constraints.maxWidth, style)) {
          return Text(
            widget.text,
            maxLines: widget.maxLines ?? 1,
            overflow: widget.overflow,
            style: style,
          );
        }
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final distance = painter.width + widget.gap;
        _startLoop(distance);
        return ClipRect(
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              children: [
                Text(widget.text, maxLines: 1, style: style),
                SizedBox(width: widget.gap),
                Text(widget.text, maxLines: 1, style: style),
              ],
            ),
          ),
        );
      },
    );
  }
}
