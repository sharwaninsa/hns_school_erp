SET NAMES utf8mb4;
SET time_zone = '+05:30';
SET FOREIGN_KEY_CHECKS = 0;
SET sql_mode = 'STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,ONLY_FULL_GROUP_BY,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO';

-- ---------------------------------------------------------------------
-- 0. Platform-level (no tenant) tables
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS platform_users;
CREATE TABLE platform_users (
  id                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  login_id              VARCHAR(64)  NOT NULL,
  email                 VARCHAR(190) NOT NULL,
  password_hash         VARCHAR(255) NOT NULL,
  password_algo         ENUM('argon2id','bcrypt') NOT NULL DEFAULT 'argon2id',
  display_name          VARCHAR(120) NOT NULL,
  status                ENUM('active','suspended','disabled') NOT NULL DEFAULT 'active',
  must_change_password  TINYINT(1)   NOT NULL DEFAULT 0,
  failed_attempts       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  locked_until          DATETIME     NULL,
  last_login_at         DATETIME     NULL,
  last_login_ip         VARBINARY(16) NULL,
  totp_secret_cipher    VARBINARY(512) NULL,   -- future 2FA, encrypted
  created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_platform_users_login (login_id),
  UNIQUE KEY uk_platform_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS platform_audit_logs;
CREATE TABLE platform_audit_logs (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  platform_user_id  INT UNSIGNED NULL,
  action            VARCHAR(64)  NOT NULL,
  entity_type       VARCHAR(64)  NULL,
  entity_id         BIGINT UNSIGNED NULL,
  old_values        JSON         NULL,
  new_values        JSON         NULL,
  ip                VARBINARY(16) NULL,
  user_agent        VARCHAR(255) NULL,
  correlation_id    CHAR(36)     NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_pal_user_time (platform_user_id, created_at),
  KEY ix_pal_action_time (action, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 1. Permissions, role templates, subscription plans
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS permissions;
CREATE TABLE permissions (
  id            SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  slug          VARCHAR(96)  NOT NULL,   -- e.g. student.view_sensitive
  module        VARCHAR(48)  NOT NULL,   -- e.g. students
  label         VARCHAR(120) NOT NULL,
  is_sensitive  TINYINT(1)   NOT NULL DEFAULT 0,  -- requires separate grant
  is_platform   TINYINT(1)   NOT NULL DEFAULT 0,  -- platform.* only
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_permissions_slug (slug),
  KEY ix_permissions_module (module)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS role_templates;
CREATE TABLE role_templates (
  id            SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  slug          VARCHAR(48)  NOT NULL,    -- e.g. institute_admin, principal, teacher
  name          VARCHAR(120) NOT NULL,
  description   VARCHAR(255) NULL,
  scope         ENUM('institute','platform') NOT NULL DEFAULT 'institute',
  is_system     TINYINT(1)   NOT NULL DEFAULT 1,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_role_templates_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS role_template_permissions;
CREATE TABLE role_template_permissions (
  role_template_id SMALLINT UNSIGNED NOT NULL,
  permission_id    SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (role_template_id, permission_id),
  CONSTRAINT fk_rtp_template FOREIGN KEY (role_template_id) REFERENCES role_templates(id) ON DELETE CASCADE,
  CONSTRAINT fk_rtp_permission FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS subscription_plans;
CREATE TABLE subscription_plans (
  id                SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  slug              VARCHAR(48)  NOT NULL,
  name              VARCHAR(120) NOT NULL,
  max_students      INT UNSIGNED NULL,
  max_staff         INT UNSIGNED NULL,
  enabled_modules   JSON         NOT NULL,   -- ["students","fees",...]
  price_monthly     DECIMAL(12,2) NULL,
  price_yearly      DECIMAL(12,2) NULL,
  is_active         TINYINT(1)   NOT NULL DEFAULT 1,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_subscription_plans_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 2. Institutions (tenants)
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS institutions;
CREATE TABLE institutions (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  slug              VARCHAR(64)  NOT NULL,     -- subdomain / short code
  name              VARCHAR(190) NOT NULL,
  legal_name        VARCHAR(190) NULL,
  institute_code    VARCHAR(32)  NOT NULL,     -- human "Institute ID" for login
  board             VARCHAR(64)  NULL,
  email             VARCHAR(190) NULL,
  phone             VARCHAR(32)  NULL,
  website           VARCHAR(190) NULL,
  address_line1     VARCHAR(190) NULL,
  address_line2     VARCHAR(190) NULL,
  city              VARCHAR(96)  NULL,
  state             VARCHAR(96)  NULL,
  pincode           VARCHAR(16)  NULL,
  country           VARCHAR(64)  NOT NULL DEFAULT 'India',
  logo_path         VARCHAR(255) NULL,
  timezone          VARCHAR(64)  NOT NULL DEFAULT 'Asia/Kolkata',
  currency          CHAR(3)      NOT NULL DEFAULT 'INR',
  plan_id           SMALLINT UNSIGNED NOT NULL,
  status            ENUM('active','suspended','trial','cancelled') NOT NULL DEFAULT 'trial',
  trial_ends_at     DATETIME     NULL,
  subscription_ends DATETIME     NULL,
  retention_years   TINYINT UNSIGNED NOT NULL DEFAULT 7,
  data_region       VARCHAR(32)  NOT NULL DEFAULT 'in',
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_institutions_slug (slug),
  UNIQUE KEY uk_institutions_code (institute_code),
  KEY ix_institutions_status (status),
  CONSTRAINT fk_institutions_plan FOREIGN KEY (plan_id) REFERENCES subscription_plans(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Impersonation sessions (super admin -> tenant)
DROP TABLE IF EXISTS impersonation_sessions;
CREATE TABLE impersonation_sessions (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  platform_user_id   INT UNSIGNED NOT NULL,
  institution_id     INT UNSIGNED NOT NULL,
  impersonated_user_id INT UNSIGNED NOT NULL,
  reason             VARCHAR(255) NOT NULL,
  started_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at         DATETIME     NOT NULL,
  ended_at           DATETIME     NULL,
  ip                 VARBINARY(16) NULL,
  user_agent         VARCHAR(255) NULL,
  PRIMARY KEY (id),
  KEY ix_imp_platform (platform_user_id, started_at),
  KEY ix_imp_inst (institution_id, started_at),
  CONSTRAINT fk_imp_platform FOREIGN KEY (platform_user_id) REFERENCES platform_users(id),
  CONSTRAINT fk_imp_inst FOREIGN KEY (institution_id) REFERENCES institutions(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 3. Tenant identity: roles, users, sessions
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS roles;
CREATE TABLE roles (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id INT UNSIGNED NOT NULL,
  slug           VARCHAR(48)  NOT NULL,   -- e.g. institute_admin, teacher
  name           VARCHAR(120) NOT NULL,
  description    VARCHAR(255) NULL,
  is_system      TINYINT(1)   NOT NULL DEFAULT 0,   -- cloned from template
  is_editable    TINYINT(1)   NOT NULL DEFAULT 1,
  created_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_roles_inst_id (institution_id, id),
  UNIQUE KEY uk_roles_inst_slug (institution_id, slug),
  KEY ix_roles_inst (institution_id),
  CONSTRAINT fk_roles_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS role_permissions;
CREATE TABLE role_permissions (
  institution_id INT UNSIGNED NOT NULL,
  role_id        INT UNSIGNED NOT NULL,
  permission_id  SMALLINT UNSIGNED NOT NULL,
  granted_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  granted_by     INT UNSIGNED NULL,
  PRIMARY KEY (institution_id, role_id, permission_id),
  KEY ix_rp_perm (permission_id),
  CONSTRAINT fk_rp_role FOREIGN KEY (institution_id, role_id) REFERENCES roles(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_rp_perm FOREIGN KEY (permission_id) REFERENCES permissions(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS users;
CREATE TABLE users (
  id                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id        INT UNSIGNED NOT NULL,
  login_id              VARCHAR(64)  NOT NULL,
  email                 VARCHAR(190) NULL,
  phone                 VARCHAR(32)  NULL,
  password_hash         VARCHAR(255) NOT NULL,
  password_algo         ENUM('argon2id','bcrypt') NOT NULL DEFAULT 'argon2id',
  display_name          VARCHAR(120) NOT NULL,
  role_id               INT UNSIGNED NOT NULL,
  -- optional links to domain entities
  staff_id              INT UNSIGNED NULL,
  student_id            INT UNSIGNED NULL,
  -- optional: guardian user maps to a student via guardians table
  is_guardian           TINYINT(1)   NOT NULL DEFAULT 0,
  status                ENUM('active','inactive','locked','pending') NOT NULL DEFAULT 'pending',
  must_change_password  TINYINT(1)   NOT NULL DEFAULT 1,
  failed_attempts       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  locked_until          DATETIME     NULL,
  last_login_at         DATETIME     NULL,
  last_login_ip         VARBINARY(16) NULL,
  password_changed_at   DATETIME     NULL,
  created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_users_inst_id (institution_id, id),
  UNIQUE KEY uk_users_inst_login (institution_id, login_id),
  KEY ix_users_inst (institution_id),
  KEY ix_users_role (institution_id, role_id),
  CONSTRAINT fk_users_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_users_role FOREIGN KEY (institution_id, role_id) REFERENCES roles(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Temporary credentials (one-time view / download)
DROP TABLE IF EXISTS temp_credentials;
CREATE TABLE temp_credentials (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  user_id         INT UNSIGNED NOT NULL,
  token_hash      CHAR(64)     NOT NULL,           -- SHA-256 of the token
  password_cipher VARBINARY(512) NOT NULL,          -- encrypted with APP_KEY
  expires_at      DATETIME     NOT NULL,
  consumed_at     DATETIME     NULL,
  created_by      INT UNSIGNED NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_tempcred_token (token_hash),
  KEY ix_tempcred_user (institution_id, user_id, expires_at),
  CONSTRAINT fk_tempcred_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_tempcred_user FOREIGN KEY (institution_id, user_id) REFERENCES users(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Login attempts (no FK — must record attempts against unknown institutes)
DROP TABLE IF EXISTS login_attempts;
CREATE TABLE login_attempts (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NULL,
  institute_code  VARCHAR(32)  NULL,
  login_id        VARCHAR(64)  NULL,
  user_id         INT UNSIGNED NULL,
  ip              VARBINARY(16) NOT NULL,
  user_agent      VARCHAR(255) NULL,
  outcome         ENUM('success','bad_credentials','locked','must_change','throttled','inactive') NOT NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_la_inst_login_time (institution_id, login_id, created_at),
  KEY ix_la_ip_time (ip, created_at),
  KEY ix_la_time (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 4. Institution settings & presets
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS institution_settings;
CREATE TABLE institution_settings (
  institution_id  INT UNSIGNED NOT NULL,
  setting_key     VARCHAR(96)  NOT NULL,
  setting_value   TEXT         NULL,
  updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (institution_id, setting_key),
  CONSTRAINT fk_isettings_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS grade_scales;
CREATE TABLE grade_scales (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  type            VARCHAR(32)  NOT NULL DEFAULT 'default',
  grade           VARCHAR(8)   NOT NULL,
  min_percent     DECIMAL(5,2) NOT NULL,
  max_percent     DECIMAL(5,2) NOT NULL,
  gpa             DECIMAL(4,2) NULL,
  remarks         VARCHAR(120) NULL,
  sort_order      SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_gradescale_inst_id (institution_id, id),
  UNIQUE KEY uk_gradescale_inst_type_grade (institution_id, type, grade),
  KEY ix_gradescale_lookup (institution_id, type, min_percent),
  CONSTRAINT fk_gradescale_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS leave_types;
CREATE TABLE leave_types (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  code            VARCHAR(16)  NOT NULL,
  name            VARCHAR(96)  NOT NULL,
  applies_to      ENUM('student','staff','both') NOT NULL,
  is_paid         TINYINT(1)   NOT NULL DEFAULT 1,
  annual_quota    DECIMAL(5,2) NULL,
  carry_forward   TINYINT(1)   NOT NULL DEFAULT 0,
  requires_doc    TINYINT(1)   NOT NULL DEFAULT 0,
  is_active       TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uk_leavetypes_inst_id (institution_id, id),
  UNIQUE KEY uk_leavetypes_inst_code (institution_id, code),
  CONSTRAINT fk_leavetypes_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS fee_heads;
CREATE TABLE fee_heads (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  code            VARCHAR(32)  NOT NULL,
  name            VARCHAR(120) NOT NULL,
  category        ENUM('tuition','transport','hostel','exam','library','misc','activity','admission') NOT NULL DEFAULT 'misc',
  is_recurring    TINYINT(1)   NOT NULL DEFAULT 1,
  is_taxable      TINYINT(1)   NOT NULL DEFAULT 0,
  gst_percent     DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  is_active       TINYINT(1)   NOT NULL DEFAULT 1,
  sort_order      SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_feeheads_inst_id (institution_id, id),
  UNIQUE KEY uk_feeheads_inst_code (institution_id, code),
  CONSTRAINT fk_feeheads_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS salary_components;
CREATE TABLE salary_components (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  code            VARCHAR(32)  NOT NULL,
  name            VARCHAR(120) NOT NULL,
  type            ENUM('earning','deduction') NOT NULL,
  calc_type       ENUM('fixed','percent_basic','percent_gross','formula','statutory') NOT NULL DEFAULT 'fixed',
  formula         VARCHAR(255) NULL,
  is_taxable      TINYINT(1)   NOT NULL DEFAULT 1,
  is_statutory    TINYINT(1)   NOT NULL DEFAULT 0,
  is_active       TINYINT(1)   NOT NULL DEFAULT 1,
  sort_order      SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_salcomp_inst_id (institution_id, id),
  UNIQUE KEY uk_salcomp_inst_code (institution_id, code),
  CONSTRAINT fk_salcomp_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 5. Academic structure
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS academic_years;
CREATE TABLE academic_years (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  name            VARCHAR(32)  NOT NULL,    -- 2024-2025
  start_date      DATE         NOT NULL,
  end_date        DATE         NOT NULL,
  is_current      TINYINT(1)   NOT NULL DEFAULT 0,
  is_locked       TINYINT(1)   NOT NULL DEFAULT 0,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_ay_inst_id (institution_id, id),
  UNIQUE KEY uk_ay_inst_name (institution_id, name),
  KEY ix_ay_inst_current (institution_id, is_current),
  CONSTRAINT fk_ay_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS classes;
CREATE TABLE classes (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  name            VARCHAR(64)  NOT NULL,      -- "1", "11-Science"
  display_order   SMALLINT     NOT NULL DEFAULT 0,
  stream          VARCHAR(32)  NULL,
  is_active       TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uk_classes_inst_id (institution_id, id),
  UNIQUE KEY uk_classes_inst_name (institution_id, name),
  CONSTRAINT fk_classes_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS sections;
CREATE TABLE sections (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  class_id        INT UNSIGNED NOT NULL,
  name            VARCHAR(16)  NOT NULL,      -- A, B, Red
  capacity        SMALLINT UNSIGNED NULL,
  room            VARCHAR(32)  NULL,
  class_teacher_staff_id INT UNSIGNED NULL,
  is_active       TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uk_sections_inst_id (institution_id, id),
  UNIQUE KEY uk_sections_inst_class_name (institution_id, class_id, name),
  CONSTRAINT fk_sections_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_sections_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS subjects;
CREATE TABLE subjects (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  code            VARCHAR(32)  NOT NULL,
  name            VARCHAR(120) NOT NULL,
  type            ENUM('theory','practical','both','activity') NOT NULL DEFAULT 'theory',
  is_language     TINYINT(1)   NOT NULL DEFAULT 0,
  is_active       TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uk_subjects_inst_id (institution_id, id),
  UNIQUE KEY uk_subjects_inst_code (institution_id, code),
  CONSTRAINT fk_subjects_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS class_subjects;
CREATE TABLE class_subjects (
  institution_id  INT UNSIGNED NOT NULL,
  academic_year_id INT UNSIGNED NOT NULL,
  class_id        INT UNSIGNED NOT NULL,
  subject_id      INT UNSIGNED NOT NULL,
  max_marks       SMALLINT UNSIGNED NOT NULL DEFAULT 100,
  pass_marks      SMALLINT UNSIGNED NOT NULL DEFAULT 33,
  is_optional     TINYINT(1)   NOT NULL DEFAULT 0,
  PRIMARY KEY (institution_id, academic_year_id, class_id, subject_id),
  CONSTRAINT fk_cs_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_cs_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_cs_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_cs_subject FOREIGN KEY (institution_id, subject_id) REFERENCES subjects(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 6. Staff
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS staff;
CREATE TABLE staff (
  id                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id        INT UNSIGNED NOT NULL,
  employee_no           VARCHAR(32)  NOT NULL,
  staff_type            ENUM('teaching','non_teaching','admin','support') NOT NULL,
  designation           VARCHAR(96)  NOT NULL,
  department            VARCHAR(96)  NULL,
  reporting_staff_id    INT UNSIGNED NULL,
  first_name            VARCHAR(96)  NOT NULL,
  middle_name           VARCHAR(96)  NULL,
  last_name             VARCHAR(96)  NULL,
  display_name          VARCHAR(190) NOT NULL,
  gender                ENUM('male','female','other','undisclosed') NOT NULL DEFAULT 'undisclosed',
  dob                   DATE         NULL,
  blood_group           VARCHAR(8)   NULL,
  personal_email        VARCHAR(190) NULL,
  work_email            VARCHAR(190) NULL,
  personal_mobile       VARCHAR(32)  NULL,
  emergency_name        VARCHAR(190) NULL,
  emergency_relation    VARCHAR(64)  NULL,
  emergency_phone       VARCHAR(32)  NULL,
  joining_date          DATE         NULL,
  employment_type       ENUM('permanent','contract','probation','intern','part_time','visiting') NOT NULL DEFAULT 'permanent',
  confirmation_date     DATE         NULL,
  exit_date             DATE         NULL,
  exit_reason           VARCHAR(255) NULL,
  status                ENUM('active','on_leave','resigned','terminated','retired') NOT NULL DEFAULT 'active',
  -- payroll identity
  pf_no                 VARCHAR(32)  NULL,
  esi_no                VARCHAR(32)  NULL,
  pan_cipher            VARBINARY(512) NULL,
  pan_bidx              CHAR(64)     NULL,
  uan                   VARCHAR(32)  NULL,
  -- qualifications summary (detailed in staff_qualifications)
  highest_qualification VARCHAR(120) NULL,
  -- police verification
  police_status         ENUM('not_started','pending','verified','failed','expired') NOT NULL DEFAULT 'not_started',
  police_cert_no        VARCHAR(64)  NULL,
  police_authority      VARCHAR(190) NULL,
  police_issue_date     DATE         NULL,
  police_valid_until    DATE         NULL,
  -- batch that created this row (for revert)
  batch_id              BIGINT UNSIGNED NULL,
  created_by            INT UNSIGNED NULL,
  created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_staff_inst_id (institution_id, id),
  UNIQUE KEY uk_staff_inst_empno (institution_id, employee_no),
  UNIQUE KEY uk_staff_inst_pan (institution_id, pan_bidx),
  KEY ix_staff_inst_status (institution_id, status),
  KEY ix_staff_inst_type (institution_id, staff_type),
  CONSTRAINT fk_staff_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_staff_reporting FOREIGN KEY (institution_id, reporting_staff_id) REFERENCES staff(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS staff_qualifications;
CREATE TABLE staff_qualifications (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  staff_id        INT UNSIGNED NOT NULL,
  degree          VARCHAR(120) NOT NULL,
  specialization  VARCHAR(120) NULL,
  institute_name  VARCHAR(190) NULL,
  year_passed     SMALLINT UNSIGNED NULL,
  grade           VARCHAR(32)  NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_staffqual_inst_id (institution_id, id),
  KEY ix_staffqual_staff (institution_id, staff_id),
  CONSTRAINT fk_staffqual_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_staffqual_staff FOREIGN KEY (institution_id, staff_id) REFERENCES staff(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS staff_experience;
CREATE TABLE staff_experience (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  staff_id        INT UNSIGNED NOT NULL,
  organization    VARCHAR(190) NOT NULL,
  designation     VARCHAR(120) NOT NULL,
  from_date       DATE         NOT NULL,
  to_date         DATE         NULL,
  reason_leaving  VARCHAR(255) NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_staffexp_inst_id (institution_id, id),
  KEY ix_staffexp_staff (institution_id, staff_id),
  CONSTRAINT fk_staffexp_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_staffexp_staff FOREIGN KEY (institution_id, staff_id) REFERENCES staff(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 7. Students & guardians
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS students;
CREATE TABLE students (
  id                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id        INT UNSIGNED NOT NULL,
  admission_no          VARCHAR(32)  NOT NULL,
  admission_date        DATE         NULL,
  first_name            VARCHAR(96)  NOT NULL,
  middle_name           VARCHAR(96)  NULL,
  last_name             VARCHAR(96)  NULL,
  display_name          VARCHAR(190) NOT NULL,
  gender                ENUM('male','female','other','undisclosed') NOT NULL DEFAULT 'undisclosed',
  dob                   DATE         NULL,
  blood_group           VARCHAR(8)   NULL,
  nationality           VARCHAR(64)  NULL,
  mother_tongue         VARCHAR(64)  NULL,
  religion              VARCHAR(64)  NULL,
  category              VARCHAR(32)  NULL,   -- General/SC/ST/OBC/EWS
  caste                 VARCHAR(64)  NULL,
  aadhaar_cipher        VARBINARY(512) NULL,
  aadhaar_bidx          CHAR(64)     NULL,
  status                ENUM('active','passed_out','tc_issued','suspended','alumni','archived') NOT NULL DEFAULT 'active',
  current_class_id      INT UNSIGNED NULL,
  current_section_id    INT UNSIGNED NULL,
  roll_no               VARCHAR(16)  NULL,
  house                 VARCHAR(32)  NULL,
  previous_school       VARCHAR(190) NULL,
  -- consent for processing minor's data
  consent_data          TINYINT(1)   NOT NULL DEFAULT 0,
  consent_photo         TINYINT(1)   NOT NULL DEFAULT 0,
  consent_at            DATETIME     NULL,
  consent_by_name       VARCHAR(190) NULL,
  -- anonymization flag
  is_anonymized         TINYINT(1)   NOT NULL DEFAULT 0,
  batch_id              BIGINT UNSIGNED NULL,
  created_by            INT UNSIGNED NULL,
  created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_students_inst_id (institution_id, id),
  UNIQUE KEY uk_students_inst_admno (institution_id, admission_no),
  UNIQUE KEY uk_students_inst_aadhaar (institution_id, aadhaar_bidx),
  KEY ix_students_inst_status (institution_id, status),
  KEY ix_students_inst_class (institution_id, current_class_id, current_section_id),
  CONSTRAINT fk_students_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_students_class FOREIGN KEY (institution_id, current_class_id) REFERENCES classes(institution_id, id),
  CONSTRAINT fk_students_section FOREIGN KEY (institution_id, current_section_id) REFERENCES sections(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS guardians;
CREATE TABLE guardians (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  student_id        INT UNSIGNED NOT NULL,
  relation          ENUM('father','mother','guardian','other') NOT NULL,
  is_primary        TINYINT(1)   NOT NULL DEFAULT 0,
  is_emergency      TINYINT(1)   NOT NULL DEFAULT 0,
  first_name        VARCHAR(96)  NOT NULL,
  last_name         VARCHAR(96)  NULL,
  display_name      VARCHAR(190) NOT NULL,
  gender            ENUM('male','female','other','undisclosed') NOT NULL DEFAULT 'undisclosed',
  mobile            VARCHAR(32)  NULL,
  alt_mobile        VARCHAR(32)  NULL,
  email             VARCHAR(190) NULL,
  occupation        VARCHAR(120) NULL,
  employer          VARCHAR(190) NULL,
  annual_income     DECIMAL(12,2) NULL,
  is_custodian      TINYINT(1)   NOT NULL DEFAULT 0,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_guardians_inst_id (institution_id, id),
  KEY ix_guardians_student (institution_id, student_id),
  CONSTRAINT fk_guardians_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_guardians_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS student_enrollments;
CREATE TABLE student_enrollments (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  student_id        INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  class_id          INT UNSIGNED NOT NULL,
  section_id        INT UNSIGNED NULL,
  roll_no           VARCHAR(16)  NULL,
  status            ENUM('enrolled','promoted','detained','transferred','passed_out','tc_issued','dropped') NOT NULL DEFAULT 'enrolled',
  enrolled_on       DATE         NULL,
  ended_on          DATE         NULL,
  remarks           VARCHAR(255) NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_enroll_inst_id (institution_id, id),
  UNIQUE KEY uk_enroll_student_year (institution_id, student_id, academic_year_id),
  KEY ix_enroll_class (institution_id, academic_year_id, class_id, section_id),
  CONSTRAINT fk_enroll_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_enroll_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_enroll_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_enroll_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id),
  CONSTRAINT fk_enroll_section FOREIGN KEY (institution_id, section_id) REFERENCES sections(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Sibling links (student <-> student)
DROP TABLE IF EXISTS student_siblings;
CREATE TABLE student_siblings (
  institution_id  INT UNSIGNED NOT NULL,
  student_id      INT UNSIGNED NOT NULL,
  sibling_id      INT UNSIGNED NOT NULL,
  PRIMARY KEY (institution_id, student_id, sibling_id),
  CONSTRAINT fk_sib_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_sib_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_sib_sibling FOREIGN KEY (institution_id, sibling_id) REFERENCES students(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Guardian login -> link to which students they can see
DROP TABLE IF EXISTS guardian_user_links;
CREATE TABLE guardian_user_links (
  institution_id  INT UNSIGNED NOT NULL,
  user_id         INT UNSIGNED NOT NULL,
  student_id      INT UNSIGNED NOT NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (institution_id, user_id, student_id),
  CONSTRAINT fk_gul_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_gul_user FOREIGN KEY (institution_id, user_id) REFERENCES users(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_gul_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 8. Polymorphic person sub-tables (addresses, IDs, bank, documents)
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS addresses;
CREATE TABLE addresses (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  person_type     ENUM('student','staff') NOT NULL,
  person_id       INT UNSIGNED NOT NULL,
  address_kind    ENUM('current','permanent','other') NOT NULL DEFAULT 'current',
  line1           VARCHAR(190) NOT NULL,
  line2           VARCHAR(190) NULL,
  city            VARCHAR(96)  NULL,
  district        VARCHAR(96)  NULL,
  state           VARCHAR(96)  NULL,
  pincode         VARCHAR(16)  NULL,
  country         VARCHAR(64)  NOT NULL DEFAULT 'India',
  same_as         ENUM('current','permanent') NULL,   -- toggle marker
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_addresses_inst_id (institution_id, id),
  UNIQUE KEY uk_addresses_person_kind (institution_id, person_type, person_id, address_kind),
  CONSTRAINT fk_addresses_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS bank_details;
CREATE TABLE bank_details (
  id                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id        INT UNSIGNED NOT NULL,
  person_type           ENUM('student','staff') NOT NULL,
  person_id             INT UNSIGNED NOT NULL,
  account_holder_name   VARCHAR(190) NOT NULL,
  bank_name             VARCHAR(190) NOT NULL,
  branch                VARCHAR(190) NULL,
  ifsc                  VARCHAR(16)  NULL,
  account_no_cipher     VARBINARY(512) NOT NULL,
  account_no_bidx       CHAR(64)     NOT NULL,
  account_no_last4      CHAR(4)      NOT NULL,
  upi_id_cipher         VARBINARY(512) NULL,
  upi_id_bidx           CHAR(64)     NULL,
  is_primary            TINYINT(1)   NOT NULL DEFAULT 1,
  verified              TINYINT(1)   NOT NULL DEFAULT 0,
  verified_by           INT UNSIGNED NULL,
  verified_at           DATETIME     NULL,
  created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_bank_inst_id (institution_id, id),
  KEY ix_bank_person (institution_id, person_type, person_id),
  KEY ix_bank_bidx (institution_id, account_no_bidx),
  CONSTRAINT fk_bank_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS id_documents;
CREATE TABLE id_documents (
  id                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id        INT UNSIGNED NOT NULL,
  person_type           ENUM('student','staff') NOT NULL,
  person_id             INT UNSIGNED NOT NULL,
  doc_type              ENUM('aadhaar','pan','voter','passport','driving_licence','ration','other') NOT NULL,
  number_cipher         VARBINARY(1024) NOT NULL,
  number_bidx           CHAR(64)     NOT NULL,
  number_last4          CHAR(4)      NULL,
  issued_by             VARCHAR(190) NULL,
  issue_date            DATE         NULL,
  valid_until           DATE         NULL,
  is_primary            TINYINT(1)   NOT NULL DEFAULT 0,
  created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_iddoc_inst_id (institution_id, id),
  UNIQUE KEY uk_iddoc_person_type (institution_id, person_type, person_id, doc_type, number_bidx),
  KEY ix_iddoc_bidx (institution_id, doc_type, number_bidx),
  CONSTRAINT fk_iddoc_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS documents;
CREATE TABLE documents (
  id                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id        INT UNSIGNED NOT NULL,
  person_type           ENUM('student','staff') NOT NULL,
  person_id             INT UNSIGNED NOT NULL,
  doc_type              VARCHAR(48)  NOT NULL,  -- e.g. birth_certificate, tc, marksheet, police_verification
  title                 VARCHAR(190) NULL,
  storage_path          VARCHAR(255) NOT NULL,  -- relative to storage/uploads/{institution_id}/
  mime_type             VARCHAR(96)  NOT NULL,
  size_bytes            INT UNSIGNED NOT NULL,
  sha256                CHAR(64)     NOT NULL,
  issue_date            DATE         NULL,
  expiry_date           DATE         NULL,
  uploaded_by           INT UNSIGNED NULL,
  batch_id              BIGINT UNSIGNED NULL,
  created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_docs_inst_id (institution_id, id),
  KEY ix_docs_person (institution_id, person_type, person_id),
  KEY ix_docs_expiry (institution_id, expiry_date),
  CONSTRAINT fk_docs_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 9. Teacher assignments (data-scope authority)
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS teacher_assignments;
CREATE TABLE teacher_assignments (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  staff_id          INT UNSIGNED NOT NULL,
  class_id          INT UNSIGNED NOT NULL,
  section_id        INT UNSIGNED NULL,
  subject_id        INT UNSIGNED NULL,
  is_class_teacher  TINYINT(1)   NOT NULL DEFAULT 0,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_ta_inst_id (institution_id, id),
  UNIQUE KEY uk_ta_unique (institution_id, academic_year_id, staff_id, class_id, section_id, subject_id, is_class_teacher),
  KEY ix_ta_scope (institution_id, academic_year_id, staff_id),
  KEY ix_ta_class (institution_id, academic_year_id, class_id, section_id),
  CONSTRAINT fk_ta_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_ta_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_ta_staff FOREIGN KEY (institution_id, staff_id) REFERENCES staff(institution_id, id),
  CONSTRAINT fk_ta_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id),
  CONSTRAINT fk_ta_section FOREIGN KEY (institution_id, section_id) REFERENCES sections(institution_id, id),
  CONSTRAINT fk_ta_subject FOREIGN KEY (institution_id, subject_id) REFERENCES subjects(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 10. Attendance, leave, holidays
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS holidays;
CREATE TABLE holidays (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  calendar_date   DATE         NOT NULL,
  name            VARCHAR(120) NOT NULL,
  applies_to      ENUM('all','students','staff') NOT NULL DEFAULT 'all',
  is_working_day  TINYINT(1)   NOT NULL DEFAULT 0,   -- e.g. sports day
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_holidays_inst_id (institution_id, id),
  UNIQUE KEY uk_holidays_inst_date_scope (institution_id, calendar_date, applies_to),
  CONSTRAINT fk_holidays_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS student_attendance;
CREATE TABLE student_attendance (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  student_id        INT UNSIGNED NOT NULL,
  class_id          INT UNSIGNED NOT NULL,
  section_id        INT UNSIGNED NULL,
  attendance_date   DATE         NOT NULL,
  period_no         SMALLINT UNSIGNED NOT NULL DEFAULT 0,   -- 0 = daily
  status            ENUM('present','absent','late','leave','half_day','excused') NOT NULL,
  remarks           VARCHAR(255) NULL,
  marked_by         INT UNSIGNED NOT NULL,
  marked_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_satt_inst_id (institution_id, id),
  UNIQUE KEY uk_satt_unique (institution_id, student_id, attendance_date, period_no),
  KEY ix_satt_class_date (institution_id, class_id, section_id, attendance_date),
  CONSTRAINT fk_satt_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_satt_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_satt_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_satt_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id),
  CONSTRAINT fk_satt_section FOREIGN KEY (institution_id, section_id) REFERENCES sections(institution_id, id),
  CONSTRAINT fk_satt_user FOREIGN KEY (institution_id, marked_by) REFERENCES users(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS staff_attendance;
CREATE TABLE staff_attendance (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  staff_id          INT UNSIGNED NOT NULL,
  attendance_date   DATE         NOT NULL,
  status            ENUM('present','absent','late','leave','half_day','on_duty') NOT NULL,
  in_time           TIME         NULL,
  out_time          TIME         NULL,
  source            ENUM('manual','biometric','import') NOT NULL DEFAULT 'manual',
  remarks           VARCHAR(255) NULL,
  marked_by         INT UNSIGNED NULL,
  marked_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_sfatt_inst_id (institution_id, id),
  UNIQUE KEY uk_sfatt_unique (institution_id, staff_id, attendance_date),
  KEY ix_sfatt_date (institution_id, attendance_date),
  CONSTRAINT fk_sfatt_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_sfatt_staff FOREIGN KEY (institution_id, staff_id) REFERENCES staff(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS leave_applications;
CREATE TABLE leave_applications (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  applicant_type    ENUM('student','staff') NOT NULL,
  applicant_id      INT UNSIGNED NOT NULL,
  leave_type_id     INT UNSIGNED NOT NULL,
  from_date         DATE         NOT NULL,
  to_date           DATE         NOT NULL,
  days              DECIMAL(5,2) NOT NULL,
  reason            VARCHAR(500) NOT NULL,
  status            ENUM('pending','approved','rejected','cancelled') NOT NULL DEFAULT 'pending',
  applied_by        INT UNSIGNED NOT NULL,
  applied_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  decided_by        INT UNSIGNED NULL,
  decided_at        DATETIME     NULL,
  decision_remarks  VARCHAR(500) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_leave_inst_id (institution_id, id),
  KEY ix_leave_applicant (institution_id, applicant_type, applicant_id, status),
  CONSTRAINT fk_leave_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_leave_type FOREIGN KEY (institution_id, leave_type_id) REFERENCES leave_types(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS leave_balances;
CREATE TABLE leave_balances (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  applicant_type  ENUM('student','staff') NOT NULL,
  applicant_id    INT UNSIGNED NOT NULL,
  leave_type_id   INT UNSIGNED NOT NULL,
  academic_year_id INT UNSIGNED NULL,
  year_label      VARCHAR(16)  NOT NULL,   -- FY or AY label
  entitled        DECIMAL(5,2) NOT NULL DEFAULT 0,
  used            DECIMAL(5,2) NOT NULL DEFAULT 0,
  carried_forward DECIMAL(5,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_leavebal_inst_id (institution_id, id),
  UNIQUE KEY uk_leavebal_unique (institution_id, applicant_type, applicant_id, leave_type_id, year_label),
  CONSTRAINT fk_leavebal_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_leavebal_type FOREIGN KEY (institution_id, leave_type_id) REFERENCES leave_types(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 11. Timetable
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS timetable_periods;
CREATE TABLE timetable_periods (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  label           VARCHAR(32)  NOT NULL,     -- P1, Break, Lunch
  start_time      TIME         NOT NULL,
  end_time        TIME         NOT NULL,
  is_break        TINYINT(1)   NOT NULL DEFAULT 0,
  sort_order      SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_ttperiod_inst_id (institution_id, id),
  UNIQUE KEY uk_ttperiod_inst_label (institution_id, label),
  CONSTRAINT fk_ttperiod_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS timetable_entries;
CREATE TABLE timetable_entries (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  class_id          INT UNSIGNED NOT NULL,
  section_id        INT UNSIGNED NULL,
  period_id         INT UNSIGNED NOT NULL,
  weekday           TINYINT UNSIGNED NOT NULL,  -- 1..7 (Mon..Sun)
  subject_id        INT UNSIGNED NULL,
  staff_id          INT UNSIGNED NULL,
  room              VARCHAR(32)  NULL,
  is_substitution   TINYINT(1)   NOT NULL DEFAULT 0,
  substitute_for_id INT UNSIGNED NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_ttentry_inst_id (institution_id, id),
  UNIQUE KEY uk_ttentry_slot (institution_id, academic_year_id, class_id, section_id, period_id, weekday),
  KEY ix_ttentry_teacher (institution_id, academic_year_id, staff_id, weekday, period_id),
  CONSTRAINT fk_ttentry_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_ttentry_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_ttentry_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id),
  CONSTRAINT fk_ttentry_section FOREIGN KEY (institution_id, section_id) REFERENCES sections(institution_id, id),
  CONSTRAINT fk_ttentry_period FOREIGN KEY (institution_id, period_id) REFERENCES timetable_periods(institution_id, id),
  CONSTRAINT fk_ttentry_subject FOREIGN KEY (institution_id, subject_id) REFERENCES subjects(institution_id, id),
  CONSTRAINT fk_ttentry_staff FOREIGN KEY (institution_id, staff_id) REFERENCES staff(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 12. Exams & marks
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS exam_terms;
CREATE TABLE exam_terms (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  name              VARCHAR(96)  NOT NULL,   -- Term 1, Half Yearly
  weightage_percent DECIMAL(5,2) NOT NULL DEFAULT 100.00,
  start_date        DATE         NULL,
  end_date          DATE         NULL,
  is_published      TINYINT(1)   NOT NULL DEFAULT 0,
  sort_order        SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_examterm_inst_id (institution_id, id),
  UNIQUE KEY uk_examterm_inst_name (institution_id, academic_year_id, name),
  CONSTRAINT fk_examterm_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_examterm_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS exams;
CREATE TABLE exams (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  term_id           INT UNSIGNED NOT NULL,
  class_id          INT UNSIGNED NOT NULL,
  subject_id        INT UNSIGNED NOT NULL,
  exam_date         DATE         NULL,
  max_marks         SMALLINT UNSIGNED NOT NULL DEFAULT 100,
  pass_marks        SMALLINT UNSIGNED NOT NULL DEFAULT 33,
  is_locked         TINYINT(1)   NOT NULL DEFAULT 0,
  locked_by         INT UNSIGNED NULL,
  locked_at         DATETIME     NULL,
  lock_reason       VARCHAR(255) NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_exams_inst_id (institution_id, id),
  UNIQUE KEY uk_exams_slot (institution_id, term_id, class_id, subject_id),
  CONSTRAINT fk_exams_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_exams_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_exams_term FOREIGN KEY (institution_id, term_id) REFERENCES exam_terms(institution_id, id),
  CONSTRAINT fk_exams_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id),
  CONSTRAINT fk_exams_subject FOREIGN KEY (institution_id, subject_id) REFERENCES subjects(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS marks;
CREATE TABLE marks (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  exam_id           INT UNSIGNED NOT NULL,
  student_id        INT UNSIGNED NOT NULL,
  class_id          INT UNSIGNED NOT NULL,
  section_id        INT UNSIGNED NULL,
  subject_id        INT UNSIGNED NOT NULL,
  marks_obtained    DECIMAL(6,2) NULL,
  is_absent         TINYINT(1)   NOT NULL DEFAULT 0,
  is_exempt         TINYINT(1)   NOT NULL DEFAULT 0,
  remarks           VARCHAR(255) NULL,
  entered_by        INT UNSIGNED NOT NULL,
  entered_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_marks_inst_id (institution_id, id),
  UNIQUE KEY uk_marks_unique (institution_id, exam_id, student_id),
  KEY ix_marks_student (institution_id, student_id, subject_id),
  CONSTRAINT fk_marks_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_marks_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_marks_exam FOREIGN KEY (institution_id, exam_id) REFERENCES exams(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_marks_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_marks_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id),
  CONSTRAINT fk_marks_section FOREIGN KEY (institution_id, section_id) REFERENCES sections(institution_id, id),
  CONSTRAINT fk_marks_subject FOREIGN KEY (institution_id, subject_id) REFERENCES subjects(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS report_cards;
CREATE TABLE report_cards (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  student_id        INT UNSIGNED NOT NULL,
  class_id          INT UNSIGNED NOT NULL,
  section_id        INT UNSIGNED NULL,
  total_marks       DECIMAL(8,2) NULL,
  max_marks         DECIMAL(8,2) NULL,
  percentage        DECIMAL(6,2) NULL,
  grade             VARCHAR(8)   NULL,
  gpa               DECIMAL(4,2) NULL,
  rank_in_class     INT UNSIGNED NULL,
  result            ENUM('pass','fail','compartment','withheld') NULL,
  is_published      TINYINT(1)   NOT NULL DEFAULT 0,
  published_at      DATETIME     NULL,
  computed_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_rc_inst_id (institution_id, id),
  UNIQUE KEY uk_rc_student_year (institution_id, student_id, academic_year_id),
  CONSTRAINT fk_rc_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_rc_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_rc_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_rc_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 13. Fees
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS fee_structures;
CREATE TABLE fee_structures (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  class_id          INT UNSIGNED NOT NULL,
  fee_head_id       INT UNSIGNED NOT NULL,
  amount            DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  frequency         ENUM('one_time','monthly','quarterly','half_yearly','annual') NOT NULL DEFAULT 'annual',
  sort_order        SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_feestruct_inst_id (institution_id, id),
  UNIQUE KEY uk_feestruct_unique (institution_id, academic_year_id, class_id, fee_head_id),
  CONSTRAINT fk_feestruct_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_feestruct_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_feestruct_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id),
  CONSTRAINT fk_feestruct_head FOREIGN KEY (institution_id, fee_head_id) REFERENCES fee_heads(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS fee_installments;
CREATE TABLE fee_installments (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  class_id          INT UNSIGNED NULL,
  name              VARCHAR(96)  NOT NULL,   -- Term 1, April
  due_date          DATE         NOT NULL,
  late_fine_per_day DECIMAL(8,2) NOT NULL DEFAULT 0.00,
  grace_days        SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  sort_order        SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_feeinst_inst_id (institution_id, id),
  CONSTRAINT fk_feeinst_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_feeinst_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_feeinst_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS invoices;
CREATE TABLE invoices (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  invoice_no        VARCHAR(32)  NOT NULL,
  student_id        INT UNSIGNED NOT NULL,
  class_id          INT UNSIGNED NULL,
  section_id        INT UNSIGNED NULL,
  installment_id    INT UNSIGNED NULL,
  issue_date        DATE         NOT NULL,
  due_date          DATE         NULL,
  subtotal          DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  discount_total    DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  tax_total         DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  late_fine_total   DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  grand_total       DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  paid_total        DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  balance           DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  status            ENUM('draft','issued','partially_paid','paid','cancelled','written_off') NOT NULL DEFAULT 'issued',
  cancelled_by      INT UNSIGNED NULL,
  cancelled_at      DATETIME     NULL,
  cancel_reason     VARCHAR(255) NULL,
  batch_id          BIGINT UNSIGNED NULL,
  created_by        INT UNSIGNED NOT NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_invoices_inst_id (institution_id, id),
  UNIQUE KEY uk_invoices_inst_no (institution_id, invoice_no),
  KEY ix_invoices_student (institution_id, student_id, status),
  KEY ix_invoices_due (institution_id, due_date, status),
  CONSTRAINT fk_invoices_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_invoices_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_invoices_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id),
  CONSTRAINT fk_invoices_class FOREIGN KEY (institution_id, class_id) REFERENCES classes(institution_id, id),
  CONSTRAINT fk_invoices_section FOREIGN KEY (institution_id, section_id) REFERENCES sections(institution_id, id),
  CONSTRAINT fk_invoices_installment FOREIGN KEY (institution_id, installment_id) REFERENCES fee_installments(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS invoice_items;
CREATE TABLE invoice_items (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  invoice_id      BIGINT UNSIGNED NOT NULL,
  fee_head_id     INT UNSIGNED NOT NULL,
  description     VARCHAR(190) NOT NULL,
  amount          DECIMAL(12,2) NOT NULL,
  discount        DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  tax_percent     DECIMAL(5,2)  NOT NULL DEFAULT 0.00,
  tax_amount      DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  total           DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_invitem_inst_id (institution_id, id),
  KEY ix_invitem_invoice (institution_id, invoice_id),
  CONSTRAINT fk_invitem_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_invitem_invoice FOREIGN KEY (institution_id, invoice_id) REFERENCES invoices(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_invitem_head FOREIGN KEY (institution_id, fee_head_id) REFERENCES fee_heads(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS concessions;
CREATE TABLE concessions (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  student_id        INT UNSIGNED NOT NULL,
  fee_head_id       INT UNSIGNED NULL,      -- NULL = all heads
  kind              ENUM('percent','amount','full') NOT NULL,
  value             DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  reason            VARCHAR(255) NOT NULL,
  valid_from        DATE         NULL,
  valid_to          DATE         NULL,
  approved_by       INT UNSIGNED NULL,
  approved_at       DATETIME     NULL,
  status            ENUM('pending','approved','rejected','expired') NOT NULL DEFAULT 'pending',
  created_by        INT UNSIGNED NOT NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_conc_inst_id (institution_id, id),
  KEY ix_conc_student (institution_id, student_id, status),
  CONSTRAINT fk_conc_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_conc_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_conc_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_conc_head FOREIGN KEY (institution_id, fee_head_id) REFERENCES fee_heads(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- IMMUTABLE after issue
DROP TABLE IF EXISTS fee_receipts;
CREATE TABLE fee_receipts (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  academic_year_id  INT UNSIGNED NOT NULL,
  receipt_no        VARCHAR(32)  NOT NULL,
  student_id        INT UNSIGNED NOT NULL,
  receipt_date      DATE         NOT NULL,
  total_amount      DECIMAL(12,2) NOT NULL,
  payment_mode      ENUM('cash','cheque','upi','card','bank','online','adjustment') NOT NULL,
  instrument_ref    VARCHAR(96)  NULL,
  bank_name         VARCHAR(120) NULL,
  remarks           VARCHAR(255) NULL,
  collected_by      INT UNSIGNED NOT NULL,
  status            ENUM('active','cancelled','refunded','bounced') NOT NULL DEFAULT 'active',
  cancelled_by      INT UNSIGNED NULL,
  cancelled_at      DATETIME     NULL,
  cancel_reason     VARCHAR(255) NULL,
  refunded_amount   DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  idempotency_key   CHAR(64)     NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_receipts_inst_id (institution_id, id),
  UNIQUE KEY uk_receipts_inst_no (institution_id, receipt_no),
  UNIQUE KEY uk_receipts_idem (institution_id, idempotency_key),
  KEY ix_receipts_student (institution_id, student_id, receipt_date),
  KEY ix_receipts_date (institution_id, receipt_date),
  CONSTRAINT fk_receipts_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_receipts_ay FOREIGN KEY (institution_id, academic_year_id) REFERENCES academic_years(institution_id, id),
  CONSTRAINT fk_receipts_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS fee_receipt_allocations;
CREATE TABLE fee_receipt_allocations (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  receipt_id      BIGINT UNSIGNED NOT NULL,
  invoice_id      BIGINT UNSIGNED NULL,
  invoice_item_id BIGINT UNSIGNED NULL,
  amount          DECIMAL(12,2) NOT NULL,
  is_advance      TINYINT(1)   NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_alloc_inst_id (institution_id, id),
  KEY ix_alloc_receipt (institution_id, receipt_id),
  KEY ix_alloc_invoice (institution_id, invoice_id),
  CONSTRAINT fk_alloc_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_alloc_receipt FOREIGN KEY (institution_id, receipt_id) REFERENCES fee_receipts(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_alloc_invoice FOREIGN KEY (institution_id, invoice_id) REFERENCES invoices(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 14. Payroll
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS salary_templates;
CREATE TABLE salary_templates (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  code            VARCHAR(32)  NOT NULL,
  name            VARCHAR(120) NOT NULL,
  grade           VARCHAR(32)  NULL,
  description     VARCHAR(255) NULL,
  is_active       TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uk_saltemp_inst_id (institution_id, id),
  UNIQUE KEY uk_saltemp_inst_code (institution_id, code),
  CONSTRAINT fk_saltemp_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS salary_template_components;
CREATE TABLE salary_template_components (
  institution_id     INT UNSIGNED NOT NULL,
  template_id        INT UNSIGNED NOT NULL,
  component_id       INT UNSIGNED NOT NULL,
  amount             DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  percent            DECIMAL(5,2)  NULL,
  PRIMARY KEY (institution_id, template_id, component_id),
  CONSTRAINT fk_saltc_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_saltc_template FOREIGN KEY (institution_id, template_id) REFERENCES salary_templates(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_saltc_component FOREIGN KEY (institution_id, component_id) REFERENCES salary_components(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS staff_salary;
CREATE TABLE staff_salary (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  staff_id        INT UNSIGNED NOT NULL,
  template_id     INT UNSIGNED NULL,
  basic           DECIMAL(12,2) NOT NULL,
  effective_from  DATE         NOT NULL,
  effective_to    DATE         NULL,
  notes           VARCHAR(255) NULL,
  created_by      INT UNSIGNED NOT NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_staffsal_inst_id (institution_id, id),
  KEY ix_staffsal_staff (institution_id, staff_id, effective_from),
  CONSTRAINT fk_staffsal_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_staffsal_staff FOREIGN KEY (institution_id, staff_id) REFERENCES staff(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_staffsal_template FOREIGN KEY (institution_id, template_id) REFERENCES salary_templates(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS staff_salary_overrides;
CREATE TABLE staff_salary_overrides (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  staff_id        INT UNSIGNED NOT NULL,
  component_id    INT UNSIGNED NOT NULL,
  amount          DECIMAL(12,2) NULL,
  percent         DECIMAL(5,2)  NULL,
  effective_from  DATE         NOT NULL,
  effective_to    DATE         NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_salso_inst_id (institution_id, id),
  KEY ix_salso_staff (institution_id, staff_id, component_id, effective_from),
  CONSTRAINT fk_salso_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_salso_staff FOREIGN KEY (institution_id, staff_id) REFERENCES staff(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_salso_component FOREIGN KEY (institution_id, component_id) REFERENCES salary_components(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS payroll_runs;
CREATE TABLE payroll_runs (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  period_year       SMALLINT UNSIGNED NOT NULL,
  period_month      TINYINT UNSIGNED NOT NULL,   -- 1..12
  status            ENUM('draft','generated','approved','paid','cancelled') NOT NULL DEFAULT 'draft',
  generated_by      INT UNSIGNED NULL,
  generated_at      DATETIME     NULL,
  approved_by       INT UNSIGNED NULL,
  approved_at       DATETIME     NULL,
  paid_by           INT UNSIGNED NULL,
  paid_at           DATETIME     NULL,
  cancel_reason     VARCHAR(255) NULL,
  notes             VARCHAR(500) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_payrun_inst_id (institution_id, id),
  UNIQUE KEY uk_payrun_period (institution_id, period_year, period_month),
  CONSTRAINT fk_payrun_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- IMMUTABLE after "approved"+"paid"
DROP TABLE IF EXISTS payslips;
CREATE TABLE payslips (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  payroll_run_id    BIGINT UNSIGNED NOT NULL,
  staff_id          INT UNSIGNED NOT NULL,
  slip_no           VARCHAR(32)  NOT NULL,
  period_year       SMALLINT UNSIGNED NOT NULL,
  period_month      TINYINT UNSIGNED NOT NULL,
  present_days      DECIMAL(5,2) NOT NULL DEFAULT 0,
  lop_days          DECIMAL(5,2) NOT NULL DEFAULT 0,
  gross             DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  total_deductions  DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  net_pay           DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  bank_account_last4 CHAR(4)     NULL,
  status            ENUM('draft','approved','paid','cancelled') NOT NULL DEFAULT 'draft',
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_payslips_inst_id (institution_id, id),
  UNIQUE KEY uk_payslips_inst_no (institution_id, slip_no),
  UNIQUE KEY uk_payslips_staff_period (institution_id, staff_id, period_year, period_month),
  KEY ix_payslips_run (institution_id, payroll_run_id),
  CONSTRAINT fk_payslips_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_payslips_run FOREIGN KEY (institution_id, payroll_run_id) REFERENCES payroll_runs(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_payslips_staff FOREIGN KEY (institution_id, staff_id) REFERENCES staff(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS payslip_lines;
CREATE TABLE payslip_lines (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  payslip_id      BIGINT UNSIGNED NOT NULL,
  component_id    INT UNSIGNED NOT NULL,
  line_type       ENUM('earning','deduction') NOT NULL,
  amount          DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_psline_inst_id (institution_id, id),
  KEY ix_psline_slip (institution_id, payslip_id),
  CONSTRAINT fk_psline_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_psline_slip FOREIGN KEY (institution_id, payslip_id) REFERENCES payslips(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_psline_component FOREIGN KEY (institution_id, component_id) REFERENCES salary_components(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS staff_loans;
CREATE TABLE staff_loans (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  staff_id        INT UNSIGNED NOT NULL,
  loan_type       ENUM('loan','advance') NOT NULL DEFAULT 'advance',
  principal       DECIMAL(12,2) NOT NULL,
  interest_rate   DECIMAL(5,2)  NOT NULL DEFAULT 0.00,
  emi_amount      DECIMAL(12,2) NOT NULL,
  start_date      DATE         NOT NULL,
  remaining       DECIMAL(12,2) NOT NULL,
  status          ENUM('active','closed','defaulted') NOT NULL DEFAULT 'active',
  notes           VARCHAR(255) NULL,
  created_by      INT UNSIGNED NOT NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_staffloan_inst_id (institution_id, id),
  KEY ix_staffloan_staff (institution_id, staff_id, status),
  CONSTRAINT fk_staffloan_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_staffloan_staff FOREIGN KEY (institution_id, staff_id) REFERENCES staff(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS loan_recoveries;
CREATE TABLE loan_recoveries (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  loan_id         BIGINT UNSIGNED NOT NULL,
  payslip_id      BIGINT UNSIGNED NULL,
  period_year     SMALLINT UNSIGNED NOT NULL,
  period_month    TINYINT UNSIGNED NOT NULL,
  amount          DECIMAL(12,2) NOT NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_loanrec_inst_id (institution_id, id),
  UNIQUE KEY uk_loanrec_unique (institution_id, loan_id, period_year, period_month),
  CONSTRAINT fk_loanrec_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_loanrec_loan FOREIGN KEY (institution_id, loan_id) REFERENCES staff_loans(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_loanrec_payslip FOREIGN KEY (institution_id, payslip_id) REFERENCES payslips(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 15. Transfers / Transfer Certificates
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS transfer_certificates;
CREATE TABLE transfer_certificates (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  student_id        INT UNSIGNED NOT NULL,
  serial_no         VARCHAR(32)  NOT NULL,
  requested_by      INT UNSIGNED NOT NULL,
  requested_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reason            VARCHAR(255) NULL,
  status            ENUM('requested','approved','issued','cancelled','duplicate') NOT NULL DEFAULT 'requested',
  approved_by       INT UNSIGNED NULL,
  approved_at       DATETIME     NULL,
  issued_by         INT UNSIGNED NULL,
  issued_at         DATETIME     NULL,
  is_duplicate_of   BIGINT UNSIGNED NULL,
  destination_school VARCHAR(190) NULL,
  remarks           VARCHAR(500) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_tc_inst_id (institution_id, id),
  UNIQUE KEY uk_tc_inst_serial (institution_id, serial_no),
  KEY ix_tc_student (institution_id, student_id),
  CONSTRAINT fk_tc_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_tc_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id),
  CONSTRAINT fk_tc_dup FOREIGN KEY (institution_id, is_duplicate_of) REFERENCES transfer_certificates(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 16. Notices, events, notifications
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS notices;
CREATE TABLE notices (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  title             VARCHAR(190) NOT NULL,
  body              MEDIUMTEXT   NOT NULL,
  audience          ENUM('all','role','class','section','staff','students','parents') NOT NULL DEFAULT 'all',
  audience_role_id  INT UNSIGNED NULL,
  audience_class_id INT UNSIGNED NULL,
  audience_section_id INT UNSIGNED NULL,
  publish_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at        DATETIME     NULL,
  is_pinned         TINYINT(1)   NOT NULL DEFAULT 0,
  created_by        INT UNSIGNED NOT NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_notices_inst_id (institution_id, id),
  KEY ix_notices_pub (institution_id, publish_at, expires_at),
  CONSTRAINT fk_notices_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_notices_class FOREIGN KEY (institution_id, audience_class_id) REFERENCES classes(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS notice_reads;
CREATE TABLE notice_reads (
  institution_id  INT UNSIGNED NOT NULL,
  notice_id       BIGINT UNSIGNED NOT NULL,
  user_id         INT UNSIGNED NOT NULL,
  read_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (institution_id, notice_id, user_id),
  CONSTRAINT fk_nr_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_nr_notice FOREIGN KEY (institution_id, notice_id) REFERENCES notices(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_nr_user FOREIGN KEY (institution_id, user_id) REFERENCES users(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS events;
CREATE TABLE events (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  title             VARCHAR(190) NOT NULL,
  description       TEXT         NULL,
  starts_at         DATETIME     NOT NULL,
  ends_at           DATETIME     NULL,
  all_day           TINYINT(1)   NOT NULL DEFAULT 0,
  venue             VARCHAR(190) NULL,
  audience          ENUM('all','staff','students','parents','class','section') NOT NULL DEFAULT 'all',
  audience_class_id INT UNSIGNED NULL,
  audience_section_id INT UNSIGNED NULL,
  created_by        INT UNSIGNED NOT NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_events_inst_id (institution_id, id),
  CONSTRAINT fk_events_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_events_class FOREIGN KEY (institution_id, audience_class_id) REFERENCES classes(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 17. Library
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS library_items;
CREATE TABLE library_items (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NOT NULL,
  item_code         VARCHAR(32)  NOT NULL,
  title             VARCHAR(190) NOT NULL,
  author            VARCHAR(190) NULL,
  isbn              VARCHAR(32)  NULL,
  publisher         VARCHAR(190) NULL,
  category          VARCHAR(64)  NULL,
  total_copies      INT UNSIGNED NOT NULL DEFAULT 1,
  available_copies  INT UNSIGNED NOT NULL DEFAULT 1,
  rack              VARCHAR(32)  NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_libitem_inst_id (institution_id, id),
  UNIQUE KEY uk_libitem_inst_code (institution_id, item_code),
  CONSTRAINT fk_libitem_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS library_issues;
CREATE TABLE library_issues (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  item_id         INT UNSIGNED NOT NULL,
  borrower_type   ENUM('student','staff') NOT NULL,
  borrower_id     INT UNSIGNED NOT NULL,
  issued_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  due_at          DATETIME     NOT NULL,
  returned_at     DATETIME     NULL,
  fine_amount     DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  fine_paid       TINYINT(1)   NOT NULL DEFAULT 0,
  status          ENUM('issued','returned','lost','damaged') NOT NULL DEFAULT 'issued',
  remarks         VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_libissue_inst_id (institution_id, id),
  KEY ix_libissue_borrower (institution_id, borrower_type, borrower_id, status),
  CONSTRAINT fk_libissue_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_libissue_item FOREIGN KEY (institution_id, item_id) REFERENCES library_items(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 18. Transport
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS transport_routes;
CREATE TABLE transport_routes (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  code            VARCHAR(32)  NOT NULL,
  name            VARCHAR(120) NOT NULL,
  vehicle_no      VARCHAR(32)  NULL,
  driver_name     VARCHAR(120) NULL,
  driver_phone    VARCHAR(32)  NULL,
  capacity        SMALLINT UNSIGNED NULL,
  is_active       TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uk_transroute_inst_id (institution_id, id),
  UNIQUE KEY uk_transroute_inst_code (institution_id, code),
  CONSTRAINT fk_transroute_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS transport_stops;
CREATE TABLE transport_stops (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  route_id        INT UNSIGNED NOT NULL,
  name            VARCHAR(120) NOT NULL,
  pickup_time     TIME         NULL,
  drop_time       TIME         NULL,
  sort_order      SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uk_transstop_inst_id (institution_id, id),
  CONSTRAINT fk_transstop_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_transstop_route FOREIGN KEY (institution_id, route_id) REFERENCES transport_routes(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS transport_allotments;
CREATE TABLE transport_allotments (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  student_id      INT UNSIGNED NOT NULL,
  route_id        INT UNSIGNED NOT NULL,
  stop_id         INT UNSIGNED NULL,
  from_date       DATE         NOT NULL,
  to_date         DATE         NULL,
  is_active       TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uk_transallot_inst_id (institution_id, id),
  KEY ix_transallot_student (institution_id, student_id, is_active),
  CONSTRAINT fk_transallot_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_transallot_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id) ON DELETE CASCADE,
  CONSTRAINT fk_transallot_route FOREIGN KEY (institution_id, route_id) REFERENCES transport_routes(institution_id, id),
  CONSTRAINT fk_transallot_stop FOREIGN KEY (institution_id, stop_id) REFERENCES transport_stops(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 19. Inventory
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS inventory_items;
CREATE TABLE inventory_items (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  code            VARCHAR(32)  NOT NULL,
  name            VARCHAR(190) NOT NULL,
  category        VARCHAR(96)  NULL,
  unit            VARCHAR(16)  NOT NULL DEFAULT 'nos',
  quantity        DECIMAL(12,2) NOT NULL DEFAULT 0,
  reorder_level   DECIMAL(12,2) NOT NULL DEFAULT 0,
  location        VARCHAR(96)  NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_invitemx_inst_id (institution_id, id),
  UNIQUE KEY uk_invitemx_inst_code (institution_id, code),
  CONSTRAINT fk_invitemx_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS inventory_movements;
CREATE TABLE inventory_movements (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  item_id         INT UNSIGNED NOT NULL,
  movement_type   ENUM('purchase','issue','return','damage','adjustment') NOT NULL,
  quantity        DECIMAL(12,2) NOT NULL,
  reference       VARCHAR(120) NULL,
  notes           VARCHAR(255) NULL,
  recorded_by     INT UNSIGNED NOT NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_invmov_inst_id (institution_id, id),
  KEY ix_invmov_item (institution_id, item_id),
  CONSTRAINT fk_invmov_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_invmov_item FOREIGN KEY (institution_id, item_id) REFERENCES inventory_items(institution_id, id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 20. Certificates (bonafide, character, study)
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS certificates;
CREATE TABLE certificates (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  student_id      INT UNSIGNED NOT NULL,
  cert_type       VARCHAR(48)  NOT NULL,
  serial_no       VARCHAR(32)  NOT NULL,
  purpose         VARCHAR(190) NULL,
  issued_by       INT UNSIGNED NOT NULL,
  issued_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  is_cancelled    TINYINT(1)   NOT NULL DEFAULT 0,
  cancel_reason   VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_certs_inst_id (institution_id, id),
  UNIQUE KEY uk_certs_inst_serial (institution_id, serial_no),
  KEY ix_certs_student (institution_id, student_id, cert_type),
  CONSTRAINT fk_certs_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_certs_student FOREIGN KEY (institution_id, student_id) REFERENCES students(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 21. Number sequences
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS number_sequences;
CREATE TABLE number_sequences (
  institution_id  INT UNSIGNED NOT NULL,
  seq_key         VARCHAR(48)  NOT NULL,   -- admission, receipt, invoice, tc, employee, certificate, payslip
  prefix          VARCHAR(16)  NOT NULL DEFAULT '',
  suffix          VARCHAR(16)  NOT NULL DEFAULT '',
  next_value      BIGINT UNSIGNED NOT NULL DEFAULT 1,
  padding         TINYINT UNSIGNED NOT NULL DEFAULT 5,
  reset_yearly    TINYINT(1)   NOT NULL DEFAULT 0,
  reset_label     VARCHAR(16)  NULL,
  updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (institution_id, seq_key),
  CONSTRAINT fk_nseq_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 22. Bulk import batches & audit logs
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS import_batches;
CREATE TABLE import_batches (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  import_type     VARCHAR(48)  NOT NULL,   -- students, staff, fee_collection, marks, ...
  original_name   VARCHAR(190) NULL,
  storage_path    VARCHAR(255) NULL,
  total_rows      INT UNSIGNED NOT NULL DEFAULT 0,
  valid_rows      INT UNSIGNED NOT NULL DEFAULT 0,
  error_rows      INT UNSIGNED NOT NULL DEFAULT 0,
  inserted_rows   INT UNSIGNED NOT NULL DEFAULT 0,
  updated_rows    INT UNSIGNED NOT NULL DEFAULT 0,
  status          ENUM('pending','preview','committed','failed','reverted') NOT NULL DEFAULT 'pending',
  error_file_path VARCHAR(255) NULL,
  reverted_by     INT UNSIGNED NULL,
  reverted_at     DATETIME     NULL,
  revert_reason   VARCHAR(255) NULL,
  performed_by    INT UNSIGNED NOT NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_importbatch_inst_id (institution_id, id),
  KEY ix_importbatch_inst_type (institution_id, import_type, status),
  CONSTRAINT fk_importbatch_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Append-only
DROP TABLE IF EXISTS audit_logs;
CREATE TABLE audit_logs (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id    INT UNSIGNED NULL,
  user_id           INT UNSIGNED NULL,
  platform_user_id  INT UNSIGNED NULL,
  impersonated_by   INT UNSIGNED NULL,          -- platform_user_id if impersonating
  action            VARCHAR(64)  NOT NULL,      -- e.g. user.login, student.view_sensitive
  entity_type       VARCHAR(64)  NULL,
  entity_id         BIGINT UNSIGNED NULL,
  old_values        JSON         NULL,
  new_values        JSON         NULL,
  ip                VARBINARY(16) NULL,
  user_agent        VARCHAR(255) NULL,
  correlation_id    CHAR(36)     NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_al_inst_time (institution_id, created_at),
  KEY ix_al_user_time (institution_id, user_id, created_at),
  KEY ix_al_action_time (action, created_at),
  KEY ix_al_entity (entity_type, entity_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 23. Idempotency, exports, backup metadata
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS idempotency_keys;
CREATE TABLE idempotency_keys (
  institution_id  INT UNSIGNED NOT NULL,
  idem_key        CHAR(64)     NOT NULL,
  scope           VARCHAR(48)  NOT NULL,
  response_json   JSON         NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at      DATETIME     NOT NULL,
  PRIMARY KEY (institution_id, idem_key),
  CONSTRAINT fk_idem_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS export_jobs;
CREATE TABLE export_jobs (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  export_type     VARCHAR(64)  NOT NULL,
  params_json     JSON         NULL,
  status          ENUM('queued','running','done','failed','expired') NOT NULL DEFAULT 'queued',
  storage_path    VARCHAR(255) NULL,
  requested_by    INT UNSIGNED NOT NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at      DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uk_exportjobs_inst_id (institution_id, id),
  CONSTRAINT fk_exportjobs_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS backup_jobs;
CREATE TABLE backup_jobs (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NULL,
  scope           ENUM('platform','institution') NOT NULL,
  status          ENUM('queued','running','done','failed') NOT NULL DEFAULT 'queued',
  storage_path    VARCHAR(255) NULL,
  size_bytes      BIGINT UNSIGNED NULL,
  checksum_sha256 CHAR(64)     NULL,
  started_by      INT UNSIGNED NULL,
  started_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at     DATETIME     NULL,
  notes           VARCHAR(500) NULL,
  PRIMARY KEY (id),
  KEY ix_bkjob_inst (institution_id, started_at),
  CONSTRAINT fk_bkjob_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 24. Retention / consent / data-subject requests
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS data_subject_requests;
CREATE TABLE data_subject_requests (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  institution_id  INT UNSIGNED NOT NULL,
  person_type     ENUM('student','staff') NOT NULL,
  person_id       INT UNSIGNED NOT NULL,
  request_type    ENUM('access','export','rectify','erase') NOT NULL,
  status          ENUM('received','in_progress','fulfilled','rejected') NOT NULL DEFAULT 'received',
  request_notes   VARCHAR(500) NULL,
  handled_by      INT UNSIGNED NULL,
  handled_at      DATETIME     NULL,
  export_job_id   BIGINT UNSIGNED NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_dsr_inst_id (institution_id, id),
  KEY ix_dsr_person (institution_id, person_type, person_id),
  CONSTRAINT fk_dsr_inst FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE,
  CONSTRAINT fk_dsr_export FOREIGN KEY (institution_id, export_job_id) REFERENCES export_jobs(institution_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- 25. Schema versioning (application-level, no Flyway)
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS schema_migrations;
CREATE TABLE schema_migrations (
  version     VARCHAR(64)  NOT NULL,
  applied_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  checksum    CHAR(64)     NULL,
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;