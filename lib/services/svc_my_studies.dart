import '../database/app_database.dart';
import 'svc_status_chapters.dart';

/// ---------------------------------------------------------------------------
/// Study Workspace Service
/// ---------------------------------------------------------------------------
///
/// This service is intentionally an ORCHESTRATOR.
///
/// It does NOT preload the study workspace.
///
/// Loading is performed only when the UI explicitly asks for it:
///
///   loadSubjects()
///   loadCurrentlyAttendingChapters()
///   loadTopics()
///   loadRecordedLectures()
///   loadRelatedTasks()
///   loadStudyNotes()
///   loadStudyBooks()
///   loadVoiceNotes()
///
/// Existing EPMS services remain the source of truth.
/// ---------------------------------------------------------------------------

class StudyWorkspaceSvc {
  StudyWorkspaceSvc._();

  static final StudyWorkspaceSvc instance = StudyWorkspaceSvc._();

  Future<List<Map<String, Object?>>> loadSubjects() async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery('''
            SELECT subject_code, subject_name, COUNT(*) AS topic_count
            FROM db_SyllabusMaster 
            GROUP BY subject_code, subject_name
            ORDER BY subject_name
                      ''');
  }

  Future<List<Map<String, Object?>>> loadInProgressChapters(
    String subjectCode,
  ) async {
    // Future<List<Map<String, Object?>>> loadCurrentlyAttendingChapters(String subjectCode,  ) async {
    return StatusChapterService.instance
        .getInProgressChaptersBySubject(subjectCode);
  }

  Future<List<Map<String, Object?>>> loadTopics({
    required String subjectCode,
    required String chapterCode,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery(
      '''
              SELECT *  FROM db_SyllabusMaster  
              WHERE subject_code = ? AND chapter_code = ?
              ORDER BY display_order, topic_code
                      ''',
      [
        subjectCode,
        chapterCode,
      ],
    );
  }

  /// Loads recorded lectures ONLY after the user taps
  /// "Recorded Lecture".
  ///
  /// Connect this adapter to the existing EPMS lecture service.

  Future<List<Map<String, Object?>>> loadRecordedLectures({
    required String subjectCode,
    required String chapterCode,
    required String topicCode,
  }) async {
// TODO:
// Connect to the existing LectureService retrieval method.
    return <Map<String, Object?>>[];
  }

  /// Loads existing EPMS tasks ONLY after the user taps
  /// "Related Tasks" or "Revise".
  ///
  /// This must reference existing tasks rather than creating duplicates.

  Future<List<Map<String, Object?>>> loadRelatedTasks({
    required String subjectCode,
    required String chapterCode,
    required String topicCode,
  }) async {
// TODO:
// Connect to the existing EPMS task retrieval service.
    return <Map<String, Object?>>[];
  }

  /// Loads notes only after "Revise Notes" is tapped.
  Future<List<Map<String, Object?>>> loadStudyNotes({
    required String subjectCode,
    required String chapterCode,
    required String topicCode,
  }) async {
// TODO:
// Connect to the existing Study Notes service/database.
    return <Map<String, Object?>>[];
  }

  /// Loads study-book/PDF resources only after "Study Book" is tapped.
  Future<List<Map<String, Object?>>> loadStudyBooks({
    required String subjectCode,
    required String chapterCode,
    required String topicCode,
  }) async {
// TODO:
// Connect to the existing study-resource/PDF service.
    return <Map<String, Object?>>[];
  }

  /// Loads voice notes only after "Voice Notes" is tapped.
  Future<List<Map<String, Object?>>> loadVoiceNotes({
    required String subjectCode,
    required String chapterCode,
    required String topicCode,
  }) async {
// TODO:
// Connect to the existing voice-note/resource service.
    return <Map<String, Object?>>[];
  }
}
