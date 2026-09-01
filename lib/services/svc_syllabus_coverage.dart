import '../database/app_database.dart';

class SyllabusCoverageService {
  SyllabusCoverageService._();

  static final SyllabusCoverageService instance = SyllabusCoverageService._();

  final AppDatabase _db = AppDatabase.instance;

  // ============================================================
  // SUBJECT COVERAGE
  // ============================================================

  /// Returns complete syllabus coverage for one subject.
  ///
  /// Source:
  /// - db_SyllabusMaster     -> complete syllabus structure
  /// - db_StatusChapters     -> chapter status indicators
  /// - db_StatusTopics       -> topic completion/progress
  Future<Map<String, Object?>> getSubjectCoverage(String subjectCode) async {
    final db = await _db.database;

    final cleanSubject = subjectCode.trim();

    final syllabusRows = await db.query(
      'db_SyllabusMaster',
      columns: const [
        'subject_name',
        'subject_code',
        'chapter_code',
        'chapter_name',
        'topic_code',
        'topic_name',
        'topic_id',
        'display_order',
      ],
      where: 'subject_code = ?',
      whereArgs: [cleanSubject],
      orderBy: 'display_order ASC',
    );

    final chapterStatusRows = await db.query(
      'db_StatusChapters',
      where: 'SubjectChapterCode LIKE ?',
      whereArgs: ['$cleanSubject-%'],
    );

    final topicStatusRows = await db.query(
      'db_StatusTopics',
      where: 'TopicID LIKE ?',
      whereArgs: ['$cleanSubject-%'],
    );

    final chapterStatusMap = <String, Map<String, Object?>>{};

    for (final row in chapterStatusRows) {
      final key = row['SubjectChapterCode']?.toString().trim() ?? '';

      if (key.isNotEmpty) {
        chapterStatusMap[key] = row;
      }
    }

    final topicStatusMap = <String, Map<String, Object?>>{};

    for (final row in topicStatusRows) {
      final key = row['TopicID']?.toString().trim() ?? '';

      if (key.isNotEmpty) {
        topicStatusMap[key] = row;
      }
    }

    final chapters = <String, Map<String, Object?>>{};

    for (final row in syllabusRows) {
      final chapterCode = row['chapter_code']?.toString().trim() ?? '';

      final chapterName = row['chapter_name']?.toString().trim() ?? '';

      final topicCode = row['topic_code']?.toString().trim() ?? '';

      final topicName = row['topic_name']?.toString().trim() ?? '';

      final topicId = row['topic_id']?.toString().trim() ?? '';

      if (chapterCode.isEmpty) {
        continue;
      }

      final chapterKey = '$cleanSubject-$chapterCode';

      final chapter = chapters.putIfAbsent(
        chapterKey,
        () => <String, Object?>{
          'subjectCode': cleanSubject,
          'subjectName': row['subject_name']?.toString() ?? '',
          'chapterCode': chapterCode,
          'chapterName': chapterName,
          'topics': <Map<String, Object?>>[],
        },
      );

      final topics = chapter['topics'] as List<Map<String, Object?>>;

      if (topicId.isNotEmpty) {
        final status = topicStatusMap[topicId];

        final topicState = status?['TopicState']?.toString() ?? 'Pending';

        topics.add(<String, Object?>{
          'topicCode': topicCode,
          'topicName': topicName,
          'topicId': topicId,
          'topicState': topicState,
          'topicLastLecNo': status?['TopicLastLecNo'] ?? 0,
          'topicStartDate': status?['TopicStartDate'],
          'topicEndDate': status?['TopicEndDate'],
        });
      }
    }

    final chapterList = chapters.values.map((chapter) {
      final topics = chapter['topics'] as List<Map<String, Object?>>;

      final totalTopics = topics.length;

      final completedTopics =
          topics.where((topic) => topic['topicState'] == 'Completed').length;

      final progress = totalTopics == 0 ? 0.0 : completedTopics / totalTopics;

      final chapterCode = chapter['chapterCode']?.toString() ?? '';

      final chapterKey = '$cleanSubject-$chapterCode';

      final status = chapterStatusMap[chapterKey];

      return <String, Object?>{
        'subjectCode': chapter['subjectCode'],
        'subjectName': chapter['subjectName'],
        'chapterCode': chapterCode,
        'chapterName': chapter['chapterName'],
        'chapterState': status?['ChapterState']?.toString() ?? 'NotStarted',
        'lecturesStartDate': status?['LecturesStartDate'],
        'lecturesEndDate': status?['LecturesEndDate'],
        'allTopicsCompleted': _isYes(status?['AllTopicsCompleted']),
        'pmtCompleted': _isYes(status?['PMTCompleted']),
        'cmtCompleted': _isYes(status?['CMTCompleted']),
        'weakAreasCleared': _isYes(status?['WeakAreasCleared']),
        'finalExamReady': _isYes(status?['FinalExamReady']),
        'totalTopics': totalTopics,
        'completedTopics': completedTopics,
        'progress': progress,
        'topics': topics,
      };
    }).toList();

    final totalChapters = chapterList.length;

    final completedChapters = chapterList
        .where((chapter) => chapter['chapterState'] == 'ExamReady')
        .length;

    final totalTopics = chapterList.fold<int>(
      0,
      (sum, chapter) => sum + (chapter['totalTopics'] as int),
    );

    final completedTopics = chapterList.fold<int>(
      0,
      (sum, chapter) => sum + (chapter['completedTopics'] as int),
    );

    final progress = totalTopics == 0 ? 0.0 : completedTopics / totalTopics;

    final subjectName = syllabusRows.isNotEmpty
        ? syllabusRows.first['subject_name']?.toString() ?? cleanSubject
        : cleanSubject;

    return <String, Object?>{
      'subjectCode': cleanSubject,
      'subjectName': subjectName,
      'completedChapters': completedChapters,
      'totalChapters': totalChapters,
      'completedTopics': completedTopics,
      'totalTopics': totalTopics,
      'progress': progress,
      'chapters': chapterList,
    };
  }

  // ============================================================
  // ALL SUBJECTS
  // ============================================================

  /// Returns coverage for all subjects present in SyllabusMaster.
  Future<List<Map<String, Object?>>> getAllSubjectCoverage() async {
    final db = await _db.database;

    final rows = await db.rawQuery('''
      SELECT  subject_code, subject_name
        FROM db_SyllabusMaster
        GROUP BY subject_code, subject_name
        ORDER BY MIN(display_order) ASC
      ''');

    final result = <Map<String, Object?>>[];

    for (final row in rows) {
      final subjectCode = row['subject_code']?.toString().trim() ?? '';

      if (subjectCode.isEmpty) {
        continue;
      }

      result.add(await getSubjectCoverage(subjectCode));
    }

    return result;
  }

  // ============================================================
  // OVERALL COVERAGE
  // ============================================================

  /// Returns combined syllabus coverage across all subjects.
  Future<Map<String, Object?>> getOverallCoverage() async {
    final subjects = await getAllSubjectCoverage();

    var totalChapters = 0;
    var completedChapters = 0;
    var totalTopics = 0;
    var completedTopics = 0;

    for (final subject in subjects) {
      totalChapters += subject['totalChapters'] as int;

      completedChapters += subject['completedChapters'] as int;

      totalTopics += subject['totalTopics'] as int;

      completedTopics += subject['completedTopics'] as int;
    }

    final progress = totalTopics == 0 ? 0.0 : completedTopics / totalTopics;

    return <String, Object?>{
      'completedChapters': completedChapters,
      'totalChapters': totalChapters,
      'completedTopics': completedTopics,
      'totalTopics': totalTopics,
      'progress': progress,
      'subjects': subjects,
    };
  }

  // ============================================================
  // HELPERS
  // ============================================================

  bool _isYes(Object? value) {
    return value?.toString() == 'Yes';
  }
}
