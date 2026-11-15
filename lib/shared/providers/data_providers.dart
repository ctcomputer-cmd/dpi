import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// All queries go through Supabase with the user's own session.
/// Row Level Security decides what each user can read; the app never
/// bypasses it.
final _sb = Supabase.instance.client;

class DashboardStats {
  const DashboardStats({
    required this.teachers,
    required this.activeTasks,
    required this.completedTasks,
    required this.overdueTasks,
  });

  final int teachers;
  final int activeTasks;
  final int completedTasks;
  final int overdueTasks;
}

final dashboardStatsProvider = FutureProvider.autoDispose<DashboardStats>((ref) async {
  const closed = '(completed,cancelled)';

  final teacherRows = await _sb.from('profiles').select('id').eq('is_active', true);

  final activeRows = await _sb
      .from('tasks')
      .select('id')
      .isFilter('deleted_at', null)
      .not('status', 'in', closed);

  final completedRows = await _sb
      .from('tasks')
      .select('id')
      .isFilter('deleted_at', null)
      .eq('status', 'completed');

  final overdueRows = await _sb
      .from('tasks')
      .select('id')
      .isFilter('deleted_at', null)
      .not('status', 'in', closed)
      .lt('deadline', DateTime.now().toUtc().toIso8601String());

  return DashboardStats(
    teachers: (teacherRows as List).length,
    activeTasks: (activeRows as List).length,
    completedTasks: (completedRows as List).length,
    overdueTasks: (overdueRows as List).length,
  );
});

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.deadline,
  });

  final String id;
  final String title;
  final String status;
  final String priority;
  final DateTime? deadline;

  factory TaskItem.fromMap(Map<String, dynamic> m) => TaskItem(
        id: m['id'] as String,
        title: m['title'] as String,
        status: m['status'] as String,
        priority: m['priority'] as String,
        deadline: m['deadline'] == null ? null : DateTime.parse(m['deadline'] as String),
      );
}

final taskListProvider = FutureProvider.autoDispose<List<TaskItem>>((ref) async {
  final rows = await _sb
      .from('tasks')
      .select('id, title, status, priority, deadline')
      .isFilter('deleted_at', null)
      .order('deadline', ascending: true)
      .limit(200);
  return (rows as List)
      .map((e) => TaskItem.fromMap(e as Map<String, dynamic>))
      .toList();
});

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.link,
  });

  final String id;
  final String title;
  final String? body;
  final bool isRead;
  final DateTime createdAt;

  /// In-app route to open when tapped, e.g. /tasks/<id>.
  final String? link;

  factory NotificationItem.fromMap(Map<String, dynamic> m) => NotificationItem(
        id: m['id'] as String,
        title: m['title'] as String,
        body: m['body'] as String?,
        isRead: m['is_read'] as bool,
        createdAt: DateTime.parse(m['created_at'] as String),
        link: m['link'] as String?,
      );
}

final notificationListProvider =
    FutureProvider.autoDispose<List<NotificationItem>>((ref) async {
  final rows = await _sb
      .from('notifications')
      .select('id, title, body, is_read, created_at, link')
      .order('created_at', ascending: false)
      .limit(100);
  return (rows as List)
      .map((e) => NotificationItem.fromMap(e as Map<String, dynamic>))
      .toList();
});
