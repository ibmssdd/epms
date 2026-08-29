import 'package:sqflite/sqflite.dart';

import '../../database/app_database.dart';

/// Read-only enquiry service for the Lecture Log.
///
/// Lecture ID format:
///   Phy-Ch01-T01-L03-20260818
///
/// Meaning:
///   Phy       = Subject Code
///   Ch01      = Chapter Code
///   T01       = Topic Code
///   L03       = Lecture Sequence
///   20260818  = Lecture Date
///
/// This service does not modify:
///   - db_StatusTopics
///   - db_StatusChapters
///   - db_LectureLog
class LectureEnquiryService {
  LectureEnquiryService._privateConstructor();

  static final LectureEnquiryService instance =
      LectureEnquiryService._privateConstructor();

  final AppDatabase _db = AppDatabase.instance;

  // ---------------------------------------------------------------------------
  // DATE-WISE ENQUIRY
  // ---------------------------------------------------------------------------

  /// Returns lectures for the current week.
  ///
  /// Latest lecture date first for date-wise enquiry.
  Future<List<Map<String, Object?>>> getThisWeekLectures() async {
    final db = await _db.database;

    final today = DateTime.now();

    final startOfWeek = _startOfWeek(today);

    final startDate = _dateToLectureIdDate(startOfWeek);

    final endDate = _dateToLectureIdDate(today);

    return _getLecturesBetweenDates(db, startDate, endDate);
  }

  /// Returns lectures for the last two weeks.
  ///
  /// Latest lecture date first for date-wise enquiry.
  Future<List<Map<String, Object?>>> getLastTwoWeeksLectures() async {
    final db = await _db.database;

    final today = DateTime.now();

    final startDateTime = today.subtract(const Duration(days: 13));

    final startDate = _dateToLectureIdDate(startDateTime);

    final endDate = _dateToLectureIdDate(today);

    return _getLecturesBetweenDates(db, startDate, endDate);
  }

  /// Returns lectures for the current month.
  ///
  /// Latest lecture date first for date-wise enquiry.
  Future<List<Map<String, Object?>>> getThisMonthLectures() async {
    final db = await _db.database;

    final today = DateTime.now();

    final firstDayOfMonth = DateTime(today.year, today.month, 1);

    final startDate = _dateToLectureIdDate(firstDayOfMonth);

    final endDate = _dateToLectureIdDate(today);

    return _getLecturesBetweenDates(db, startDate, endDate);
  }

  // ---------------------------------------------------------------------------
  // SUBJECT-WISE ENQUIRY
  // ---------------------------------------------------------------------------

  /// Returns all Physics lectures.
  Future<List<Map<String, Object?>>> getPhysicsLectures() {
    return getSubjectLectures('Phy');
  }

  /// Returns all Chemistry lectures.
  Future<List<Map<String, Object?>>> getChemistryLectures() {
    return getSubjectLectures('Chem');
  }

  /// Returns all Biology lectures.
  Future<List<Map<String, Object?>>> getBiologyLectures() {
    return getSubjectLectures('Bio');
  }

  /// Returns all lectures belonging to [subjectCode].
  ///
  /// The returned records are sorted for lecture-view display:
  ///
  ///   Chapter Code
  ///   Topic Code
  ///   Lecture Sequence
  ///
  /// Lecture date is NOT used for sorting.
  Future<List<Map<String, Object?>>> getSubjectLectures(
    String subjectCode,
  ) async {
    final db = await _db.database;

    final rows = await db.query(
      'db_LectureLog',
      where: 'lecture_id LIKE ?',
      whereArgs: ['${subjectCode.trim()}-%'],
    );

    final lectures = _convertRows(rows);

    return sortLecturesForView(lectures);
  }

  // ---------------------------------------------------------------------------
  // GENERIC ENQUIRY
  // ---------------------------------------------------------------------------

  /// Returns all lecture records.
  ///
  /// Sorted for lecture-view display:
  ///
  ///   Chapter Code
  ///   Topic Code
  ///   Lecture Sequence
  ///
  /// Lecture date is displayed but does not determine the order.
  Future<List<Map<String, Object?>>> getAllLectures() async {
    final db = await _db.database;

    final rows = await db.query('db_LectureLog');

    final lectures = _convertRows(rows);

    return sortLecturesForView(lectures);
  }

  /// Returns one lecture using its complete lecture ID.
  Future<Map<String, Object?>?> getLectureById(String lectureId) async {
    final db = await _db.database;

    final rows = await db.query(
      'db_LectureLog',
      where: 'lecture_id = ?',
      whereArgs: [lectureId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final converted = _convertRows(rows);

    return converted.first;
  }

  // ---------------------------------------------------------------------------
  // LECTURE VIEW SORTING
  // ---------------------------------------------------------------------------

  /// Sorts lectures specifically for the Lecture View panel.
  ///
  /// Required order:
  ///
  ///   1. Chapter Code
  ///   2. Topic Code
  ///   3. Lecture Sequence
  ///
  /// Lecture date is intentionally NOT used as a sort key.
  ///
  /// Example:
  ///
  ///   Phy-Ch01-T01-L01
  ///   Phy-Ch01-T01-L02
  ///   Phy-Ch01-T01-L03
  ///   Phy-Ch01-T02-L01
  ///   Phy-Ch01-T02-L02
  ///   Phy-Ch02-T01-L01
  ///
  /// The lecture date remains available in each record for display.
  List<Map<String, Object?>> sortLecturesForView(
    List<Map<String, Object?>> lectures,
  ) {
    final sorted = List<Map<String, Object?>>.from(lectures);

    sorted.sort((a, b) {
      // ---------------------------------------------------------------
      // 1. CHAPTER CODE
      // ---------------------------------------------------------------

      final chapterCompare = _compareCode(a['chapterCode'], b['chapterCode']);

      if (chapterCompare != 0) {
        return chapterCompare;
      }

      // ---------------------------------------------------------------
      // 2. TOPIC CODE
      // ---------------------------------------------------------------

      final topicCompare = _compareCode(a['topicCode'], b['topicCode']);

      if (topicCompare != 0) {
        return topicCompare;
      }

      // ---------------------------------------------------------------
      // 3. LECTURE SEQUENCE
      // ---------------------------------------------------------------

      final aLectureSequence = _lectureSequenceNumber(a['lectureSequence']);

      final bLectureSequence = _lectureSequenceNumber(b['lectureSequence']);

      return aLectureSequence.compareTo(bLectureSequence);
    });

    return sorted;
  }

  /// Compares codes such as:
  ///
  ///   Ch01 < Ch02 < Ch10
  ///   T01 < T02 < T10
  ///
  /// Numeric portions are compared numerically when possible.
  int _compareCode(Object? first, Object? second) {
    final firstValue = first?.toString().trim() ?? '';

    final secondValue = second?.toString().trim() ?? '';

    final firstNumber = _extractTrailingNumber(firstValue);

    final secondNumber = _extractTrailingNumber(secondValue);

    if (firstNumber != null && secondNumber != null) {
      final numberCompare = firstNumber.compareTo(secondNumber);

      if (numberCompare != 0) {
        return numberCompare;
      }
    }

    return firstValue.compareTo(secondValue);
  }

  /// Extracts the numeric part from codes such as:
  ///
  ///   Ch01 -> 1
  ///   Ch10 -> 10
  ///   T02  -> 2
  ///   T11  -> 11
  int? _extractTrailingNumber(String value) {
    final match = RegExp(r'(\d+)$').firstMatch(value);

    if (match == null) {
      return null;
    }

    return int.tryParse(match.group(1)!);
  }

  /// Converts:
  ///
  ///   L01 -> 1
  ///   L02 -> 2
  ///   L10 -> 10
  ///
  /// Also accepts an already numeric value.
  int _lectureSequenceNumber(Object? value) {
    if (value is int) {
      return value;
    }

    final text = value?.toString().trim() ?? '';

    if (text.isEmpty) {
      return 0;
    }

    final cleaned = text.toUpperCase().startsWith('L')
        ? text.substring(1)
        : text;

    return int.tryParse(cleaned) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // PRIVATE DATABASE QUERIES
  // ---------------------------------------------------------------------------

  Future<List<Map<String, Object?>>> _getLecturesBetweenDates(
    Database db,
    String startDate,
    String endDate,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM db_LectureLog
      WHERE substr(lecture_id, -8) >= ?
        AND substr(lecture_id, -8) <= ?
      ORDER BY substr(lecture_id, -8) DESC,
               created_at DESC
      ''',
      [startDate, endDate],
    );

    return _convertRows(rows);
  }

  // ---------------------------------------------------------------------------
  // ROW CONVERSION
  // ---------------------------------------------------------------------------

  List<Map<String, Object?>> _convertRows(List<Map<String, Object?>> rows) {
    return rows.map((row) {
      final lectureId = row['lecture_id']?.toString() ?? '';

      final parsed = _parseLectureId(lectureId);

      return <String, Object?>{
        'lectureId': lectureId,

        'lectureTypeCode': row['lecture_type_code'],

        'shortDetails': row['lecture_short_details'],

        'notesFilePath': row['lecture_class_notes_file_path'],

        'notesImages': row['lecture_class_notes_images'],

        'createdAt': row['created_at'],

        'subjectCode': parsed['subjectCode'],

        'chapterCode': parsed['chapterCode'],

        'topicCode': parsed['topicCode'],

        'lectureSequence': parsed['lectureSequence'],

        'lectureDate': parsed['lectureDate'],

        'lectureDateDisplay': _formatLectureDate(
          parsed['lectureDate']?.toString() ?? '',
        ),

        'chapterGroupKey':
            '${parsed['subjectCode'] ?? ''}-'
            '${parsed['chapterCode'] ?? ''}',

        'subjectName': _subjectName(parsed['subjectCode']?.toString() ?? ''),

        // Temporary value.
        //
        // db_LectureLog does not contain topicName.
        // The enquiry UI can currently use topicCode.
        // Later this can be populated by looking up
        // StatusTopics using the reconstructed key.
        'topicName': null,
      };
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // LECTURE ID PARSER
  // ---------------------------------------------------------------------------

  Map<String, Object?> _parseLectureId(String lectureId) {
    final parts = lectureId.split('-');

    if (parts.length < 5) {
      return <String, Object?>{
        'subjectCode': null,
        'chapterCode': null,
        'topicCode': null,
        'lectureSequence': null,
        'lectureDate': null,
      };
    }

    final subjectCode = parts[0];

    final chapterCode = parts[1];

    final topicCode = parts[2];

    final lectureSequence = parts[3];

    final lectureDate = parts[4];

    return <String, Object?>{
      'subjectCode': subjectCode,
      'chapterCode': chapterCode,
      'topicCode': topicCode,
      'lectureSequence': lectureSequence,
      'lectureDate': lectureDate,
    };
  }

  // ---------------------------------------------------------------------------
  // DATE HELPERS
  // ---------------------------------------------------------------------------

  DateTime _startOfWeek(DateTime date) {
    final difference = date.weekday - DateTime.monday;

    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: difference));
  }

  String _dateToLectureIdDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _formatLectureDate(String value) {
    if (value.length != 8) {
      return value;
    }

    return '${value.substring(6, 8)}/'
        '${value.substring(4, 6)}/'
        '${value.substring(0, 4)}';
  }

  // ---------------------------------------------------------------------------
  // DISPLAY HELPERS
  // ---------------------------------------------------------------------------

  String _subjectName(String subjectCode) {
    switch (subjectCode) {
      case 'Phy':
        return 'Physics';

      case 'Chem':
        return 'Chemistry';

      case 'Bio':
        return 'Biology';

      default:
        return subjectCode;
    }
  }

  /// Displays:
  ///
  /// Lecture ID - Topic Code
  ///
  /// Example:
  /// Phy-Ch01-T01-L02-20260819 - T01
  ///
  /// Topic name can later replace the topic code
  /// once StatusTopics lookup is added.
  String lectureSummary(Map<String, Object?> lecture) {
    final lectureId = lecture['lectureId']?.toString() ?? '';

    final topicName = lecture['topicName']?.toString().trim() ?? '';

    final topicCode = lecture['topicCode']?.toString() ?? '';

    final topicDisplay = topicName.isNotEmpty ? topicName : topicCode;

    return '$lectureId - $topicDisplay';
  }

  String subjectChapterLabel(Map<String, Object?> lecture) {
    final subject =
        lecture['subjectName']?.toString() ??
        lecture['subjectCode']?.toString() ??
        '';

    final chapter = lecture['chapterCode']?.toString() ?? '';

    return '$subject - $chapter';
  }

  bool hasNotesFile(Map<String, Object?> lecture) {
    final value = lecture['notesFilePath']?.toString().trim() ?? '';

    return value.isNotEmpty;
  }

  bool hasNotesImages(Map<String, Object?> lecture) {
    final value = lecture['notesImages']?.toString().trim() ?? '';

    return value.isNotEmpty;
  }

  bool hasAnyNotes(Map<String, Object?> lecture) {
    return hasNotesFile(lecture) || hasNotesImages(lecture);
  }

  // ---------------------------------------------------------------------------
  // GROUPING HELPERS
  // ---------------------------------------------------------------------------

  /// Groups lectures by lecture date.
  ///
  /// Dates are returned latest first.
  Map<String, List<Map<String, Object?>>> groupByDate(
    List<Map<String, Object?>> lectures,
  ) {
    final grouped = <String, List<Map<String, Object?>>>{};

    for (final lecture in lectures) {
      final date = lecture['lectureDate']?.toString() ?? '';

      if (date.isEmpty) {
        continue;
      }

      grouped.putIfAbsent(date, () => <Map<String, Object?>>[]);

      grouped[date]!.add(lecture);
    }

    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return <String, List<Map<String, Object?>>>{
      for (final key in sortedKeys) key: grouped[key]!,
    };
  }

  /// Groups lectures by SubjectChapterCode.
  ///
  /// Example:
  ///
  ///   Phy-Ch01
  ///   Chem-Ch03
  ///   Bio-Ch02
  ///
  /// Groups are sorted by their latest lecture date,
  /// latest group first.
  Map<String, List<Map<String, Object?>>> groupBySubjectChapter(
    List<Map<String, Object?>> lectures,
  ) {
    final grouped = <String, List<Map<String, Object?>>>{};

    for (final lecture in lectures) {
      final subject = lecture['subjectCode']?.toString() ?? '';

      final chapter = lecture['chapterCode']?.toString() ?? '';

      if (subject.isEmpty || chapter.isEmpty) {
        continue;
      }

      final key = '$subject-$chapter';

      grouped.putIfAbsent(key, () => <Map<String, Object?>>[]);

      grouped[key]!.add(lecture);
    }

    final entries = grouped.entries.toList();

    entries.sort((a, b) {
      final aDate = _latestLectureDate(a.value);

      final bDate = _latestLectureDate(b.value);

      return bDate.compareTo(aDate);
    });

    return <String, List<Map<String, Object?>>>{
      for (final entry in entries) entry.key: entry.value,
    };
  }

  String _latestLectureDate(List<Map<String, Object?>> lectures) {
    var latest = '';

    for (final lecture in lectures) {
      final date = lecture['lectureDate']?.toString() ?? '';

      if (date.compareTo(latest) > 0) {
        latest = date;
      }
    }

    return latest;
  }
}
