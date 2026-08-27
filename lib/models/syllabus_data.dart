enum SyllabusGroup { overall, mathematics, physics, chemistry }

class SyllabusChapter {
  final String name;
  final int completedTopics;
  final int totalTopics;

  const SyllabusChapter({
    required this.name,
    required this.completedTopics,
    required this.totalTopics,
  });

  double get progress => totalTopics == 0 ? 0 : completedTopics / totalTopics;
  bool get completed => totalTopics > 0 && completedTopics == totalTopics;
}

class SyllabusSubject {
  final String name;
  final List<SyllabusChapter> chapters;

  const SyllabusSubject({required this.name, required this.chapters});

  int get completedChapters => chapters.where((c) => c.completed).length;
  int get totalChapters => chapters.length;
  int get completedTopics =>
      chapters.fold(0, (sum, chapter) => sum + chapter.completedTopics);
  int get totalTopics =>
      chapters.fold(0, (sum, chapter) => sum + chapter.totalTopics);
}

class SyllabusDummyData {
  static const subjects = <SyllabusSubject>[
    SyllabusSubject(
      name: 'Mathematics',
      chapters: [
        SyllabusChapter(
          name: 'Chapter 1 — Algebra',
          completedTopics: 8,
          totalTopics: 8,
        ),
        SyllabusChapter(
          name: 'Chapter 2 — Functions',
          completedTopics: 7,
          totalTopics: 7,
        ),
        SyllabusChapter(
          name: 'Chapter 3 — Differentiation',
          completedTopics: 9,
          totalTopics: 9,
        ),
        SyllabusChapter(
          name: 'Chapter 4 — Integration',
          completedTopics: 6,
          totalTopics: 10,
        ),
        SyllabusChapter(
          name: 'Chapter 5 — Sequences',
          completedTopics: 0,
          totalTopics: 7,
        ),
        SyllabusChapter(
          name: 'Chapter 6 — Probability',
          completedTopics: 0,
          totalTopics: 8,
        ),
      ],
    ),
    SyllabusSubject(
      name: 'Physics',
      chapters: [
        SyllabusChapter(
          name: 'Chapter 1 — Mechanics',
          completedTopics: 8,
          totalTopics: 8,
        ),
        SyllabusChapter(
          name: 'Chapter 2 — Waves',
          completedTopics: 7,
          totalTopics: 7,
        ),
        SyllabusChapter(
          name: 'Chapter 3 — Electricity',
          completedTopics: 6,
          totalTopics: 6,
        ),
        SyllabusChapter(
          name: 'Chapter 4 — Magnetism',
          completedTopics: 4,
          totalTopics: 9,
        ),
        SyllabusChapter(
          name: 'Chapter 5 — Electromagnetism',
          completedTopics: 0,
          totalTopics: 8,
        ),
        SyllabusChapter(
          name: 'Chapter 6 — Electromagnetic Induction',
          completedTopics: 0,
          totalTopics: 9,
        ),
        SyllabusChapter(
          name: 'Chapter 7 — Modern Physics',
          completedTopics: 0,
          totalTopics: 7,
        ),
      ],
    ),
    SyllabusSubject(
      name: 'Chemistry',
      chapters: [
        SyllabusChapter(
          name: 'Chapter 1 — Atomic Structure',
          completedTopics: 7,
          totalTopics: 7,
        ),
        SyllabusChapter(
          name: 'Chapter 2 — Chemical Bonding',
          completedTopics: 8,
          totalTopics: 8,
        ),
        SyllabusChapter(
          name: 'Chapter 3 — Thermodynamics',
          completedTopics: 3,
          totalTopics: 8,
        ),
        SyllabusChapter(
          name: 'Chapter 4 — Equilibrium',
          completedTopics: 0,
          totalTopics: 8,
        ),
        SyllabusChapter(
          name: 'Chapter 5 — Organic Chemistry',
          completedTopics: 0,
          totalTopics: 10,
        ),
        SyllabusChapter(
          name: 'Chapter 6 — Inorganic Chemistry',
          completedTopics: 0,
          totalTopics: 9,
        ),
        SyllabusChapter(
          name: 'Chapter 7 — Electrochemistry',
          completedTopics: 0,
          totalTopics: 7,
        ),
        SyllabusChapter(
          name: 'Chapter 8 — Polymers',
          completedTopics: 0,
          totalTopics: 6,
        ),
      ],
    ),
  ];

  static int completedTopicsFor(SyllabusGroup group) {
    if (group == SyllabusGroup.overall) {
      return subjects.fold(0, (sum, subject) => sum + subject.completedTopics);
    }
    return subjectFor(group).completedTopics;
  }

  static int totalTopicsFor(SyllabusGroup group) {
    if (group == SyllabusGroup.overall) {
      return subjects.fold(0, (sum, subject) => sum + subject.totalTopics);
    }
    return subjectFor(group).totalTopics;
  }

  static int completedChaptersFor(SyllabusGroup group) {
    if (group == SyllabusGroup.overall) {
      return subjects.fold(
        0,
        (sum, subject) => sum + subject.completedChapters,
      );
    }
    return subjectFor(group).completedChapters;
  }

  static int totalChaptersFor(SyllabusGroup group) {
    if (group == SyllabusGroup.overall) {
      return subjects.fold(0, (sum, subject) => sum + subject.totalChapters);
    }
    return subjectFor(group).totalChapters;
  }

  static SyllabusSubject subjectFor(SyllabusGroup group) {
    switch (group) {
      case SyllabusGroup.mathematics:
        return subjects[0];
      case SyllabusGroup.physics:
        return subjects[1];
      case SyllabusGroup.chemistry:
        return subjects[2];
      case SyllabusGroup.overall:
        return subjects[0];
    }
  }
}
