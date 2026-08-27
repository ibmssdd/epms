import 'package:sqflite/sqflite.dart';

/// Data-access service for the db_Milestones table.
///
/// Current database schema (as created in EPMS):
///   milestone_type  TEXT NOT NULL
///   milestone_date  TEXT NOT NULL   (YYYY-MM-DD)
///   milestone_phy_chapters  TEXT NOT NULL
///   milestone_chem_chapters TEXT NOT NULL
///   milestone_bio_chapters  TEXT NOT NULL
///   milestone_timestamp     TEXT NOT NULL
///
/// Primary key: (milestone_date, milestone_type).
/// The service deliberately uses the actual live table/column names above.
/// No model class is required; screens consume Map<String, Object?> rows.
class MilestoneCalendarSvc {
  MilestoneCalendarSvc(this._db);

  final Database _db;

  static const String table = 'db_Milestones';

  static const String colType = 'milestone_type';
  static const String colDate = 'milestone_date';
  static const String colPhy = 'milestone_phy_chapters';
  static const String colChem = 'milestone_chem_chapters';
  static const String colBio = 'milestone_bio_chapters';

  Future<Map<String, Object?>?> getMilestone({
    required String milestoneType,
    required DateTime date,
  }) async {
    final rows = await _db.query(
      table,
      where: '$colType = ? AND $colDate = ?',
      whereArgs: [milestoneType.trim(), formatDate(date)],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> getMilestonesForDate(DateTime date) {
    return _db.query(
      table,
      where: '$colDate = ?',
      whereArgs: [formatDate(date)],
      orderBy: '$colType ASC',
    );
  }

  Future<List<Map<String, Object?>>> getUpcomingMilestones({
    DateTime? from,
    int? limit,
  }) {
    final start = formatDate(from ?? DateTime.now());
    return _db.query(
      table,
      where: '$colDate >= ?',
      whereArgs: [start],
      orderBy: '$colDate ASC, $colType ASC',
      limit: limit,
    );
  }

  Future<List<Map<String, Object?>>> getMilestonesInRange({
    required DateTime from,
    required DateTime to,
  }) {
    return _db.query(
      table,
      where: '$colDate >= ? AND $colDate <= ?',
      whereArgs: [formatDate(from), formatDate(to)],
      orderBy: '$colDate ASC, $colType ASC',
    );
  }

  Future<List<Map<String, Object?>>> getNextSundayMilestones() {
    return getMilestonesForDate(nextSunday(DateTime.now()));
  }

  /// Returns upcoming milestone rows enriched with chapter names from
  /// db_SyllabusMaster. The original database columns remain unchanged.
  Future<List<Map<String, Object?>>> getUpcomingMilestonesWithNames({
    DateTime? from,
    int? limit,
  }) async {
    final rows = await getUpcomingMilestones(from: from, limit: limit);
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final copy = <String, Object?>{...row};
      copy['scope'] = await resolveScope(row);
      result.add(copy);
    }
    return result;
  }

  Future<List<Map<String, Object?>>> getNextSundayMilestonesWithNames() async {
    final rows = await getMilestonesForDate(nextSunday(DateTime.now()));
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final copy = <String, Object?>{...row};
      copy['scope'] = await resolveScope(row);
      result.add(copy);
    }
    return result;
  }

  /// Inserts a new milestone or updates the scope for the same
  /// (milestone_type, milestone_date) key.
  Future<void> saveMilestone({
    required String milestoneType,
    required DateTime date,
    required String phyChapters,
    required String chemChapters,
    required String bioChapters,
  }) async {
    final type = milestoneType.trim();
    if (type.isEmpty) {
      throw ArgumentError('Milestone type is required.');
    }
    if (!isMilestoneSunday(date)) {
      throw ArgumentError('Milestone date must be a Sunday.');
    }

    await _db.insert(table, {
      colType: type,
      colDate: formatDate(date),
      colPhy: normalizeCodes(phyChapters),
      colChem: normalizeCodes(chemChapters),
      colBio: normalizeCodes(bioChapters),
      'milestone_timestamp': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateMilestoneScope({
    required String milestoneType,
    required DateTime date,
    required String phyChapters,
    required String chemChapters,
    required String bioChapters,
  }) {
    return saveMilestone(
      milestoneType: milestoneType,
      date: date,
      phyChapters: phyChapters,
      chemChapters: chemChapters,
      bioChapters: bioChapters,
    );
  }

  Future<void> deleteMilestone({
    required String milestoneType,
    required DateTime date,
  }) async {
    await _db.delete(
      table,
      where: '$colType = ? AND $colDate = ?',
      whereArgs: [milestoneType.trim(), formatDate(date)],
    );
  }

  /// Resolves the comma-separated chapter codes in one milestone row into
  /// display-friendly subject/chapter information from db_SyllabusMaster.
  Future<Map<String, List<Map<String, Object?>>>> resolveScope(
    Map<String, Object?> milestone,
  ) async {
    final result = <String, List<Map<String, Object?>>>{
      'Phy': [],
      'Chem': [],
      'Bio': [],
    };

    await _resolveSubjectScope(
      result,
      subjectKey: 'Phy',
      subjectCodes: const ['PHY', 'PHYSICS', 'PHY'],
      rawCodes: milestone[colPhy]?.toString(),
    );
    await _resolveSubjectScope(
      result,
      subjectKey: 'Chem',
      subjectCodes: const ['CHEM', 'CHEMISTRY', 'CHEM'],
      rawCodes: milestone[colChem]?.toString(),
    );
    await _resolveSubjectScope(
      result,
      subjectKey: 'Bio',
      subjectCodes: const ['BIO', 'BIOLOGY'],
      rawCodes: milestone[colBio]?.toString(),
    );

    return result;
  }

  Future<void> _resolveSubjectScope(
    Map<String, List<Map<String, Object?>>> result, {
    required String subjectKey,
    required List<String> subjectCodes,
    required String? rawCodes,
  }) async {
    final codes = splitCodes(rawCodes);
    if (codes.isEmpty) return;

    final rows = <Map<String, Object?>>[];
    for (final chapterCode in codes) {
      Map<String, Object?>? found;
      for (final subjectCode in subjectCodes) {
        final matches = await _db.query(
          'db_SyllabusMaster',
          where: 'UPPER(subject_code) = ? AND UPPER(chapter_code) = ?',
          whereArgs: [subjectCode.toUpperCase(), chapterCode.toUpperCase()],
          limit: 1,
        );
        if (matches.isNotEmpty) {
          found = matches.first;
          break;
        }
      }

      found ??= {'chapter_code': chapterCode, 'chapter_name': chapterCode};
      rows.add(found);
    }

    result[subjectKey] = rows;
  }

  static List<String> splitCodes(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String normalizeCodes(String value) {
    return splitCodes(value).join(',');
  }

  static String formatDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  /// UI display format for every milestone date.
  ///
  /// Database storage remains YYYY-MM-DD. Milestone dates are Sunday-only,
  /// so the displayed value is always: Sunday, DD-MMM-YYYY.
  static String formatDisplayDate(DateTime date) {
    if (date.weekday != DateTime.sunday) {
      return 'Invalid milestone date';
    }

    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return 'Sunday, ${date.day.toString().padLeft(2, '0')}-'
        '${months[date.month - 1]}-${date.year}';
  }

  static bool isMilestoneSunday(DateTime date) =>
      date.weekday == DateTime.sunday;

  static DateTime parseDate(String value) {
    return DateTime.parse(value);
  }

  static DateTime nextSunday(DateTime from) {
    final day = DateTime(from.year, from.month, from.day);
    final delta = DateTime.sunday - day.weekday;
    return day.add(Duration(days: delta == 0 ? 7 : delta));
  }
}
