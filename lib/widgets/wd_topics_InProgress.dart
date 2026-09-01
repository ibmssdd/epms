import 'package:flutter/material.dart';

import '../services/svc_status_topics.dart';

class CurrentTopicsWidget extends StatefulWidget {
  const CurrentTopicsWidget({
    super.key,
  });

  @override
  State<CurrentTopicsWidget> createState() => _CurrentTopicsWidgetState();
}

class _CurrentTopicsWidgetState extends State<CurrentTopicsWidget> {
  static const Color gold = Color(0xFFD4AF37);

  List<Map<String, Object?>> _topics = [];

  bool _loading = true;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadCurrentTopics();
  }

  // ============================================================
  // LOAD CURRENT TOPICS
  // ============================================================

  Future<void> _loadCurrentTopics() async {
    try {
      final pending =
      await StatusTopicService.instance.getPendingTopics();

      final inProgress =
      await StatusTopicService.instance.getInProgressTopics();

      final topics = <Map<String, Object?>>[
        ...pending,
        ...inProgress,
      ];

      topics.sort(
            (a, b) => (a['TopicID']?.toString() ?? '')
            .compareTo(b['TopicID']?.toString() ?? ''),
      );

      if (!mounted) return;

      setState(() {
        _topics = topics;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _topics = [];
        _loading = false;
      });
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1C1C1C),
            Color(0xFF0B0B0B),
          ],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: gold.withValues(alpha: .22),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 6),
          _buildContent(),
        ],
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return const Text(
      'CURRENT TOPICS',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: gold,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
      ),
    );
  }

  // ============================================================
  // CONTENT
  // ============================================================

  Widget _buildContent() {
    if (_loading) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    if (_topics.isEmpty) {
      return Text(
        'No current topics found.',
        style: TextStyle(
          color: Colors.white.withValues(alpha: .55),
          fontSize: 9.5,
        ),
      );
    }

    final grouped =
    <String, Map<String, List<Map<String, Object?>>>>{};

    for (final topic in _topics) {
      final topicId =
          topic['TopicID']?.toString().trim() ?? '';

      final chapterName =
          topic['TopicChapterName']?.toString().trim() ?? '';

      if (topicId.isEmpty) {
        continue;
      }

      final parts = topicId.split('-');

      if (parts.length < 3) {
        continue;
      }

      final subjectCode = parts[0];

      final subjectName =
      _subjectName(subjectCode);

      final cleanChapterName = chapterName.isNotEmpty
          ? chapterName
          : parts[1];

      grouped.putIfAbsent(
        subjectName,
            () => {},
      );

      grouped[subjectName]!.putIfAbsent(
        cleanChapterName,
            () => [],
      );

      grouped[subjectName]![cleanChapterName]!
          .add(topic);
    }

    final subjectOrder = <String>[
      'Physics',
      'Chemistry',
      'Biology',
    ];

    final children = <Widget>[];

    for (final subject in subjectOrder) {
      final chapters = grouped[subject];

      if (chapters == null || chapters.isEmpty) {
        continue;
      }

      children.add(
        _buildSubject(
          subject,
          chapters,
        ),
      );

      children.add(
        const SizedBox(height: 8),
      );
    }

    for (final entry in grouped.entries) {
      if (subjectOrder.contains(entry.key)) {
        continue;
      }

      children.add(
        _buildSubject(
          entry.key,
          entry.value,
        ),
      );

      children.add(
        const SizedBox(height: 8),
      );
    }

    if (children.isNotEmpty) {
      children.removeLast();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // ============================================================
  // SUBJECT
  // ============================================================

  Widget _buildSubject(
      String subject,
      Map<String, List<Map<String, Object?>>> chapters,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subject,
          style: const TextStyle(
            color: gold,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 4),

        ...chapters.entries.map(
              (entry) => _buildChapter(
            entry.key,
            entry.value,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CHAPTER
  // ============================================================

  Widget _buildChapter(
      String chapterName,
      List<Map<String, Object?>> topics,
      ) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 7,
        bottom: 5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chapterName,
            softWrap: true,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 2),

          ...topics.map(
            _buildTopic,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TOPIC
  // ============================================================

  Widget _buildTopic(
      Map<String, Object?> topic,
      ) {
    const gold = Color(0xFFD4AF37);

    final topicName =
        topic['TopicName']?.toString().trim() ?? '';

    final topicState =
        topic['TopicState']?.toString().trim() ?? '';

    if (topicName.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(
        left: 7,
        top: 1.5,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              color: gold.withValues(alpha: .75),
              fontSize: 9,
            ),
          ),

          Expanded(
            child: Text(
              topicName,
              softWrap: true,
              style: TextStyle(
                color: topicState == 'InProgress'
                    ? Colors.white
                    : Colors.white.withValues(alpha: .58),
                fontSize: 9,
                fontWeight: topicState == 'InProgress'
                    ? FontWeight.w600
                    : FontWeight.w400,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUBJECT NAME
  // ============================================================

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
}