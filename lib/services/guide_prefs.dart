import 'package:shared_preferences/shared_preferences.dart';

/// Where the guided setup got to.
///
/// Kept outside the project on purpose: it describes the person, not one
/// invitation, so finishing the tour on a phone does not restart it on a
/// tablet. Every call swallows storage errors — a missing preferences plugin
/// must never block the editor.
class GuidePrefs {
  const GuidePrefs();

  static const String doneKey = 'guide.done';
  static const String stepKey = 'guide.step';
  static const String offKey = 'guide.off';

  Future<GuideProgress> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return GuideProgress(
        done: (prefs.getStringList(doneKey) ?? const []).toSet(),
        step: prefs.getString(stepKey),
        off: prefs.getBool(offKey) ?? false,
      );
    } catch (_) {
      return const GuideProgress(done: {}, step: null, off: false);
    }
  }

  Future<void> saveDone(Set<String> anchors) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(doneKey, anchors.toList()..sort());
    } catch (_) {
      // The in-memory set still drives this session.
    }
  }

  Future<void> saveStep(String? anchor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (anchor == null) {
        await prefs.remove(stepKey);
      } else {
        await prefs.setString(stepKey, anchor);
      }
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> saveOff(bool off) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(offKey, off);
    } catch (_) {
      // Best-effort.
    }
  }
}

/// A snapshot of the saved tour state.
class GuideProgress {
  const GuideProgress({
    required this.done,
    required this.step,
    required this.off,
  });

  final Set<String> done;
  final String? step;
  final bool off;
}
