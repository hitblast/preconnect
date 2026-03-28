class ExamSorting {
  static int typeRank(String type) {
    final normalized = type.trim().toLowerCase();
    if (normalized == 'midterm' || normalized == 'mid') return 0;
    if (normalized == 'final') return 1;
    return 2;
  }

  static int compareExamEntries({
    required String typeA,
    required String typeB,
    required DateTime? dateTimeA,
    required DateTime? dateTimeB,
    required String courseCodeA,
    required String courseCodeB,
    required String sectionNameA,
    required String sectionNameB,
  }) {
    final typeCmp = typeRank(typeA).compareTo(typeRank(typeB));
    if (typeCmp != 0) return typeCmp;

    final dateTimeCmp = _compareNullableDateTimesByDateThenTime(
      dateTimeA,
      dateTimeB,
    );
    if (dateTimeCmp != 0) return dateTimeCmp;

    final courseCmp = _compareNaturalText(courseCodeA, courseCodeB);
    if (courseCmp != 0) return courseCmp;
    return _compareNaturalText(sectionNameA, sectionNameB);
  }

  static int _compareNullableDateTimesByDateThenTime(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    final dateCmp = DateTime(
      a.year,
      a.month,
      a.day,
    ).compareTo(DateTime(b.year, b.month, b.day));
    if (dateCmp != 0) return dateCmp;
    return a.compareTo(b);
  }

  static int _compareNaturalText(String a, String b) {
    final x = a.trim().toLowerCase();
    final y = b.trim().toLowerCase();
    if (x == y) return 0;

    final xParts = _splitNatural(x);
    final yParts = _splitNatural(y);
    final len = xParts.length < yParts.length ? xParts.length : yParts.length;
    for (var i = 0; i < len; i++) {
      final left = xParts[i];
      final right = yParts[i];
      final leftNum = int.tryParse(left);
      final rightNum = int.tryParse(right);
      if (leftNum != null && rightNum != null) {
        final cmp = leftNum.compareTo(rightNum);
        if (cmp != 0) return cmp;
        continue;
      }
      final cmp = left.compareTo(right);
      if (cmp != 0) return cmp;
    }
    return xParts.length.compareTo(yParts.length);
  }

  static List<String> _splitNatural(String value) {
    return RegExp(r'\d+|[^\d]+')
        .allMatches(value)
        .map((m) => m.group(0) ?? '')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }
}
