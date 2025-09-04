import 'dart:async';
import 'package:flutter/material.dart';
import '../services/prefs.dart';
import 'widgets/primary_button.dart';
import 'widgets/score_text.dart';

class GameOverPage extends StatefulWidget {
  const GameOverPage({super.key});

  @override
  State<GameOverPage> createState() => _GameOverPageState();
}

class _GameOverPageState extends State<GameOverPage> {
  late final int _finalScore;
  int _best = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _finalScore = (ModalRoute.of(context)?.settings.arguments as int?) ?? 0;
    _commitBest();
  }

  Future<void> _commitBest() async {
    final best = await Prefs.getBestScore();
    if (_finalScore > best) {
      await Prefs.setBestScore(_finalScore);
      _best = _finalScore;
    } else {
      _best = best;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('GAME OVER',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 16),
                    ScoreText(label: 'Final Score', value: _finalScore),
                    const SizedBox(height: 12),
                    ScoreText(label: 'Best Score', value: _best),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PrimaryButton(
                          onPressed: () => Navigator.pushReplacementNamed(
                              context, '/game'),
                          child: const Icon(Icons.refresh_rounded, size: 28),
                          size: 72,
                        ),
                        const SizedBox(width: 24),
                        PrimaryButton(
                          onPressed: () => Navigator.pushNamedAndRemoveUntil(
                              context, '/', (r) => false),
                          child: const Icon(Icons.home_filled, size: 28),
                          size: 72,
                          glow: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Opacity(
                      opacity: 0.7,
                      child: Text(
                        'Tip: Flip early on steep diagonals.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
