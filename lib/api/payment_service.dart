import 'package:shared_preferences/shared_preferences.dart';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/prefs_cache_utils.dart';
import 'package:preconnect/api/profile_service.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  final ApiClient _client = ApiClient();

  static const String _cacheKey = 'SemesterPaymentInfo';

  Future<String?> fetchPaymentInfo({bool fromGet = false}) async {
    final asyncPrefs = SharedPreferencesAsync();
    final id = await resolvePortfolioId(
      prefs: asyncPrefs,
      refreshProfile: () => ProfileService().fetchProfile(fromGet: true),
    );
    if (id == null || id.isEmpty) {
      if (fromGet) return null;
      return getPaymentInfo(fromFetch: true);
    }

    final url = ApiConfig.paymentUrl(id);

    return _client.fetchWithFallback<String>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        await asyncPrefs.setString(_cacheKey, response.body);
      },
      readCache: ({required bool fromFetch}) =>
          getPaymentInfo(fromFetch: fromFetch),
    );
  }

  Future<String?> getPaymentInfo({bool fromFetch = false}) async {
    return readCachedStringWithFallback(
      key: _cacheKey,
      fromFetch: fromFetch,
      onCacheMiss: () => fetchPaymentInfo(fromGet: true),
    );
  }
}
