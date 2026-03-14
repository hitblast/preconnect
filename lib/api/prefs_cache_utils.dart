import 'package:preconnect/api/sembast_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String?> resolvePortfolioId({
  required SharedPreferencesAsync prefs,
  required Future<void> Function() refreshProfile,
}) async {
  var id = await SembastCache().getString('id');
  id ??= await prefs.getString('id');
  if (id == null || id.isEmpty) {
    await refreshProfile();
    id = await SembastCache().getString('id');
    id ??= await prefs.getString('id');
  }
  if (id == null || id.isEmpty) return null;
  return id;
}
