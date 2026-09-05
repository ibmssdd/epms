import 'package:flutter/material.dart';

import '../services/svc_my_studies.dart';

/// ===========================================================================
/// STUDY WORKSPACE
/// ===========================================================================
///
/// Loading rules:
///
/// 1. Nothing loads in initState().
/// 2. Opening the workspace shows only "Start Studying Today".
/// 3. Subjects load after Start Studying Today is tapped.
/// 4. Chapters load after a subject is tapped.
/// 5. Topics load after a chapter is tapped.
/// 6. Lectures/tasks/notes/books/voice notes load only after their
///    corresponding option is tapped.
/// 7. The left navigator can be hidden for maximum study space.
/// ===========================================================================

class MyStudyScreen extends StatefulWidget {
  const MyStudyScreen({
    super.key,
  });

  @override
  State<MyStudyScreen> createState() => _MyStudyScreenState();
}

enum _StudyWorkspaceStage {
  start,
  subjects,
  chapters,
  topics,
  topicWorkspace,
}

enum _StudyContentType {
  notes,
  studyBook,
  recordedLecture,
  voiceNotes,
  revise,
  relatedTasks,
}

class _MyStudyScreenState extends State<MyStudyScreen> {
  final StudyWorkspaceSvc _service = StudyWorkspaceSvc.instance;

  _StudyWorkspaceStage _stage = _StudyWorkspaceStage.start;

  bool _leftPanelVisible = true;
  bool _loading = false;

  String? _selectedSubjectCode;
  String? _selectedSubjectName;

  String? _selectedChapterCode;
  String? _selectedChapterName;

  String? _selectedTopicCode;
  String? _selectedTopicName;

  List<Map<String, Object?>> _subjects = [];
  List<Map<String, Object?>> _chapters = [];
  List<Map<String, Object?>> _topics = [];

  List<Map<String, Object?>> _content = [];

  _StudyContentType? _selectedContent;

// ===========================================================================
// START STUDYING
// ===========================================================================

  Future<void> _startStudyingToday() async {
    await _runLazyLoad(() async {
      final rows = await _service.loadSubjects();

      if (!mounted) return;

      setState(() {
        _subjects = rows;
        _stage = _StudyWorkspaceStage.subjects;
      });
    });
  }

// ===========================================================================
// SUBJECT
// ===========================================================================

  Future<void> _selectSubject(
    Map<String, Object?> subject,
  ) async {
    final subjectCode = subject['subject_code']?.toString() ?? '';

    final subjectName = subject['subject_name']?.toString() ?? subjectCode;

    if (subjectCode.isEmpty) return;

    await _runLazyLoad(() async {
      final rows = await _service.loadInProgressChapters(
        subjectCode,
      );

      if (!mounted) return;

      setState(() {
        _selectedSubjectCode = subjectCode;
        _selectedSubjectName = subjectName;

        _selectedChapterCode = null;
        _selectedChapterName = null;

        _selectedTopicCode = null;
        _selectedTopicName = null;

        _chapters = rows;
        _topics = [];
        _content = [];

        _selectedContent = null;

        _stage = _StudyWorkspaceStage.chapters;
        _leftPanelVisible = true;
      });
    });
  }

// ===========================================================================
// CHAPTER
// ===========================================================================

  Future<void> _selectChapter(
    Map<String, Object?> chapter,
  ) async {
    final chapterCode = chapter['chapter_code']?.toString() ??
        chapter['ChapterCode']?.toString() ??
        _extractChapterCode(
          chapter['SubjectChapterCode']?.toString(),
        );

    final chapterName = chapter['chapter_name']?.toString() ??
        chapter['ChapterName']?.toString() ??
        chapterCode;

    if (chapterCode == null ||
        chapterCode.isEmpty ||
        _selectedSubjectCode == null) {
      return;
    }

    await _runLazyLoad(() async {
      final rows = await _service.loadTopics(
        subjectCode: _selectedSubjectCode!,
        chapterCode: chapterCode,
      );

      if (!mounted) return;

      setState(() {
        _selectedChapterCode = chapterCode;
        _selectedChapterName = chapterName;

        _selectedTopicCode = null;
        _selectedTopicName = null;

        _topics = rows;
        _content = [];
        _selectedContent = null;

        _stage = _StudyWorkspaceStage.topics;
        _leftPanelVisible = true;
      });
    });
  }

// ===========================================================================
// TOPIC
// ===========================================================================

  Future<void> _selectTopic(
    Map<String, Object?> topic,
  ) async {
    final topicCode =
        topic['topic_code']?.toString() ?? topic['TopicCode']?.toString() ?? '';

    final topicName = topic['topic_name']?.toString() ??
        topic['TopicName']?.toString() ??
        topicCode;

    if (topicCode.isEmpty) return;

    setState(() {
      _selectedTopicCode = topicCode;
      _selectedTopicName = topicName;

      _selectedContent = null;
      _content = [];

      _stage = _StudyWorkspaceStage.topicWorkspace;

      _leftPanelVisible = true;
    });
  }

// ===========================================================================
// CONTENT
// ===========================================================================

  Future<void> _openContent(
    _StudyContentType type,
  ) async {
    final subjectCode = _selectedSubjectCode;
    final chapterCode = _selectedChapterCode;
    final topicCode = _selectedTopicCode;

    if (subjectCode == null || chapterCode == null || topicCode == null) {
      return;
    }

    await _runLazyLoad(() async {
      late final List<Map<String, Object?>> rows;

      switch (type) {
        case _StudyContentType.notes:
          rows = await _service.loadStudyNotes(
            subjectCode: subjectCode,
            chapterCode: chapterCode,
            topicCode: topicCode,
          );
          break;

        case _StudyContentType.studyBook:
          rows = await _service.loadStudyBooks(
            subjectCode: subjectCode,
            chapterCode: chapterCode,
            topicCode: topicCode,
          );
          break;

        case _StudyContentType.recordedLecture:
          rows = await _service.loadRecordedLectures(
            subjectCode: subjectCode,
            chapterCode: chapterCode,
            topicCode: topicCode,
          );
          break;

        case _StudyContentType.voiceNotes:
          rows = await _service.loadVoiceNotes(
            subjectCode: subjectCode,
            chapterCode: chapterCode,
            topicCode: topicCode,
          );
          break;

        case _StudyContentType.revise:
        case _StudyContentType.relatedTasks:
          rows = await _service.loadRelatedTasks(
            subjectCode: subjectCode,
            chapterCode: chapterCode,
            topicCode: topicCode,
          );
          break;
      }

      if (!mounted) return;
      setState(() {
        _selectedContent = type;
        _content = rows;
      });
    });
  }

// ===========================================================================
// LAZY LOAD HELPER
// ===========================================================================

  Future<void> _runLazyLoad(
    Future<void> Function() action,
  ) async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      await action();
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

// ===========================================================================
// LEFT PANEL
// ===========================================================================
  void _toggleLeftPanel() {
    setState(() {
      _leftPanelVisible = !_leftPanelVisible;
    });
  }

// ===========================================================================
// BUILD
// ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Row(
                children: [
                  if (_leftPanelVisible && _stage != _StudyWorkspaceStage.start)
                    _buildLeftPanel(context),
                  Expanded(
                    child: _buildMainWorkspace(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

// ===========================================================================
// HEADER
// ===========================================================================

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          if (_stage != _StudyWorkspaceStage.start)
            IconButton(
              tooltip: _leftPanelVisible
                  ? 'Hide study navigator'
                  : 'Show study navigator',
              onPressed: _toggleLeftPanel,
              icon: Icon(
                _leftPanelVisible ? Icons.menu_open : Icons.menu,
              ),
            ),
          const SizedBox(width: 8),
          const Text(
            'STUDY WORKSPACE',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const Spacer(),
          if (_selectedTopicName != null)
            Flexible(
              child: Text(
                _selectedTopicName!,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

// ===========================================================================
// LEFT PANEL
// ===========================================================================

  Widget _buildLeftPanel(
    BuildContext context,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 270,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _buildNavigatorContent(),
      ),
    );
  }

  Widget _buildNavigatorContent() {
    switch (_stage) {
      case _StudyWorkspaceStage.subjects:
        return _buildSubjectNavigator();

      case _StudyWorkspaceStage.chapters:
        return _buildChapterNavigator();

      case _StudyWorkspaceStage.topics:
      case _StudyWorkspaceStage.topicWorkspace:
        return _buildTopicNavigator();

      case _StudyWorkspaceStage.start:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSubjectNavigator() {
    return ListView(
      children: [
        const Text(
          'SUBJECTS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        ..._subjects.map(
          (subject) {
            final code = subject['subject_code']?.toString() ?? '';

            final name = subject['subject_name']?.toString() ?? code;

            return _navigationTile(
              title: name,
              subtitle: code,
              selected: code == _selectedSubjectCode,
              onTap: () => _selectSubject(subject),
            );
          },
        ),
      ],
    );
  }

  Widget _buildChapterNavigator() {
    return ListView(
      children: [
        _breadcrumb(
          _selectedSubjectName ?? 'Subject',
        ),
        const SizedBox(height: 18),
        const Text(
          'CURRENTLY ATTENDING',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        if (_chapters.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text(
              'No currently attending chapters.',
            ),
          ),
        ..._chapters.map(
          (chapter) {
            final code = chapter['chapter_code']?.toString() ??
                chapter['ChapterCode']?.toString() ??
                _extractChapterCode(
                  chapter['SubjectChapterCode']?.toString(),
                ) ??
                '';

            final name = chapter['chapter_name']?.toString() ??
                chapter['ChapterName']?.toString() ??
                code;

            return _navigationTile(
              title: name,
              subtitle: code,
              selected: code == _selectedChapterCode,
              onTap: () => _selectChapter(chapter),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTopicNavigator() {
    return ListView(
      children: [
        _breadcrumb(
          _selectedSubjectName ?? 'Subject',
        ),
        const SizedBox(height: 4),
        _breadcrumb(
          _selectedChapterName ?? 'Chapter',
        ),
        const SizedBox(height: 18),
        const Text(
          'TOPICS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        ..._topics.map(
          (topic) {
            final code = topic['topic_code']?.toString() ??
                topic['TopicCode']?.toString() ??
                '';

            final name = topic['topic_name']?.toString() ??
                topic['TopicName']?.toString() ??
                code;

            return _navigationTile(
              title: name,
              subtitle: code,
              selected: code == _selectedTopicCode,
              onTap: () => _selectTopic(topic),
            );
          },
        ),
      ],
    );
  }

// ===========================================================================
// MAIN WORKSPACE
// ===========================================================================

  Widget _buildMainWorkspace(
    BuildContext context,
  ) {
    switch (_stage) {
      case _StudyWorkspaceStage.start:
        return _buildStartView(context);

      case _StudyWorkspaceStage.subjects:
        return _buildSubjectsView(context);

      case _StudyWorkspaceStage.chapters:
        return _buildChaptersView(context);

      case _StudyWorkspaceStage.topics:
        return _buildTopicsView(context);

      case _StudyWorkspaceStage.topicWorkspace:
        return _buildTopicWorkspace(context);
    }
  }

// ===========================================================================
// START VIEW
// ===========================================================================

  Widget _buildStartView(
    BuildContext context,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 560,
        ),
        child: Card(
          elevation: 0,
          color: const Color(0xFF151515),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _loading ? null : _startStudyingToday,
            child: Padding(
              padding: const EdgeInsets.all(42),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 58,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary,
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  const Text(
                    'START STUDYING TODAY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  Text(
                    'Choose what you want to study '
                    'and continue from your currently '
                    'attending chapters.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(
                    height: 28,
                  ),
                  FilledButton.icon(
                    onPressed: _loading ? null : _startStudyingToday,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.play_arrow,
                          ),
                    label: Text(
                      _loading ? 'Loading Subjects...' : 'Start Studying',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// SUBJECT VIEW
// ===========================================================================

  Widget _buildSubjectsView(
    BuildContext context,
  ) {
    return _pageContent(
      title: 'WHAT DO YOU WANT TO STUDY?',
      subtitle: 'Choose a subject.',
      child: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          mainAxisExtent: 145,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _subjects.length,
        itemBuilder: (context, index) {
          final subject = _subjects[index];

          final code = subject['subject_code']?.toString() ?? '';

          final name = subject['subject_name']?.toString() ?? code;

          return _studyCard(
            icon: Icons.school_outlined,
            title: name,
            subtitle: 'Continue studying',
            onTap: () => _selectSubject(
              subject,
            ),
          );
        },
      ),
    );
  }

// ===========================================================================
// CHAPTER VIEW
// ===========================================================================

  Widget _buildChaptersView(
    BuildContext context,
  ) {
    return _pageContent(
      title: _selectedSubjectName ?? 'SUBJECT',
      subtitle: 'Currently attending chapters',
      child: _chapters.isEmpty
          ? const Center(
              child: Text(
                'There are no currently '
                'attending chapters.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: _chapters.map(
                (chapter) {
                  final name = chapter['chapter_name']?.toString() ??
                      chapter['ChapterName']?.toString() ??
                      'Chapter';

                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: 12,
                    ),
                    child: _studyCard(
                      icon: Icons.layers_outlined,
                      title: name,
                      subtitle: 'Open chapter topics',
                      onTap: () => _selectChapter(
                        chapter,
                      ),
                    ),
                  );
                },
              ).toList(),
            ),
    );
  }

// ===========================================================================
// TOPIC VIEW
// ===========================================================================

  Widget _buildTopicsView(
    BuildContext context,
  ) {
    return _pageContent(
      title: _selectedChapterName ?? 'CHAPTER',
      subtitle: 'Choose a topic to study',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: _topics.map(
          (topic) {
            final name = topic['topic_name']?.toString() ??
                topic['TopicName']?.toString() ??
                'Topic';

            return Padding(
              padding: const EdgeInsets.only(
                bottom: 10,
              ),
              child: _studyCard(
                icon: Icons.topic_outlined,
                title: name,
                subtitle: 'Open study workspace',
                onTap: () => _selectTopic(topic),
              ),
            );
          },
        ).toList(),
      ),
    );
  }

// ===========================================================================
// TOPIC WORKSPACE
// ===========================================================================

  Widget _buildTopicWorkspace(
    BuildContext context,
  ) {
    return _pageContent(
      title: _selectedTopicName ?? 'TOPIC',
      subtitle: _selectedChapterName ?? '',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              'WHAT DO YOU WANT TO DO?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 900
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _actionCard(
                      width: width,
                      icon: Icons.note_alt_outlined,
                      title: 'Revise Notes',
                      subtitle: 'Open notes and captured study material',
                      onTap: () => _openContent(
                        _StudyContentType.notes,
                      ),
                    ),
                    _actionCard(
                      width: width,
                      icon: Icons.menu_book_outlined,
                      title: 'Study Book',
                      subtitle: 'Open study books and PDF material',
                      onTap: () => _openContent(
                        _StudyContentType.studyBook,
                      ),
                    ),
                    _actionCard(
                      width: width,
                      icon: Icons.play_circle_outline,
                      title: 'Recorded Lecture',
                      subtitle: 'Open lectures recorded for this topic',
                      onTap: () => _openContent(
                        _StudyContentType.recordedLecture,
                      ),
                    ),
                    _actionCard(
                      width: width,
                      icon: Icons.headphones_outlined,
                      title: 'Voice Notes',
                      subtitle: 'Listen to topic-specific voice notes',
                      onTap: () => _openContent(
                        _StudyContentType.voiceNotes,
                      ),
                    ),
                    _actionCard(
                      width: width,
                      icon: Icons.refresh,
                      title: 'Revise',
                      subtitle: 'Continue revision for this topic',
                      onTap: () => _openContent(
                        _StudyContentType.revise,
                      ),
                    ),
                    _actionCard(
                      width: width,
                      icon: Icons.task_alt_outlined,
                      title: 'Related Tasks',
                      subtitle: 'Open existing EPMS tasks for this topic',
                      onTap: () => _openContent(
                        _StudyContentType.relatedTasks,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_selectedContent != null) ...[
              const SizedBox(
                height: 30,
              ),
              _buildContentArea(
                context,
              ),
            ],
          ],
        ),
      ),
    );
  }

// ===========================================================================
// CONTENT AREA
// ===========================================================================

  Widget _buildContentArea(
    BuildContext context,
  ) {
    final title = switch (_selectedContent!) {
      _StudyContentType.notes => 'REVISION NOTES',
      _StudyContentType.studyBook => 'STUDY BOOK',
      _StudyContentType.recordedLecture => 'RECORDED LECTURES',
      _StudyContentType.voiceNotes => 'VOICE NOTES',
      _StudyContentType.revise => 'REVISION',
      _StudyContentType.relatedTasks => 'RELATED TASKS',
    };

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_content.isEmpty) {
      return Card(
        elevation: 0,
        color: const Color(0xFF151515),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: Text(
                  'No $title content is currently '
                  'available for this topic.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        ..._content.map(
          (row) => Card(
            elevation: 0,
            color: const Color(0xFF151515),
            child: ListTile(
              title: Text(
                row['title']?.toString() ??
                    row['name']?.toString() ??
                    'Study item',
              ),
              subtitle: Text(
                row['description']?.toString() ?? '',
              ),
            ),
          ),
        ),
      ],
    );
  }

// ===========================================================================
// COMMON UI
// ===========================================================================

  Widget _pageContent({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            4,
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
          ),
          child: Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: child),
      ],
    );
  }

  Widget _studyCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: const Color(0xFF151515),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                icon,
                size: 32,
              ),
              const SizedBox(
                width: 16,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(
                          0.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionCard({
    required double width,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        color: const Color(0xFF151515),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _loading ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 34,
                ),
                const SizedBox(
                  width: 16,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(
                            0.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navigationTile({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 6,
      ),
      child: ListTile(
        dense: true,
        selected: selected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: const Icon(
          Icons.chevron_right,
          size: 18,
        ),
        onTap: _loading ? null : onTap,
      ),
    );
  }

  Widget _breadcrumb(String text) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: Colors.white.withOpacity(0.55),
      ),
    );
  }

  String? _extractChapterCode(
    String? value,
  ) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final separator = value.indexOf('-');

    if (separator < 0) {
      return null;
    }

    return value.substring(separator + 1).trim();
  }
}
