# ER Summary — School ERP

Legend: [P] = platform-owned (no institution_id), [T] = tenant-owned (institution_id NOT NULL, indexed, FK → institutions).
Every [T] table carries UNIQUE(institution_id, id) so that it can be the target of a composite tenant FK.

PLATFORM
  platform_users [P] 1─┬─* impersonation_sessions ──* institutions [T]
                       └─* platform_audit_logs [P]
  subscription_plans [P] 1──* institutions

TENANT ROOT
  institutions [T]
    ├─ 1 * roles ──* role_permissions ──* permissions [P]
    ├─ 1 * users ──* temp_credentials
    ├─ 1 * academic_years
    │     ├─* class_subjects
    │     ├─* exams ──* marks
    │     ├─* fee_structures, fee_installments
    │     └─* invoices ──* invoice_items
    ├─ 1 * classes ──* sections
    │     ├─* class_subjects
    │     ├─* teacher_assignments
    │     └─* timetable_entries
    ├─ 1 * subjects
    ├─ 1 * staff ──* staff_qualifications, staff_experience
    │     ├─* staff_attendance, leave_applications, leave_balances
    │     ├─* staff_salary, staff_salary_overrides
    │     ├─* staff_loans ──* loan_recoveries
    │     └─* payslips ──* payslip_lines
    ├─ 1 * students ──* guardians
    │     ├─* student_enrollments
    │     ├─* student_attendance, marks, report_cards
    │     ├─* invoices, fee_receipts, concessions
    │     ├─* transfer_certificates
    │     ├─* certificates
    │     └─* student_siblings (self, via sibling_id)
    ├─ 1 * users (portal) ──* guardian_user_links ──* students
    ├─ 1 * addresses, bank_details, id_documents, documents  (polymorphic: person_type, person_id)
    ├─ 1 * fee_heads ──* fee_structures, invoice_items, concessions
    ├─ 1 * salary_components ──* salary_template_components, payslip_lines
    ├─ 1 * salary_templates ──* salary_template_components
    ├─ 1 * payroll_runs ──* payslips
    ├─ 1 * library_items ──* library_issues
    ├─ 1 * transport_routes ──* transport_stops, transport_allotments
    ├─ 1 * inventory_items ──* inventory_movements
    ├─ 1 * notices ──* notice_reads
    ├─ 1 * events
    ├─ 1 * holidays, leave_types
    ├─ 1 * timetable_periods ──* timetable_entries
    ├─ 1 * exam_terms ──* exams
    ├─ 1 * grade_scales (per institution, per "type")
    ├─ 1 * number_sequences (composite PK: institution_id, seq_key)
    ├─ 1 * import_batches
    ├─ 1 * audit_logs (append-only)
    ├─ 1 * export_jobs, backup_jobs, data_subject_requests
    └─ 1 * idempotency_keys, institution_settings

KEY RELATIONSHIPS
  users.staff_id   -> staff.id      (optional, only for staff logins)
  users.student_id -> students.id   (optional, only for student logins)
  guardian_user_links: a parent login maps to N students (their children)

ENCRYPTION COLUMN PATTERN (AES-256-GCM + HMAC-SHA256 blind index)
  students.aadhaar_cipher  VARBINARY(512)  + students.aadhaar_bidx  CHAR(64)
  staff.pan_cipher         VARBINARY(512)  + staff.pan_bidx         CHAR(64)
  id_documents.number_cipher VARBINARY(1024) + id_documents.number_bidx CHAR(64)
  bank_details.account_no_cipher VARBINARY(512) + account_no_bidx CHAR(64) + last4
  bank_details.upi_id_cipher VARBINARY(512) + upi_id_bidx CHAR(64)

IMMUTABLE TABLES (no UPDATE path in app; append-only)
  audit_logs, login_attempts, platform_audit_logs,
  fee_receipts (post-issue), invoices (post-issue, cancellation creates new row),
  payslips (post-approved+paid), transfer_certificates (post-issue, duplicate = new row)

COMPOSITE TENANT FK (example)
  marks(institution_id, exam_id) -> exams(institution_id, id)
  marks(institution_id, student_id) -> students(institution_id, id)
  → a row cannot reference an exam or student from a different institution,
    even if application code is bypassed.

NO-FK POLYMORPHIC TABLES (with compensating controls)
  addresses, bank_details, id_documents, documents
  reason: MySQL cannot FK on a polymorphic discriminator.
  mitigation: all app reads go through service layer; nightly integrity job
              documented in SCHEMA_SECURITY_NOTES.md.