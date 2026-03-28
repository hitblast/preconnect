class ExamScheduleOverride {
  const ExamScheduleOverride({
    this.midDate,
    this.midStartTime,
    this.midEndTime,
    this.midRoomNumber,
    this.finalDate,
    this.finalStartTime,
    this.finalEndTime,
    this.finalRoomNumber,
  });

  final String? midDate;
  final String? midStartTime;
  final String? midEndTime;
  final String? midRoomNumber;

  final String? finalDate;
  final String? finalStartTime;
  final String? finalEndTime;
  final String? finalRoomNumber;

  ExamScheduleOverride copyWith({
    String? midDate,
    String? midStartTime,
    String? midEndTime,
    String? midRoomNumber,
    String? finalDate,
    String? finalStartTime,
    String? finalEndTime,
    String? finalRoomNumber,
  }) {
    return ExamScheduleOverride(
      midDate: midDate ?? this.midDate,
      midStartTime: midStartTime ?? this.midStartTime,
      midEndTime: midEndTime ?? this.midEndTime,
      midRoomNumber: midRoomNumber ?? this.midRoomNumber,
      finalDate: finalDate ?? this.finalDate,
      finalStartTime: finalStartTime ?? this.finalStartTime,
      finalEndTime: finalEndTime ?? this.finalEndTime,
      finalRoomNumber: finalRoomNumber ?? this.finalRoomNumber,
    );
  }
}

class ExamSectionResolved {
  const ExamSectionResolved({
    required this.midDate,
    required this.midStartTime,
    required this.midEndTime,
    required this.midRoomNumber,
    required this.finalDate,
    required this.finalStartTime,
    required this.finalEndTime,
    required this.finalRoomNumber,
  });

  final String? midDate;
  final String? midStartTime;
  final String? midEndTime;
  final String midRoomNumber;
  final String? finalDate;
  final String? finalStartTime;
  final String? finalEndTime;
  final String finalRoomNumber;
}
