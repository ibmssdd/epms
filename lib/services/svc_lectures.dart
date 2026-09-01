import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'svc_syllabus.dart';

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
  // DEBUG
  // ============================================================

  void _log(String message) {
    print('[LECTURE SERVICE] ${DateTime.now().toIso8601String()} $message');
  }

  void _section(String title) {
    print('');
    print(
      '[LECTURE SERVICE] ============================================================',
    );
    print('[LECTURE SERVICE] $title');
    print(
      '[LECTURE SERVICE] ============================================================',
    );
  }

  // ============================================================
  // CONTINUATION FLOW
  // ============================================================

  Future<List<Map<String, Object?>>> getContinuationChapters(
    String subjectCode,
  ) async {
    _section('getContinuationChapters() START');

    _log('subjectCode=$subjectCode');

    final db = await _db.database;

    final cleanSubject = subjectCode.trim();

    if (cleanSubject.isEmpty) {
      _log('Empty subject code. Returning [].');
      return [];
    }

    _log('Querying db_StatusTopics for Pending/InProgress chapters...');

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

    _log('db_StatusTopics returned ${rows.length} rows.');

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

    _log('Returning ${result.length} continuation chapters.');

    return result;
  }

  Future<List<Map<String, Object?>>> getContinuationTopics({
    required String subjectCode,
    required String chapterCode,
  }) async {
    _section('getContinuationTopics() START');

    _log('subjectCode=$subjectCode');
    _log('chapterCode=$chapterCode');

    final db = await _db.database;

    final cleanSubject = subjectCode.trim();
    final cleanChapter = chapterCode.trim();

    if (cleanSubject.isEmpty || cleanChapter.isEmpty) {
      _log('Invalid subject/chapter. Returning [].');
      return [];
    }

    final prefix = '$cleanSubject-$cleanChapter-';

    _log('Query prefix=$prefix');
    _log('Querying db_StatusTopics...');

    final rows = await db.query(
      'db_StatusTopics',
      where: '''
        TopicID LIKE ?
        AND TopicState IN (?, ?)
      ''',
      whereArgs: ['$prefix%', 'Pending', 'InProgress'],
      orderBy: 'TopicID ASC',
    );

    _log('db_StatusTopics returned ${rows.length} rows.');

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
  // NEW CHAPTER FLOW - UI READS
  // ============================================================

  Future<List<Map<String, Object?>>> getNewChapterChapters(
    String subjectCode,
  ) async {
    _section('getNewChapterChapters() START');

    _log('Reading chapters from db_SyllabusMaster...');

    final chapters = await _syllabusService.getChapters(subjectCode);

    _log('Syllabus returned ${chapters.length} chapters.');

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
    _section('getNewChapterTopics() START');

    _log('Reading topics from db_SyllabusMaster...');
    _log('subjectCode=$subjectCode');
    _log('chapterCode=$chapterCode');

    final topics = await _syllabusService.getTopics(subjectCode, chapterCode);

    _log('Syllabus returned ${topics.length} topics.');

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
  // IMPORTANT DATABASE DESIGN:
  //
  // We deliberately DO NOT keep one large transaction around
  // the complete operation.
  //
  // NEW CHAPTER:
  //
  //   Transaction #1
  //       Check chapter
  //       Create StatusChapter
  //       COMMIT
  //
  //   No transaction
  //       Read SyllabusMaster
  //
  //   Transaction #2
  //       Create StatusTopics
  //       Activate selected topic
  //       COMMIT
  //
  //   Transaction #3
  //       Insert LectureLog
  //       Complete chapter if required
  //       COMMIT
  //
  // CONTINUATION:
  //
  //   Transaction #1
  //       Update topic
  //       Insert LectureLog
  //       Complete chapter if required
  //       COMMIT
  //
  // This prevents SyllabusSvc from opening the main database
  // while another transaction is active.
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
    _section('saveLecture() START');

    _log('METHOD ENTERED');

    _log('Input arguments:');
    _log('  subjectCode=$subjectCode');
    _log('  chapterCode=$chapterCode');
    _log('  topicCode=$topicCode');
    _log('  chapterName=$chapterName');
    _log('  topicName=$topicName');
    _log('  topicId=$topicId');
    _log('  lectureDate=$lectureDate');
    _log('  shortNotesLength=${shortNotes?.length ?? 0}');
    _log('  lastLecture=$lastLecture');
    _log('  newChapter=$newChapter');

    // ----------------------------------------------------------
    // CLEAN INPUT
    // ----------------------------------------------------------

    final cleanSubject = subjectCode.trim();
    final cleanChapter = chapterCode.trim();
    final cleanTopic = topicCode.trim();
    final cleanTopicId = topicId.trim();
    final cleanChapterName = chapterName.trim();
    final cleanTopicName = topicName.trim();

    _log('Cleaned values:');
    _log('  cleanSubject=$cleanSubject');
    _log('  cleanChapter=$cleanChapter');
    _log('  cleanTopic=$cleanTopic');
    _log('  cleanTopicId=$cleanTopicId');
    _log('  cleanChapterName=$cleanChapterName');
    _log('  cleanTopicName=$cleanTopicName');

    final day = _dateOnly(lectureDate);

    _log('Normalized lecture date=$day');

    // ----------------------------------------------------------
    // VALIDATION
    // ----------------------------------------------------------

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

    _log('ALL SERVICE VALIDATION PASSED');

    // ==========================================================
    // TRANSACTION #1
    // CHECK / CREATE CHAPTER
    // ==========================================================

    _section('TRANSACTION #1 - CHAPTER');

    final db = await _db.database;

    _log('Database obtained.');

    bool chapterAlreadyExists = false;

    if (newChapter) {
      _log('Starting Transaction #1...');
      _log('Checking whether chapter already exists...');

      chapterAlreadyExists = await db.transaction((txn) async {
        _log('Transaction #1 STARTED.');

        final exists = await _chapterExistsTxn(
          txn,
          subjectCode: cleanSubject,
          chapterCode: cleanChapter,
        );

        _log('Transaction #1: chapterAlreadyExists=$exists');

        if (!exists) {
          _log('Transaction #1: NEW CHAPTER detected.');
          _log('Creating db_StatusChapters row...');

          final subjectChapterCode = _subjectChapterCode(
            cleanSubject,
            cleanChapter,
          );

          final insertedId = await txn.insert('db_StatusChapters', {
            'SubjectChapterCode': subjectChapterCode,
            'ChapterName': cleanChapterName,
            'ChapterState': 'InProgress',
            'LecturesStartDate': _yyyyMmDd(day),
            'LecturesEndDate': null,
            'AllTopicsCompleted': 'No',
            'PMTCompleted': 'No',
            'CMTCompleted': 'No',
            'WeakAreasCleared': 'No',
            'FinalExamReady': 'No',
          });

          _log(
            'Transaction #1: db_StatusChapters INSERT completed. '
            'rowId=$insertedId',
          );
        } else {
          _log(
            'Transaction #1: chapter already exists. '
            'No StatusChapter insert.',
          );
        }

        _log('Transaction #1 callback completed.');
        return exists;
      });

      _log('Transaction #1 COMMITTED and database released.');
      _log('chapterAlreadyExists=$chapterAlreadyExists');
    } else {
      _log(
        'newChapter=false. '
        'Skipping chapter creation transaction.',
      );
    }

    final useContinuation = !newChapter || chapterAlreadyExists;

    _log('Final flow decision:');
    _log('  newChapter=$newChapter');
    _log('  chapterAlreadyExists=$chapterAlreadyExists');
    _log('  useContinuation=$useContinuation');

    // ==========================================================
    // CONTINUATION FLOW
    // ==========================================================

    if (useContinuation) {
      _section('CONTINUATION FLOW');

      _log('Calling _saveContinuationLecture()...');
      _log(
        'This is the final lecture transaction. '
        'No SyllabusSvc call will occur inside it.',
      );

      final result = await _saveContinuationLecture(
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

      _log('Continuation lecture save completed.');
      _log('lectureId=${result.lectureId}');
      _log('closedTopic=${result.closedTopic}');
      _log('completedChapter=${result.completedChapter}');

      return result;
    }

    // ==========================================================
    // READ SYLLABUS
    // ==========================================================
    //
    // VERY IMPORTANT:
    //
    // There is NO ACTIVE TRANSACTION here.
    //
    // SyllabusSvc.getTopics() obtains the normal database
    // connection and reads db_SyllabusMaster.
    //
    // ==========================================================

    _section('SYLLABUS READ - NO TRANSACTION ACTIVE');

    _log(
      'About to call SyllabusSvc.getTopics(). '
      'There is NO active transaction now.',
    );

    final syllabusTopics = await _syllabusService.getTopics(
      cleanSubject,
      cleanChapter,
    );

    _log(
      'SyllabusSvc.getTopics() completed. '
      'Returned ${syllabusTopics.length} topics.',
    );

    if (syllabusTopics.isEmpty) {
      throw StateError(
        'No syllabus topics found for '
        '$cleanSubject-$cleanChapter.',
      );
    }

    // ==========================================================
    // TRANSACTION #2
    // CREATE STATUS TOPICS
    // ==========================================================

    _section('TRANSACTION #2 - STATUS TOPICS');

    _log('Starting Transaction #2...');

    await db.transaction((txn) async {
      _log('Transaction #2 STARTED.');

      // --------------------------------------------------------
      // Safety check
      // --------------------------------------------------------

      final existingChapter = await _chapterExistsTxn(
        txn,
        subjectCode: cleanSubject,
        chapterCode: cleanChapter,
      );

      _log(
        'Transaction #2 safety check: '
        'chapterExists=$existingChapter',
      );

      // --------------------------------------------------------
      // Create all StatusTopics
      // --------------------------------------------------------

      _log(
        'Creating ${syllabusTopics.length} rows in '
        'db_StatusTopics...',
      );

      int insertedTopics = 0;

      for (final topic in syllabusTopics) {
        final syllabusTopicId = topic.topicId.trim();

        if (syllabusTopicId.isEmpty) {
          _log(
            'Skipping syllabus topic with empty topicId. '
            'topicName=${topic.topicName}',
          );
          continue;
        }

        // Avoid duplicate insertion if a row somehow already exists.
        final existingRows = await txn.query(
          'db_StatusTopics',
          columns: ['TopicID'],
          where: 'TopicID = ?',
          whereArgs: [syllabusTopicId],
          limit: 1,
        );

        if (existingRows.isNotEmpty) {
          _log(
            'Topic already exists. Skipping insert: '
            '$syllabusTopicId',
          );
          continue;
        }

        await txn.insert('db_StatusTopics', {
          'TopicID': syllabusTopicId,
          'TopicLastLecNo': 0,
          'TopicStartDate': null,
          'TopicEndDate': null,
          'TopicState': 'Pending',
          'TopicChapterName': cleanChapterName,
          'TopicName': topic.topicName,
        });

        insertedTopics++;
      }

      _log(
        'Transaction #2: inserted $insertedTopics '
        'new StatusTopics.',
      );

      // --------------------------------------------------------
      // Verify selected topic
      // --------------------------------------------------------

      _log(
        'Transaction #2: checking selected topic '
        '$cleanTopicId...',
      );

      final selectedRows = await txn.query(
        'db_StatusTopics',
        where: 'TopicID = ?',
        whereArgs: [cleanTopicId],
        limit: 1,
      );

      if (selectedRows.isEmpty) {
        throw StateError(
          'Unable to initialise selected topic: '
          '$cleanTopicId',
        );
      }

      _log('Transaction #2: selected topic exists.');

      // --------------------------------------------------------
      // Activate selected topic
      // --------------------------------------------------------

      final selectedState = lastLecture ? 'Completed' : 'InProgress';

      _log('Transaction #2: activating selected topic.');

      _log('  TopicID=$cleanTopicId');
      _log('  TopicLastLecNo=1');
      _log('  TopicState=$selectedState');
      _log('  TopicStartDate=${_yyyyMmDd(day)}');

      final selectedUpdate = await txn.update(
        'db_StatusTopics',
        {
          'TopicLastLecNo': 1,
          'TopicStartDate': _yyyyMmDd(day),
          'TopicEndDate': lastLecture ? _yyyyMmDd(day) : null,
          'TopicState': selectedState,
        },
        where: 'TopicID = ?',
        whereArgs: [cleanTopicId],
      );

      _log('Transaction #2: selected topic updateCount=$selectedUpdate');

      if (selectedUpdate != 1) {
        throw StateError(
          'Unable to activate selected topic: '
          '$cleanTopicId',
        );
      }

      _log('Transaction #2 callback completed.');
    });

    _log('Transaction #2 COMMITTED and database released.');

    // ==========================================================
    // TRANSACTION #3
    // SAVE LECTURE
    // ==========================================================

    _section('TRANSACTION #3 - LECTURE');

    _log('Starting final lecture transaction...');

    final lectureResult = await db.transaction((txn) async {
      _log('Transaction #3 STARTED.');

      // --------------------------------------------------------
      // Build Lecture ID
      // --------------------------------------------------------

      final lectureId = _buildLectureId(
        subjectCode: cleanSubject,
        chapterCode: cleanChapter,
        topicCode: cleanTopic,
        lectureNumber: 1,
        lectureDate: day,
      );

      _log('Generated lectureId=$lectureId');

      // --------------------------------------------------------
      // Insert lecture log
      // --------------------------------------------------------

      _log('Inserting db_LectureLog...');

      await _insertLectureLog(
        txn,
        lectureId: lectureId,
        shortNotes: shortNotes,
      );

      _log('db_LectureLog INSERT completed.');

      // --------------------------------------------------------
      // Complete chapter if required
      // --------------------------------------------------------

      bool completedChapter = false;

      if (lastLecture) {
        _log(
          'lastLecture=true. '
          'Checking whether entire chapter is completed...',
        );

        completedChapter = await _completeChapterIfRequired(
          txn,
          subjectCode: cleanSubject,
          chapterCode: cleanChapter,
          lectureDate: day,
        );

        _log('Chapter completion result=$completedChapter');
      } else {
        _log(
          'lastLecture=false. '
          'Skipping chapter completion check.',
        );
      }

      _log('Transaction #3 callback completed.');

      return LectureSaveResult(
        lectureId: lectureId,
        closedTopic: lastLecture,
        completedChapter: completedChapter,
        usedContinuationFlow: false,
      );
    });

    _log('Transaction #3 COMMITTED and database released.');

    _section('saveLecture() COMPLETED SUCCESSFULLY');

    _log('lectureId=${lectureResult.lectureId}');
    _log('closedTopic=${lectureResult.closedTopic}');
    _log('completedChapter=${lectureResult.completedChapter}');
    _log('usedContinuationFlow=${lectureResult.usedContinuationFlow}');

    return lectureResult;
  }

  // ============================================================
  // CONTINUATION SAVE
  // ============================================================

  Future<LectureSaveResult> _saveContinuationLecture({
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
    _section('_saveContinuationLecture()');

    _log('Starting continuation transaction...');

    final db = await _db.database;

    final result = await db.transaction((txn) async {
      _log('Continuation transaction STARTED.');

      // --------------------------------------------------------
      // Load existing topic
      // --------------------------------------------------------

      _log('Querying db_StatusTopics for TopicID=$topicId...');

      final rows = await txn.query(
        'db_StatusTopics',
        where: 'TopicID = ?',
        whereArgs: [topicId],
        limit: 1,
      );

      _log('db_StatusTopics returned ${rows.length} rows.');

      if (rows.isEmpty) {
        throw StateError(
          'The selected topic does not exist in '
          'db_StatusTopics: $topicId',
        );
      }

      final existing = rows.first;

      final currentState = existing['TopicState']?.toString() ?? 'Pending';

      final currentLectureNo = _asInt(existing['TopicLastLecNo']) ?? 0;

      _log('Existing topic information:');
      _log('  TopicID=$topicId');
      _log('  TopicState=$currentState');
      _log('  TopicLastLecNo=$currentLectureNo');

      if (currentState == 'Completed') {
        throw StateError('The selected topic is already completed.');
      }

      if (currentState != 'Pending' && currentState != 'InProgress') {
        throw StateError('Invalid topic state: $currentState');
      }

      final nextLectureNo = currentLectureNo + 1;

      _log('nextLectureNo=$nextLectureNo');

      // --------------------------------------------------------
      // Dates
      // --------------------------------------------------------

      final oldStartDate = existing['TopicStartDate']?.toString();

      final startDate = oldStartDate == null || oldStartDate.trim().isEmpty
          ? _yyyyMmDd(lectureDate)
          : oldStartDate;

      final endDate = lastLecture ? _yyyyMmDd(lectureDate) : null;

      _log('startDate=$startDate');
      _log('endDate=$endDate');

      // --------------------------------------------------------
      // Lecture ID
      // --------------------------------------------------------

      final lectureId = _buildLectureId(
        subjectCode: subjectCode,
        chapterCode: chapterCode,
        topicCode: topicCode,
        lectureNumber: nextLectureNo,
        lectureDate: lectureDate,
      );

      _log('Generated lectureId=$lectureId');

      // --------------------------------------------------------
      // Update topic
      // --------------------------------------------------------

      final newState = lastLecture ? 'Completed' : 'InProgress';

      _log('Updating db_StatusTopics...');
      _log('  TopicLastLecNo=$nextLectureNo');
      _log('  TopicState=$newState');
      _log('  TopicStartDate=$startDate');
      _log('  TopicEndDate=$endDate');

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

      _log('db_StatusTopics updateCount=$updateCount');

      if (updateCount != 1) {
        throw StateError('Unable to update StatusTopic: $topicId');
      }

      // --------------------------------------------------------
      // Lecture log
      // --------------------------------------------------------

      _log('Inserting db_LectureLog...');

      await _insertLectureLog(
        txn,
        lectureId: lectureId,
        shortNotes: shortNotes,
      );

      _log('db_LectureLog INSERT completed.');

      // --------------------------------------------------------
      // Chapter completion
      // --------------------------------------------------------

      bool completedChapter = false;

      if (lastLecture) {
        _log(
          'lastLecture=true. '
          'Checking chapter completion...',
        );

        completedChapter = await _completeChapterIfRequired(
          txn,
          subjectCode: subjectCode,
          chapterCode: chapterCode,
          lectureDate: lectureDate,
        );

        _log('completedChapter=$completedChapter');
      }

      _log('Continuation transaction callback completed.');

      return LectureSaveResult(
        lectureId: lectureId,
        closedTopic: lastLecture,
        completedChapter: completedChapter,
        usedContinuationFlow: true,
      );
    });

    _log(
      'Continuation transaction COMMITTED '
      'and database released.',
    );

    return result;
  }

  // ============================================================
  // CHAPTER COMPLETION
  // ============================================================

  Future<bool> _completeChapterIfRequired(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
    required DateTime lectureDate,
  }) async {
    _section('_completeChapterIfRequired()');

    final prefix = '$subjectCode-$chapterCode-';

    _log('Checking topics using prefix=$prefix');

    final rows = await txn.query(
      'db_StatusTopics',
      columns: ['TopicID', 'TopicState'],
      where: 'TopicID LIKE ?',
      whereArgs: ['$prefix%'],
    );

    _log('Found ${rows.length} topics for chapter.');

    if (rows.isEmpty) {
      _log('No topics found. Chapter not completed.');
      return false;
    }

    final allCompleted = rows.every(
      (row) => row['TopicState']?.toString() == 'Completed',
    );

    _log('allCompleted=$allCompleted');

    if (!allCompleted) {
      _log(
        'Not all topics are completed. '
        'db_StatusChapters will NOT be modified.',
      );
      return false;
    }

    final subjectChapterCode = _subjectChapterCode(subjectCode, chapterCode);

    _log(
      'All topics completed. Updating '
      'db_StatusChapters.',
    );

    final updateCount = await txn.update(
      'db_StatusChapters',
      {'LecturesEndDate': _yyyyMmDd(lectureDate)},
      where: 'SubjectChapterCode = ?',
      whereArgs: [subjectChapterCode],
    );

    _log('db_StatusChapters updateCount=$updateCount');

    return updateCount == 1;
  }

  // ============================================================
  // CHAPTER EXISTS
  // ============================================================

  Future<bool> _chapterExistsTxn(
    Transaction txn, {
    required String subjectCode,
    required String chapterCode,
  }) async {
    _log(
      '_chapterExistsTxn(): START '
      'subjectCode=$subjectCode '
      'chapterCode=$chapterCode',
    );

    final prefix = '${subjectCode.trim()}-'
        '${chapterCode.trim()}-';

    _log('_chapterExistsTxn(): prefix=$prefix');

    final rows = await txn.query(
      'db_StatusTopics',
      columns: ['TopicID'],
      where: 'TopicID LIKE ?',
      whereArgs: ['$prefix%'],
      limit: 1,
    );

    _log('_chapterExistsTxn(): returned ${rows.length} rows.');

    final exists = rows.isNotEmpty;

    _log('_chapterExistsTxn(): exists=$exists');

    return exists;
  }

  // ============================================================
  // LECTURE LOG
  // ============================================================

  Future<void> _insertLectureLog(
    Transaction txn, {
    required String lectureId,
    String? shortNotes,
  }) async {
    _log(
      '_insertLectureLog(): START '
      'lectureId=$lectureId',
    );

    final cleanedNotes = _cleanNotes(shortNotes);

    _log(
      '_insertLectureLog(): '
      'shortNotesLength=${cleanedNotes?.length ?? 0}',
    );

    await txn.insert('db_LectureLog', {
      'lecture_id': lectureId,
      'lecture_type_code': _lectureTypeCode,
      'lecture_short_details': cleanedNotes,
      'lecture_class_notes_file_path': null,
      'lecture_class_notes_images': null,
      'lecture_task_created': 0,
      'created_at': DateTime.now().toIso8601String(),
    });

    _log('_insertLectureLog(): INSERT completed.');
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
    final id = '$subjectCode-'
        '$chapterCode-'
        '$topicCode-'
        'L${lectureNumber.toString().padLeft(2, '0')}-'
        '${_yyyymmdd(lectureDate)}';

    _log('_buildLectureId(): $id');

    return id;
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
