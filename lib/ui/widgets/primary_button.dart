import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final double size;
  final bool glow;

  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.size = 88,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFCCCCCC)],
            ),
            boxShadow: glow
                ? const [
                    BoxShadow(
                      color: Color(0x33FFFFFF),
                      blurRadius: 30,
                      spreadRadius: 4,
                    )
                  ]
                : null,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
