import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'speech_bubble.dart';

class FloatingSpeechBubble extends StatefulWidget {
  final String text;
  final Color backgroundColor;
  final Color textColor;

  const FloatingSpeechBubble({
    super.key,
    required this.text,
    this.backgroundColor = Colors.white,
    this.textColor = Colors.black87,
  });

  @override
  State<FloatingSpeechBubble> createState() => _FloatingSpeechBubbleState();
}

class _FloatingSpeechBubbleState extends State<FloatingSpeechBubble> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 5 * math.sin(_controller.value * 2 * math.pi)),
          child: child,
        );
      },
      child: SpeechBubble(
        text: widget.text,
        backgroundColor: widget.backgroundColor,
        textColor: widget.textColor,
      ),
    );
  }
}
