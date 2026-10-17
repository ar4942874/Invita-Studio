import 'package:shared_preferences/shared_preferences.dart';

/// Favourites and recently-used designs.
///
/// Kept outside the project on purpose: they describe the person's taste, not
/// one invitation, so they follow them across every draft. All calls swallow
/// storage errors — a missing preferences plugin must never break the picker.
class CatalogPrefs {
  const CatalogPrefs();

  static const String favouritesKey = 'catalog.favourites';
  static const String recentKey = 'catalog.recent';

  /// How many designs "Recently used" remembers.
  static const int maxRecent = 8;

  Future<Set<String>> loadFavourites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(favouritesKey) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveFavourites(Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(favouritesKey, ids.toList());
    } catch (_) {
      // Preferences are a convenience; the session keeps the in-memory value.
    }
  }

  Future<List<String>> loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(recentKey) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveRecent(List<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(recentKey, ids.take(maxRecent).toList());
    } catch (_) {
      // Best-effort.
    }
  }
}
