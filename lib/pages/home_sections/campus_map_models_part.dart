part of 'package:preconnect/pages/home.dart';

class _CampusMapData {
  const _CampusMapData({
    required this.campusName,
    required this.address,
    required this.googleMapsUrl,
    required this.sourceUrl,
    required this.highlights,
    required this.primaryEmail,
    required this.primaryPhone,
    required this.offices,
    required this.emergencyContacts,
  });

  final String campusName;
  final String address;
  final String googleMapsUrl;
  final String sourceUrl;
  final List<String> highlights;
  final String primaryEmail;
  final String primaryPhone;
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

    String firstValueFromList(dynamic value) {
      if (value is List) {
        for (final item in value) {
          final cleaned = '$item'.trim();
          if (cleaned.isNotEmpty) return cleaned;
        }
      }
      return '';
    }

    final primaryEmail = '${contactMap?['email'] ?? ''}'.trim().isNotEmpty
        ? '${contactMap?['email'] ?? ''}'.trim()
        : firstValueFromList(contactMap?['emails']);
    final primaryPhone = '${contactMap?['telephone'] ?? ''}'.trim().isNotEmpty
        ? '${contactMap?['telephone'] ?? ''}'.trim()
        : firstValueFromList(contactMap?['phones']);

    return _CampusMapData(
      campusName: '${json['campus_name'] ?? ''}'.trim(),
      address: '${json['address'] ?? ''}'.trim(),
      googleMapsUrl: '${json['google_maps_url'] ?? ''}'.trim(),
      sourceUrl: '${json['source_url'] ?? ''}'.trim(),
      highlights: highlights,
      primaryEmail: primaryEmail,
      primaryPhone: primaryPhone,
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
