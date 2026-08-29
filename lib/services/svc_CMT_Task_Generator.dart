import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// CMT Task Generator
///
/// Generation hierarchy:
///
///   db_Milestones
///        │
///        ├── PHY
///        │     └── CMT Rule
///        │            └── MT_Subject_Code + MT_Type
///        │                   └── partial SubjectTaskID lookup
///        │                          └── db_SubjectTasks
///        │                                 └── SubjectTaskActivities
///        │                                        └── db_Activities
///        │
///        ├── CHEM
///        │     └── same flow
///        │
///        ├── BIO
///        │     └── same flow
///        │
///        └── PCB
///              └── PCB_CMT_TEST
///                     └── SubjectTaskActivities
///                            └── db_Activities
///
/// Subject task lookup:
///
///   MT_Subject_Code + MT_Type
///              ↓
///       partial SubjectTaskID
///              ↓
///       LIKE 'PHY_CMT_%'
///       LIKE 'CHE_CMT_%'
///       LIKE 'BIO_CMT_%'
///
/// Created task data:
///   db_TaskLogWeekEnd
///   db_TaskActivityStatus
///
/// Return value:
///   {
///     'PHY':  <number of PHY tasks created/present>,
///     'CHEM': <number of CHEM tasks created/present>,
///     'BIO':  <number of BIO tasks created/present>,
///     'PCB':  <number of PCB tasks created/present>,
///   }
class CmtTaskGenerator {
CmtTaskGenerator({
required Database db,
DateTime Function()? now,
})  : _db = db,
_now = now ?? DateTime.now;

final Database _db;
final DateTime Function() _now;

// ---------------------------------------------------------------------------
// TABLES
// ---------------------------------------------------------------------------

static const String _milestoneTable =
'db_Milestones';

static const String _ruleTable =
'db_Milestones_TC_Rules';

static const String _subjectTaskTable =
'db_SubjectTasks';

static const String _subjectTaskActivityTable =
'db_SubjectTaskActivities';

static const String _activityTable =
'db_Activities';

static const String _taskLogTable =
'db_TaskLogWeekEnd';

static const String _taskActivityStatusTable =
'db_TaskActivityStatus';

// ---------------------------------------------------------------------------
// MILESTONE COLUMNS
// ---------------------------------------------------------------------------

static const String _milestoneDateColumn =
'milestone_date';

static const String _milestoneTypeColumn =
'milestone_type';

static const String _phyColumn =
'milestone_phy_chapters';

static const String _chemColumn =
'milestone_chem_chapters';

static const String _bioColumn =
'milestone_bio_chapters';

// Task-created flags.

static const String _phyTaskCreatedColumn =
'milestone_phy_task_created';

static const String _chemTaskCreatedColumn =
'milestone_chem_task_created';

static const String _bioTaskCreatedColumn =
'milestone_bio_task_created';

static const String _commonTasksCreatedColumn =
'milestone_common_tasks_created';

// ---------------------------------------------------------------------------
// TASK CREATION RULE COLUMNS
// ---------------------------------------------------------------------------

static const String _ruleIdColumn =
'MT_Rule_ID';

static const String _ruleActiveColumn =
'MT_Rule_IsActive';

static const String _ruleTypeColumn =
'MT_Type';

static const String _ruleSubjectColumn =
'MT_Subject_Code';

static const String _ruleDescriptionColumn =
'MT_Rule_Description';

// NOTE:
// MT_Task_Code is intentionally NOT used by this CMT generator.
//
// SubjectTasks are located using:
//
//     MT_Subject_Code + MT_Type
//
// which forms a partial SubjectTaskID such as:
//
//     PHY_CMT_
//     CHE_CMT_
//     BIO_CMT_

// ---------------------------------------------------------------------------
// SUBJECT TASK COLUMNS
// ---------------------------------------------------------------------------

static const String _subjectTaskIdColumn =
'SubjectTaskID';

static const String _subjectTaskNameColumn =
'SubjectTaskName';

static const String _subjectTaskActiveColumn =
'SubjectTaskIsActive';

static const String _subjectTaskDurationColumn =
'SubjectTaskDurationMinutes';

// ---------------------------------------------------------------------------
// PCB CONFIGURATION
// ---------------------------------------------------------------------------

/// Existing milestone-level SubjectTask.
static const String _pcbSubjectTaskId =
'PCB_CMT_TEST';

// ---------------------------------------------------------------------------
// PUBLIC METHOD
// ---------------------------------------------------------------------------

/// Generates all CMT tasks for [milestoneDate].
///
/// PHY/CHEM/BIO:
///   - Requires milestone chapter scope.
///   - Finds the active CMT rule for that subject.
///   - Builds a partial SubjectTaskID from:
///
///         MT_Subject_Code + MT_Type
///
///   - Finds all matching active SubjectTasks.
///   - Creates/checks a task for each matching SubjectTask.
///
/// PCB:
///   - Is milestone-level.
///   - Does not require chapter scope.
///   - Uses PCB_CMT_TEST.
Future<Map<String, int>> generateCmtTasks({
DateTime? milestoneDate,
}) async {
final date = _dateOnly(
milestoneDate ?? _now(),
);

debugPrint('');
debugPrint('================================================');
debugPrint('          CMT TASK GENERATION START');
debugPrint('================================================');
debugPrint(
'Milestone Date : ${_formatDate(date)}',
);
debugPrint('Milestone Type : CMT');

if (date.weekday != DateTime.sunday) {
throw ArgumentError(
'CMT task generation requires a Sunday milestone date.',
);
}

final milestone = await _getCmtMilestone(
date,
);

if (milestone == null) {
debugPrint(
'CMT milestone NOT FOUND.',
);

return const {
'PHY': 0,
'CHEM': 0,
'BIO': 0,
'PCB': 0,
};
}

debugPrint(
'CMT milestone found.',
);

final results = <String, int>{
'PHY': 0,
'CHEM': 0,
'BIO': 0,
'PCB': 0,
};

// -----------------------------------------------------------------------
// 1. SUBJECT TASKS
// -----------------------------------------------------------------------

results['PHY'] = await _processSubject(
milestone: milestone,
subjectCode: 'PHY',
);

results['CHEM'] = await _processSubject(
milestone: milestone,
subjectCode: 'CHEM',
);

results['BIO'] = await _processSubject(
milestone: milestone,
subjectCode: 'BIO',
);

// -----------------------------------------------------------------------
// 2. COMMON / PCB TASKS
// -----------------------------------------------------------------------

results['PCB'] = await _processCommonTasks(
milestone: milestone,
milestoneDate: date,
);

// -----------------------------------------------------------------------
// END
// -----------------------------------------------------------------------

debugPrint('');
debugPrint('================================================');
debugPrint('          CMT TASK GENERATION END');
debugPrint('================================================');
debugPrint(
'PHY  : ${results['PHY']}',
);
debugPrint(
'CHEM : ${results['CHEM']}',
);
debugPrint(
'BIO  : ${results['BIO']}',
);
debugPrint(
'PCB  : ${results['PCB']}',
);

return results;
}

// ---------------------------------------------------------------------------
// SUBJECT PROCESSING
// ---------------------------------------------------------------------------

Future<int> _processSubject({
required Map<String, Object?> milestone,
required String subjectCode,
}) async {
debugPrint('');
debugPrint('------------------------------------------------');
debugPrint(
'PROCESSING SUBJECT: $subjectCode',
);
debugPrint('------------------------------------------------');

// -----------------------------------------------------------------------
// 1. READ MILESTONE CHAPTER SCOPE
// -----------------------------------------------------------------------

final chapters = _milestoneScope(
milestone,
subjectCode,
);

debugPrint(
'Selected chapters: $chapters',
);

if (chapters.isEmpty) {
debugPrint(
'$subjectCode: no chapter scope. Result = 0',
);

return 0;
}

// -----------------------------------------------------------------------
// 2. FIND ACTIVE CMT RULE
// -----------------------------------------------------------------------

final rules = await _getCmtRulesForSubject(
subjectCode,
);

debugPrint(
'Active rules found: ${rules.length}',
);

if (rules.isEmpty) {
debugPrint(
'$subjectCode: no active task creation rules. Result = 0',
);

return 0;
}

var taskCount = 0;

// -----------------------------------------------------------------------
// 3. PROCESS EACH RULE
// -----------------------------------------------------------------------

for (final rule in rules) {
final ruleId = _string(
rule[_ruleIdColumn],
);

if (ruleId == null) {
debugPrint(
'$subjectCode: rule skipped because '
'$_ruleIdColumn is missing.',
);

continue;
}

final ruleDescription = _string(
rule[_ruleDescriptionColumn],
);

final ruleSubjectCode = _string(
rule[_ruleSubjectColumn],
);

final ruleType = _string(
rule[_ruleTypeColumn],
);

debugPrint('');
debugPrint('==============================================');
debugPrint(
'$subjectCode CMT RULE',
);
debugPrint(
'Rule ID          : $ruleId',
);
debugPrint(
'Rule Description : '
'${ruleDescription ?? '(none)'}',
);
debugPrint(
'MT_Subject_Code  : '
'${ruleSubjectCode ?? '(none)'}',
);
debugPrint(
'MT_Type          : '
'${ruleType ?? '(none)'}',
);
debugPrint('==============================================');

// ---------------------------------------------------------------------
// MT_Subject_Code + MT_Type form the partial SubjectTaskID.
//
// Example:
//
//     PHY + CMT  -> PHY_CMT_
//     CHE + CMT  -> CHE_CMT_
//     BIO + CMT  -> BIO_CMT_
//
// MT_Task_Code is intentionally NOT used.
// ---------------------------------------------------------------------

if (ruleSubjectCode == null ||
ruleType == null) {
debugPrint(
'$subjectCode: rule is missing '
'MT_Subject_Code or MT_Type. Rule skipped.',
);

continue;
}

final partialKey =
'${ruleSubjectCode}_'
'${ruleType}_';

debugPrint(
'SubjectTask partial key: $partialKey',
);

final subjectTasks =
await _getSubjectTasksByPartialKey(
partialKey,
);

if (subjectTasks.isEmpty) {
debugPrint(
'$subjectCode: no active SubjectTasks found '
'for partial key $partialKey',
);

continue;
}

// ---------------------------------------------------------------------
// 4. CREATE A TASK FOR EACH MATCHING SUBJECT TASK
// ---------------------------------------------------------------------

debugPrint(
'$subjectCode: processing '
'${subjectTasks.length} matching SubjectTask(s).',
);

for (final subjectTask in subjectTasks) {
final subjectTaskId = _string(
subjectTask[_subjectTaskIdColumn],
);

debugPrint(
'Processing SubjectTask: '
'${subjectTaskId ?? '(missing ID)'}',
);

final created =
await _createTaskFromSubjectTask(
subjectTask: subjectTask,
rule: rule,
milestone: milestone,
milestoneDate: _parseMilestoneDate(
milestone,
),
chapterCodes: chapters,
);

if (created) {
taskCount++;
}
}
}

// -----------------------------------------------------------------------
// 5. MARK SUBJECT TASKS CREATED
// -----------------------------------------------------------------------

if (taskCount > 0) {
await _markSubjectTasksCreated(
subjectCode: subjectCode,
milestone: milestone,
);
}

debugPrint(
'$subjectCode RESULT = '
'$taskCount (CREATED/PRESENT)',
);

return taskCount;
}

// ---------------------------------------------------------------------------
// COMMON / PCB PROCESSING
// ---------------------------------------------------------------------------

Future<int> _processCommonTasks({
required Map<String, Object?> milestone,
required DateTime milestoneDate,
}) async {
debugPrint('');
debugPrint('------------------------------------------------');
debugPrint('PROCESSING COMMON TASKS: PCB');
debugPrint('------------------------------------------------');

debugPrint(
'PCB is milestone-level and does not require chapter scope.',
);

final subjectTask =
await _getSubjectTaskById(
_pcbSubjectTaskId,
);

if (subjectTask == null) {
debugPrint(
'PCB SubjectTask NOT FOUND or inactive: '
'$_pcbSubjectTaskId',
);

return 0;
}

debugPrint('');
debugPrint('==============================================');
debugPrint('PCB SUBJECT TASK');
debugPrint(
'SubjectTaskID   : '
'${subjectTask[_subjectTaskIdColumn]}',
);
debugPrint(
'SubjectTaskName : '
'${subjectTask[_subjectTaskNameColumn]}',
);
debugPrint('==============================================');

final activities =
await _getActivitiesForSubjectTask(
_pcbSubjectTaskId,
);

debugPrint(
'SubjectTaskActivity rows: '
'${activities.length}',
);

if (activities.isEmpty) {
debugPrint(
'PCB has no active activities.',
);

return 0;
}

final taskDescription =
_string(
subjectTask[_subjectTaskNameColumn],
) ??
_pcbSubjectTaskId;

final taskId = _buildTaskId(
milestoneDate: milestoneDate,
ruleId: 'PCB',
subjectTaskId: _pcbSubjectTaskId,
);

debugPrint('PCB TaskDescription:');
debugPrint(taskDescription);

debugPrint('');
debugPrint('PCB Activities:');

for (var i = 0; i < activities.length; i++) {
final activityId = _string(
activities[i]['ActivityID'],
);

final activityDescription =
_activityDescription(
activities[i],
);

debugPrint(
'${i + 1}. '
'$activityId - '
'$activityDescription',
);
}

final duration = _taskDuration(
subjectTask,
activities,
);

debugPrint('');
debugPrint(
'PCB TaskID: $taskId',
);
debugPrint(
'PCB Duration: $duration minutes',
);

final result =
await _createTaskAndActivityStatus(
taskId: taskId,
taskDescription: taskDescription,
dueDate: milestoneDate,
durationMinutes: duration,
activities: activities,
);

if (result) {
await _markCommonTasksCreated(
milestone: milestone,
);

debugPrint(
'PCB/common milestone task-created flag = 1',
);

debugPrint(
'PCB RESULT = 1 (CREATED/PRESENT)',
);

return 1;
}

return 0;
}

// ---------------------------------------------------------------------------
// SUBJECT TASK CREATION
// ---------------------------------------------------------------------------

Future<bool> _createTaskFromSubjectTask({
required Map<String, Object?> subjectTask,
required Map<String, Object?> rule,
required Map<String, Object?> milestone,
required DateTime milestoneDate,
required List<String> chapterCodes,
}) async {
final subjectTaskId =
_string(
subjectTask[_subjectTaskIdColumn],
);

if (subjectTaskId == null) {
debugPrint(
'SubjectTask skipped because '
'$_subjectTaskIdColumn is missing.',
);

return false;
}

final subjectTaskName =
_string(
subjectTask[_subjectTaskNameColumn],
) ??
subjectTaskId;

final ruleId =
_string(
rule[_ruleIdColumn],
) ??
'0';

final ruleSubjectCode =
_string(
rule[_ruleSubjectColumn],
);

final ruleType =
_string(
rule[_ruleTypeColumn],
);

debugPrint('');
debugPrint('==============================================');
debugPrint('SUBJECT TASK');
debugPrint(
'SubjectTaskID   : $subjectTaskId',
);
debugPrint(
'SubjectTaskName : $subjectTaskName',
);
debugPrint(
'RuleID          : $ruleId',
);
debugPrint(
'MT_Subject_Code : '
'${ruleSubjectCode ?? '(none)'}',
);
debugPrint(
'MT_Type         : '
'${ruleType ?? '(none)'}',
);
debugPrint('==============================================');

// -----------------------------------------------------------------------
// ACTIVITIES
// -----------------------------------------------------------------------

final activities =
await _getActivitiesForSubjectTask(
subjectTaskId,
);

debugPrint(
'SubjectTaskActivity rows: '
'${activities.length}',
);

if (activities.isEmpty) {
debugPrint(
'No active activities for $subjectTaskId',
);

return false;
}

debugPrint('');
debugPrint('Activities:');

for (var i = 0; i < activities.length; i++) {
final activityId =
_string(
activities[i]['ActivityID'],
);

final activityDescription =
_activityDescription(
activities[i],
);

debugPrint(
'${i + 1}. '
'$activityId - '
'$activityDescription',
);
}

// -----------------------------------------------------------------------
// DESCRIPTION
// -----------------------------------------------------------------------

final taskDescription =
subjectTaskName;

debugPrint('');
debugPrint('Final TaskDescription:');
debugPrint(taskDescription);

// -----------------------------------------------------------------------
// SCOPE
// -----------------------------------------------------------------------

debugPrint('');
debugPrint(
'Scope: ${chapterCodes.join(', ')}',
);

// -----------------------------------------------------------------------
// DURATION
// -----------------------------------------------------------------------

final duration = _taskDuration(
subjectTask,
activities,
);

// -----------------------------------------------------------------------
// TASK ID
// -----------------------------------------------------------------------

final taskId = _buildTaskId(
milestoneDate: milestoneDate,
ruleId: ruleId,
subjectTaskId: subjectTaskId,
);

debugPrint(
'TaskID: $taskId',
);

// -----------------------------------------------------------------------
// CREATE
// -----------------------------------------------------------------------

final result =
await _createTaskAndActivityStatus(
taskId: taskId,
taskDescription: taskDescription,
dueDate: milestoneDate,
durationMinutes: duration,
activities: activities,
);

if (result) {
debugPrint(
'Task + activity status created/present: '
'$taskId',
);
}

return result;
}

// ---------------------------------------------------------------------------
// TASK + ACTIVITY STATUS INSERT
// ---------------------------------------------------------------------------

Future<bool> _createTaskAndActivityStatus({
required String taskId,
required String taskDescription,
required DateTime dueDate,
required int durationMinutes,
required List<Map<String, Object?>> activities,
}) async {
debugPrint('');
debugPrint(
'CREATE TASK: $taskId',
);

// -----------------------------------------------------------------------
// TASK LOG
// -----------------------------------------------------------------------

final existingTask = await _db.query(
_taskLogTable,
columns: const [
'TaskID',
],
where: 'TaskID = ?',
whereArgs: [
taskId,
],
limit: 1,
);

final alreadyExists =
existingTask.isNotEmpty;

if (!alreadyExists) {
await _db.insert(
_taskLogTable,
<String, Object?>{
'TaskID': taskId,
'TaskDescription': taskDescription,
'TaskDueDate': _formatDate(dueDate),
'TaskStartTime': null,
'TaskDurationMinutes': durationMinutes,
'TaskCalendarEventID': null,
'TaskReminderMinutes': null,
'TaskStatus': 'PENDING',
},
conflictAlgorithm:
ConflictAlgorithm.ignore,
);

debugPrint(
'TaskLog inserted: $taskId',
);
} else {
debugPrint(
'Task already exists: $taskId',
);
}

// -----------------------------------------------------------------------
// ACTIVITY STATUS JSON
// -----------------------------------------------------------------------

final activityStatus =
<String, bool>{};

for (final activity in activities) {
final activityId =
_string(
activity['ActivityID'],
);

if (activityId == null) {
continue;
}

activityStatus[activityId] = false;
}

final activityStatusJson =
jsonEncode(activityStatus);

debugPrint(
'ActivityStatusJSON: '
'$activityStatusJson',
);

// -----------------------------------------------------------------------
// ACTIVITY STATUS TABLE
// -----------------------------------------------------------------------

final existingStatus =
await _db.query(
_taskActivityStatusTable,
columns: const [
'TaskID',
],
where: 'TaskID = ?',
whereArgs: [
taskId,
],
limit: 1,
);

if (existingStatus.isEmpty) {
await _db.insert(
_taskActivityStatusTable,
<String, Object?>{
'TaskID': taskId,
'ActivityStatusJSON':
activityStatusJson,
'TaskActivityUpdatedDate':
_now().toIso8601String(),
},
conflictAlgorithm:
ConflictAlgorithm.ignore,
);

debugPrint(
'Activity status inserted: $taskId',
);
} else {
debugPrint(
'Activity status already exists: $taskId',
);
}

return true;
}

// ---------------------------------------------------------------------------
// RULE LOOKUP
// ---------------------------------------------------------------------------

/// Returns active CMT rules for a specific subject.
///
/// The rule itself does NOT provide the SubjectTask directly.
///
/// The rule provides:
///
///   MT_Subject_Code
///   MT_Type
///
/// These are later combined to create the partial SubjectTaskID.
///
/// Example:
///
///   MT_Subject_Code = PHY
///   MT_Type         = CMT
///
/// produces:
///
///   PHY_CMT_
///
/// Active rule value:
///
///   MT_Rule_IsActive = 1
Future<List<Map<String, Object?>>> _getCmtRulesForSubject(
String subjectCode,
) async {
final normalizedSubject =
_normalizeSubjectCode(
subjectCode,
);

debugPrint('');
debugPrint(
'RULE LOOKUP: $normalizedSubject',
);

final rows = await _db.query(
_ruleTable,
where:
'$_ruleActiveColumn = ? '
'AND $_ruleTypeColumn = ?',
whereArgs: [
1,
'CMT',
],
orderBy:
'$_ruleIdColumn ASC',
);

debugPrint(
'Total active CMT rule rows: '
'${rows.length}',
);

final result =
<Map<String, Object?>>[];

for (final row in rows) {
final ruleId =
_string(
row[_ruleIdColumn],
);

final ruleSubject =
_string(
row[_ruleSubjectColumn],
)?.toUpperCase();

final normalizedRuleSubject =
ruleSubject == null
? null
    : _normalizeSubjectCode(
ruleSubject,
);

final ruleType =
_string(
row[_ruleTypeColumn],
);

final description =
_string(
row[_ruleDescriptionColumn],
);

debugPrint(
'Rule candidate: '
'ID=$ruleId, '
'Subject=$ruleSubject, '
'Type=$ruleType',
);

// ---------------------------------------------------------------------
// Subject-specific rule
// ---------------------------------------------------------------------

if (normalizedRuleSubject ==
normalizedSubject) {
debugPrint(
'  -> MATCHED $normalizedSubject',
);

result.add(row);
continue;
}

// ---------------------------------------------------------------------
// Ignore other subjects and PCB here.
// ---------------------------------------------------------------------

debugPrint(
'  -> ignored',
);

if (description != null) {
debugPrint(
'     Description: $description',
);
}
}

return result;
}

// ---------------------------------------------------------------------------
// SUBJECT TASK LOOKUP BY PARTIAL KEY
// ---------------------------------------------------------------------------

/// Finds all active SubjectTasks whose SubjectTaskID begins with
/// [partialKey].
///
/// Example:
///
///   partialKey = PHY_CMT_
///
/// executes the equivalent of:
///
///   SubjectTaskID LIKE 'PHY_CMT_%'
///
/// This intentionally replaces the old exact MT_Task_Code lookup.
Future<List<Map<String, Object?>>>
_getSubjectTasksByPartialKey(
String partialKey,
) async {
debugPrint(
'Looking up SubjectTasks with partial key: '
'$partialKey',
);

final rows = await _db.query(
_subjectTaskTable,
where:
'$_subjectTaskIdColumn LIKE ? '
'AND $_subjectTaskActiveColumn = ?',
whereArgs: [
'$partialKey%',
'Yes',
],
orderBy:
'$_subjectTaskIdColumn ASC',
);

debugPrint(
'SubjectTasks found: ${rows.length}',
);

for (final row in rows) {
debugPrint(
'  SubjectTask: '
'${row[_subjectTaskIdColumn]}',
);
}

return rows;
}

// ---------------------------------------------------------------------------
// SUBJECT TASK LOOKUP BY ID
// ---------------------------------------------------------------------------

Future<Map<String, Object?>?> _getSubjectTaskById(
String subjectTaskId,
) async {
final rows = await _db.query(
_subjectTaskTable,
where:
'$_subjectTaskIdColumn = ? '
'AND $_subjectTaskActiveColumn = ?',
whereArgs: [
subjectTaskId,
'Yes',
],
limit: 1,
);

if (rows.isEmpty) {
return null;
}

return rows.first;
}

// ---------------------------------------------------------------------------
// SUBJECT TASK ACTIVITIES + db_ACTIVITIES
// ---------------------------------------------------------------------------

Future<List<Map<String, Object?>>>
_getActivitiesForSubjectTask(
String subjectTaskId,
) async {
final links = await _db.query(
_subjectTaskActivityTable,
where: 'SubjectTaskID = ?',
whereArgs: [
subjectTaskId,
],
orderBy:
'ActivitySequence ASC',
);

final result =
<Map<String, Object?>>[];

for (final link in links) {
final activityId =
_string(
link['ActivityID'],
);

if (activityId == null) {
continue;
}

final activityRows =
await _db.query(
_activityTable,
where:
'ActivityID = ? '
'AND IsActive = ?',
whereArgs: [
activityId,
'Yes',
],
limit: 1,
);

if (activityRows.isEmpty) {
debugPrint(
'Activity inactive/not found: '
'$activityId',
);

continue;
}

result.add(
<String, Object?>{
...link,
...activityRows.first,
},
);
}

return result;
}

// ---------------------------------------------------------------------------
// DURATION
// ---------------------------------------------------------------------------

int _taskDuration(
Map<String, Object?> subjectTask,
List<Map<String, Object?>> activities,
) {
final configured =
_int(
subjectTask[
_subjectTaskDurationColumn
],
);

if (configured != null) {
return configured;
}

return activities.fold<int>(
0,
(sum, row) =>
sum +
(_int(
row['ActivityDurationMinutes'],
) ??
0),
);
}

// ---------------------------------------------------------------------------
// MILESTONE LOOKUP
// ---------------------------------------------------------------------------

Future<Map<String, Object?>?> _getCmtMilestone(
DateTime date,
) async {
final rows = await _db.query(
_milestoneTable,
where:
'$_milestoneTypeColumn = ? '
'AND $_milestoneDateColumn = ?',
whereArgs: [
'CMT',
_formatDate(date),
],
limit: 1,
);

return rows.isEmpty
? null
    : rows.first;
}

// ---------------------------------------------------------------------------
// MILESTONE CHAPTER SCOPE
// ---------------------------------------------------------------------------

List<String> _milestoneScope(
Map<String, Object?> milestone,
String subjectCode,
) {
final column = switch (subjectCode) {
'PHY' => _phyColumn,
'CHEM' => _chemColumn,
'BIO' => _bioColumn,
_ => null,
};

if (column == null) {
return const [];
}

return _splitCodes(
milestone[column]?.toString(),
);
}

// ---------------------------------------------------------------------------
// MARK SUBJECT TASKS CREATED
// ---------------------------------------------------------------------------

Future<void> _markSubjectTasksCreated({
required String subjectCode,
required Map<String, Object?> milestone,
}) async {
final column = switch (subjectCode) {
'PHY' => _phyTaskCreatedColumn,
'CHEM' => _chemTaskCreatedColumn,
'BIO' => _bioTaskCreatedColumn,
_ => null,
};

if (column == null) {
return;
}

await _db.update(
_milestoneTable,
{
column: 1,
},
where:
'$_milestoneTypeColumn = ? '
'AND $_milestoneDateColumn = ?',
whereArgs: [
milestone[
_milestoneTypeColumn
],
milestone[
_milestoneDateColumn
],
],
);

debugPrint(
'$subjectCode milestone '
'task-created flag = 1',
);
}

// ---------------------------------------------------------------------------
// MARK COMMON / PCB TASKS CREATED
// ---------------------------------------------------------------------------

Future<void> _markCommonTasksCreated({
required Map<String, Object?> milestone,
}) async {
await _db.update(
_milestoneTable,
{
_commonTasksCreatedColumn: 1,
},
where:
'$_milestoneTypeColumn = ? '
'AND $_milestoneDateColumn = ?',
whereArgs: [
milestone[
_milestoneTypeColumn
],
milestone[
_milestoneDateColumn
],
],
);

debugPrint(
'PCB/common milestone '
'task-created flag = 1',
);
}

// ---------------------------------------------------------------------------
// TASK ID
// ---------------------------------------------------------------------------

String _buildTaskId({
required DateTime milestoneDate,
required String ruleId,
required String subjectTaskId,
}) {
return 'MT_${_compactDate(milestoneDate)}_'
'${ruleId}_'
'$subjectTaskId';
}

// ---------------------------------------------------------------------------
// ACTIVITY DESCRIPTION
// ---------------------------------------------------------------------------

String _activityDescription(
Map<String, Object?> activity,
) {
return _string(
activity['ActivityDescription'],
) ??
_string(
activity['ActivityName'],
) ??
_string(
activity['ActivityID'],
) ??
'Activity';
}

// ---------------------------------------------------------------------------
// SUBJECT CODE NORMALIZATION
// ---------------------------------------------------------------------------

String _normalizeSubjectCode(
String value,
) {
final code =
value.trim().toUpperCase();

switch (code) {
case 'PHYSICS':
case 'PHY':
return 'PHY';

case 'CHEMISTRY':
case 'CHEM':
case 'CHE':
case 'BHEM':
return 'CHEM';

case 'BIOLOGY':
case 'BIO':
return 'BIO';

case 'PCB':
return 'PCB';

default:
return code;
}
}

// ---------------------------------------------------------------------------
// DATE HELPERS
// ---------------------------------------------------------------------------

DateTime _parseMilestoneDate(
Map<String, Object?> milestone,
) {
final value =
_string(
milestone[
_milestoneDateColumn
],
);

if (value == null) {
throw StateError(
'Milestone date is missing.',
);
}

return DateTime.parse(value);
}

static DateTime _dateOnly(
DateTime date,
) {
return DateTime(
date.year,
date.month,
date.day,
);
}

static String _formatDate(
DateTime date,
) {
final month =
date.month
    .toString()
    .padLeft(2, '0');

final day =
date.day
    .toString()
    .padLeft(2, '0');

return '${date.year}-$month-$day';
}

static String _compactDate(
DateTime date,
) {
return '${date.year.toString().padLeft(4, '0')}'
'${date.month.toString().padLeft(2, '0')}'
'${date.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// GENERIC HELPERS
// ---------------------------------------------------------------------------

static List<String> _splitCodes(
String? value,
) {
if (value == null ||
value.trim().isEmpty) {
return const [];
}

return value
    .split(',')
    .map(
(e) => e.trim(),
)
    .where(
(e) => e.isNotEmpty,
)
    .toList();
}

static String? _string(
Object? value,
) {
final text =
value?.toString().trim();

if (text == null ||
text.isEmpty) {
return null;
}

return text;
}

static int? _int(
Object? value,
) {
if (value is int) {
return value;
}

return int.tryParse(
value?.toString() ?? '',
);
}
}