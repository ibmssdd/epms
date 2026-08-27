import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class StatusChapterService {
  StatusChapterService._();

  static final StatusChapterService instance = StatusChapterService._();

  final AppDatabase _db = AppDatabase.instance;

  // ============================================================
  // COMMON LOOKUPS
  // ============================================================

  /// Finds a StatusChapter record using:
  ///
  /// SubjectChapterCode = <SubjectCode>-<ChapterCode>
  ///
  /// This is the primary key of db_StatusChapters.
  Future<Map<String, Object?>?> getBySubjectChapterCode(
    String subjectChapterCode,
  ) async {
    final db = await _db.database;

    final rows = await db.query(
      'db_StatusChapters',
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode.trim()],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  /// Transaction version of getBySubjectChapterCode().
  Future<Map<String, Object?>?> getBySubjectChapterCodeTxn(
    Transaction txn,
    String subjectChapterCode,
  ) async {
    final rows = await txn.query(
      'db_StatusChapters',
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode.trim()],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  /// Checks whether a StatusChapter record already exists.
  Future<bool> exists(String subjectChapterCode) async {
    final row = await getBySubjectChapterCode(subjectChapterCode);

    return row != null;
  }

  /// Transaction version of exists().
  Future<bool> existsTxn(Transaction txn, String subjectChapterCode) async {
    final row = await getBySubjectChapterCodeTxn(txn, subjectChapterCode);

    return row != null;
  }

  // ============================================================
  // NEW CHAPTER FLOW
  // ============================================================
  //
  // Used ONLY when LectureService has established that the
  // selected chapter is genuinely new.
  //
  // IMPORTANT:
  // db_StatusChapters does NOT contain ChapterCode.
  //
  // The primary key is:
  //     SubjectChapterCode
  //
  // Therefore ChapterCode is never inserted into this table.
  // ============================================================

  Future<int> createNewChapter(
    Transaction txn, {
    required String subjectChapterCode,
    required String chapterName,
    required String startDate,
  }) async {
    return txn.insert('db_StatusChapters', {
      'SubjectChapterCode': subjectChapterCode.trim(),
      'ChapterName': chapterName.trim(),
      'ChapterState': 'InProgress',
      'LecturesStartDate': startDate,
      'LecturesEndDate': null,
      'AllTopicsCompleted': 'No',
      'PMTCompleted': 'No',
      'CMTCompleted': 'No',
      'WeakAreasCleared': 'No',
      'FinalExamReady': 'No',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // ============================================================
  // CONTINUATION FLOW
  // ============================================================
  //
  // Continuation normally does NOT touch StatusChapters.
  //
  // The exception is the final completion check:
  // when ALL StatusTopics belonging to the chapter become
  // Completed, LectureService may call completeChapter().
  // ============================================================

  Future<int> completeChapter(
    Transaction txn, {
    required String subjectChapterCode,
    required String endDate,
  }) async {
    return txn.update(
      'db_StatusChapters',
      {
        'ChapterState': 'ExamReady',
        'LecturesEndDate': endDate,
        'AllTopicsCompleted': 'Yes',
      },
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode.trim()],
    );
  }

  // ============================================================
  // EXPLICIT COMPLETION CHECK
  // ============================================================

  /// Updates the chapter only when all topics have been completed.
  ///
  /// Returns true when the chapter was updated.
  ///
  /// Returns false when the chapter still has incomplete topics.
  ///
  /// This method deliberately does not inspect or modify
  /// db_StatusTopics. The caller supplies the result of the
  /// topic completion check.
  Future<bool> completeChapterIfAllTopicsCompleted(
    Transaction txn, {
    required String subjectChapterCode,
    required bool allTopicsCompleted,
    required String endDate,
  }) async {
    if (!allTopicsCompleted) {
      return false;
    }

    final existing = await getBySubjectChapterCodeTxn(txn, subjectChapterCode);

    if (existing == null) {
      return false;
    }

    await txn.update(
      'db_StatusChapters',
      {
        'ChapterState': 'ExamReady',
        'LecturesEndDate': endDate,
        'AllTopicsCompleted': 'Yes',
      },
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode.trim()],
    );

    return true;
  }

  // ============================================================
  // STATUS UPDATES
  // ============================================================

  Future<int> updateStatusChapter(
    String subjectChapterCode, {
    required Map<String, Object?> values,
  }) async {
    final db = await _db.database;

    return db.update(
      'db_StatusChapters',
      values,
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode.trim()],
    );
  }

  Future<int> updateStatusChapterTxn(
    Transaction txn,
    String subjectChapterCode, {
    required Map<String, Object?> values,
  }) async {
    return txn.update(
      'db_StatusChapters',
      values,
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode.trim()],
    );
  }

  // ============================================================
  // GENERAL STATUS QUERIES
  // ============================================================

  Future<List<Map<String, Object?>>> getByStatus(String status) async {
    final db = await _db.database;

    return db.query(
      'db_StatusChapters',
      where: 'ChapterState = ?',
      whereArgs: [status],
      orderBy: 'SubjectChapterCode ASC',
    );
  }

  Future<List<Map<String, Object?>>> getNotStartedChapters() {
    return getByStatus('NotStarted');
  }

  Future<List<Map<String, Object?>>> getInProgressChapters() {
    return getByStatus('InProgress');
  }

  Future<List<Map<String, Object?>>> getExamReadyChapters() {
    return getByStatus('ExamReady');
  }

  // ============================================================
  // SUBJECT-SPECIFIC CONTINUATION DATA
  // ============================================================

  /// Returns all currently InProgress chapters belonging to
  /// the supplied subject.
  ///
  /// This is useful for other parts of EPMS that need chapter
  /// status information.
  ///
  /// NOTE:
  /// The LectureScreen continuation dropdown should primarily
  /// obtain its chapter list from StatusTopicService because
  /// continuation is topic-driven.
  Future<List<Map<String, Object?>>> getInProgressChaptersBySubject(
    String subjectCode,
  ) async {
    final db = await _db.database;

    return db.query(
      'db_StatusChapters',
      where: 'ChapterState = ? AND SubjectChapterCode LIKE ?',
      whereArgs: ['InProgress', '${subjectCode.trim()}-%'],
      orderBy: 'SubjectChapterCode ASC',
    );
  }

  // ============================================================
  // START CHAPTER IF REQUIRED
  // ============================================================
  //
  // Compatibility/helper method.
  //
  // IMPORTANT:
  // It does NOT insert ChapterCode because that column does not
  // exist in db_StatusChapters.
  // ============================================================

  Future<void> startChapterIfRequired(
    Transaction txn, {
    required String subjectChapterCode,
    required String chapterName,
    required String lectureDate,
  }) async {
    final existing = await getBySubjectChapterCodeTxn(txn, subjectChapterCode);

    if (existing != null) {
      return;
    }

    await createNewChapter(
      txn,
      subjectChapterCode: subjectChapterCode,
      chapterName: chapterName,
      startDate: lectureDate,
    );
  }

  // ============================================================
  // SAFE CHAPTER STATE UPDATE
  // ============================================================

  Future<int> markChapterInProgress(
    Transaction txn, {
    required String subjectChapterCode,
    String? chapterName,
    String? startDate,
  }) async {
    final values = <String, Object?>{'ChapterState': 'InProgress'};

    if (chapterName != null && chapterName.trim().isNotEmpty) {
      values['ChapterName'] = chapterName.trim();
    }

    if (startDate != null && startDate.trim().isNotEmpty) {
      values['LecturesStartDate'] = startDate;
    }

    return txn.update(
      'db_StatusChapters',
      values,
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode.trim()],
    );
  }

  // ============================================================
  // CHAPTER COMPLETION FLAGS
  // ============================================================

  Future<int> setAllTopicsCompleted(
    Transaction txn, {
    required String subjectChapterCode,
    required String endDate,
  }) async {
    return txn.update(
      'db_StatusChapters',
      {
        'ChapterState': 'ExamReady',
        'LecturesEndDate': endDate,
        'AllTopicsCompleted': 'Yes',
      },
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode.trim()],
    );
  }

  // ============================================================
  // DELETE / RESET SUPPORT
  // ============================================================
  //
  // Not used by lecture recording.
  // Kept explicit so future maintenance does not require raw SQL
  // scattered throughout the application.
  // ============================================================

  Future<int> deleteChapter(String subjectChapterCode) async {
    final db = await _db.database;

    return db.delete(
      'db_StatusChapters',
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode.trim()],
    );
  }
}
