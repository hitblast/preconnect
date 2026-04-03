import 'dart:convert';

import 'package:preconnect/api/api_client.dart';
import 'package:preconnect/api/api_config.dart';

class FacultyRatingStats {
  const FacultyRatingStats({
    required this.reviewsTotal,
    required this.overall,
    required this.teaching,
    required this.fairness,
    required this.behavior,
  });

  final int reviewsTotal;
  final double overall;
  final double teaching;
  final double fairness;
  final double behavior;

  factory FacultyRatingStats.fromJson(Map<String, dynamic> json) {
    return FacultyRatingStats(
      reviewsTotal: (json['reviewsTotal'] as num?)?.toInt() ?? 0,
      overall: (json['overall'] as num?)?.toDouble() ?? 0,
      teaching: (json['teaching'] as num?)?.toDouble() ?? 0,
      fairness: (json['fairness'] as num?)?.toDouble() ?? 0,
      behavior: (json['behavior'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FacultySummary {
  const FacultySummary({
    required this.facultyId,
    required this.initial,
    required this.name,
    required this.email,
    required this.courses,
    required this.stats,
  });

  final int facultyId;
  final String initial;
  final String name;
  final String email;
  final List<String> courses;
  final FacultyRatingStats stats;

  factory FacultySummary.fromJson(Map<String, dynamic> json) {
    return FacultySummary(
      facultyId: (json['facultyId'] as num?)?.toInt() ?? 0,
      initial: '${json['initial'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      email: '${json['email'] ?? ''}'.trim(),
      courses:
          (json['courses'] as List?)
              ?.map((v) => '$v'.trim())
              .where((v) => v.isNotEmpty)
              .toList() ??
          const <String>[],
      stats: FacultyRatingStats.fromJson(
        (json['stats'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class FacultyReviewItem {
  const FacultyReviewItem({
    required this.reviewId,
    required this.facultyInitial,
    required this.facultyName,
    required this.overall,
    required this.teaching,
    required this.fairness,
    required this.behavior,
    required this.comment,
    required this.isAnonymous,
    required this.isApproved,
    this.createdAt,
    this.updatedAt,
  });

  final int reviewId;
  final String facultyInitial;
  final String facultyName;
  final int overall;
  final int teaching;
  final int fairness;
  final int behavior;
  final String comment;
  final bool isAnonymous;
  final bool isApproved;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FacultyReviewItem.fromJson(Map<String, dynamic> json) {
    final ratings = (json['ratings'] as Map?)?.cast<String, dynamic>();
    return FacultyReviewItem(
      reviewId: (json['reviewId'] as num?)?.toInt() ?? 0,
      facultyInitial: '${json['facultyInitial'] ?? ''}'.trim(),
      facultyName: '${json['facultyName'] ?? ''}'.trim(),
      overall:
          (ratings?['overall'] as num?)?.toInt() ??
          (json['overall'] as num?)?.toInt() ??
          0,
      teaching:
          (ratings?['teaching'] as num?)?.toInt() ??
          (json['teaching'] as num?)?.toInt() ??
          0,
      fairness:
          (ratings?['fairness'] as num?)?.toInt() ??
          (json['fairness'] as num?)?.toInt() ??
          0,
      behavior:
          (ratings?['behavior'] as num?)?.toInt() ??
          (json['behavior'] as num?)?.toInt() ??
          0,
      comment: '${json['comment'] ?? ''}'.trim(),
      isAnonymous: json['isAnonymous'] == true || json['is_anonymous'] == true,
      isApproved: json['isApproved'] == true || json['is_approved'] == true,
      createdAt: DateTime.tryParse(
        '${json['createdAt'] ?? json['created_at'] ?? ''}',
      ),
      updatedAt: DateTime.tryParse(
        '${json['updatedAt'] ?? json['updated_at'] ?? ''}',
      ),
    );
  }
}

class FacultyReviewFeed {
  const FacultyReviewFeed({
    required this.faculty,
    required this.reviews,
    required this.limit,
    required this.offset,
  });

  final FacultySummary faculty;
  final List<FacultyReviewItem> reviews;
  final int limit;
  final int offset;

  factory FacultyReviewFeed.fromJson(Map<String, dynamic> json) {
    final facultyJson =
        (json['faculty'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final items =
        (json['reviews'] as List?)
            ?.whereType<Map>()
            .map((e) => FacultyReviewItem.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const <FacultyReviewItem>[];
    return FacultyReviewFeed(
      faculty: FacultySummary.fromJson(facultyJson),
      reviews: items,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }
}

class FacultyReviewUpsertInput {
  const FacultyReviewUpsertInput({
    required this.facultyInitial,
    required this.overall,
    required this.teaching,
    required this.fairness,
    required this.behavior,
    required this.comment,
    required this.isAnonymous,
  });

  final String facultyInitial;
  final int overall;
  final int teaching;
  final int fairness;
  final int behavior;
  final String comment;
  final bool isAnonymous;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'facultyInitial': facultyInitial,
      'overall': overall,
      'teaching': teaching,
      'fairness': fairness,
      'behavior': behavior,
      'comment': comment,
      'isAnonymous': isAnonymous,
    };
  }
}

class FacultyReviewService {
  FacultyReviewService._internal();
  static final FacultyReviewService _instance =
      FacultyReviewService._internal();
  factory FacultyReviewService() => _instance;

  final ApiClient _client = ApiClient();

  String get _base => ApiConfig.seatStatusProxyBase;

  Future<FacultyReviewFeed> getFacultyReviews(
    String facultyInitial, {
    int limit = 20,
    int offset = 0,
  }) async {
    final initial = facultyInitial.trim().toUpperCase();
    final response = await _client.publicGet(
      '$_base/v1/faculty-reviews/${Uri.encodeComponent(initial)}?limit=$limit&offset=$offset',
    );
    return FacultyReviewFeed.fromJson(_decodeMap(response.body));
  }

  Future<FacultyReviewItem> upsertReview(FacultyReviewUpsertInput input) async {
    final response = await _client.authenticatedRequest(
      'POST',
      '$_base/v1/faculty-reviews',
      body: jsonEncode(input.toJson()),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
    );
    final map = _decodeMap(response.body);
    final item =
        (map['item'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return FacultyReviewItem.fromJson(item);
  }

  Future<void> deleteReview(int reviewId) async {
    await _client.authenticatedRequest(
      'DELETE',
      '$_base/v1/faculty-reviews/$reviewId',
    );
  }

  Future<bool> reportReview(int reviewId, {required String reason}) async {
    final response = await _client.authenticatedRequest(
      'POST',
      '$_base/v1/faculty-reviews/$reviewId/report',
      body: jsonEncode(<String, dynamic>{'reason': reason}),
      additionalHeaders: const <String, String>{
        'Content-Type': 'application/json',
      },
    );
    final map = _decodeMap(response.body);
    return map['reported'] == true;
  }

  Map<String, dynamic> _decodeMap(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return const <String, dynamic>{};
  }
}
