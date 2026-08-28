import 'package:flutter/material.dart';

import '../services/lecture_enquiry_svc.dart';
import '../services/lecture_svc.dart';

class LectureScreen extends StatefulWidget {
  final String? initialSubjectCode;

  const LectureScreen({super.key, this.initialSubjectCode});

  @override
  State<LectureScreen> createState() => _LectureScreenState();
}

class _LectureScreenState extends State<LectureScreen> {
  final LectureService _lectureService = LectureService.instance;

  final LectureEnquiryService _lectureEnquiryService =
      LectureEnquiryService.instance;

  // ---------------------------------------------------------------------------
  // SUBJECTS
  // ---------------------------------------------------------------------------

  static const List<Map<String, String>> _subjects = [
    {'code': 'Phy', 'name': 'Physics'},
    {'code': 'Chem', 'name': 'Chemistry'},
    {'code': 'Bio', 'name': 'Biology'},
  ];

  // ---------------------------------------------------------------------------
  // SCREEN TABS
  // ---------------------------------------------------------------------------

  int _mainTabIndex = 0;

  // ---------------------------------------------------------------------------
  // RECORDING STATE
  // ---------------------------------------------------------------------------

  String? _selectedSubjectCode;

  bool? _newChapter;

  bool _saving = false;

  bool _lastLecture = false;

  List<Map<String, Object?>> _chapters = [];

  List<Map<String, Object?>> _topics = [];

  Map<String, Object?>? _selectedChapter;

  Map<String, Object?>? _selectedTopic;

  String? _selectedChapterCode;

  String? _selectedTopicCode;

  bool _chaptersLoading = false;

  bool _topicsLoading = false;

  DateTime _lectureDate = DateTime.now();

  final TextEditingController _shortNotesController = TextEditingController();

  // ---------------------------------------------------------------------------
  // VIEW LECTURE STATE
  // ---------------------------------------------------------------------------

  int _viewMode = 0;

  bool _viewLoading = false;

  List<Map<String, Object?>> _viewLectures = [];

  final Set<String> _expandedViewGroups = <String>{};

  final Set<String> _expandedViewLectures = <String>{};

  // ---------------------------------------------------------------------------
  // NOTES / IMAGES
  // ---------------------------------------------------------------------------

  String? _selectedNotesFilePath;

  String? _selectedNotesImages;

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    final initialSubject = widget.initialSubjectCode?.trim();

    if (initialSubject != null && initialSubject.isNotEmpty) {
      _selectedSubjectCode = initialSubject;
    }

    _loadViewLectures();
  }

  @override
  void dispose() {
    _shortNotesController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // MAIN TAB
  // ---------------------------------------------------------------------------

  void _changeMainTab(int index) {
    if (_mainTabIndex == index) {
      return;
    }

    setState(() {
      _mainTabIndex = index;
    });

    if (index == 0) {
      _loadViewLectures();
    }
  }

  // ---------------------------------------------------------------------------
  // SUBJECT
  // ---------------------------------------------------------------------------

  Future<void> _selectSubject(String subjectCode) async {
    setState(() {
      _selectedSubjectCode = subjectCode;

      _newChapter = null;

      _chapters = [];
      _topics = [];

      _selectedChapter = null;
      _selectedTopic = null;

      _selectedChapterCode = null;
      _selectedTopicCode = null;

      _lastLecture = false;

      _selectedNotesFilePath = null;
      _selectedNotesImages = null;
    });
  }

  // ---------------------------------------------------------------------------
  // WORKFLOW
  // ---------------------------------------------------------------------------

  Future<void> _selectWorkflow(bool newChapter) async {
    final subjectCode = _selectedSubjectCode;

    if (subjectCode == null) {
      _showMessage('Please select a subject first.');
      return;
    }

    setState(() {
      _newChapter = newChapter;

      _chapters = [];
      _topics = [];

      _selectedChapter = null;
      _selectedTopic = null;

      _selectedChapterCode = null;
      _selectedTopicCode = null;

      _lastLecture = false;
    });

    await _loadChapters();
  }

  // ---------------------------------------------------------------------------
  // CHAPTERS
  // ---------------------------------------------------------------------------

  Future<void> _loadChapters() async {
    final subjectCode = _selectedSubjectCode;

    final newChapter = _newChapter;

    if (subjectCode == null || newChapter == null) {
      return;
    }

    setState(() {
      _chaptersLoading = true;
    });

    try {
      final List<Map<String, Object?>> chapters;

      if (newChapter) {
        chapters = await _lectureService.getNewChapterChapters(subjectCode);
      } else {
        chapters = await _lectureService.getContinuationChapters(subjectCode);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _chapters = chapters;
        _chaptersLoading = false;
      });

      // -----------------------------------------------------------------------
      // CONTINUATION REFINEMENT
      //
      // If only one chapter is currently in progress, do not make the user
      // select it manually. Preload it and immediately enable Topic selection.
      // -----------------------------------------------------------------------

      if (!newChapter && chapters.length == 1) {
        final onlyChapter = chapters.first;

        final chapterCode = onlyChapter['chapterCode']?.toString();

        if (chapterCode != null && chapterCode.isNotEmpty) {
          await _selectChapter(onlyChapter, showSelectionMessage: false);
        }
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _chaptersLoading = false;
      });

      _showMessage('Unable to load chapters: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // CHAPTER SELECTION
  // ---------------------------------------------------------------------------

  Future<void> _selectChapter(
    Map<String, Object?>? chapter, {
    bool showSelectionMessage = true,
  }) async {
    if (chapter == null) {
      return;
    }

    final subjectCode = _selectedSubjectCode;

    if (subjectCode == null) {
      return;
    }

    final chapterCode = chapter['chapterCode']?.toString();

    if (chapterCode == null || chapterCode.isEmpty) {
      _showMessage('Invalid chapter selected.');
      return;
    }

    setState(() {
      _selectedChapter = chapter;

      _selectedChapterCode = chapterCode;

      _selectedTopic = null;

      _selectedTopicCode = null;

      _topics = [];

      _topicsLoading = true;
    });

    try {
      final List<Map<String, Object?>> topics;

      if (_newChapter == true) {
        topics = await _lectureService.getNewChapterTopics(
          subjectCode: subjectCode,
          chapterCode: chapterCode,
        );
      } else {
        topics = await _lectureService.getContinuationTopics(
          subjectCode: subjectCode,
          chapterCode: chapterCode,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _topics = topics;
        _topicsLoading = false;
      });

      if (showSelectionMessage && topics.isEmpty) {
        _showMessage('No selectable topics found for this chapter.');
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _topicsLoading = false;
      });

      _showMessage('Unable to load topics: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // TOPIC SELECTION
  // ---------------------------------------------------------------------------

  void _selectTopic(Map<String, Object?>? topic) {
    if (topic == null) {
      return;
    }

    setState(() {
      _selectedTopic = topic;

      _selectedTopicCode = topic['topicCode']?.toString();
    });
  }

  // ---------------------------------------------------------------------------
  // DATE
  // ---------------------------------------------------------------------------

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _lectureDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _lectureDate = selected;
    });
  }

  // ---------------------------------------------------------------------------
  // NOTES / IMAGES
  // ---------------------------------------------------------------------------

  void _captureNotesImages() {
    /*
     * UI hook only for now.
     *
     * Actual camera/gallery/file implementation can be connected later.
     *
     * Keeping this method here prevents the UI from becoming coupled to a
     * particular image/file package before that decision is finalized.
     */

    _showMessage('Notes / image capture will be connected here.');
  }

  void _selectNotesFile() {
    /*
     * UI hook only for now.
     */

    _showMessage('Class notes file selection will be connected here.');
  }

  // ---------------------------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------------------------

  Future<void> _saveLecture() async {
    if (_saving) {
      return;
    }

    final subjectCode = _selectedSubjectCode;

    final chapter = _selectedChapter;

    final topic = _selectedTopic;

    final newChapter = _newChapter;

    if (subjectCode == null) {
      _showMessage('Please select a subject.');
      return;
    }

    if (newChapter == null) {
      _showMessage('Please select the lecture type.');
      return;
    }

    if (chapter == null) {
      _showMessage('Please select a chapter.');
      return;
    }

    if (topic == null) {
      _showMessage('Please select a topic.');
      return;
    }

    final chapterCode = chapter['chapterCode']?.toString() ?? '';

    final chapterName = chapter['chapterName']?.toString() ?? '';

    final topicId = topic['topicId']?.toString() ?? '';

    final topicCode = topic['topicCode']?.toString() ?? '';

    final topicName = topic['topicName']?.toString() ?? '';

    if (chapterCode.isEmpty ||
        chapterName.isEmpty ||
        topicId.isEmpty ||
        topicCode.isEmpty ||
        topicName.isEmpty) {
      _showMessage('Selected chapter or topic contains incomplete data.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final result = await _lectureService.saveLecture(
        subjectCode: subjectCode,
        chapterCode: chapterCode,
        topicCode: topicCode,
        chapterName: chapterName,
        topicName: topicName,
        topicId: topicId,
        lectureDate: _lectureDate,
        shortNotes: _shortNotesController.text,
        lastLecture: _lastLecture,
        newChapter: newChapter,
      );

      if (!mounted) {
        return;
      }

      _resetRecordingState();

      setState(() {
        _mainTabIndex = 0;
      });

      await _loadViewLectures();

      if (!mounted) {
        return;
      }

      _showMessage(
        result.completedChapter
            ? 'Lecture saved for $topicName. Chapter completed.'
            : 'Lecture saved for $topicName.\nLecture ID: ${result.lectureId}',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to save lecture: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CANCEL
  // ---------------------------------------------------------------------------

  void _cancelRecording() {
    if (_saving) {
      return;
    }

    _resetRecordingState();

    setState(() {
      _mainTabIndex = 0;
    });

    _loadViewLectures();

    _showMessage('Lecture recording cancelled.');
  }

  void _resetRecordingState() {
    setState(() {
      _newChapter = null;

      _chapters = [];

      _topics = [];

      _selectedChapter = null;

      _selectedTopic = null;

      _selectedChapterCode = null;

      _selectedTopicCode = null;

      _chaptersLoading = false;

      _topicsLoading = false;

      _lastLecture = false;

      _lectureDate = DateTime.now();

      _shortNotesController.clear();

      _selectedNotesFilePath = null;

      _selectedNotesImages = null;
    });
  }

  // ===========================================================================
  // VIEW LECTURES
  // ===========================================================================

  Future<void> _loadViewLectures() async {
    setState(() {
      _viewLoading = true;
    });

    try {
      List<Map<String, Object?>> lectures;

      if (_viewMode == 0) {
        lectures = await _lectureEnquiryService.getThisWeekLectures();
      } else if (_viewMode == 1) {
        lectures = await _lectureEnquiryService.getPhysicsLectures();
      } else {
        lectures = await _lectureEnquiryService.getAllLectures();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _viewLectures = lectures;

        _viewLoading = false;

        _expandedViewGroups.clear();

        _expandedViewLectures.clear();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _viewLoading = false;
      });

      _showMessage('Unable to load lectures: $e');
    }
  }

  Future<void> _selectViewMode(int mode) async {
    setState(() {
      _viewMode = mode;
    });

    await _loadViewLectures();
  }

  // ---------------------------------------------------------------------------
  // VIEW MODE DATA
  // ---------------------------------------------------------------------------

  Future<List<Map<String, Object?>>> _loadDateLectures(int index) {
    if (index == 0) {
      return _lectureEnquiryService.getThisWeekLectures();
    }

    if (index == 1) {
      return _lectureEnquiryService.getLastTwoWeeksLectures();
    }

    return _lectureEnquiryService.getThisMonthLectures();
  }

  Future<List<Map<String, Object?>>> _loadSubjectLectures(String subjectCode) {
    return _lectureEnquiryService.getSubjectLectures(subjectCode);
  }

  // ---------------------------------------------------------------------------
  // DATE-WISE VIEW
  // ---------------------------------------------------------------------------

  Widget _buildDateWiseView() {
    return Column(
      children: [
        _buildCollapsiblePeriod(
          keyName: 'this_week',
          title: 'This Week',
          loader: () => _loadDateLectures(0),
        ),
        _buildCollapsiblePeriod(
          keyName: 'last_two_weeks',
          title: 'Last Two Weeks',
          loader: () => _loadDateLectures(1),
        ),
        _buildCollapsiblePeriod(
          keyName: 'this_month',
          title: 'This Month',
          loader: () => _loadDateLectures(2),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SUBJECT-WISE VIEW
  // ---------------------------------------------------------------------------

  Widget _buildSubjectWiseView() {
    return Column(
      children: [
        _buildCollapsiblePeriod(
          keyName: 'subject_phy',
          title: 'Physics Lectures',
          loader: () => _loadSubjectLectures('Phy'),
        ),
        _buildCollapsiblePeriod(
          keyName: 'subject_chem',
          title: 'Chemistry Lectures',
          loader: () => _loadSubjectLectures('Chem'),
        ),
        _buildCollapsiblePeriod(
          keyName: 'subject_bio',
          title: 'Biology Lectures',
          loader: () => _loadSubjectLectures('Bio'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // COLLAPSIBLE PERIOD / SUBJECT ROW
  // ---------------------------------------------------------------------------

  Widget _buildCollapsiblePeriod({
    required String keyName,
    required String title,
    required Future<List<Map<String, Object?>>> Function() loader,
  }) {
    final expanded = _expandedViewGroups.contains(keyName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            if (expanded) {
              setState(() {
                _expandedViewGroups.remove(keyName);
              });
              return;
            }

            setState(() {
              _expandedViewGroups.add(keyName);
            });

            if (_viewLectures.isEmpty) {
              try {
                final rows = await loader();

                if (!mounted) {
                  return;
                }

                setState(() {
                  _viewLectures = rows;
                });
              } catch (e) {
                if (!mounted) {
                  return;
                }

                _showMessage('Unable to load lectures: $e');
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 10),
                  FutureBuilder<List<Map<String, Object?>>>(
                    future: loader(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Text(
                          'Unable to load lectures.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        );
                      }

                      final rows = snapshot.data ?? [];

                      if (rows.isEmpty) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('No lectures found.'),
                        );
                      }

                      return _buildLectureGroups(rows);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LECTURE GROUPS
  // ---------------------------------------------------------------------------

  Widget _buildLectureGroups(List<Map<String, Object?>> lectures) {
    final grouped = _viewMode == 0
        ? _lectureEnquiryService.groupByDate(lectures)
        : _lectureEnquiryService.groupBySubjectChapter(lectures);

    return Column(
      children: grouped.entries.map((entry) {
        final key = entry.key;

        final rows = entry.value;

        final expanded = _expandedViewGroups.contains('nested_$key');

        final label = _viewMode == 0
            ? _displayDateKey(key)
            : _displaySubjectChapter(rows);

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(11),
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: () {
                setState(() {
                  if (expanded) {
                    _expandedViewGroups.remove('nested_$key');
                  } else {
                    _expandedViewGroups.add('nested_$key');
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 10,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          '${rows.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                        ),
                      ],
                    ),
                    if (expanded) ...[
                      const SizedBox(height: 7),
                      ...rows.map(_buildLectureRow),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // INDIVIDUAL LECTURE ROW
  // ---------------------------------------------------------------------------

  Widget _buildLectureRow(Map<String, Object?> lecture) {
    final lectureId = lecture['lectureId']?.toString() ?? '';

    final topicCode = lecture['topicCode']?.toString() ?? '';

    final expanded = _expandedViewLectures.contains(lectureId);

    final hasFile = _lectureEnquiryService.hasNotesFile(lecture);

    final hasImages = _lectureEnquiryService.hasNotesImages(lecture);

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              if (expanded) {
                _expandedViewLectures.remove(lectureId);
              } else {
                _expandedViewLectures.add(lectureId);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$lectureId - $topicCode',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 19,
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 7),
                  _buildLectureDetail(
                    lecture,
                    hasFile: hasFile,
                    hasImages: hasImages,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LECTURE DETAILS
  // ---------------------------------------------------------------------------

  Widget _buildLectureDetail(
    Map<String, Object?> lecture, {
    required bool hasFile,
    required bool hasImages,
  }) {
    final shortDetails = lecture['shortDetails']?.toString().trim() ?? '';

    final lectureDate = lecture['lectureDateDisplay']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lectureDate.isNotEmpty)
          _detailLine(Icons.calendar_today, lectureDate),

        if (shortDetails.isNotEmpty) ...[
          const SizedBox(height: 6),
          _detailLine(Icons.notes, shortDetails),
        ],

        if (hasFile || hasImages) ...[
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (hasFile)
                _attachmentChip(Icons.insert_drive_file, 'Class Notes'),
              if (hasImages)
                _attachmentChip(Icons.photo_library, 'Captured Images'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _detailLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 7),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
      ],
    );
  }

  Widget _attachmentChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11.5)),
        ],
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopTabs(),

            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _mainTabIndex == 0
                    ? _buildViewLecturesWorkspace()
                    : _buildRecordLecturesWorkspace(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TOP TABS
  // ---------------------------------------------------------------------------

  Widget _buildTopTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: _topTabButton(
                label: 'View Lectures',
                icon: Icons.view_list,
                selected: _mainTabIndex == 0,
                onTap: () => _changeMainTab(0),
              ),
            ),
            Expanded(
              child: _topTabButton(
                label: 'Record Lecture',
                icon: Icons.mic,
                selected: _mainTabIndex == 1,
                onTap: () => _changeMainTab(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topTabButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.surface
          : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      elevation: selected ? 1 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // VIEW WORKSPACE
  // ===========================================================================

  Widget _buildViewLecturesWorkspace() {
    return Column(
      children: [
        _buildViewModeSelector(),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
            child: _viewLoading
                ? const Padding(
                    padding: EdgeInsets.only(top: 30),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _viewMode == 0
                ? _buildDateWiseView()
                : _viewMode == 1
                ? _buildSubjectWiseView()
                : _buildAllLecturesView(),
          ),
        ),

        _buildReturnButton(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // VIEW MODE SELECTOR
  // ---------------------------------------------------------------------------

  Widget _buildViewModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: _viewOption(
              label: 'Date-Wise',
              icon: Icons.calendar_month,
              selected: _viewMode == 0,
              onTap: () => _selectViewMode(0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _viewOption(
              label: 'Subject-Wise',
              icon: Icons.school,
              selected: _viewMode == 1,
              onTap: () => _selectViewMode(1),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _viewOption(
              label: 'All Lectures',
              icon: Icons.list_alt,
              selected: _viewMode == 2,
              onTap: () => _selectViewMode(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      elevation: selected ? 1 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
          child: Column(
            children: [
              Icon(icon, size: 18),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ALL LECTURES
  // ---------------------------------------------------------------------------

  Widget _buildAllLecturesView() {
    if (_viewLectures.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 25),
        child: Center(child: Text('No lectures found.')),
      );
    }

    return _buildLectureGroups(_viewLectures);
  }

  // ===========================================================================
  // RECORD WORKSPACE
  // ===========================================================================

  Widget _buildRecordLecturesWorkspace() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSubjectSection(),

          if (_selectedSubjectCode != null) ...[
            const SizedBox(height: 7),
            _buildWorkflowSection(),
          ],

          if (_newChapter != null) ...[
            const SizedBox(height: 7),
            _buildChapterTopicSection(),
          ],

          if (_selectedTopic != null) ...[
            const SizedBox(height: 7),
            _buildLectureDetailsSection(),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SUBJECT SECTION
  // ---------------------------------------------------------------------------

  Widget _buildSubjectSection() {
    return Row(
      children: _subjects.map((subject) {
        final code = subject['code']!;

        final name = subject['name']!;

        final selected = _selectedSubjectCode == code;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _selectionButton(
              label: name,
              selected: selected,
              onTap: () => _selectSubject(code),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // WORKFLOW SECTION
  // ---------------------------------------------------------------------------

  Widget _buildWorkflowSection() {
    return Row(
      children: [
        Expanded(
          child: _selectionButton(
            label: 'Continued Topic Lecture',
            selected: _newChapter == false,
            onTap: _chaptersLoading ? null : () => _selectWorkflow(false),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _selectionButton(
            label: 'Start New Chapter',
            selected: _newChapter == true,
            onTap: _chaptersLoading ? null : () => _selectWorkflow(true),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // CHAPTER + TOPIC
  // ---------------------------------------------------------------------------

  Widget _buildChapterTopicSection() {
    if (_chaptersLoading) {
      return _compactLoading();
    }

    if (_chapters.isEmpty) {
      return _compactInfo(
        _newChapter == true
            ? 'No syllabus chapters found.'
            : 'No continued chapters found.',
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildChapterDropdown()),
        const SizedBox(width: 7),
        Expanded(child: _buildTopicDropdown()),
      ],
    );
  }

  Widget _buildChapterDropdown() {
    return _softField(
      child: DropdownButtonFormField<String>(
        initialValue: _selectedChapterCode,
        isExpanded: true,
        decoration: const InputDecoration(
          hintText: 'Select a chapter first',
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        ),
        items: _chapters.map((chapter) {
          final code = chapter['chapterCode']?.toString() ?? '';

          final name = chapter['chapterName']?.toString() ?? '';

          return DropdownMenuItem<String>(
            value: code,
            child: Text(
              name.isEmpty ? code : '$code - $name',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          );
        }).toList(),
        onChanged: _selectChapterByCode,
      ),
    );
  }

  Future<void> _selectChapterByCode(String? code) async {
    if (code == null || code.isEmpty) {
      return;
    }

    Map<String, Object?>? chapter;

    for (final item in _chapters) {
      if (item['chapterCode']?.toString() == code) {
        chapter = item;
        break;
      }
    }

    if (chapter != null) {
      await _selectChapter(chapter);
    }
  }

  Widget _buildTopicDropdown() {
    if (_topicsLoading) {
      return _softField(
        child: const SizedBox(
          height: 20,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (_topics.isEmpty) {
      return _softField(
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Text('Select chapter first', style: TextStyle(fontSize: 12)),
        ),
      );
    }

    return _softField(
      child: DropdownButtonFormField<String>(
        initialValue: _selectedTopicCode,
        isExpanded: true,
        decoration: const InputDecoration(
          hintText: 'Select topic',
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        ),
        items: _topics.map((topic) {
          final code = topic['topicCode']?.toString() ?? '';

          final name = topic['topicName']?.toString() ?? '';

          return DropdownMenuItem<String>(
            value: code,
            child: Text(
              name.isEmpty ? code : '$code - $name',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          );
        }).toList(),
        onChanged: _selectTopicByCode,
      ),
    );
  }

  void _selectTopicByCode(String? code) {
    if (code == null || code.isEmpty) {
      return;
    }

    Map<String, Object?>? topic;

    for (final item in _topics) {
      if (item['topicCode']?.toString() == code) {
        topic = item;
        break;
      }
    }

    if (topic != null) {
      _selectTopic(topic);
    }
  }

  // ---------------------------------------------------------------------------
  // LECTURE DETAILS
  // ---------------------------------------------------------------------------

  Widget _buildLectureDetailsSection() {
    return _softPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _buildDateField()),
              const SizedBox(width: 7),
              Expanded(child: _buildLastLectureField()),
            ],
          ),

          const SizedBox(height: 7),

          TextField(
            controller: _shortNotesController,
            minLines: 5,
            maxLines: 7,
            decoration: InputDecoration(
              hintText: 'Short lecture details',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),

          const SizedBox(height: 7),

          Row(
            children: [
              Expanded(
                child: _smallActionButton(
                  icon: Icons.attach_file,
                  label: 'Class Notes',
                  onTap: _selectNotesFile,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _smallActionButton(
                  icon: Icons.photo_camera,
                  label: 'Notes / Images',
                  onTap: _captureNotesImages,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _cancelRecording,
                  style: _roundedButtonStyle(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveLecture,
                  style: _roundedFilledButtonStyle(),
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save, size: 18),
                  label: Text(_saving ? 'Saving...' : 'Save Lecture'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: _selectDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lecture Date',
                      style: TextStyle(fontSize: 10.5),
                    ),
                    Text(
                      _formatDate(_lectureDate),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLastLectureField() {
    return Material(
      color: _lastLecture
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(13),
      elevation: _lastLecture ? 1 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: _saving
            ? null
            : () {
                setState(() {
                  _lastLecture = !_lastLecture;
                });
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Last Lecture',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
              Switch(
                value: _lastLecture,
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(() {
                          _lastLecture = value;
                        });
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // COMMON COMPACT UI
  // ===========================================================================

  Widget _selectionButton({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(13),
      elevation: selected ? 1 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _softField({required Widget child}) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(13),
      elevation: 1,
      child: child,
    );
  }

  Widget _softPanel({required Widget child}) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: Padding(padding: const EdgeInsets.all(9), child: child),
    );
  }

  Widget _compactLoading() {
    return _softPanel(
      child: const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }

  Widget _compactInfo(String message) {
    return _softPanel(
      child: Text(message, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _smallActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReturnButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _mainTabIndex = 1;
            });
          },
          style: _roundedButtonStyle(),
          icon: const Icon(Icons.arrow_back, size: 17),
          label: const Text('Record Lecture'),
        ),
      ),
    );
  }

  ButtonStyle _roundedButtonStyle() {
    return OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      padding: const EdgeInsets.symmetric(vertical: 10),
    );
  }

  ButtonStyle _roundedFilledButtonStyle() {
    return FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      padding: const EdgeInsets.symmetric(vertical: 10),
    );
  }

  // ===========================================================================
  // DISPLAY HELPERS
  // ===========================================================================

  String _displayDateKey(String value) {
    if (value.length != 8) {
      return value;
    }

    return '${value.substring(6, 8)}/'
        '${value.substring(4, 6)}/'
        '${value.substring(0, 4)}';
  }

  String _displaySubjectChapter(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return '';
    }

    final first = rows.first;

    final subject =
        first['subjectName']?.toString() ??
        first['subjectCode']?.toString() ??
        '';

    final chapter = first['chapterCode']?.toString() ?? '';

    return chapter.isEmpty ? subject : '$subject - $chapter';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // ---------------------------------------------------------------------------
  // MESSAGE
  // ---------------------------------------------------------------------------

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }
}
