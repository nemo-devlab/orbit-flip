import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  static const _kBest = 'best_score';

  static Future<int> getBestScore() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kBest) ?? 0;
    // If you prefer an in-memory fallback, replace with a static field.
  }

  static Future<void> setBestScore(int value) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kBest, value);
  }
}
