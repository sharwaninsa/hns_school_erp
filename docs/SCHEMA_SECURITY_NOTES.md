# Schema Security Notes

## 1. Tenant isolation

Every tenant-owned table has:
- `institution_id INT UNSIGNED NOT NULL` as the first business column
- `KEY ix_<table>_inst (institution_id)` (often composite with other cols)
- `CONSTRAINT fk_<table>_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE`
- `UNIQUE KEY uk_<table>_inst_id (institution_id, id)`

The redundant `UNIQUE(institution_id, id)` is not decoration — MySQL requires a unique index on the parent columns for a composite foreign key target. It is the mechanism that makes cross-tenant references impossible at the InnoDB level.

Children reference parents with `FOREIGN KEY (institution_id, parent_id) REFERENCES parent (institution_id, id)`. This means:
- an `invoice` row cannot reference a `student` from another institution;
- a `marks` row cannot reference an `exam` or a `student` from another institution;
- a `role_permission` row cannot reference a role from another institution.

Application code (`TenantDB`, Phase 2) *also* filters by `institution_id` from the session on every query. The DB constraint is the second line of defence, not the first.

## 2. Platform vs tenant identity

- Platform owners are in `platform_users`, a table with **no `institution_id` column at all**. There is no path for a tenant row to reference a platform owner and no path for a tenant user to become a platform user.
- `permissions.is_platform = 1` marks permissions that can only be attached to the platform-owner role template. The TenantProvisioner (Phase 2) and the roles editor refuse to grant any `is_platform = 1` permission to a tenant role, and the permission check in `Permission` treats `platform.*` as unreachable when `is_platform` session flag is not set.
- Role blueprints live in `role_templates` and `role_template_permissions` — platform-owned tables with no `institution_id`. Tenant `roles` is a separate table with `institution_id NOT NULL`. This satisfies "no NULL institution_id rows in tenant roles" literally and structurally.

## 3. Encryption columns

For each sensitive number, we store **two** columns:

| Purpose | Column | Type |
|---|---|---|
| Ciphertext | `<field>_cipher` | `VARBINARY(512)` / `VARBINARY(1024)` |
| Blind index (exact-match, uniqueness) | `<field>_bidx` | `CHAR(64)` (hex of HMAC-SHA256) |
| Display hint (optional) | `<field>_last4` | `CHAR(4)` |

- Algorithm: AES-256-GCM, key from `APP_KEY` via `Crypto` (Phase 2). A `key_version` byte is prepended to the ciphertext so keys can be rotated without a schema change.
- Blind index: HMAC-SHA256 with a **separate** key derived from `APP_KEY` (`HKDF(APP_KEY, "blind-index")`). Uniqueness constraints use `(institution_id, <field>_bidx)`. This is deterministic only within an institution, which is fine because we only need per-tenant duplicate detection and per-tenant exact search.
- Masking is a UI/Service concern (`student.view_sensitive`, `staff.view_sensitive`, `payroll.view_bank` permissions). The DB never returns plaintext — the service decrypts on demand and audits the reveal.
- Full plaintext values are **never** written to `audit_logs`. The `Audit` service (Phase 2) masks sensitive columns before JSON-encoding `old_values` / `new_values`.
- Log statements, error messages, and URLs are lint-checked in Phase 2 (`tests/security/`) for these column names.

## 4. Immutable tables

The schema does not use triggers to enforce immutability — triggers hide logic, complicate logical replication and restore, and are easy to disable. Instead:

- `audit_logs`, `login_attempts`, `platform_audit_logs` are write-only in the service layer. There is no `UPDATE`/`DELETE` code path; Phase 2 provides a static-analysis test that greps for the table name in `UPDATE`/`DELETE` SQL.
- `fee_receipts`, `invoices`, `payslips`, `transfer_certificates`: post-issue corrections are modelled as **new rows** (cancellation, refund, duplicate TC, reversal), never as in-place edits. The `status` column captures the state; the `cancel_reason`, `cancelled_by`, `cancelled_at` columns capture the audit trail.
- The app-layer guard is in the corresponding service (Phase 8, 9, 10) and is enforced before any UPDATE.

## 5. Polymorphic tables

`addresses`, `bank_details`, `id_documents`, `documents` use `(institution_id, person_type, person_id)` because MySQL cannot express a partial FK on a discriminator. Compensating controls:

1. All writes go through service code that resolves the person via the tenant-scoped `students`/`staff` table first.
2. A nightly integrity check (Phase 11 cron) deletes or reports orphans.
3. `UNIQUE(institution_id, person_type, person_id, ...)` prevents duplicate attachments.
4. The `person_type` ENUM is small and closed; adding a new value is a migration with review.

## 6. Money and sequences

- All money columns are `DECIMAL(12,2)`. There is no `FLOAT`/`DOUBLE` anywhere in the schema.
- `number_sequences` is the single source of sequence numbers. Phase 2's `NumberSequence` service will `SELECT ... FOR UPDATE` inside the transaction that also inserts the consuming row. `MAX()+1` is forbidden by a static-analysis rule in `tests/security/`.

## 7. Audit log design

`audit_logs` is a single append-only table with:
- `institution_id NULL` (platform events have no tenant)
- `user_id` (tenant) and `platform_user_id` (platform) — exactly one is set for real events
- `impersonated_by` set when a platform owner acts as a tenant user
- `old_values` / `new_values` JSON with sensitive columns masked by the `Audit` service before write
- `correlation_id` links to the error log and the user-visible error page

The absence of FKs from `audit_logs` to mutable entities is deliberate: retention pruning of old `students`/`staff` rows must not cascade-delete audit history. `institution_id` keeps the tenant FK because institutions are never hard-deleted (they are archived); if they ever are, `ON DELETE CASCADE` on the audit log is the correct behaviour.

## 8. Retention and anonymization

- `institutions.retention_years` (default 7).
- `students.is_anonymized` marks rows that have been anonymized past retention.
- `data_subject_requests` records access/export/erase requests and their fulfilment.
- `students.consent_data`, `students.consent_photo`, `students.consent_at`, `students.consent_by_name` capture consent (a minor cannot consent for themselves; the guardian does).

## 9. Known trade-offs accepted in this phase

| Trade-off | Why | Compensating control |
|---|---|---|
| `UNIQUE(institution_id, id)` duplicates the PK | Required by MySQL for composite FK targets | Storage overhead is one extra index per table |
| No DB-level immutability triggers | Triggers hide logic, break logical replication | App-layer guard + static-analysis test in Phase 2 |
| No FK on polymorphic tables | MySQL limitation | Service-layer validation + nightly orphan check |
| `login_attempts` has no FK | Must record attempts against unknown institutes/users | Append-only, pruned by retention job |
| `VARBINARY(1024)` for ID numbers | GCM overhead + IV + key version + future key rotation | Not a performance concern at 10k–1M rows |