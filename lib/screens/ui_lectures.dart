import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/svc_task_generator_lectured.dart';
import '../services/svc_Lecture_Enquiry.dart';
import '../services/svc_Lectures.dart';

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

  //final TaskGeneratorLectured _taskGenerator = TaskGeneratorLectured();
  late TaskGeneratorLectured _taskGenerator;
  // ---------------------------------------------------------------------------
  // DEBUG
  // ---------------------------------------------------------------------------

  void _debug(String message) {
    debugPrint(
      '[LECTURE UI] '
      '${DateTime.now().toIso8601String()} '
      '$message',
    );
  }

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

    _debug('initState() START');

    final initialSubject = widget.initialSubjectCode?.trim();

    _debug(
      'initState(): '
      'initialSubjectCode=$initialSubject',
    );

    if (initialSubject != null && initialSubject.isNotEmpty) {
      _selectedSubjectCode = initialSubject;

      _debug(
        'initState(): '
        'selectedSubjectCode=$_selectedSubjectCode',
      );
    }

    _loadViewLectures();

    _debug('initState() END');
  }

  @override
  void dispose() {
    _debug('dispose()');

    _shortNotesController.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // MAIN TAB
  // ---------------------------------------------------------------------------

  void _changeMainTab(int index) {
    _debug(
      '_changeMainTab(): '
      'old=$_mainTabIndex, new=$index',
    );

    if (_mainTabIndex == index) {
      return;
    }

    setState(() {
      _mainTabIndex = index;
    });

    if (index == 0) {
      _debug('_changeMainTab(): loading view lectures');

      _loadViewLectures();
    }
  }

  // ---------------------------------------------------------------------------
  // SUBJECT
  // ---------------------------------------------------------------------------

  Future<void> _selectSubject(String subjectCode) async {
    _debug(
      '_selectSubject(): '
      'subjectCode=$subjectCode',
    );

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

    _debug('_selectSubject(): state reset complete');
  }

  // ---------------------------------------------------------------------------
  // WORKFLOW
  // ---------------------------------------------------------------------------

  Future<void> _selectWorkflow(bool newChapter) async {
    _debug(
      '_selectWorkflow() START - '
      'newChapter=$newChapter',
    );

    final subjectCode = _selectedSubjectCode;

    _debug(
      '_selectWorkflow(): '
      'subjectCode=$subjectCode',
    );

    if (subjectCode == null) {
      _debug('_selectWorkflow(): ABORT - no subject');

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

    _debug('_selectWorkflow(): state updated');

    await _loadChapters();

    _debug('_selectWorkflow() END');
  }

  // ---------------------------------------------------------------------------
  // CHAPTERS
  // ---------------------------------------------------------------------------

  Future<void> _loadChapters() async {
    _debug('_loadChapters() START');

    final subjectCode = _selectedSubjectCode;

    final newChapter = _newChapter;

    _debug(
      '_loadChapters(): '
      'subject=$subjectCode, '
      'newChapter=$newChapter',
    );

    if (subjectCode == null || newChapter == null) {
      _debug('_loadChapters(): ABORT - missing state');

      return;
    }

    setState(() {
      _chaptersLoading = true;
    });

    _debug(
      '_loadChapters(): '
      '_chaptersLoading=true',
    );

    try {
      final List<Map<String, Object?>> chapters;

      if (newChapter) {
        _debug(
          '_loadChapters(): '
          'calling getNewChapterChapters()',
        );

        chapters = await _lectureService.getNewChapterChapters(subjectCode);
      } else {
        _debug(
          '_loadChapters(): '
          'calling getContinuationChapters()',
        );

        chapters = await _lectureService.getContinuationChapters(subjectCode);
      }

      _debug(
        '_loadChapters(): '
        'service returned ${chapters.length} chapters',
      );

      if (!mounted) {
        _debug('_loadChapters(): widget no longer mounted');

        return;
      }

      setState(() {
        _chapters = chapters;
        _chaptersLoading = false;
      });

      _debug(
        '_loadChapters(): state updated, '
        'chapters=${_chapters.length}',
      );

      if (!newChapter && chapters.length == 1) {
        final onlyChapter = chapters.first;

        final chapterCode = onlyChapter['chapterCode']?.toString();

        _debug(
          '_loadChapters(): '
          'continuation has exactly one chapter '
          'chapterCode=$chapterCode',
        );

        if (chapterCode != null && chapterCode.isNotEmpty) {
          await _selectChapter(onlyChapter, showSelectionMessage: false);
        }
      }

      _debug('_loadChapters() END');
    } catch (e, stackTrace) {
      _debug('_loadChapters(): EXCEPTION=$e');

      _debug('_loadChapters(): STACK=$stackTrace');

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
    _debug(
      '_selectChapter() START - '
      'chapter=$chapter',
    );

    if (chapter == null) {
      _debug('_selectChapter(): ABORT - null chapter');

      return;
    }

    final subjectCode = _selectedSubjectCode;

    if (subjectCode == null) {
      _debug('_selectChapter(): ABORT - no subject');

      return;
    }

    final chapterCode = chapter['chapterCode']?.toString();

    _debug(
      '_selectChapter(): '
      'subject=$subjectCode, '
      'chapterCode=$chapterCode',
    );

    if (chapterCode == null || chapterCode.isEmpty) {
      _debug('_selectChapter(): INVALID chapter code');

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

    _debug(
      '_selectChapter(): '
      'state updated, loading topics',
    );

    try {
      final List<Map<String, Object?>> topics;

      if (_newChapter == true) {
        _debug(
          '_selectChapter(): '
          'calling getNewChapterTopics()',
        );

        topics = await _lectureService.getNewChapterTopics(
          subjectCode: subjectCode,
          chapterCode: chapterCode,
        );
      } else {
        _debug(
          '_selectChapter(): '
          'calling getContinuationTopics()',
        );

        topics = await _lectureService.getContinuationTopics(
          subjectCode: subjectCode,
          chapterCode: chapterCode,
        );
      }

      _debug(
        '_selectChapter(): '
        'service returned ${topics.length} topics',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _topics = topics;
        _topicsLoading = false;
      });

      _debug('_selectChapter(): topics state updated');

      if (showSelectionMessage && topics.isEmpty) {
        _showMessage('No selectable topics found for this chapter.');
      }

      _debug('_selectChapter() END');
    } catch (e, stackTrace) {
      _debug('_selectChapter(): EXCEPTION=$e');

      _debug('_selectChapter(): STACK=$stackTrace');

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
    _debug('_selectTopic(): topic=$topic');

    if (topic == null) {
      _debug('_selectTopic(): ABORT - null topic');

      return;
    }

    setState(() {
      _selectedTopic = topic;

      _selectedTopicCode = topic['topicCode']?.toString();
    });

    _debug(
      '_selectTopic(): '
      'selectedTopicCode=$_selectedTopicCode',
    );
  }

  // ---------------------------------------------------------------------------
  // DATE
  // ---------------------------------------------------------------------------

  Future<void> _selectDate() async {
    _debug(
      '_selectDate(): '
      'current=$_lectureDate',
    );

    final selected = await showDatePicker(
      context: context,
      initialDate: _lectureDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (selected == null) {
      _debug('_selectDate(): user cancelled');

      return;
    }

    setState(() {
      _lectureDate = selected;
    });

    _debug(
      '_selectDate(): '
      'new=$_lectureDate',
    );
  }

  // ---------------------------------------------------------------------------
  // NOTES / IMAGES
  // ---------------------------------------------------------------------------

  void _captureNotesImages() {
    _debug('_captureNotesImages() clicked');

    _showMessage('Notes / image capture will be connected here.');
  }

  void _selectNotesFile() {
    _debug('_selectNotesFile() clicked');

    _showMessage('Class notes file selection will be connected here.');
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _saveLecture() async {
    _debug('');
    _debug('================================================');
    _debug('SAVE BUTTON CLICKED');
    _debug('================================================');
    print('');
    print('================================================');
    print('[LECTURE SERVICE] saveLecture() ENTERED');
    print('================================================');

    if (_saving) {
      _debug('_saveLecture(): ABORT - already saving');

      return;
    }

    _debug(
      '_saveLecture(): '
      'beginning validation',
    );

    final subjectCode = _selectedSubjectCode;
    final chapter = _selectedChapter;
    final topic = _selectedTopic;
    final newChapter = _newChapter;
    _debug(
      '_saveLecture(): '
      'subjectCode=$subjectCode',
    );

    _debug(
      '_saveLecture(): '
      'newChapter=$newChapter',
    );

    _debug(
      '_saveLecture(): '
      'chapter=$chapter',
    );

    _debug(
      '_saveLecture(): '
      'topic=$topic',
    );

    _debug(
      '_saveLecture(): '
      'lectureDate=$_lectureDate',
    );

    _debug(
      '_saveLecture(): '
      'lastLecture=$_lastLecture',
    );

    if (subjectCode == null) {
      _debug('_saveLecture(): VALIDATION FAILED - subject');

      _showMessage('Please select a subject.');

      return;
    }

    if (newChapter == null) {
      _debug('_saveLecture(): VALIDATION FAILED - workflow');

      _showMessage('Please select the lecture type.');

      return;
    }

    if (chapter == null) {
      _debug('_saveLecture(): VALIDATION FAILED - chapter');

      _showMessage('Please select a chapter.');

      return;
    }

    if (topic == null) {
      _debug('_saveLecture(): VALIDATION FAILED - topic');

      _showMessage('Please select a topic.');

      return;
    }

    final chapterCode = chapter['chapterCode']?.toString() ?? '';

    final chapterName = chapter['chapterName']?.toString() ?? '';

    final topicId = topic['topicId']?.toString() ?? '';

    final topicCode = topic['topicCode']?.toString() ?? '';

    final topicName = topic['topicName']?.toString() ?? '';

    final shortNotes = _shortNotesController.text;

    _debug('_saveLecture(): extracted values');

    _debug('  subjectCode=$subjectCode');

    _debug('  chapterCode=$chapterCode');

    _debug('  chapterName=$chapterName');

    _debug('  topicId=$topicId');

    _debug('  topicCode=$topicCode');

    _debug('  topicName=$topicName');

    _debug('  lectureDate=$_lectureDate');

    _debug('  shortNotesLength=${shortNotes.length}');

    _debug('  lastLecture=$_lastLecture');

    _debug('  newChapter=$newChapter');

    if (chapterCode.isEmpty ||
        chapterName.isEmpty ||
        topicId.isEmpty ||
        topicCode.isEmpty ||
        topicName.isEmpty) {
      _debug(
        '_saveLecture(): VALIDATION FAILED - '
        'incomplete chapter/topic data',
      );

      _showMessage('Selected chapter or topic contains incomplete data.');

      return;
    }

    _debug('_saveLecture(): ALL VALIDATION PASSED');

    setState(() {
      _saving = true;
    });

    _debug(
      '_saveLecture(): '
      '_saving=true',
    );

    try {
      _debug('');
      _debug('------------------------------------------------');
      _debug('CALLING LectureService.saveLecture()');
      _debug('------------------------------------------------');

      _debug('saveLecture arguments:');

      _debug('  subjectCode=$subjectCode');

      _debug('  chapterCode=$chapterCode');

      _debug('  topicCode=$topicCode');

      _debug('  chapterName=$chapterName');

      _debug('  topicName=$topicName');

      _debug('  topicId=$topicId');

      _debug('  lectureDate=$_lectureDate');

      _debug('  shortNotesLength=${shortNotes.length}');

      _debug('  lastLecture=$_lastLecture');

      _debug('  newChapter=$newChapter');

      _debug('WAITING FOR LectureService.saveLecture()...');

      final result = await _lectureService.saveLecture(
        subjectCode: subjectCode,
        chapterCode: chapterCode,
        topicCode: topicCode,
        chapterName: chapterName,
        topicName: topicName,
        topicId: topicId,
        lectureDate: _lectureDate,
        shortNotes: shortNotes,
        lastLecture: _lastLecture,
        newChapter: newChapter,
      );

      final db = await AppDatabase.instance.database;
      _taskGenerator = TaskGeneratorLectured(
        db: db,
      );

      _debug('');
      _debug('================================================');
      _debug('LectureService.saveLecture() RETURNED');
      _debug('================================================');

      _debug('result=$result');

      _debug('result.lectureId=${result.lectureId}');

      _debug('result.completedChapter=${result.completedChapter}');

      final taskResult = await _taskGenerator.generateLectureTasks(
        lectureId: result.lectureId,
      );

      if (!mounted) {
        _debug('_saveLecture(): widget no longer mounted');

        return;
      }

      _debug('_saveLecture(): resetting recording state');

      _resetRecordingState();

      _debug('_saveLecture(): recording state reset');

      setState(() {
        _mainTabIndex = 0;
      });

      _debug(
        '_saveLecture(): '
        'changed main tab to View Lectures',
      );

      _debug(
        '_saveLecture(): '
        'calling _loadViewLectures()',
      );

      await _loadViewLectures();

      _debug(
        '_saveLecture(): '
        '_loadViewLectures() completed',
      );

      if (!mounted) {
        _debug('_saveLecture(): widget unmounted after reload');

        return;
      }

      final message = result.completedChapter
          ? 'Lecture saved for $topicName. Chapter completed.\n'
              'Tasks generated: ${taskResult.tasksCreated}'
          : 'Lecture saved for $topicName.\n'
              'Lecture ID: ${result.lectureId}\n'
              'Tasks generated: ${taskResult.tasksCreated}';

      _debug(
        '_saveLecture(): '
        'showing success message',
      );

      //_showMessage(message);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Lecture Saved'),
          content: Text(
            'Lecture saved successfully.\n\n'
            'Tasks Created: ${taskResult.tasksCreated}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      _debug('_saveLecture() SUCCESS END');
    } catch (e, stackTrace) {
      _debug('');
      _debug('================================================');
      _debug('LectureService.saveLecture() THREW EXCEPTION');
      _debug('================================================');

      _debug('EXCEPTION=$e');

      _debug('STACK TRACE=$stackTrace');

      if (!mounted) {
        return;
      }

      _showMessage('Unable to save lecture: $e');
    } finally {
      _debug('_saveLecture(): entering finally');

      if (mounted) {
        setState(() {
          _saving = false;
        });

        _debug(
          '_saveLecture(): '
          '_saving=false',
        );
      }

      _debug('_saveLecture() FINALLY END');

      _debug('================================================');
    }
  }

  // ---------------------------------------------------------------------------
  // CANCEL
  // ---------------------------------------------------------------------------

  void _cancelRecording() {
    _debug('_cancelRecording() START');

    if (_saving) {
      _debug('_cancelRecording(): ABORT - saving');

      return;
    }

    _resetRecordingState();

    setState(() {
      _mainTabIndex = 0;
    });

    _debug(
      '_cancelRecording(): '
      'loading view lectures',
    );

    _loadViewLectures();

    _showMessage('Lecture recording cancelled.');

    _debug('_cancelRecording() END');
  }

  void _resetRecordingState() {
    _debug('_resetRecordingState() START');

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

    _debug('_resetRecordingState() END');
  }

  // ===========================================================================
  // VIEW LECTURES
  // ===========================================================================

  Future<void> _loadViewLectures() async {
    _debug('_loadViewLectures() START');

    setState(() {
      _viewLoading = true;
    });

    _debug(
      '_loadViewLectures(): '
      '_viewLoading=true',
    );

    try {
      List<Map<String, Object?>> lectures;

      if (_viewMode == 0) {
        _debug(
          '_loadViewLectures(): '
          'mode=Date-Wise',
        );

        lectures = await _lectureEnquiryService.getThisWeekLectures();
      } else if (_viewMode == 1) {
        _debug(
          '_loadViewLectures(): '
          'mode=Subject-Wise / Physics',
        );

        lectures = await _lectureEnquiryService.getPhysicsLectures();
      } else {
        _debug(
          '_loadViewLectures(): '
          'mode=All Lectures',
        );

        lectures = await _lectureEnquiryService.getAllLectures();
      }

      _debug(
        '_loadViewLectures(): '
        'received ${lectures.length} lectures',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _viewLectures = lectures;

        _viewLoading = false;

        _expandedViewGroups.clear();

        _expandedViewLectures.clear();
      });

      _debug('_loadViewLectures() END');
    } catch (e, stackTrace) {
      _debug('_loadViewLectures(): EXCEPTION=$e');

      _debug('_loadViewLectures(): STACK=$stackTrace');

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
    _debug(
      '_selectViewMode(): '
      'old=$_viewMode, new=$mode',
    );

    setState(() {
      _viewMode = mode;
    });

    await _loadViewLectures();
  }

  // ---------------------------------------------------------------------------
  // VIEW MODE DATA
  // ---------------------------------------------------------------------------

  Future<List<Map<String, Object?>>> _loadDateLectures(int index) {
    _debug('_loadDateLectures(): index=$index');

    if (index == 0) {
      return _lectureEnquiryService.getThisWeekLectures();
    }

    if (index == 1) {
      return _lectureEnquiryService.getLastTwoWeeksLectures();
    }

    return _lectureEnquiryService.getThisMonthLectures();
  }

  Future<List<Map<String, Object?>>> _loadSubjectLectures(String subjectCode) {
    _debug(
      '_loadSubjectLectures(): '
      'subjectCode=$subjectCode',
    );

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
            _debug(
              '_buildCollapsiblePeriod onTap: '
              'key=$keyName, '
              'expanded=$expanded',
            );

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
                _debug(
                  'Loading collapsed section: '
                  '$keyName',
                );

                final rows = await loader();

                _debug(
                  'Collapsed section returned '
                  '${rows.length} rows',
                );

                if (!mounted) {
                  return;
                }

                setState(() {
                  _viewLectures = rows;
                });
              } catch (e, stackTrace) {
                _debug('Collapsed section ERROR=$e');

                _debug('Collapsed section STACK=$stackTrace');

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
                _debug(
                  'Lecture group tapped: '
                  '$key',
                );

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
      color:
          selected ? Theme.of(context).colorScheme.surface : Colors.transparent,
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
    _debug(
      '_selectChapterByCode(): '
      'code=$code',
    );

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
    _debug(
      '_selectTopicByCode(): '
      'code=$code',
    );

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

                _debug(
                  'Last Lecture toggled: '
                  '$_lastLecture',
                );
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

                        _debug(
                          'Last Lecture switch: '
                          '$value',
                        );
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
            _debug('Return to Record Lecture clicked');

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

    final subject = first['subjectName']?.toString() ??
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
    _debug('SnackBar: $message');

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }
}
