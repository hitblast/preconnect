import 'dart:convert';

class SeatStatusDetailsResponse {
  SeatStatusDetailsResponse({
    required this.section,
    required this.childSection,
  });

  final SeatStatusSection section;
  final SeatStatusSection? childSection;

  factory SeatStatusDetailsResponse.fromJson(Map<String, dynamic> json) {
    return SeatStatusDetailsResponse(
      section: SeatStatusSection.fromJson(
        (json['section'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      childSection: json['childSection'] is Map<String, dynamic>
          ? SeatStatusSection.fromJson(
              json['childSection'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'section': section.toJson(),
      'childSection': childSection?.toJson(),
    };
  }
}

class SeatStatusSection {
  SeatStatusSection({
    required this.sectionId,
    required this.courseCode,
    required this.sectionName,
    required this.name,
    required this.courseCredit,
    required this.capacity,
    required this.consumedSeat,
    required this.faculties,
    required this.facultyName,
    required this.facultyEmail,
    required this.facultyDesignation,
    required this.facultyPhone,
    required this.roomName,
    required this.roomNumber,
    required this.sectionSchedule,
  });

  final int sectionId;
  final String courseCode;
  final String sectionName;
  final String name;
  final int courseCredit;
  final int capacity;
  final int consumedSeat;
  final String faculties;
  final String facultyName;
  final String facultyEmail;
  final String facultyDesignation;
  final String facultyPhone;
  final String roomName;
  final String roomNumber;
  final SeatStatusSchedule sectionSchedule;

  factory SeatStatusSection.fromJson(Map<String, dynamic> json) {
    final rawSchedule = json['sectionSchedule'];
    final scheduleJson = switch (rawSchedule) {
      String s when s.trim().isNotEmpty =>
        (jsonDecode(s) as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      Map<String, dynamic> m => m,
      _ => const <String, dynamic>{},
    };
    final facultyInfo = _extractFacultyInfo(json);

    return SeatStatusSection(
      sectionId: _toInt(json['sectionId']),
      courseCode: _toString(json['courseCode']),
      sectionName: _toString(json['sectionName']),
      name: _toString(json['name']),
      courseCredit: _toInt(json['courseCredit']),
      capacity: _toInt(json['capacity']),
      consumedSeat: _toInt(json['consumedSeat']),
      faculties: facultyInfo.initial,
      facultyName: facultyInfo.name,
      facultyEmail: facultyInfo.email,
      facultyDesignation: facultyInfo.designation,
      facultyPhone: facultyInfo.phone,
      roomName: _toString(json['roomName']),
      roomNumber: _toString(json['roomNumber']),
      sectionSchedule: SeatStatusSchedule.fromJson(scheduleJson),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sectionId': sectionId,
      'courseCode': courseCode,
      'sectionName': sectionName,
      'name': name,
      'courseCredit': courseCredit,
      'capacity': capacity,
      'consumedSeat': consumedSeat,
      'faculties': faculties,
      'facultyName': facultyName,
      'facultyEmail': facultyEmail,
      'facultyDesignation': facultyDesignation,
      'facultyPhone': facultyPhone,
      'roomName': roomName,
      'roomNumber': roomNumber,
      'sectionSchedule': sectionSchedule.toJson(),
    };
  }
}

class SeatStatusSchedule {
  SeatStatusSchedule({
    required this.classSchedules,
    this.midExamDate,
    this.midExamStartTime,
    this.midExamEndTime,
    this.finalExamDate,
    this.finalExamStartTime,
    this.finalExamEndTime,
  });

  final List<SeatStatusClassSchedule> classSchedules;
  final String? midExamDate;
  final String? midExamStartTime;
  final String? midExamEndTime;
  final String? finalExamDate;
  final String? finalExamStartTime;
  final String? finalExamEndTime;

  factory SeatStatusSchedule.fromJson(Map<String, dynamic> json) {
    final rawSchedules = json['classSchedules'];
    final classSchedules = rawSchedules is List
        ? rawSchedules
              .whereType<Map<String, dynamic>>()
              .map(SeatStatusClassSchedule.fromJson)
              .toList()
        : const <SeatStatusClassSchedule>[];

    return SeatStatusSchedule(
      classSchedules: classSchedules,
      midExamDate: _toNullableString(json['midExamDate']),
      midExamStartTime: _toNullableString(json['midExamStartTime']),
      midExamEndTime: _toNullableString(json['midExamEndTime']),
      finalExamDate: _toNullableString(json['finalExamDate']),
      finalExamStartTime: _toNullableString(json['finalExamStartTime']),
      finalExamEndTime: _toNullableString(json['finalExamEndTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'classSchedules': classSchedules.map((e) => e.toJson()).toList(),
      'midExamDate': midExamDate,
      'midExamStartTime': midExamStartTime,
      'midExamEndTime': midExamEndTime,
      'finalExamDate': finalExamDate,
      'finalExamStartTime': finalExamStartTime,
      'finalExamEndTime': finalExamEndTime,
    };
  }
}

class SeatStatusClassSchedule {
  SeatStatusClassSchedule({
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  final String day;
  final String startTime;
  final String endTime;

  factory SeatStatusClassSchedule.fromJson(Map<String, dynamic> json) {
    return SeatStatusClassSchedule(
      day: _toString(json['day']),
      startTime: _toString(json['startTime']),
      endTime: _toString(json['endTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'day': day,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse('$value') ?? 0;
}

String _toString(dynamic value) {
  if (value == null) return '';
  return '$value'.trim();
}

String? _toNullableString(dynamic value) {
  final parsed = _toString(value);
  if (parsed.isEmpty || parsed.toUpperCase() == 'NULL') return null;
  return parsed;
}

class _FacultyInfo {
  const _FacultyInfo({
    required this.initial,
    required this.name,
    required this.email,
    required this.designation,
    required this.phone,
  });

  final String initial;
  final String name;
  final String email;
  final String designation;
  final String phone;
}

_FacultyInfo _extractFacultyInfo(Map<String, dynamic> json) {
  final initial = _toFacultyString(json);
  final name = _pickDirect(json, const <String>[
    'facultyName',
    'instructorName',
    'teacherName',
    'facultyFullName',
    'facultyMemberName',
  ]);
  final email = _pickDirect(json, const <String>[
    'facultyEmail',
    'instructorEmail',
    'teacherEmail',
    'email',
  ]);
  final designation = _pickDirect(json, const <String>[
    'facultyDesignation',
    'instructorDesignation',
    'designation',
  ]);
  final phone = _pickDirect(json, const <String>[
    'facultyPhone',
    'instructorPhone',
    'phone',
    'mobile',
  ]);

  final listItem = _firstFacultyListItem(json);
  final resolvedName = _isMeaningful(name)
      ? name
      : _pickFromMap(
          listItem,
          const <String>[
            'fullName',
            'name',
            'facultyName',
            'instructorName',
            'teacherName',
          ],
        );
  final resolvedEmail = _isMeaningful(email)
      ? email
      : _pickFromMap(
          listItem,
          const <String>[
            'email',
            'facultyEmail',
            'instructorEmail',
            'teacherEmail',
          ],
        );
  final resolvedDesignation = _isMeaningful(designation)
      ? designation
      : _pickFromMap(
          listItem,
          const <String>[
            'designation',
            'facultyDesignation',
            'instructorDesignation',
          ],
        );
  final resolvedPhone = _isMeaningful(phone)
      ? phone
      : _pickFromMap(
          listItem,
          const <String>[
            'phone',
            'mobile',
            'facultyPhone',
            'instructorPhone',
          ],
        );

  return _FacultyInfo(
    initial: initial,
    name: resolvedName,
    email: resolvedEmail,
    designation: resolvedDesignation,
    phone: resolvedPhone,
  );
}

String _toFacultyString(Map<String, dynamic> json) {
  const directKeys = <String>[
    'faculties',
    'faculty',
    'facultyInitial',
    'instructorInitial',
    'teacherInitial',
    'shortName',
    'initial',
  ];
  for (final key in directKeys) {
    final value = _toString(json[key]);
    if (_isMeaningful(value)) return value;
  }

  const listKeys = <String>[
    'facultyDetails',
    'facultyProfiles',
    'instructors',
    'teachers',
    'sectionFacultyProfiles',
  ];
  for (final key in listKeys) {
    final raw = json[key];
    if (raw is! List) continue;
    for (final item in raw.whereType<Map>()) {
      final map = item.cast<dynamic, dynamic>();
      final value = _pickFromMap(
        map.cast<String, dynamic>(),
        const <String>[
          'initial',
          'shortName',
          'facultyInitial',
          'instructorInitial',
          'teacherInitial',
          'faculties',
        ],
      );
      if (_isMeaningful(value)) return value;
    }
  }

  return 'TBA';
}

String _pickDirect(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = _toString(map[key]);
    if (_isMeaningful(value)) return value;
  }
  return '';
}

Map<String, dynamic>? _firstFacultyListItem(Map<String, dynamic> json) {
  const listKeys = <String>[
    'facultyDetails',
    'facultyProfiles',
    'instructors',
    'teachers',
    'sectionFacultyProfiles',
  ];
  for (final key in listKeys) {
    final raw = json[key];
    if (raw is! List) continue;
    for (final item in raw.whereType<Map>()) {
      return item.cast<String, dynamic>();
    }
  }
  return null;
}

String _pickFromMap(Map<String, dynamic>? map, List<String> keys) {
  if (map == null) return '';
  for (final key in keys) {
    final value = _toString(map[key]);
    if (_isMeaningful(value)) return value;
  }
  return '';
}

bool _isMeaningful(String value) {
  if (value.isEmpty) return false;
  final normalized = value.trim().toUpperCase();
  if (normalized == 'NULL') return false;
  if (normalized == 'N/A') return false;
  if (normalized == 'TBA') return false;
  if (normalized == 'TO BE ANNOUNCED') return false;
  if (normalized == '--') return false;
  return true;
}
