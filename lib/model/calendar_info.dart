class CalendarFeed {
  const CalendarFeed({
    required this.rangeStart,
    required this.rangeEnd,
    required this.sourceFingerprint,
    required this.items,
  });

  final String rangeStart;
  final String rangeEnd;
  final String sourceFingerprint;
  final List<CalendarEntry> items;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'rangeStart': rangeStart,
    'rangeEnd': rangeEnd,
    'sourceFingerprint': sourceFingerprint,
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory CalendarFeed.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return CalendarFeed(
      rangeStart: (json['rangeStart'] ?? '').toString().trim(),
      rangeEnd: (json['rangeEnd'] ?? '').toString().trim(),
      sourceFingerprint: (json['sourceFingerprint'] ?? '').toString().trim(),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) =>
                      CalendarEntry.fromJson(item.cast<String, dynamic>()),
                )
                .toList()
          : const <CalendarEntry>[],
    );
  }
}

class CalendarEntry {
  const CalendarEntry({
    required this.id,
    required this.label,
    required this.typeKey,
    required this.date,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.place,
    required this.isRepeatable,
    required this.isCancelled,
    required this.ref,
    required this.roomName,
    required this.roomNumber,
    required this.sessionLabel,
    required this.building,
    required this.faculty,
    required this.department,
    required this.actor,
  });

  final String id;
  final String label;
  final String typeKey;
  final String date;
  final String startDate;
  final String endDate;
  final String startTime;
  final String endTime;
  final String place;
  final bool isRepeatable;
  final bool isCancelled;
  final String ref;
  final String roomName;
  final String roomNumber;
  final String sessionLabel;
  final String building;
  final String faculty;
  final String department;
  final String actor;

  String get primaryDate => date.isNotEmpty ? date : startDate;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'typeKey': typeKey,
    'date': date,
    'startDate': startDate,
    'endDate': endDate,
    'startTime': startTime,
    'endTime': endTime,
    'place': place,
    'isRepeatable': isRepeatable,
    'isCancelled': isCancelled,
    'ref': ref,
    'roomName': roomName,
    'roomNumber': roomNumber,
    'sessionLabel': sessionLabel,
    'building': building,
    'faculty': faculty,
    'department': department,
    'actor': actor,
  };

  factory CalendarEntry.fromJson(Map<String, dynamic> json) {
    return CalendarEntry(
      id: (json['id'] ?? '').toString().trim(),
      label: (json['label'] ?? '').toString().trim(),
      typeKey: (json['typeKey'] ?? '').toString().trim(),
      date: (json['date'] ?? '').toString().trim(),
      startDate: (json['startDate'] ?? '').toString().trim(),
      endDate: (json['endDate'] ?? '').toString().trim(),
      startTime: (json['startTime'] ?? '').toString().trim(),
      endTime: (json['endTime'] ?? '').toString().trim(),
      place: (json['place'] ?? '').toString().trim(),
      isRepeatable: json['isRepeatable'] == true,
      isCancelled: json['isCancelled'] == true,
      ref: (json['ref'] ?? '').toString().trim(),
      roomName: (json['roomName'] ?? '').toString().trim(),
      roomNumber: (json['roomNumber'] ?? '').toString().trim(),
      sessionLabel: (json['sessionLabel'] ?? '').toString().trim(),
      building: (json['building'] ?? '').toString().trim(),
      faculty: (json['faculty'] ?? '').toString().trim(),
      department: (json['department'] ?? '').toString().trim(),
      actor: (json['actor'] ?? '').toString().trim(),
    );
  }
}
