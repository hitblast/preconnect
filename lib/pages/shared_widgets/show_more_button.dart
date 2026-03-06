import 'package:flutter/material.dart';
import 'package:preconnect/pages/ui_kit.dart';

class ShowMoreButton extends StatelessWidget {
  const ShowMoreButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: BracuPalette.primary,
          side: const BorderSide(color: BracuPalette.primary, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: const Text(
          'Show More',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
