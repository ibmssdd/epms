import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class StatusTopicService {
  StatusTopicService._();

  static final StatusTopicService instance = StatusTopicService._();

  final AppDatabase _db = AppDatabase.instance;

  // ============================================================
  // CONTINUATION FLOW
  // ============================================================
  //
  // These methods are ONLY for:
  // "Continue Existing Chapter"
  //
  // Data source:
  //     db_StatusTopics
  //
  // Allowed topic states:
  //     Pending
  //     InProgress
  //
  // Completed topics are deliberately excluded.
  // ============================================================

  Future<List<Map<String, Object?>>> getContinuationChapters(
    String subjectCode,
  ) async {
    final db = await _db.database;

    return db
        .rawQuery(
          '''
      SELECT
          TopicID,
          TopicChapterName
      FROM db_StatusTopics
      WHERE TopicID LIKE ?
        AND TopicState IN ('Pending', 'InProgress')
      GROUP BY
          TopicID,
          TopicChapterName
      ORDER BY
          TopicID ASC
      ''',
          ['${subjectCode.trim()}-%'],
        )
        .then((rows) {
          final result = <Map<String, Object?>>[];
          final seen = <String>{};

          for (final row in rows) {
            final topicId = row['TopicID']?.toString() ?? '';
            final chapterName = row['TopicChapterName']?.toString() ?? '';

            if (topicId.isEmpty) continue;

            final parts = topicId.split('-');

            if (parts.length < 3) continue;

            if (parts[0] != subjectCode.trim()) {
              continue;
            }

            final chapterCode = parts[1];

            if (chapterCode.isEmpty) continue;

            if (seen.contains(chapterCode)) {
              continue;
            }

            seen.add(chapterCode);

            result.add({
              'chapterCode': chapterCode,
              'chapterName': chapterName,
            });
          }

          return result;
        });
  }

  /// Returns ALL usable topics belonging to one existing chapter.
  ///
  /// Pending       -> included
  /// InProgress    -> included
  /// Completed     -> excluded
  ///
  /// This method intentionally reads ONLY db_StatusTopics.
  Future<List<Map<String, Object?>>> getContinuationTopics({
    required String subjectCode,
    required String chapterCode,
  }) async {
    final db = await _db.database;

    final cleanSubject = subjectCode.trim();
    final cleanChapter = chapterCode.trim();

    final rows = await db.rawQuery(
      '''
      SELECT
          TopicID,
          TopicName,
          TopicChapterName,
          TopicState,
          TopicLastLecNo,
          TopicStartDate,
          TopicEndDate
      FROM db_StatusTopics
      WHERE TopicID LIKE ?
        AND TopicState IN ('Pending', 'InProgress')
      ORDER BY TopicID ASC
      ''',
      ['$cleanSubject-$cleanChapter-%'],
    );

    return rows.map((row) {
      final topicId = row['TopicID']?.toString() ?? '';

      final parts = topicId.split('-');

      return <String, Object?>{
        'topicId': topicId,
        'topicCode': parts.length >= 3 ? parts.sublist(2).join('-') : '',
        'topicName': row['TopicName']?.toString() ?? '',
        'chapterCode': cleanChapter,
        'chapterName': row['TopicChapterName']?.toString() ?? '',
        'topicState': row['TopicState']?.toString() ?? '',
        'topicLastLecNo': row['TopicLastLecNo'] ?? 0,
        'topicStartDate': row['TopicStartDate'],
        'topicEndDate': row['TopicEndDate'],
      };
    }).toList();
  }

  /// Finds an existing topic status record.
  Future<Map<String, Object?>?> getByTopicId(
    Transaction txn,
    String topicId,
  ) async {
    final rows = await txn.query(
      'db_StatusTopics',
      where: 'TopicID = ?',
      whereArgs: [topicId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  /// Finds an existing topic status record using the normal database
  /// connection rather than a transaction.
  Future<Map<String, Object?>?> findByTopicId(String topicId) async {
    final db = await _db.database;

    final rows = await db.query(
      'db_StatusTopics',
      where: 'TopicID = ?',
      whereArgs: [topicId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  /// Returns all status-topic records belonging to a chapter.
  ///
  /// Used by the final chapter-completion check.
  Future<List<Map<String, Object?>>> getTopicsByChapter(
    String subjectCode,
    String chapterCode,
  ) async {
    final db = await _db.database;

    return db.rawQuery(
      '''
      SELECT
          TopicID,
          TopicLastLecNo,
          TopicStartDate,
          TopicEndDate,
          TopicState,
          TopicChapterName,
          TopicName
      FROM db_StatusTopics
      WHERE TopicID LIKE ?
      ORDER BY TopicID ASC
      ''',
      ['${subjectCode.trim()}-${chapterCode.trim()}-%'],
    );
  }

  /// Same query as above, but intended for use inside a transaction.
  Future<List<Map<String, Object?>>> getTopicsByChapterTxn(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
  }) async {
    return txn.rawQuery(
      '''
      SELECT
          TopicID,
          TopicLastLecNo,
          TopicStartDate,
          TopicEndDate,
          TopicState,
          TopicChapterName,
          TopicName
      FROM db_StatusTopics
      WHERE TopicID LIKE ?
      ORDER BY TopicID ASC
      ''',
      ['${subjectCode.trim()}-${chapterCode.trim()}-%'],
    );
  }

  // ============================================================
  // NEW CHAPTER FLOW
  // ============================================================
  //
  // These methods are used when LectureService determines that
  // the selected chapter is genuinely new.
  //
  // SyllabusSvc supplies the actual syllabus topics.
  // LectureService then calls these methods to initialise the
  // StatusTopics table.
  // ============================================================

  /// Returns whether this chapter already has any StatusTopic
  /// records for the supplied subject/chapter.
  ///
  /// This is intentionally a simple existence check.
  Future<bool> chapterExists(String subjectCode, String chapterCode) async {
    final db = await _db.database;

    final rows = await db.rawQuery(
      '''
      SELECT TopicID
      FROM db_StatusTopics
      WHERE TopicID LIKE ?
      LIMIT 1
      ''',
      ['${subjectCode.trim()}-${chapterCode.trim()}-%'],
    );

    return rows.isNotEmpty;
  }

  /// Transaction version of chapterExists().
  Future<bool> chapterExistsTxn(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT TopicID
      FROM db_StatusTopics
      WHERE TopicID LIKE ?
      LIMIT 1
      ''',
      ['${subjectCode.trim()}-${chapterCode.trim()}-%'],
    );

    return rows.isNotEmpty;
  }

  /// Inserts one initial StatusTopic record.
  ///
  /// This is used by the NEW CHAPTER workflow to initialise all
  /// topics belonging to the selected syllabus chapter.
  Future<int> createInitialTopic(
    Transaction txn, {
    required String topicId,
    required String topicName,
    required String chapterName,
  }) async {
    return txn.insert('db_StatusTopics', {
      'TopicID': topicId,
      'TopicLastLecNo': 0,
      'TopicStartDate': null,
      'TopicEndDate': null,
      'TopicState': 'Pending',
      'TopicChapterName': chapterName,
      'TopicName': topicName,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Creates all StatusTopic records for a new chapter.
  ///
  /// The supplied syllabusTopics list is expected to contain maps
  /// with:
  ///
  /// topicId
  /// topicName
  ///
  /// The selected topic is NOT activated here. That is deliberately
  /// handled separately by activateTopic().
  Future<void> createInitialChapterTopics(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
    required String chapterName,
    required List<Map<String, Object?>> syllabusTopics,
  }) async {
    final cleanSubject = subjectCode.trim();
    final cleanChapter = chapterCode.trim();

    for (final topic in syllabusTopics) {
      final topicCode = topic['topicCode']?.toString().trim() ?? '';

      final topicIdFromSyllabus = topic['topicId']?.toString().trim() ?? '';

      final topicName = topic['topicName']?.toString().trim() ?? '';

      if (topicName.isEmpty) {
        continue;
      }

      final topicId = topicIdFromSyllabus.isNotEmpty
          ? topicIdFromSyllabus
          : '$cleanSubject-$cleanChapter-$topicCode';

      if (topicId.isEmpty) {
        continue;
      }

      await createInitialTopic(
        txn,
        topicId: topicId,
        topicName: topicName,
        chapterName: chapterName,
      );
    }
  }

  // ============================================================
  // STATUS UPDATE OPERATIONS
  // ============================================================

  /// Activates the selected topic for its first lecture.
  ///
  /// Used by NEW CHAPTER workflow.
  Future<int> activateNewTopic(
    Transaction txn, {
    required String topicId,
    required String startDate,
  }) async {
    return txn.update(
      'db_StatusTopics',
      {
        'TopicLastLecNo': 1,
        'TopicStartDate': startDate,
        'TopicEndDate': null,
        'TopicState': 'InProgress',
      },
      where: 'TopicID = ?',
      whereArgs: [topicId],
    );
  }

  /// Advances an existing Pending/InProgress topic.
  ///
  /// Pending topic:
  ///     lecture becomes 1
  ///     state becomes InProgress
  ///     start date is established
  ///
  /// InProgress topic:
  ///     lecture number is incremented
  ///     state remains InProgress
  ///
  /// If lastLecture is true, the topic becomes Completed and the
  /// end date is written.
  Future<int> updateLectureProgress(
    Transaction txn, {
    required String topicId,
    required int lectureNumber,
    required bool lastLecture,
    String? startDate,
    String? endDate,
  }) async {
    final values = <String, Object?>{
      'TopicLastLecNo': lectureNumber,
      'TopicState': lastLecture ? 'Completed' : 'InProgress',
    };

    if (startDate != null && startDate.trim().isNotEmpty) {
      values['TopicStartDate'] = startDate;
    }

    if (lastLecture && endDate != null && endDate.trim().isNotEmpty) {
      values['TopicEndDate'] = endDate;
    }

    return txn.update(
      'db_StatusTopics',
      values,
      where: 'TopicID = ?',
      whereArgs: [topicId],
    );
  }

  /// Marks a topic as completed.
  ///
  /// Kept separate from updateLectureProgress() so the business
  /// operation is explicit when required elsewhere.
  Future<int> completeTopic(
    Transaction txn, {
    required String topicId,
    required String endDate,
  }) async {
    return txn.update(
      'db_StatusTopics',
      {'TopicState': 'Completed', 'TopicEndDate': endDate},
      where: 'TopicID = ?',
      whereArgs: [topicId],
    );
  }

  // ============================================================
  // GENERAL STATUS QUERIES
  // ============================================================

  Future<List<Map<String, Object?>>> getByStatus(String status) async {
    final db = await _db.database;

    return db.query(
      'db_StatusTopics',
      where: 'TopicState = ?',
      whereArgs: [status],
      orderBy: 'TopicID ASC',
    );
  }

  Future<List<Map<String, Object?>>> getPendingTopics() {
    return getByStatus('Pending');
  }

  Future<List<Map<String, Object?>>> getInProgressTopics() {
    return getByStatus('InProgress');
  }

  Future<List<Map<String, Object?>>> getCompletedTopics() {
    return getByStatus('Completed');
  }

  Future<List<Map<String, Object?>>> getInProgressTopicsBySubject(
    String subjectCode,
  ) async {
    final db = await _db.database;

    return db.query(
      'db_StatusTopics',
      where: 'TopicState = ? AND TopicID LIKE ?',
      whereArgs: ['InProgress', '${subjectCode.trim()}-%'],
      orderBy: 'TopicID ASC',
    );
  }

  Future<List<Map<String, Object?>>> getPendingTopicsBySubject(
    String subjectCode,
  ) async {
    final db = await _db.database;

    return db.query(
      'db_StatusTopics',
      where: 'TopicState = ? AND TopicID LIKE ?',
      whereArgs: ['Pending', '${subjectCode.trim()}-%'],
      orderBy: 'TopicID ASC',
    );
  }

  // ============================================================
  // CHAPTER COMPLETION CHECK
  // ============================================================

  /// Returns true only when every topic belonging to the chapter
  /// is Completed.
  ///
  /// This method does NOT modify db_StatusChapters.
  Future<bool> areAllTopicsCompleted(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
  }) async {
    final rows = await getTopicsByChapterTxn(
      txn,
      subjectCode: subjectCode,
      chapterCode: chapterCode,
    );

    if (rows.isEmpty) {
      return false;
    }

    for (final row in rows) {
      final state = row['TopicState']?.toString() ?? '';

      if (state != 'Completed') {
        return false;
      }
    }

    return true;
  }

  // ============================================================
  // LEGACY-COMPATIBILITY HELPERS
  // ============================================================
  //
  // These are intentionally kept simple so other existing screens
  // that may still call these methods do not break.
  // ============================================================

  Future<void> ensureExists(
    Transaction txn, {
    required String topicId,
    required String topicName,
    required String chapterName,
  }) async {
    await txn.insert('db_StatusTopics', {
      'TopicID': topicId,
      'TopicLastLecNo': 0,
      'TopicStartDate': null,
      'TopicEndDate': null,
      'TopicState': 'Pending',
      'TopicChapterName': chapterName,
      'TopicName': topicName,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> ensureChapterTopics(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
    required String chapterName,
  }) async {
    final exists = await chapterExistsTxn(
      txn,
      subjectCode: subjectCode,
      chapterCode: chapterCode,
    );

    if (exists) {
      return;
    }

    final syllabusRows = await txn.query(
      'db_SyllabusMaster',
      columns: const ['topic_id', 'topic_code', 'topic_name', 'chapter_name'],
      where: 'subject_code = ? AND chapter_code = ?',
      whereArgs: [subjectCode, chapterCode],
      orderBy: 'display_order ASC',
    );

    for (final row in syllabusRows) {
      final topicId = row['topic_id']?.toString() ?? '';

      final topicName = row['topic_name']?.toString() ?? '';

      final syllabusChapterName = row['chapter_name']?.toString() ?? '';

      if (topicId.isEmpty || topicName.isEmpty) {
        continue;
      }

      await ensureExists(
        txn,
        topicId: topicId,
        topicName: topicName,
        chapterName: syllabusChapterName.isEmpty
            ? chapterName
            : syllabusChapterName,
      );
    }
  }
}
