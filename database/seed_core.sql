-- =====================================================================
-- school-erp / database / seed_core.sql
-- Global (platform-level) seed. Idempotent via INSERT ... ON DUPLICATE.
-- NO USERS. NO PASSWORDS. NO DEMO INSTITUTION.
-- =====================================================================

SET NAMES utf8mb4;

-- ---------- Permissions ----------
INSERT INTO permissions (slug, module, label, is_sensitive, is_platform) VALUES
-- academic
('academic.view',        'academic',   'View academic structure', 0, 0),
('academic.manage',      'academic',   'Manage academic years',   0, 0),
('class.manage',         'academic',   'Manage classes & sections',0,0),
('subject.manage',       'academic',   'Manage subjects',         0, 0),
('timetable.view',       'timetable',  'View timetable',          0, 0),
('timetable.manage',     'timetable',  'Manage timetable',        0, 0),
-- admissions & students
('admission.manage',     'admissions', 'Manage admissions',       0, 0),
('student.view',         'students',   'View students',           0, 0),
('student.manage',       'students',   'Create/edit students',    0, 0),
('student.view_sensitive','students',  'Reveal student PII',      1, 0),
('student.promote',      'students',   'Promote/detain students', 0, 0),
('student.transfer',     'students',   'Transfer students',       0, 0),
-- staff
('staff.view',           'staff',      'View staff',              0, 0),
('staff.manage',         'staff',      'Create/edit staff',       0, 0),
('staff.view_sensitive', 'staff',      'Reveal staff PII',        1, 0),
('staff.view_police',    'staff',      'View police verification',1, 0),
('staff.exit',           'staff',      'Process staff exit',      0, 0),
-- attendance & leave
('attendance.view',      'attendance', 'View attendance',         0, 0),
('attendance.mark',      'attendance', 'Mark attendance',         0, 0),
('attendance.import',    'attendance', 'Import attendance',       0, 0),
('leave.apply',          'leave',      'Apply leave',             0, 0),
('leave.approve',        'leave',      'Approve leave',           0, 0),
('holiday.manage',       'leave',      'Manage holidays',         0, 0),
-- exams
('exam.view',            'exams',      'View exams',              0, 0),
('exam.manage',          'exams',      'Manage exam terms',       0, 0),
('marks.enter',          'exams',      'Enter marks',             0, 0),
('marks.lock',           'exams',      'Lock/unlock marks',       0, 0),
('marksheet.publish',    'exams',      'Publish report cards',    0, 0),
-- fees
('fee.view',             'fees',       'View fees',               0, 0),
('fee.manage',           'fees',       'Manage fee structure',    0, 0),
('fee.collect',          'fees',       'Collect fees',            0, 0),
('fee.cancel',           'fees',       'Cancel fee receipt',      0, 0),
('fee.refund',           'fees',       'Refund fees',             0, 0),
('fee.report',           'fees',       'Fee reports',             0, 0),
-- payroll
('payroll.view',         'payroll',    'View payroll',            0, 0),
('payroll.manage',       'payroll',    'Manage payroll masters',  0, 0),
('payroll.run',          'payroll',    'Run payroll',             0, 0),
('payroll.approve',      'payroll',    'Approve payroll',         0, 0),
('payroll.pay',          'payroll',    'Mark payroll paid',       0, 0),
('payroll.view_bank',    'payroll',    'Reveal bank details',     1, 0),
('payslip.view_own',     'payroll',    'View own payslips',       0, 0),
-- transfers & certificates
('certificate.manage',   'certificates','Manage certificates',    0, 0),
('tc.request',           'transfers',  'Request TC',              0, 0),
('tc.approve',           'transfers',  'Approve TC',              0, 0),
('tc.issue',             'transfers',  'Issue TC',                0, 0),
-- library / transport / inventory
('library.view',         'library',    'View library',            0, 0),
('library.manage',       'library',    'Manage library',          0, 0),
('transport.view',       'transport',  'View transport',          0, 0),
('transport.manage',     'transport',  'Manage transport',        0, 0),
('inventory.manage',     'inventory',  'Manage inventory',        0, 0),
-- notices
('notice.view',          'notices',    'View notices',            0, 0),
('notice.manage',        'notices',    'Manage notices',          0, 0),
-- users & roles
('users.view',           'users',      'View users',              0, 0),
('users.manage',         'users',      'Manage users & roles',    0, 0),
('users.reset_password', 'users',      'Reset user passwords',    0, 0),
('users.unlock',         'users',      'Unlock accounts',         0, 0),
-- imports
('imports.view',         'imports',    'View import history',     0, 0),
('bulk.import',          'imports',    'Run bulk imports',        0, 0),
('bulk.revert',          'imports',    'Revert import batch',     1, 0),
-- reporting
('reports.view',         'reports',    'View reports',            0, 0),
('export.data',          'reports',    'Export data',             0, 0),
('export.institute',     'reports',    'Export full institute data',1,0),
-- settings
('settings.view',        'settings',   'View institution settings',0,0),
('settings.manage',      'settings',   'Manage institution settings',0,0),
-- portal (own-scope)
('portal.profile',       'portal',     'Portal: own profile',     0, 0),
('portal.attendance',    'portal',     'Portal: own attendance',  0, 0),
('portal.marks',         'portal',     'Portal: own marks',       0, 0),
('portal.fees',          'portal',     'Portal: own fees',        0, 0),
('portal.timetable',     'portal',     'Portal: own timetable',   0, 0),
('portal.notices',       'portal',     'Portal: notices',         0, 0),
-- platform (only for platform_users, never grantable in tenant)
('platform.manage_institutes','platform','Manage institutes',     1, 1),
('platform.manage_plans',    'platform','Manage plans',           1, 1),
('platform.impersonate',     'platform','Impersonate tenant user',1, 1),
('platform.view_audit',      'platform','View platform audit',    1, 1)
ON DUPLICATE KEY UPDATE
  module = VALUES(module), label = VALUES(label),
  is_sensitive = VALUES(is_sensitive), is_platform = VALUES(is_platform);

-- ---------- Role templates ----------
INSERT INTO role_templates (slug, name, description, scope, is_system) VALUES
('institute_admin', 'Institute Admin',  'Full tenant administrator', 'institute', 1),
('principal',       'Principal',        'Academic head & approver',  'institute', 1),
('accounts',        'Accounts',         'Fees & payroll accountant', 'institute', 1),
('teacher',         'Teacher',          'Teaching staff',            'institute', 1),
('class_teacher',   'Class Teacher',    'Teacher with class duties', 'institute', 1),
('librarian',       'Librarian',        'Library operations',        'institute', 1),
('transport_mgr',   'Transport Manager','Transport operations',      'institute', 1),
('student',         'Student',          'Student portal',            'institute', 1),
('parent',          'Parent/Guardian',  'Parent portal',             'institute', 1),
('platform_owner',  'Platform Owner',   'Platform super admin',      'platform',  1)
ON DUPLICATE KEY UPDATE name = VALUES(name), scope = VALUES(scope), is_system = VALUES(is_system);

-- ---------- Role template -> permission mapping ----------
-- Institute Admin: everything non-platform
INSERT IGNORE INTO role_template_permissions (role_template_id, permission_id)
SELECT rt.id, p.id FROM role_templates rt JOIN permissions p ON p.is_platform = 0
WHERE rt.slug = 'institute_admin';

-- Principal: broad read + approvals, no payroll.run/pay, no users.manage
INSERT IGNORE INTO role_template_permissions (role_template_id, permission_id)
SELECT rt.id, p.id FROM role_templates rt JOIN permissions p
  ON p.slug IN (
    'academic.view','academic.manage','class.manage','subject.manage','timetable.view','timetable.manage',
    'admission.manage','student.view','student.manage','student.view_sensitive','student.promote','student.transfer',
    'staff.view','staff.view_sensitive','staff.view_police','staff.exit',
    'attendance.view','attendance.mark','leave.approve','holiday.manage',
    'exam.view','exam.manage','marks.enter','marks.lock','marksheet.publish',
    'fee.view','fee.report','fee.cancel','fee.refund',
    'payroll.view','payroll.approve',
    'certificate.manage','tc.request','tc.approve','tc.issue',
    'library.view','transport.view','notice.view','notice.manage',
    'reports.view','export.data','settings.view'
  )
WHERE rt.slug = 'principal';

-- Accounts: fees + payroll only
INSERT IGNORE INTO role_template_permissions (role_template_id, permission_id)
SELECT rt.id, p.id FROM role_templates rt JOIN permissions p
  ON p.slug IN (
    'fee.view','fee.manage','fee.collect','fee.cancel','fee.refund','fee.report',
    'payroll.view','payroll.manage','payroll.run','payroll.pay','payroll.view_bank',
    'student.view','staff.view','reports.view','export.data','imports.view','bulk.import'
  )
WHERE rt.slug = 'accounts';

-- Teacher
INSERT IGNORE INTO role_template_permissions (role_template_id, permission_id)
SELECT rt.id, p.id FROM role_templates rt JOIN permissions p
  ON p.slug IN (
    'academic.view','timetable.view',
    'student.view','attendance.view','attendance.mark',
    'leave.apply','exam.view','marks.enter','notice.view','portal.profile'
  )
WHERE rt.slug = 'teacher';

-- Class Teacher: teacher + class-scope approvals
INSERT IGNORE INTO role_template_permissions (role_template_id, permission_id)
SELECT rt.id, p.id FROM role_templates rt JOIN permissions p
  ON p.slug IN (
    'academic.view','timetable.view','student.view','student.promote',
    'attendance.view','attendance.mark','leave.apply','leave.approve',
    'exam.view','marks.enter','marksheet.publish','notice.view','notice.manage','portal.profile'
  )
WHERE rt.slug = 'class_teacher';

-- Librarian
INSERT IGNORE INTO role_template_permissions (role_template_id, permission_id)
SELECT rt.id, p.id FROM role_templates rt JOIN permissions p
  ON p.slug IN ('library.view','library.manage','student.view','staff.view','notice.view','portal.profile')
WHERE rt.slug = 'librarian';

-- Transport manager
INSERT IGNORE INTO role_template_permissions (role_template_id, permission_id)
SELECT rt.id, p.id FROM role_templates rt JOIN permissions p
  ON p.slug IN ('transport.view','transport.manage','student.view','fee.view','notice.view','portal.profile')
WHERE rt.slug = 'transport_mgr';

-- Student portal
INSERT IGNORE INTO role_template_permissions (role_template_id, permission_id)
SELECT rt.id, p.id FROM role_templates rt JOIN permissions p
  ON p.slug IN ('portal.profile','portal.attendance','portal.marks','portal.fees','portal.timetable','portal.notices')
WHERE rt.slug = 'student';

-- Parent portal
INSERT IGNORE INTO role_template_permissions (role_template_id, permission_id)
SELECT rt.id, p.id FROM role_templates rt JOIN permissions p
  ON p.slug IN ('portal.profile','portal.attendance','portal.marks','portal.fees','portal.timetable','portal.notices')
WHERE rt.slug = 'parent';

-- Platform owner: all platform.* + audit
INSERT IGNORE INTO role_template_permissions (role_template_id, permission_id)
SELECT rt.id, p.id FROM role_templates rt JOIN permissions p ON p.is_platform = 1
WHERE rt.slug = 'platform_owner';

-- ---------- Subscription plans ----------
INSERT INTO subscription_plans (slug, name, max_students, max_staff, enabled_modules, price_monthly, price_yearly, is_active) VALUES
('trial',       'Trial',        100,    25,
 JSON_ARRAY('academic','admissions','students','attendance','exams','fees','notices','portal','reports','imports'),
 0.00, 0.00, 1),
('standard',    'Standard',     1000,   200,
 JSON_ARRAY('academic','admissions','students','staff','attendance','leave','timetable','exams','fees','notices','certificates','users','settings','reports','imports','portal'),
 4999.00, 49999.00, 1),
('premium',     'Premium',      10000,  2000,
 JSON_ARRAY('academic','admissions','students','staff','attendance','leave','timetable','exams','fees','payroll','notices','certificates','transfers','library','transport','inventory','users','settings','reports','imports','portal'),
 9999.00, 99999.00, 1),
('enterprise',  'Enterprise',   NULL,   NULL,
 JSON_ARRAY('academic','admissions','students','staff','attendance','leave','timetable','exams','fees','payroll','notices','certificates','transfers','library','transport','inventory','users','settings','reports','imports','portal'),
 NULL, NULL, 1)
ON DUPLICATE KEY UPDATE
  name = VALUES(name), max_students = VALUES(max_students), max_staff = VALUES(max_staff),
  enabled_modules = VALUES(enabled_modules), price_monthly = VALUES(price_monthly),
  price_yearly = VALUES(price_yearly), is_active = VALUES(is_active);

INSERT INTO schema_migrations (version) VALUES ('0001_initial_schema')
ON DUPLICATE KEY UPDATE version = version;