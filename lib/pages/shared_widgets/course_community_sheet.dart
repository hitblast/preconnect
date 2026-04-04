import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:preconnect/api/course_material_service.dart';
import 'package:preconnect/api/faculty_review_service.dart';
import 'package:preconnect/api/profile_service.dart';
import 'package:preconnect/model/section_info.dart' as section;
import 'package:preconnect/pages/shared_widgets/schedule_entry_card.dart';
import 'package:preconnect/pages/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CourseCommunitySheet extends StatefulWidget {
  const CourseCommunitySheet.forClass({
    super.key,
    required this.courseCode,
    required this.sectionName,
    required this.semesterLabel,
    required this.roomNumber,
    required this.faculties,
    required this.consumedSeat,
    required this.courseType,
    required this.classSchedule,
    required this.isRamadan,
    this.showActions = true,
  }) : examType = null,
       examDateLabel = null,
       examTimeLabel = null;

  const CourseCommunitySheet.forExam({
    super.key,
    required this.courseCode,
    required this.sectionName,
    required this.semesterLabel,
    required this.roomNumber,
    required this.faculties,
    required this.consumedSeat,
    required this.courseType,
    required this.examType,
    required this.examDateLabel,
    required this.examTimeLabel,
    this.showActions = true,
  }) : classSchedule = null,
       isRamadan = false;

  final String courseCode;
  final String sectionName;
  final String semesterLabel;
  final String? roomNumber;
  final String? faculties;
  final int? consumedSeat;
  final String? courseType;
  final section.ClassSchedule? classSchedule;
  final bool isRamadan;

  final String? examType;
  final String? examDateLabel;
  final String? examTimeLabel;
  final bool showActions;

  bool get isExamMode => classSchedule == null;

  @override
  State<CourseCommunitySheet> createState() => _CourseCommunitySheetState();
}

class _CourseCommunitySheetState extends State<CourseCommunitySheet> {
  final FacultyReviewService _facultyService = FacultyReviewService();
  final CourseMaterialService _materialService = CourseMaterialService();
  final ProfileService _profileService = ProfileService();
  final TextEditingController _reviewCommentController =
      TextEditingController();

  FacultyReviewFeed? _reviewFeed;
  List<CourseMaterialItem> _materials = const <CourseMaterialItem>[];
  bool _reviewsLoading = true;
  bool _materialsLoading = true;
  bool _busyWriteAction = false;
  bool _showAllReviews = false;
  bool _showAllMaterials = false;
  String? _reviewsError;
  String? _materialsError;
  String _currentUserName = '';
  _LocalFacultyReviewDraft? _localDraft;

  String get _facultyInitial {
    final raw = (widget.faculties ?? '').trim().toUpperCase();
    if (raw.isEmpty) return '';
    final first = raw.split(RegExp(r'[,/\\s]+')).first.trim();
    final cleaned = first.replaceAll(RegExp(r'[^A-Z]'), '');
    return cleaned;
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _reviewCommentController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait<void>(<Future<void>>[
      _loadReviews(),
      _loadMaterials(),
      _loadLocalDraft(),
      _loadCurrentUserName(),
    ]);
  }

  String get _draftKey => 'faculty_review_draft_v1_$_facultyInitial';

  Future<void> _loadLocalDraft() async {
    final initial = _facultyInitial;
    if (initial.isEmpty) {
      if (!mounted) return;
      setState(() {
        _localDraft = null;
      });
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (!mounted) return;
      if (raw == null || raw.trim().isEmpty) {
        setState(() {
          _localDraft = null;
        });
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        setState(() {
          _localDraft = _LocalFacultyReviewDraft.fromJson(decoded);
        });
      } else if (decoded is Map) {
        setState(() {
          _localDraft = _LocalFacultyReviewDraft.fromJson(
            decoded.cast<String, dynamic>(),
          );
        });
      } else {
        setState(() {
          _localDraft = null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localDraft = null;
      });
    }
  }

  Future<void> _loadCurrentUserName() async {
    try {
      final profile = await _profileService.getProfile();
      final fullName = (profile?['fullName'] ?? '').trim();
      if (!mounted) return;
      setState(() {
        _currentUserName = fullName;
      });
    } catch (_) {}
  }

  Future<void> _saveLocalDraft(_LocalFacultyReviewDraft draft) async {
    final initial = _facultyInitial;
    if (initial.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(draft.toJson()));
    if (!mounted) return;
    setState(() {
      _localDraft = draft;
    });
  }

  Future<void> _clearLocalDraft() async {
    final initial = _facultyInitial;
    if (initial.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
    if (!mounted) return;
    setState(() {
      _localDraft = null;
    });
  }

  Future<void> _loadReviews() async {
    setState(() {
      _reviewsLoading = true;
      _reviewsError = null;
    });
    final initial = _facultyInitial;
    if (initial.isEmpty) {
      setState(() {
        _reviewsLoading = false;
        _reviewsError = 'Not available';
      });
      return;
    }
    try {
      final feed = await _facultyService.getFacultyReviews(initial, limit: 20);
      if (!mounted) return;
      setState(() {
        _reviewFeed = feed;
        _reviewsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reviewsLoading = false;
        _reviewsError = 'Not available';
      });
    }
  }

  Future<void> _loadMaterials() async {
    setState(() {
      _materialsLoading = true;
      _materialsError = null;
    });
    try {
      final list = await _materialService.list(
        courseCode: widget.courseCode,
        limit: 20,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _materials = list;
        _materialsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _materialsLoading = false;
        _materialsError = 'Not available';
      });
    }
  }

  Future<void> _writeReview() async {
    if (_busyWriteAction) return;
    final initial = _facultyInitial;
    if (initial.isEmpty) {
      showAppSnackBar(context, 'Not available');
      return;
    }

    final existingDraft = _localDraft;
    _reviewCommentController.text = existingDraft?.comment ?? '';
    int? overall;
    int? teaching;
    int? fairness;
    int? behavior;
    if (existingDraft != null) {
      overall = existingDraft.overall;
      teaching = existingDraft.teaching;
      fairness = existingDraft.fairness;
      behavior = existingDraft.behavior;
    }

    final result = await showBracuBottomSheet<bool>(
      context,
      title: existingDraft == null ? 'Write' : 'Edit',
      builder: (sheetContext, textPrimary, textSecondary) {
        final sheetScroll = bracuBottomSheetScrollController(sheetContext);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget ratingRow(
              String label,
              int? value,
              ValueChanged<int> onChanged,
            ) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ...List<Widget>.generate(5, (index) {
                    final star = index + 1;
                    final selected = value != null && star <= value;
                    return IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setSheetState(() => onChanged(star)),
                      icon: Icon(
                        selected ? Icons.star_rounded : Icons.star_border,
                        color: BracuPalette.warning,
                      ),
                    );
                  }),
                ],
              );
            }

            final comment = _reviewCommentController.text.trim();
            final ratingsReady =
                overall != null &&
                teaching != null &&
                fairness != null &&
                behavior != null;
            final canSubmit = ratingsReady && comment.isNotEmpty;

            return SingleChildScrollView(
              controller: sheetScroll,
              child: Column(
                children: [
                  ratingRow('Overall', overall, (v) => overall = v),
                  ratingRow('Teaching', teaching, (v) => teaching = v),
                  ratingRow('Fairness', fairness, (v) => fairness = v),
                  ratingRow('Behavior', behavior, (v) => behavior = v),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _reviewCommentController,
                    maxLines: 4,
                    maxLength: 500,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Write your review...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: canSubmit
                              ? () => Navigator.of(sheetContext).pop(true)
                              : null,
                          child: Text(
                            existingDraft == null ? 'Submit' : 'Save',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != true) return;
    if (!mounted) return;
    final comment = _reviewCommentController.text.trim();
    if (comment.isEmpty) {
      showAppSnackBar(context, 'Comment is required');
      return;
    }
    if (overall == null ||
        teaching == null ||
        fairness == null ||
        behavior == null) {
      showAppSnackBar(context, 'All star ratings are required');
      return;
    }

    setState(() {
      _busyWriteAction = true;
    });
    try {
      await _facultyService.upsertReview(
        FacultyReviewUpsertInput(
          facultyInitial: initial,
          overall: overall!,
          teaching: teaching!,
          fairness: fairness!,
          behavior: behavior!,
          comment: comment,
        ),
      );
      await _saveLocalDraft(
        _LocalFacultyReviewDraft(
          overall: overall!,
          teaching: teaching!,
          fairness: fairness!,
          behavior: behavior!,
          comment: comment,
        ),
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        existingDraft == null ? 'Review submitted' : 'Review saved',
      );
      await _loadReviews();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Review not available now');
    } finally {
      if (mounted) {
        setState(() {
          _busyWriteAction = false;
        });
      }
    }
  }

  Future<String?> _askReason(String title) async {
    final controller = TextEditingController();
    final ok = await showBracuBottomSheet<bool>(
      context,
      title: title,
      initialChildSize: 0.56,
      builder: (sheetContext, textPrimary, textSecondary) {
        final sheetScroll = bracuBottomSheetScrollController(sheetContext);
        return SingleChildScrollView(
          controller: sheetScroll,
          child: Column(
            children: [
              TextField(
                controller: controller,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) {
      controller.dispose();
      return null;
    }
    final reason = controller.text.trim();
    controller.dispose();
    if (reason.isEmpty) return null;
    return reason;
  }

  Future<void> _reportReview(int reviewId) async {
    final reason = await _askReason('Report Review');
    if (reason == null || reason.isEmpty) return;
    setState(() {
      _busyWriteAction = true;
    });
    try {
      final reported = await _facultyService.reportReview(
        reviewId,
        reason: reason,
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        reported ? 'Review reported' : 'Already reported by you',
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Report not available now');
    } finally {
      if (mounted) {
        setState(() {
          _busyWriteAction = false;
        });
      }
    }
  }

  Future<void> _deleteReview(int reviewId) async {
    final ok = await showBracuConfirmationDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Delete Review?',
      message: 'You can only delete your own review.',
      confirmLabel: 'Delete',
      confirmColor: BracuPalette.danger,
    );
    if (!ok) return;
    setState(() {
      _busyWriteAction = true;
    });
    try {
      await _facultyService.deleteReview(reviewId);
      await _clearLocalDraft();
      if (!mounted) return;
      showAppSnackBar(context, 'Review deleted');
      await _loadReviews();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Delete not available now');
    } finally {
      if (mounted) {
        setState(() {
          _busyWriteAction = false;
        });
      }
    }
  }

  Future<void> _openMaterial(CourseMaterialItem item) async {
    try {
      final parsed = _parseMaterialMeta(item);
      final directLink = parsed.linkUrl;
      if (_isValidHttpUrl(directLink)) {
        await openExternalUrl(context, directLink);
        return;
      }
      final detail = await _materialService.get(
        semester: item.semester,
        courseCode: item.courseCode,
        fileName: item.fileName,
      );
      if (!mounted) return;
      final detailParsed = _parseMaterialMeta(detail.item);
      final detailLink = detailParsed.linkUrl;
      if (_isValidHttpUrl(detailLink)) {
        await openExternalUrl(context, detailLink);
        return;
      }
      if (detail.downloadUrl.isEmpty) {
        showAppSnackBar(context, 'Download URL unavailable');
        return;
      }
      final publicUrl = _materialService.resolvePublicDownloadUrl(
        item: detail.item,
        signedDownloadUrl: detail.downloadUrl,
      );
      await openExternalUrl(context, publicUrl);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Open not available now');
    }
  }

  Future<void> _reportMaterial(CourseMaterialItem item) async {
    final reason = await _askReason('Report Material');
    if (reason == null || reason.isEmpty) return;
    setState(() {
      _busyWriteAction = true;
    });
    try {
      final reported = await _materialService.report(
        semester: item.semester,
        courseCode: item.courseCode,
        fileName: item.fileName,
        reason: reason,
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        reported ? 'Material reported' : 'Already reported by you',
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Report not available now');
    } finally {
      if (mounted) {
        setState(() {
          _busyWriteAction = false;
        });
      }
    }
  }

  Future<void> _deleteMaterial(CourseMaterialItem item) async {
    final ok = await showBracuConfirmationDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'Delete Material?',
      message: 'You can only delete your own uploaded material.',
      confirmLabel: 'Delete',
      confirmColor: BracuPalette.danger,
    );
    if (!ok) return;
    setState(() {
      _busyWriteAction = true;
    });
    try {
      await _materialService.delete(
        semester: item.semester,
        courseCode: item.courseCode,
        fileName: item.fileName,
      );
      if (!mounted) return;
      showAppSnackBar(context, 'Material deleted');
      await _loadMaterials();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, 'Delete not available now');
    } finally {
      if (mounted) {
        setState(() {
          _busyWriteAction = false;
        });
      }
    }
  }

  String _contentTypeForPath(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.url')) return 'text/uri-list';
    return 'application/octet-stream';
  }

  Future<void> _openAddMaterialSheet() async {
    if (_busyWriteAction) return;
    final linkController = TextEditingController();
    final titleController = TextEditingController();
    Uint8List? selectedFileBytes;
    String selectedFileName = '';
    bool pickingFile = false;
    bool submitting = false;
    _AddMaterialTab activeTab = _AddMaterialTab.file;
    await showBracuBottomSheet<void>(
      context,
      title: 'Add Material',
      subtitle: 'Choose File or Link',
      builder: (sheetContext, textPrimary, textSecondary) {
        final sheetScroll = bracuBottomSheetScrollController(sheetContext);
        return StatefulBuilder(
          builder: (innerContext, setSheetState) {
            return ListView(
              controller: sheetScroll,
              shrinkWrap: true,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: BracuPalette.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: BracuPalette.textSecondary(
                        context,
                      ).withValues(alpha: 0.2),
                    ),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AddTabButton(
                          label: 'File',
                          icon: Icons.upload_file_rounded,
                          selected: activeTab == _AddMaterialTab.file,
                          onTap: () {
                            setSheetState(() {
                              activeTab = _AddMaterialTab.file;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _AddTabButton(
                          label: 'Link',
                          icon: Icons.link_rounded,
                          selected: activeTab == _AddMaterialTab.link,
                          onTap: () {
                            setSheetState(() {
                              activeTab = _AddMaterialTab.link;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                BracuCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (activeTab == _AddMaterialTab.file) ...[
                        Text(
                          'Add File',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Upload PDF, DOCX, PPTX, images, .zip and more.',
                          style: TextStyle(color: textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: (pickingFile || submitting)
                                ? null
                                : () async {
                                    setSheetState(() {
                                      pickingFile = true;
                                    });
                                    final picked = await FilePicker.platform
                                        .pickFiles(
                                          type: FileType.any,
                                          allowMultiple: false,
                                          withData: true,
                                        );
                                    if (!mounted) return;
                                    if (picked == null ||
                                        picked.files.isEmpty) {
                                      setSheetState(() {
                                        pickingFile = false;
                                      });
                                      return;
                                    }
                                    final selected = picked.files.first;
                                    final bytes = selected.bytes;
                                    setSheetState(() {
                                      pickingFile = false;
                                    });
                                    if (bytes == null || bytes.isEmpty) {
                                      showAppSnackBar(
                                        context,
                                        'Unable to read selected file',
                                      );
                                      return;
                                    }
                                    setSheetState(() {
                                      selectedFileName = selected.name.trim();
                                      selectedFileBytes = bytes;
                                    });
                                  },
                            icon: pickingFile
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.upload_file_rounded),
                            label: Text(
                              pickingFile ? 'Choosing file...' : 'Choose File',
                            ),
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Add Link',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Accessible YouTube video/playlist, GitHub repositories, or any web resource.',
                          style: TextStyle(color: textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: linkController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Link URL',
                            hintText: 'https://youtube.com/...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: titleController,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Title (optional)',
                            hintText: 'Lecture 03 Recording',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (activeTab == _AddMaterialTab.file &&
                    selectedFileName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Selected: $selectedFileName',
                    style: TextStyle(color: textSecondary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: (pickingFile || submitting)
                            ? null
                            : () => Navigator.of(sheetContext).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: (pickingFile || submitting)
                            ? null
                            : () async {
                                if (activeTab == _AddMaterialTab.file) {
                                  if (selectedFileBytes == null ||
                                      selectedFileName.trim().isEmpty) {
                                    showAppSnackBar(
                                      context,
                                      'Choose a file first',
                                    );
                                    return;
                                  }
                                  setSheetState(() {
                                    submitting = true;
                                  });
                                  if (sheetContext.mounted) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                  await _uploadMaterialBytes(
                                    fileName: selectedFileName.trim(),
                                    bytes: selectedFileBytes!,
                                    titleHint: selectedFileName
                                        .replaceAll(RegExp(r'\.[^.]+$'), '')
                                        .trim(),
                                    descriptionHint:
                                        'Uploaded from class/exam schedule',
                                    linkUrl: '',
                                  );
                                  return;
                                }

                                final url = linkController.text.trim();
                                final customTitle = titleController.text.trim();
                                if (!_isValidHttpUrl(url)) {
                                  showAppSnackBar(
                                    context,
                                    'Enter a valid http/https link',
                                  );
                                  return;
                                }
                                final uri = Uri.parse(url);
                                final fileName = _materialLinkFileName(uri);
                                final bytes = Uint8List.fromList(
                                  utf8.encode('$url\n'),
                                );
                                final title = customTitle.isNotEmpty
                                    ? customTitle
                                    : _defaultMaterialLinkTitle(uri);
                                setSheetState(() {
                                  submitting = true;
                                });
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                                await _uploadMaterialBytes(
                                  fileName: fileName,
                                  bytes: bytes,
                                  titleHint: title,
                                  descriptionHint:
                                      'Link shared from class/exam schedule',
                                  linkUrl: url,
                                );
                              },
                        icon: submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                activeTab == _AddMaterialTab.file
                                    ? Icons.check_circle_outline
                                    : Icons.link_rounded,
                              ),
                        label: Text(submitting ? 'Submitting...' : 'Submit'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    linkController.dispose();
    titleController.dispose();
  }

  Future<void> _uploadMaterialBytes({
    required String fileName,
    required Uint8List bytes,
    required String titleHint,
    required String descriptionHint,
    required String linkUrl,
  }) async {
    if (_busyWriteAction) return;
    final normalizedName = fileName.trim();
    if (normalizedName.isEmpty || bytes.isEmpty) return;
    setState(() {
      _busyWriteAction = true;
    });
    try {
      final contentType = _contentTypeForPath(normalizedName);
      final uploadMeta = await _materialService.createUploadUrl(
        CourseMaterialUploadUrlInput(
          fileName: normalizedName,
          contentType: contentType,
          courseCode: widget.courseCode,
          semester: widget.semesterLabel,
        ),
      );
      await _materialService.uploadToSignedUrl(
        uploadUrl: uploadMeta.uploadUrl,
        contentType: contentType,
        bytes: bytes,
      );
      final title = titleHint.trim();
      final finalTitle = title.isEmpty ? 'Course material' : title;
      await _materialService.finalize(
        CourseMaterialFinalizeInput(
          key: uploadMeta.key,
          courseCode: widget.courseCode,
          courseTitle: widget.courseCode,
          semester: widget.semesterLabel,
          title: finalTitle,
          description: _materialDescription(
            base: descriptionHint,
            uploaderName: _currentUserName,
            linkUrl: linkUrl,
          ),
          fileName: normalizedName,
          contentType: contentType,
          fileSize: bytes.length,
        ),
      );
      if (!mounted) return;
      showAppSnackBar(
        context,
        linkUrl.isNotEmpty ? 'Link added' : 'Material uploaded',
      );
      await _loadMaterials();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        linkUrl.isNotEmpty ? 'Link add not available now' : 'Upload not available now',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyWriteAction = false;
        });
      }
    }
  }

  bool _isValidHttpUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    return uri.hasAuthority;
  }

  String _materialLinkFileName(Uri uri) {
    final host = uri.host.trim().replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeHost = host.isEmpty ? 'link' : host.toLowerCase();
    return '$safeHost-$ts.url';
  }

  String _defaultMaterialLinkTitle(Uri uri) {
    final host = uri.host.trim().toLowerCase();
    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      if ((uri.queryParameters['list'] ?? '').trim().isNotEmpty) {
        return 'YouTube playlist';
      }
      return 'YouTube video';
    }
    if (host.contains('github.com')) {
      final parts = uri.pathSegments
          .where((segment) => segment.trim().isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        return 'GitHub ${parts[0]}/${parts[1]}';
      }
      return 'GitHub resource';
    }
    return host.isEmpty ? 'Shared link' : host;
  }

  String _materialDescription({
    required String base,
    required String uploaderName,
    required String linkUrl,
  }) {
    final payload = <String, String>{
      if (uploaderName.trim().isNotEmpty) 'uploader': uploaderName.trim(),
      if (linkUrl.trim().isNotEmpty) 'linkUrl': linkUrl.trim(),
    };
    if (payload.isEmpty) return base;
    final encoded = base64Url.encode(
      utf8.encode(jsonEncode(payload)),
    ).replaceAll('=', '');
    return '$base\nPCMETA:$encoded';
  }

  Widget _buildSummaryCard() {
    if (!widget.isExamMode && widget.classSchedule != null) {
      return ScheduleEntryCard(
        sectionName: widget.sectionName,
        courseCode: widget.courseCode,
        schedule: widget.classSchedule!,
        isRamadan: widget.isRamadan,
        roomNumber: widget.roomNumber,
        faculties: widget.faculties,
        consumedSeat: widget.consumedSeat,
        courseType: widget.courseType,
      );
    }
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final roomLabel = (widget.roomNumber ?? '').trim().isEmpty
        ? 'TBA'
        : widget.roomNumber!.trim();
    final facultyLabel = (widget.faculties ?? '').trim();
    final consumedLabel = (widget.consumedSeat ?? 0) > 0
        ? '(${widget.consumedSeat})'
        : '';
    final examType = (widget.examType ?? '').trim().toLowerCase();
    final badgeColor = examType == 'midterm'
        ? BracuPalette.primary
        : BracuPalette.accent;
    return BracuCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionBadge(
            label: formatSectionBadge(widget.sectionName),
            color: badgeColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.courseCode,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.examTimeLabel ?? 'TBA',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  roomLabel,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (facultyLabel.isNotEmpty || consumedLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$facultyLabel${facultyLabel.isNotEmpty && consumedLabel.isNotEmpty ? ' ' : ''}$consumedLabel',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = BracuPalette.textPrimary(context);
    final textSecondary = BracuPalette.textSecondary(context);
    final sheetScroll = bracuBottomSheetScrollController(context);
    String normalizeComment(String input) {
      return input.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    }

    final allReviewsRaw = _reviewFeed?.reviews ?? const <FacultyReviewItem>[];
    final reviewSeenKeys = <String>{};
    final allReviews = allReviewsRaw.where((review) {
      final key = review.reviewId > 0
          ? 'id:${review.reviewId}'
          : '${review.facultyInitial}|${review.overall}|${review.teaching}|${review.fairness}|${review.behavior}|${normalizeComment(review.comment)}';
      return reviewSeenKeys.add(key);
    }).toList();
    final displayReviews = _showAllReviews
        ? allReviews
        : allReviews.take(3).toList();
    final materialSeenKeys = <String>{};
    final allMaterials = _materials.where((item) {
      final key = '${item.semester}|${item.courseCode}|${item.fileName}';
      return materialSeenKeys.add(key);
    }).toList();
    final displayMaterials = _showAllMaterials
        ? allMaterials
        : allMaterials.take(3).toList();
    final totalReviews = _reviewFeed?.faculty.stats.reviewsTotal ?? 0;
    final hasReviews = totalReviews > 0 || allReviews.isNotEmpty;
    final localDraft = _localDraft;

    final isLocalDraftVisibleInFeed =
        localDraft != null &&
        allReviews.any(
          (review) =>
              review.overall == localDraft.overall &&
              review.teaching == localDraft.teaching &&
              review.fairness == localDraft.fairness &&
              review.behavior == localDraft.behavior &&
              normalizeComment(review.comment) ==
                  normalizeComment(localDraft.comment),
        );
    return ListView(
      controller: sheetScroll,
      children: [
        _buildSummaryCard(),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: BracuSectionTitle(title: 'Faculty Reviews')),
            if (widget.showActions)
              TextButton(
                onPressed: _busyWriteAction ? null : _writeReview,
                child: Text(_localDraft == null ? 'Write' : 'Edit'),
              ),
          ],
        ),
        if (_reviewsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: BracuLoading(label: 'Loading reviews...'),
          )
        else if (_reviewsError != null)
          BracuCard(
            child: Text(
              'No reviews yet for ${_facultyInitial.isEmpty ? 'this faculty' : _facultyInitial}.',
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
          )
        else ...[
          if (hasReviews) ...[
            BracuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _reviewFeed?.faculty.name.isNotEmpty == true
                        ? _reviewFeed!.faculty.name
                        : (_facultyInitial.isEmpty
                              ? 'Faculty'
                              : _facultyInitial),
                    style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Average rating: ${_reviewFeed?.faculty.stats.overall.toStringAsFixed(1) ?? '0.0'}/5'
                    ' based on $totalReviews ${totalReviews == 1 ? 'review' : 'reviews'}',
                    style: TextStyle(color: textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ] else if (localDraft == null)
            BracuCard(
              child: Text(
                'No reviews yet for this faculty.',
                style: TextStyle(color: textSecondary, fontSize: 12),
              ),
            ),
          ...displayReviews.map((review) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BracuCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Overall ${review.overall}/5',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Report',
                          onPressed: _busyWriteAction
                              ? null
                              : () => _reportReview(review.reviewId),
                          icon: const Icon(Icons.flag_outlined, size: 18),
                        ),
                        if (review.canDelete != false)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Delete',
                            onPressed: _busyWriteAction
                                ? null
                                : () => _deleteReview(review.reviewId),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                    if (review.comment.isNotEmpty)
                      Text(
                        review.comment,
                        style: TextStyle(color: textSecondary, fontSize: 12),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Teaching ${review.teaching}/5 • Fairness ${review.fairness}/5 • Behavior ${review.behavior}/5',
                      style: TextStyle(color: textSecondary, fontSize: 11),
                    ),
                    if (!review.isApproved) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Pending approval',
                        style: TextStyle(color: textSecondary, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          if (allReviews.length > 3)
            buildCenteredOutlinedActionButton(
              label: _showAllReviews ? 'Show Less' : 'Show More',
              onPressed: () {
                setState(() {
                  _showAllReviews = !_showAllReviews;
                });
              },
              padding: const EdgeInsets.only(top: 2, bottom: 8),
            ),
        ],
        if (localDraft != null && !isLocalDraftVisibleInFeed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BracuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your review',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Overall ${localDraft.overall}/5',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Teaching ${localDraft.teaching}/5 • Fairness ${localDraft.fairness}/5 • Behavior ${localDraft.behavior}/5',
                    style: TextStyle(color: textSecondary, fontSize: 11),
                  ),
                  if (localDraft.comment.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      localDraft.comment,
                      style: TextStyle(color: textSecondary, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: BracuSectionTitle(title: 'Course Materials')),
            if (widget.showActions)
              TextButton(
                onPressed: _busyWriteAction ? null : _openAddMaterialSheet,
                child: const Text('Add'),
              ),
          ],
        ),
        if (_materialsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: BracuLoading(label: 'Loading materials...'),
          )
        else if (_materialsError != null)
          BracuCard(
            child: Text(
              _materialsError!,
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
          )
        else if (allMaterials.isEmpty)
          BracuCard(
            child: Text(
              'No materials yet for ${widget.courseCode}.',
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
          )
        else ...[
          ...displayMaterials.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BracuCard(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _openMaterial(item),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title.isEmpty ? item.fileName : item.title,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _materialSubtitle(item),
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Report',
                      onPressed: _busyWriteAction
                          ? null
                          : () => _reportMaterial(item),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                    ),
                    if (item.canDelete != false)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Delete',
                        onPressed: _busyWriteAction
                            ? null
                            : () => _deleteMaterial(item),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          if (allMaterials.length > 3)
            buildCenteredOutlinedActionButton(
              label: _showAllMaterials ? 'Show Less' : 'Show More',
              onPressed: () {
                setState(() {
                  _showAllMaterials = !_showAllMaterials;
                });
              },
              padding: const EdgeInsets.only(top: 2, bottom: 8),
            ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  String _materialSubtitle(CourseMaterialItem item) {
    final parsed = _parseMaterialMeta(item);
    final parts = <String>[];
    final uploader = parsed.uploaderName;
    if (uploader.isNotEmpty) {
      parts.add('by $uploader');
    } else {
      parts.add('by Unknown');
    }
    if (parsed.linkUrl.isNotEmpty) {
      parts.add('Link');
    }
    final semester = item.semester.trim();
    if (semester.isNotEmpty) {
      parts.add(semester);
    }
    final size = parsed.linkUrl.isNotEmpty ? '' : _formatFileSize(item.fileSize);
    if (size.isNotEmpty) {
      parts.add(size);
    }
    return parts.isEmpty ? 'Course material' : parts.join(' • ');
  }

  _MaterialMeta _parseMaterialMeta(CourseMaterialItem item) {
    var uploader = item.uploaderName.trim();
    var linkUrl = item.externalUrl.trim();
    final marker = _extractMetaMarker(item.description);
    if (marker != null) {
      final maybeUploader = (marker['uploader'] ?? '').trim();
      final maybeUrl = (marker['linkUrl'] ?? '').trim();
      if (uploader.isEmpty && maybeUploader.isNotEmpty) {
        uploader = maybeUploader;
      }
      if (linkUrl.isEmpty && maybeUrl.isNotEmpty) {
        linkUrl = maybeUrl;
      }
    }
    if (linkUrl.isEmpty && item.contentType.trim().toLowerCase() == 'text/uri-list') {
      final extracted = _extractFirstHttpUrl(item.description);
      if (extracted.isNotEmpty) linkUrl = extracted;
    }
    return _MaterialMeta(uploaderName: uploader, linkUrl: linkUrl);
  }

  Map<String, String>? _extractMetaMarker(String description) {
    final raw = description.trim();
    if (raw.isEmpty) return null;
    final markerPrefix = 'PCMETA:';
    final markerLine = raw
        .split('\n')
        .map((line) => line.trim())
        .firstWhere(
          (line) => line.startsWith(markerPrefix),
          orElse: () => '',
        );
    if (markerLine.isEmpty) return null;
    final payload = markerLine.substring(markerPrefix.length).trim();
    if (payload.isEmpty) return null;
    try {
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded);
      if (map is Map<String, dynamic>) {
        return map.map(
          (key, value) => MapEntry(key, '${value ?? ''}'.trim()),
        );
      }
      if (map is Map) {
        return map.cast<String, dynamic>().map(
          (key, value) => MapEntry(key, '${value ?? ''}'.trim()),
        );
      }
    } catch (_) {}
    return null;
  }

  String _extractFirstHttpUrl(String raw) {
    final match = RegExp(r'https?://[^\s]+').firstMatch(raw);
    if (match == null) return '';
    return match.group(0)?.trim() ?? '';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _LocalFacultyReviewDraft {
  const _LocalFacultyReviewDraft({
    required this.overall,
    required this.teaching,
    required this.fairness,
    required this.behavior,
    required this.comment,
  });

  final int overall;
  final int teaching;
  final int fairness;
  final int behavior;
  final String comment;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'overall': overall,
      'teaching': teaching,
      'fairness': fairness,
      'behavior': behavior,
      'comment': comment,
    };
  }

  factory _LocalFacultyReviewDraft.fromJson(Map<String, dynamic> json) {
    return _LocalFacultyReviewDraft(
      overall: (json['overall'] as num?)?.toInt() ?? 0,
      teaching: (json['teaching'] as num?)?.toInt() ?? 0,
      fairness: (json['fairness'] as num?)?.toInt() ?? 0,
      behavior: (json['behavior'] as num?)?.toInt() ?? 0,
      comment: '${json['comment'] ?? ''}'.trim(),
    );
  }
}

class _MaterialMeta {
  const _MaterialMeta({required this.uploaderName, required this.linkUrl});

  final String uploaderName;
  final String linkUrl;
}

enum _AddMaterialTab { file, link }

class _AddTabButton extends StatelessWidget {
  const _AddTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = BracuPalette.primary;
    final textColor = selected
        ? Colors.white
        : BracuPalette.textSecondary(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
