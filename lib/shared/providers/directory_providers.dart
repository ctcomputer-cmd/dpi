import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _sb = Supabase.instance.client;

/// A staff profile (teacher, HoD, admin, etc.).
class StaffMember {
  const StaffMember({
    required this.id,
    required this.fullName,
    required this.isActive,
    this.designation,
    this.employeeId,
    this.email,
    this.phone,
    this.bio,
    this.joiningDate,
  });

  final String id;
  final String fullName;
  final bool isActive;
  final String? designation;
  final String? employeeId;
  final String? email;
  final String? phone;
  final String? bio;
  final String? joiningDate;

  factory StaffMember.fromMap(Map<String, dynamic> m) => StaffMember(
        id: m['id'] as String,
        fullName: (m['full_name'] as String?) ?? '',
        isActive: (m['is_active'] as bool?) ?? false,
        designation: m['designation'] as String?,
        employeeId: m['employee_id'] as String?,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        bio: m['bio'] as String?,
        joiningDate: m['joining_date'] as String?,
      );
}

class DepartmentItem {
  const DepartmentItem({required this.id, required this.name, required this.code});

  final String id;
  final String name;
  final String code;
}

final staffListProvider = FutureProvider.autoDispose<List<StaffMember>>((ref) async {
  final rows = await _sb
      .from('profiles')
      .select('id, full_name, designation, employee_id, email, phone, bio, joining_date, is_active')
      .isFilter('deleted_at', null)
      .order('full_name', ascending: true)
      .limit(500);
  return (rows as List)
      .map((e) => StaffMember.fromMap(e as Map<String, dynamic>))
      .toList();
});

final departmentListProvider = FutureProvider.autoDispose<List<DepartmentItem>>((ref) async {
  final rows = await _sb
      .from('departments')
      .select('id, name, code')
      .isFilter('deleted_at', null)
      .order('name');
  return (rows as List)
      .map((e) => DepartmentItem(
            id: e['id'] as String,
            name: e['name'] as String,
            code: e['code'] as String,
          ))
      .toList();
});

/// Task statuses and priorities as stored in the database.
const taskPriorities = ['low', 'medium', 'high', 'urgent'];
const taskStatuses = [
  'not_started',
  'in_progress',
  'under_review',
  'revision_required',
  'completed',
  'cancelled',
];

String prettyLabel(String value) => value.replaceAll('_', ' ');

/// Roles of the currently signed-in user (used to show admin-only actions).
final myRolesProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final uid = _sb.auth.currentUser?.id;
  if (uid == null) return <String>[];
  final rows = await _sb.from('user_roles').select('role').eq('user_id', uid);
  return (rows as List).map((e) => e['role'] as String).toList();
});
