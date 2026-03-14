import 'dart:async';
import 'dart:convert';
import 'package:preconnect/api/api_config.dart';
import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/sembast_cache.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  final ApiClient _client = ApiClient();
  final Map<String, Future<Map<String, String?>?>> _profileFetchInFlight =
      <String, Future<Map<String, String?>?>>{};
  static const Map<String, String> _bloodTypeIdToLabel = {
    '7157': 'A+',
    '7158': 'B+',
    '7159': 'AB+',
    '7160': 'O+',
    '7161': 'A-',
    '7162': 'B-',
    '7163': 'AB-',
    '7164': 'O-',
  };

  static String _normalizeBloodType({
    required dynamic bloodGroup,
    required dynamic bloodGroupName,
    required dynamic bloodType,
  }) {
    final candidates = <String>{
      bloodGroup?.toString().trim() ?? '',
      bloodGroupName?.toString().trim() ?? '',
      bloodType?.toString().trim() ?? '',
    };
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      final mapped = _bloodTypeIdToLabel[candidate];
      if (mapped != null) return mapped;
    }

    return '';
  }

  static const List<String> cacheKeys = [
    'id',
    'studentId',
    'fullName',
    'email',
    'studentEmail',
    'program',
    'programOrCourse',
    'currentSemester',
    'cgpa',
    'earnedCredit',
    'attemptedCredit',
    'enrolledSessionSemesterId',
    'currentSessionSemesterId',
    'enrolledSemester',
    'departmentName',
    'academicType',
    'bloodGroup',
    'mobileNo',
    'shortCode',
    'filePath',
    'photoFilePath',
    'permanentAddress',
    'presentAddress',
    'isBothAddressSame',
    'permanentUpazilaName',
    'presentUpazilaName',
    'fatherName',
    'fatherMobileNo',
    'fatherEmail',
    'motherName',
    'motherMobileNo',
    'motherEmail',
    'localGuardianName',
    'localGuardianMobileNo',
    'localGuardianEmail',
    'sponsoredBy',
    'countryName',
    'hobbies',
    'awards',
    'hasDisability',
    'disabilityDetails',
  ];

  static const Set<String> _requiredKeys = {
    'studentId',
    'fullName',
    'program',
    'currentSemester',
    'enrolledSessionSemesterId',
    'enrolledSemester',
    'mobileNo',
    'photoFilePath',
  };
  static const Set<String> _miscKeys = {
    'permanentAddress',
    'presentAddress',
    'isBothAddressSame',
    'permanentUpazilaName',
    'presentUpazilaName',
    'fatherName',
    'fatherMobileNo',
    'fatherEmail',
    'motherName',
    'motherMobileNo',
    'motherEmail',
    'localGuardianName',
    'localGuardianMobileNo',
    'localGuardianEmail',
    'sponsoredBy',
    'countryName',
    'hobbies',
    'awards',
    'hasDisability',
    'disabilityDetails',
  };

  static String _boolToYesNo(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'Yes' : 'No';
    final raw = value.toString().trim().toLowerCase();
    if (raw.isEmpty) return '';
    if (raw == 'true' || raw == '1') return 'Yes';
    if (raw == 'false' || raw == '0') return 'No';
    return value.toString();
  }

  Future<Map<String, String?>?> fetchProfile({bool fromGet = false}) async {
    final inFlightKey = 'profile|$fromGet';
    final inFlight = _profileFetchInFlight[inFlightKey];
    if (inFlight != null) {
      return await inFlight;
    }
    final request = _fetchProfileInternal(fromGet: fromGet);
    _profileFetchInFlight[inFlightKey] = request;
    try {
      return await request;
    } finally {
      _profileFetchInFlight.remove(inFlightKey);
    }
  }

  Future<Map<String, String?>?> _fetchProfileInternal({
    required bool fromGet,
  }) async {
    final url = '${ApiConfig.connectApiBase}${ApiConfig.profilePath}';

    return _client.fetchWithFallback<Map<String, String?>>(
      url: url,
      fromGet: fromGet,
      cacheResponse: (response) async {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty) {
          final profile = data[0];
          final cache = SembastCache();
          await cache.setStringMap(<String, String>{
            'id': profile['id']?.toString() ?? '',
            'studentId': profile['studentId']?.toString() ?? '',
            'program': profile['programOrCourse'] ?? '',
            'programOrCourse': profile['programOrCourse'] ?? '',
            'currentSemester': profile['currentSemester'] ?? '',
            'earnedCredit': profile['earnedCredit']?.toString() ?? '',
            'photoFilePath': profile['filePath'] ?? '',
            'filePath': profile['filePath'] ?? '',
            'academicType': profile['academicType'] ?? '',
            'attemptedCredit': profile['attemptedCredit']?.toString() ?? '',
            'enrolledSessionSemesterId':
                profile['enrolledSessionSemesterId']?.toString() ?? '',
            'currentSessionSemesterId':
                profile['currentSessionSemesterId']?.toString() ?? '',
            'enrolledSemester': profile['enrolledSemester'] ?? '',
            'departmentName': profile['departmentName'] ?? '',
            'studentEmail': profile['studentEmail'] ?? '',
            'bloodGroup': _normalizeBloodType(
              bloodGroup: profile['bloodGroup'],
              bloodGroupName: profile['bloodGroupName'],
              bloodType: profile['bloodType'],
            ),
            'mobileNo': profile['mobileNo'] ?? '',
            'shortCode': profile['shortCode'] ?? '',
            'fullName': profile['fullName'] ?? '',
            'email': profile['studentEmail'] ?? '',
            'cgpa': profile['cgpa']?.toString() ?? '',
          });

          try {
            final miscUrl =
                '${ApiConfig.connectApiBase}${ApiConfig.miscellaneousInfoPath}';
            final miscResponse = await _client.authenticatedGet(miscUrl);
            final miscData = jsonDecode(miscResponse.body);
            if (miscData is Map<String, dynamic>) {
              final resolvedBloodGroup = _normalizeBloodType(
                bloodGroup: miscData['bloodGroup'],
                bloodGroupName: miscData['bloodGroupName'],
                bloodType: miscData['bloodType'],
              );
              await cache.setStringMap(<String, String>{
                if (resolvedBloodGroup.isNotEmpty)
                  'bloodGroup': resolvedBloodGroup,
                'permanentAddress':
                    miscData['permanentAddress']?.toString() ?? '',
                'presentAddress': miscData['presentAddress']?.toString() ?? '',
                'isBothAddressSame':
                    _boolToYesNo(miscData['isBothAddressSame']),
                'permanentUpazilaName':
                    miscData['permanentUpazilaName']?.toString() ?? '',
                'presentUpazilaName':
                    miscData['presentUpazilaName']?.toString() ?? '',
                'fatherName': miscData['fatherName']?.toString() ?? '',
                'fatherMobileNo':
                    miscData['fatherMobileNo']?.toString() ?? '',
                'fatherEmail': miscData['fatherEmail']?.toString() ?? '',
                'motherName': miscData['motherName']?.toString() ?? '',
                'motherMobileNo':
                    miscData['motherMobileNo']?.toString() ?? '',
                'motherEmail': miscData['motherEmail']?.toString() ?? '',
                'localGuardianName':
                    miscData['localGuardianName']?.toString() ?? '',
                'localGuardianMobileNo':
                    miscData['localGuardianMobileNo']?.toString() ?? '',
                'localGuardianEmail':
                    miscData['localGuardianEmail']?.toString() ?? '',
                'sponsoredBy': miscData['sponsoredBy']?.toString() ?? '',
                'countryName': miscData['countryName']?.toString() ?? '',
                'hobbies': miscData['hobbies']?.toString() ?? '',
                'awards': miscData['awards']?.toString() ?? '',
                'hasDisability': _boolToYesNo(miscData['hasDisability']),
                'disabilityDetails':
                    miscData['disabilityDetails']?.toString() ?? '',
              });
            }
          } catch (_) {}
        }
      },
      readCache: ({required bool fromFetch}) =>
          getProfile(fromFetch: fromFetch),
    );
  }

  Future<Map<String, String?>?> getProfile({bool fromFetch = false}) async {
    final profileData = await SembastCache().getStringMap(cacheKeys.toSet());

    final anyRequiredMissing = _requiredKeys.any((key) {
      final value = profileData[key];
      return value == null || value.isEmpty;
    });

    if (anyRequiredMissing && !fromFetch) {
      return await fetchProfile(fromGet: true);
    }
    if (!fromFetch) {
      final anyMiscMissing = _miscKeys.any((key) {
        final value = profileData[key];
        return value == null || value.isEmpty;
      });
      if (anyMiscMissing) {
        unawaited(fetchProfile(fromGet: true));
      }
    }
    return profileData;
  }
}
