import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'svc_Syllabus.dart';

class LectureSaveResult {
  final String lectureId;
  final bool closedTopic;
  final bool completedChapter;
  final bool usedContinuationFlow;

  const LectureSaveResult({
    required this.lectureId,
    required this.closedTopic,
    required this.completedChapter,
    required this.usedContinuationFlow,
  });
}

class LectureService {
  LectureService._();

  static final LectureService instance = LectureService._();

  static const String _lectureTypeCode = 'CC-XC';

  final AppDatabase _db = AppDatabase.instance;

  final SyllabusSvc _syllabusService = SyllabusSvc();

  // ============================================================
  // CONTINUATION FLOW
  // ============================================================
  //
  // Continued Topic Lecture
  //
  // Source:
  //   db_StatusTopics
  //
  // Rules:
  //   - only chapters having Pending/InProgress topics
  //   - Completed topics are excluded
  //   - if only one active chapter exists, the UI can preload it
  //   - topics returned are Pending + InProgress
  // ============================================================

  Future<List<Map<String, Object?>>> getContinuationChapters(
    String subjectCode,
  ) async {
    final db = await _db.database;

    final cleanSubject = subjectCode.trim();

    if (cleanSubject.isEmpty) {
      return [];
    }

    final rows = await db.query(
      'db_StatusTopics',
      columns: ['TopicID', 'TopicChapterName', 'TopicState'],
      where: '''
        TopicID LIKE ?
        AND TopicState IN (?, ?)
      ''',
      whereArgs: ['$cleanSubject-%', 'Pending', 'InProgress'],
      orderBy: 'TopicID ASC',
    );

    final chapters = <String, Map<String, Object?>>{};

    for (final row in rows) {
      final topicId = row['TopicID']?.toString() ?? '';

      final parsed = _parseTopicId(topicId);

      final chapterCode = parsed['chapterCode']?.toString() ?? '';

      if (chapterCode.isEmpty) {
        continue;
      }

      final chapterName = row['TopicChapterName']?.toString() ?? '';

      final key = '$cleanSubject-$chapterCode';

      chapters.putIfAbsent(
        key,
        () => <String, Object?>{
          'chapterCode': chapterCode,
          'chapterName': chapterName,
          'subjectChapterCode': key,
        },
      );
    }

    final result = chapters.values.toList();

    result.sort((a, b) {
      final aCode = a['chapterCode']?.toString() ?? '';

      final bCode = b['chapterCode']?.toString() ?? '';

      return aCode.compareTo(bCode);
    });

    return result;
  }

  /// Returns all Pending + InProgress topics
  /// belonging to the selected continuation chapter.
  ///
  /// Completed topics are deliberately excluded.
  Future<List<Map<String, Object?>>> getContinuationTopics({
    required String subjectCode,
    required String chapterCode,
  }) async {
    final db = await _db.database;

    final cleanSubject = subjectCode.trim();

    final cleanChapter = chapterCode.trim();

    if (cleanSubject.isEmpty || cleanChapter.isEmpty) {
      return [];
    }

    final prefix = '$cleanSubject-$cleanChapter-';

    final rows = await db.query(
      'db_StatusTopics',
      where: '''
        TopicID LIKE ?
        AND TopicState IN (?, ?)
      ''',
      whereArgs: ['$prefix%', 'Pending', 'InProgress'],
      orderBy: 'TopicID ASC',
    );

    return rows.map((row) {
      final topicId = row['TopicID']?.toString() ?? '';

      final parsed = _parseTopicId(topicId);

      return <String, Object?>{
        'topicId': topicId,
        'topicCode': parsed['topicCode'] ?? '',
        'topicName': row['TopicName'] ?? '',
        'chapterCode': cleanChapter,
        'chapterName': row['TopicChapterName'] ?? '',
        'topicState': row['TopicState'] ?? 'Pending',
        'topicLastLecNo': row['TopicLastLecNo'] ?? 0,
        'topicStartDate': row['TopicStartDate'],
        'topicEndDate': row['TopicEndDate'],
      };
    }).toList();
  }

  // ============================================================
  // NEW CHAPTER FLOW
  // ============================================================
  //
  // Source:
  //   Syllabus Master through SyllabusSvc
  //
  // These methods deliberately return the simple Map structure
  // expected by LectureScreen.
  // ============================================================

  Future<List<Map<String, Object?>>> getNewChapterChapters(
    String subjectCode,
  ) async {
    final chapters = await _syllabusService.getChapters(subjectCode);

    return chapters.map((chapter) {
      return <String, Object?>{
        'chapterCode': chapter.chapterCode,
        'chapterName': chapter.chapterName,
      };
    }).toList();
  }

  Future<List<Map<String, Object?>>> getNewChapterTopics({
    required String subjectCode,
    required String chapterCode,
  }) async {
    final topics = await _syllabusService.getTopics(subjectCode, chapterCode);

    return topics.map((topic) {
      return <String, Object?>{
        'topicId': topic.topicId,
        'topicCode': topic.topicCode,
        'topicName': topic.topicName,
        'chapterCode': chapterCode,
      };
    }).toList();
  }

  // ============================================================
  // SAVE LECTURE
  // ============================================================
  //
  // newChapter == false
  //     -> Continued Topic Lecture
  //
  // newChapter == true
  //     -> Start New Chapter
  //
  // IMPORTANT:
  // Even if the UI says Start New Chapter, we check StatusTopics
  // again. If that chapter already exists, we safely switch to
  // continuation behaviour.
  // ============================================================

  Future<LectureSaveResult> saveLecture({
    required String subjectCode,
    required String chapterCode,
    required String topicCode,
    required String chapterName,
    required String topicName,
    required String topicId,
    required DateTime lectureDate,
    String? shortNotes,
    required bool lastLecture,
    required bool newChapter,
  }) async {
    final cleanSubject = subjectCode.trim();

    final cleanChapter = chapterCode.trim();

    final cleanTopic = topicCode.trim();

    final cleanTopicId = topicId.trim();

    final cleanChapterName = chapterName.trim();

    final cleanTopicName = topicName.trim();

    final day = _dateOnly(lectureDate);

    if (day.isAfter(_dateOnly(DateTime.now()))) {
      throw ArgumentError('Future lecture dates are not allowed.');
    }

    if (cleanSubject.isEmpty) {
      throw ArgumentError('Subject code is required.');
    }

    if (cleanChapter.isEmpty) {
      throw ArgumentError('Chapter code is required.');
    }

    if (cleanTopic.isEmpty) {
      throw ArgumentError('Topic code is required.');
    }

    if (cleanTopicId.isEmpty) {
      throw ArgumentError('Topic ID is required.');
    }

    if (cleanChapterName.isEmpty) {
      throw ArgumentError('Chapter name is required.');
    }

    if (cleanTopicName.isEmpty) {
      throw ArgumentError('Topic name is required.');
    }

    final db = await _db.database;

    return db.transaction((txn) async {
      final chapterAlreadyExists = await _chapterExistsTxn(
        txn,
        subjectCode: cleanSubject,
        chapterCode: cleanChapter,
      );

      final useContinuation = !newChapter || chapterAlreadyExists;

      if (useContinuation) {
        return _saveContinuationLecture(
          txn,
          subjectCode: cleanSubject,
          chapterCode: cleanChapter,
          topicCode: cleanTopic,
          topicId: cleanTopicId,
          chapterName: cleanChapterName,
          topicName: cleanTopicName,
          lectureDate: day,
          shortNotes: shortNotes,
          lastLecture: lastLecture,
        );
      }

      return _saveNewChapterLecture(
        txn,
        subjectCode: cleanSubject,
        chapterCode: cleanChapter,
        topicCode: cleanTopic,
        topicId: cleanTopicId,
        chapterName: cleanChapterName,
        topicName: cleanTopicName,
        lectureDate: day,
        shortNotes: shortNotes,
        lastLecture: lastLecture,
      );
    });
  }

  // ============================================================
  // CONTINUATION SAVE
  // ============================================================

  Future<LectureSaveResult> _saveContinuationLecture(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
    required String topicCode,
    required String topicId,
    required String chapterName,
    required String topicName,
    required DateTime lectureDate,
    String? shortNotes,
    required bool lastLecture,
  }) async {
    final rows = await txn.query(
      'db_StatusTopics',
      where: 'TopicID = ?',
      whereArgs: [topicId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError(
        'The selected topic does not exist in '
        'db_StatusTopics: $topicId',
      );
    }

    final existing = rows.first;

    final currentState = existing['TopicState']?.toString() ?? 'Pending';

    if (currentState == 'Completed') {
      throw StateError('The selected topic is already completed.');
    }

    if (currentState != 'Pending' && currentState != 'InProgress') {
      throw StateError('Invalid topic state: $currentState');
    }

    final currentLectureNo = _asInt(existing['TopicLastLecNo']) ?? 0;

    final nextLectureNo = currentLectureNo + 1;

    final oldStartDate = existing['TopicStartDate']?.toString();

    final startDate = oldStartDate == null || oldStartDate.trim().isEmpty
        ? _yyyyMmDd(lectureDate)
        : oldStartDate;

    final endDate = lastLecture ? _yyyyMmDd(lectureDate) : null;

    final lectureId = _buildLectureId(
      subjectCode: subjectCode,
      chapterCode: chapterCode,
      topicCode: topicCode,
      lectureNumber: nextLectureNo,
      lectureDate: lectureDate,
    );

    // ----------------------------------------------------------
    // TopicState:
    //
    // Pending + first lecture
    //     -> InProgress
    //
    // InProgress + normal lecture
    //     -> InProgress
    //
    // Last lecture
    //     -> Completed
    //
    // IMPORTANT:
    // Never use "Close". It violates the CHECK constraint.
    // ----------------------------------------------------------

    final newState = lastLecture ? 'Completed' : 'InProgress';

    final updateCount = await txn.update(
      'db_StatusTopics',
      {
        'TopicLastLecNo': nextLectureNo,
        'TopicState': newState,
        'TopicStartDate': startDate,
        'TopicEndDate': endDate,
      },
      where: 'TopicID = ?',
      whereArgs: [topicId],
    );

    if (updateCount != 1) {
      throw StateError('Unable to update StatusTopic: $topicId');
    }

    await _insertLectureLog(txn, lectureId: lectureId, shortNotes: shortNotes);

    bool completedChapter = false;

    if (lastLecture) {
      completedChapter = await _completeChapterIfRequired(
        txn,
        subjectCode: subjectCode,
        chapterCode: chapterCode,
        lectureDate: lectureDate,
      );
    }

    return LectureSaveResult(
      lectureId: lectureId,
      closedTopic: lastLecture,
      completedChapter: completedChapter,
      usedContinuationFlow: true,
    );
  }

  // ============================================================
  // NEW CHAPTER SAVE
  // ============================================================

  Future<LectureSaveResult> _saveNewChapterLecture(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
    required String topicCode,
    required String topicId,
    required String chapterName,
    required String topicName,
    required DateTime lectureDate,
    String? shortNotes,
    required bool lastLecture,
  }) async {
    // ----------------------------------------------------------
    // Load ALL syllabus topics for this chapter.
    // ----------------------------------------------------------

    final syllabusTopics = await _syllabusService.getTopics(
      subjectCode,
      chapterCode,
    );

    if (syllabusTopics.isEmpty) {
      throw StateError(
        'No syllabus topics found for '
        '$subjectCode-$chapterCode.',
      );
    }

    // ----------------------------------------------------------
    // Safety check inside transaction.
    // ----------------------------------------------------------

    final chapterAlreadyExists = await _chapterExistsTxn(
      txn,
      subjectCode: subjectCode,
      chapterCode: chapterCode,
    );

    if (chapterAlreadyExists) {
      return _saveContinuationLecture(
        txn,
        subjectCode: subjectCode,
        chapterCode: chapterCode,
        topicCode: topicCode,
        topicId: topicId,
        chapterName: chapterName,
        topicName: topicName,
        lectureDate: lectureDate,
        shortNotes: shortNotes,
        lastLecture: lastLecture,
      );
    }

    // ----------------------------------------------------------
    // Create ALL StatusTopics as Pending.
    // ----------------------------------------------------------

    for (final topic in syllabusTopics) {
      final syllabusTopicId = topic.topicId.trim();

      if (syllabusTopicId.isEmpty) {
        continue;
      }

      await txn.insert('db_StatusTopics', {
        'TopicID': syllabusTopicId,
        'TopicLastLecNo': 0,
        'TopicStartDate': null,
        'TopicEndDate': null,
        'TopicState': 'Pending',
        'TopicChapterName': chapterName,
        'TopicName': topic.topicName,
      });
    }

    // ----------------------------------------------------------
    // Make sure the selected topic was created.
    // ----------------------------------------------------------

    final selectedRows = await txn.query(
      'db_StatusTopics',
      where: 'TopicID = ?',
      whereArgs: [topicId],
      limit: 1,
    );

    if (selectedRows.isEmpty) {
      throw StateError(
        'Unable to initialise selected topic: '
        '$topicId',
      );
    }

    // ----------------------------------------------------------
    // Activate selected topic.
    // ----------------------------------------------------------

    final selectedState = lastLecture ? 'Completed' : 'InProgress';

    final selectedUpdate = await txn.update(
      'db_StatusTopics',
      {
        'TopicLastLecNo': 1,
        'TopicStartDate': _yyyyMmDd(lectureDate),
        'TopicEndDate': lastLecture ? _yyyyMmDd(lectureDate) : null,
        'TopicState': selectedState,
      },
      where: 'TopicID = ?',
      whereArgs: [topicId],
    );

    if (selectedUpdate != 1) {
      throw StateError(
        'Unable to activate selected topic: '
        '$topicId',
      );
    }

    // ----------------------------------------------------------
    // Create StatusChapter.
    // ----------------------------------------------------------

    final subjectChapterCode = _subjectChapterCode(subjectCode, chapterCode);

    await txn.insert('db_StatusChapters', {
      'SubjectChapterCode': subjectChapterCode,
      'ChapterName': chapterName,
      'ChapterState': 'InProgress',
      'LecturesStartDate': _yyyyMmDd(lectureDate),
      'LecturesEndDate': null,
      'AllTopicsCompleted': 'No',
      'PMTCompleted': 'No',
      'CMTCompleted': 'No',
      'WeakAreasCleared': 'No',
      'FinalExamReady': 'No',
    });

    // ----------------------------------------------------------
    // Lecture 1.
    // ----------------------------------------------------------

    final lectureId = _buildLectureId(
      subjectCode: subjectCode,
      chapterCode: chapterCode,
      topicCode: topicCode,
      lectureNumber: 1,
      lectureDate: lectureDate,
    );

    await _insertLectureLog(txn, lectureId: lectureId, shortNotes: shortNotes);

    bool completedChapter = false;

    if (lastLecture) {
      completedChapter = await _completeChapterIfRequired(
        txn,
        subjectCode: subjectCode,
        chapterCode: chapterCode,
        lectureDate: lectureDate,
      );
    }

    return LectureSaveResult(
      lectureId: lectureId,
      closedTopic: lastLecture,
      completedChapter: completedChapter,
      usedContinuationFlow: false,
    );
  }

  // ============================================================
  // CHAPTER COMPLETION
  // ============================================================
  //
  // Only StatusTopics is inspected first.
  //
  // If EVERY topic belonging to this chapter is Completed:
  //
  //     update db_StatusChapters.LecturesEndDate
  //
  // Otherwise:
  //
  //     DO NOT TOUCH db_StatusChapters
  //
  // This follows the agreed design.
  // ============================================================

  Future<bool> _completeChapterIfRequired(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
    required DateTime lectureDate,
  }) async {
    final prefix = '$subjectCode-$chapterCode-';

    final rows = await txn.query(
      'db_StatusTopics',
      columns: ['TopicID', 'TopicState'],
      where: 'TopicID LIKE ?',
      whereArgs: ['$prefix%'],
    );

    if (rows.isEmpty) {
      return false;
    }

    final allCompleted = rows.every(
      (row) => row['TopicState']?.toString() == 'Completed',
    );

    if (!allCompleted) {
      return false;
    }

    final subjectChapterCode = _subjectChapterCode(subjectCode, chapterCode);

    final updateCount = await txn.update(
      'db_StatusChapters',
      {'LecturesEndDate': _yyyyMmDd(lectureDate)},
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode],
    );

    return updateCount == 1;
  }

  // ============================================================
  // CHAPTER EXISTS
  // ============================================================
  //
  // StatusTopics does not have a separate SubjectCode or
  // ChapterCode column.
  //
  // TopicID contains:
  //
  //     Phy-Ch01-T01
  //
  // Therefore chapter existence is determined from TopicID.
  // ============================================================

  Future<bool> _chapterExistsTxn(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
  }) async {
    final prefix =
        '${subjectCode.trim()}-'
        '${chapterCode.trim()}-';

    final rows = await txn.query(
      'db_StatusTopics',
      columns: ['TopicID'],
      where: 'TopicID LIKE ?',
      whereArgs: ['$prefix%'],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  // ============================================================
  // LECTURE LOG
  // ============================================================

  Future<void> _insertLectureLog(
    Transaction txn, {
    required String lectureId,
    String? shortNotes,
  }) async {
    await txn.insert('db_LectureLog', {
      'lecture_id': lectureId,
      'lecture_type_code': _lectureTypeCode,
      'lecture_short_details': _cleanNotes(shortNotes),
      'lecture_class_notes_file_path': null,
      'lecture_class_notes_images': null,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ============================================================
  // LECTURE ID
  // ============================================================

  String _buildLectureId({
    required String subjectCode,
    required String chapterCode,
    required String topicCode,
    required int lectureNumber,
    required DateTime lectureDate,
  }) {
    return '$subjectCode-'
        '$chapterCode-'
        '$topicCode-'
        'L${lectureNumber.toString().padLeft(2, '0')}-'
        '${_yyyymmdd(lectureDate)}';
  }

  // ============================================================
  // TOPIC ID PARSER
  // ============================================================

  Map<String, String> _parseTopicId(String topicId) {
    final parts = topicId.split('-');

    if (parts.length < 3) {
      return {'subjectCode': '', 'chapterCode': '', 'topicCode': ''};
    }

    return {
      'subjectCode': parts[0],
      'chapterCode': parts[1],
      'topicCode': parts[2],
    };
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _subjectChapterCode(String subjectCode, String chapterCode) {
    return '${subjectCode.trim()}-'
        '${chapterCode.trim()}';
  }

  String? _cleanNotes(String? value) {
    final cleaned = value?.trim();

    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }

    return cleaned;
  }

  int? _asInt(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(value.toString());
  }

  String _yyyymmdd(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}'
        '${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}';
  }

  String _yyyyMmDd(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
