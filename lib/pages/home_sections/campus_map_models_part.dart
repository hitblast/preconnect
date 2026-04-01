part of 'package:preconnect/pages/home.dart';

String _normalizePhoneValue(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return '';
  value = value.replaceAll(
    RegExp(r'\s*\(\s*press\s*\d+\s*\)\s*$', caseSensitive: false),
    '',
  );
  value = value.replaceAll(
    RegExp(r'\s*[,;-]?\s*press\s*\d+\s*$', caseSensitive: false),
    '',
  );
  value = value.replaceAll(
    RegExp(r'\s*(ext|extension)\.?\s*\d+.*$', caseSensitive: false),
    '',
  );
  value = value.replaceAll(RegExp(r'[^\d+]'), '');
  return value;
}

class _CampusMapData {
  const _CampusMapData({
    required this.campusName,
    required this.address,
    required this.googleMapsUrl,
    required this.sourceUrl,
    required this.transportScheduleUrl,
    required this.highlights,
    required this.primaryEmail,
    required this.primaryPhone,
    required this.primaryPhoneRaw,
    required this.offices,
    required this.emergencyContacts,
  });

  final String campusName;
  final String address;
  final String googleMapsUrl;
  final String sourceUrl;
  final String transportScheduleUrl;
  final List<String> highlights;
  final String primaryEmail;
  final String primaryPhone;
  final String primaryPhoneRaw;
  final List<_CampusOfficeContact> offices;
  final List<_CampusEmergencyContact> emergencyContacts;

  factory _CampusMapData.fromJson(Map<String, dynamic> json) {
    final contact = json['contact'];
    final contactMap = contact is Map ? contact.cast<String, dynamic>() : null;
    final officeRows = json['general_contacts'];
    final emergencyRows = json['emergency_contacts'];

    final offices = officeRows is List
        ? officeRows
              .whereType<Map>()
              .map((item) => _CampusOfficeContact.fromJson(item))
              .toList(growable: false)
        : const <_CampusOfficeContact>[];
    final emergencies = emergencyRows is List
        ? emergencyRows
              .whereType<Map>()
              .map((item) => _CampusEmergencyContact.fromJson(item))
              .toList(growable: false)
        : const <_CampusEmergencyContact>[];

    final highlightsRaw = json['highlights'];
    final highlights = highlightsRaw is List
        ? highlightsRaw
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final transportRaw = json['transport'];
    final transportMap = transportRaw is Map
        ? transportRaw.cast<String, dynamic>()
        : null;

    String firstValueFromList(dynamic value) {
      if (value is List) {
        for (final item in value) {
          final cleaned = '$item'.trim();
          if (cleaned.isNotEmpty) return cleaned;
        }
      }
      return '';
    }

    String firstPhoneFromList(dynamic value) {
      if (value is List) {
        for (final item in value) {
          final normalized = _normalizePhoneValue('$item');
          if (normalized.isNotEmpty) return normalized;
        }
      }
      return '';
    }

    final primaryEmail = '${contactMap?['email'] ?? ''}'.trim().isNotEmpty
        ? '${contactMap?['email'] ?? ''}'.trim()
        : firstValueFromList(contactMap?['emails']);
    final primaryPhoneRaw =
        '${contactMap?['telephone'] ?? ''}'.trim().isNotEmpty
        ? '${contactMap?['telephone'] ?? ''}'.trim()
        : firstValueFromList(contactMap?['phones']);
    final primaryPhoneFromList = firstPhoneFromList(contactMap?['phones']);
    final primaryPhone = primaryPhoneFromList.isNotEmpty
        ? primaryPhoneFromList
        : _normalizePhoneValue('${contactMap?['telephone'] ?? ''}');

    return _CampusMapData(
      campusName: '${json['campus_name'] ?? ''}'.trim(),
      address: '${json['address'] ?? ''}'.trim(),
      googleMapsUrl: '${json['google_maps_url'] ?? ''}'.trim(),
      sourceUrl: '${json['source_url'] ?? ''}'.trim(),
      transportScheduleUrl: '${json['schedule_url'] ?? ''}'.trim().isNotEmpty
          ? '${json['schedule_url'] ?? ''}'.trim()
          : '${transportMap?['schedule_url'] ?? ''}'.trim(),
      highlights: highlights,
      primaryEmail: primaryEmail,
      primaryPhone: primaryPhone,
      primaryPhoneRaw: primaryPhoneRaw,
      offices: offices,
      emergencyContacts: emergencies,
    );
  }
}

class _CampusOfficeContact {
  const _CampusOfficeContact({required this.office, required this.emails});

  final String office;
  final List<String> emails;

  factory _CampusOfficeContact.fromJson(Map<dynamic, dynamic> json) {
    final rawEmails = json['emails'];
    return _CampusOfficeContact(
      office: '${json['office'] ?? ''}'.trim(),
      emails: rawEmails is List
          ? rawEmails
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}

class _CampusEmergencyContact {
  const _CampusEmergencyContact({
    required this.name,
    required this.services,
    required this.phones,
  });

  final String name;
  final String services;
  final List<String> phones;

  factory _CampusEmergencyContact.fromJson(Map<dynamic, dynamic> json) {
    final rawPhones = json['phones'];
    return _CampusEmergencyContact(
      name: '${json['name'] ?? ''}'.trim(),
      services: '${json['services'] ?? ''}'.trim(),
      phones: rawPhones is List
          ? rawPhones
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}
