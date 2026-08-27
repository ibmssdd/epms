class ChapterProgress {
  final String subjectId;
  final String chapterName;
  final int completedTopics;
  final int totalTopics;

  const ChapterProgress({
    required this.subjectId,
    required this.chapterName,
    required this.completedTopics,
    required this.totalTopics,
  });

  double get percentage {
    if (totalTopics == 0) {
      return 0;
    }

    return completedTopics / totalTopics;
  }
}
