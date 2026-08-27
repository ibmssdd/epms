import '../database/app_database.dart';

class SyllabusChapter {
  final String chapterCode;
  final String chapterName;

  const SyllabusChapter({required this.chapterCode, required this.chapterName});

  String get displayName => '$chapterCode - $chapterName';
}

class SyllabusTopic {
  final String topicCode;
  final String topicName;
  final String topicId;

  const SyllabusTopic({
    required this.topicCode,
    required this.topicName,
    required this.topicId,
  });

  String get displayName => '$topicCode - $topicName';
}

class SyllabusSvc {
  final AppDatabase _dbConnection = AppDatabase.instance;

  Future<List<SyllabusChapter>> getChapters(String subjectCode) async {
    final db = await _dbConnection.database;

    final result = await db.rawQuery(
      '''
      SELECT
          chapter_code,
          chapter_name
      FROM db_SyllabusMaster
      WHERE subject_code = ?
      GROUP BY chapter_code, chapter_name
      ORDER BY MIN(display_order) ASC
      ''',
      [subjectCode],
    );

    return result.map((row) {
      return SyllabusChapter(
        chapterCode: row['chapter_code']?.toString() ?? '',
        chapterName: row['chapter_name']?.toString() ?? '',
      );
    }).toList();
  }

  Future<List<SyllabusTopic>> getTopics(
    String subjectCode,
    String chapterCode,
  ) async {
    final db = await _dbConnection.database;

    final result = await db.query(
      'db_SyllabusMaster',
      columns: const ['topic_code', 'topic_name', 'topic_id'],
      where: 'subject_code = ? AND chapter_code = ?',
      whereArgs: [subjectCode, chapterCode],
      orderBy: 'display_order ASC',
    );

    return result.map((row) {
      return SyllabusTopic(
        topicCode: row['topic_code']?.toString() ?? '',
        topicName: row['topic_name']?.toString() ?? '',
        topicId: row['topic_id']?.toString() ?? '',
      );
    }).toList();
  }
}
