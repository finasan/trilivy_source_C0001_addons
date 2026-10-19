-- Trilivy Demo add-on - database addon_demo (playbook 19 runs this once).
-- Never edit a shipped migration: add 002_..., 003_... instead.

CREATE TABLE IF NOT EXISTS cx_demo_settings (
  k           VARCHAR(80) PRIMARY KEY,
  v           MEDIUMTEXT NULL,
  updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  updated_by  VARCHAR(120) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_operators (
  oid           INT PRIMARY KEY,
  role          ENUM('admin','sales','se','system') NOT NULL DEFAULT 'sales',
  display_name  VARCHAR(120) NULL,
  email         VARCHAR(200) NULL,
  active        TINYINT(1) NOT NULL DEFAULT 1,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_prospects (
  seq             INT AUTO_INCREMENT PRIMARY KEY,
  pid             VARCHAR(8) NOT NULL,
  oid             INT NULL,
  email           VARCHAR(200) NOT NULL,
  fname           VARCHAR(50) NULL,
  lname           VARCHAR(50) NULL,
  company         VARCHAR(100) NULL,
  audience        ENUM('business','it','finance','hr','exec') NOT NULL DEFAULT 'business',
  industry        VARCHAR(80) NULL,
  language        CHAR(2) NOT NULL DEFAULT 'en',
  owner_oid       INT NULL,
  status          ENUM('building','invited','active','expiring','expired','suspended','purged','converted','failed') NOT NULL DEFAULT 'building',
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  invited_at      DATETIME NULL,
  first_login_at  DATETIME NULL,
  last_seen_at    DATETIME NULL,
  expires_at      DATETIME NOT NULL,
  purge_after     DATETIME NULL,
  consent_at      DATETIME NULL,
  consent_version VARCHAR(20) NULL,
  score           INT NOT NULL DEFAULT 0,
  score_band      ENUM('cold','warm','hot') NOT NULL DEFAULT 'cold',
  caps_preset     VARCHAR(20) NOT NULL DEFAULT 'standard',
  caps_json       TEXT NULL,
  notes           TEXT NULL,
  converted_company_id INT NULL,
  purged_summary_json  TEXT NULL,
  created_by      INT NULL,
  UNIQUE KEY uq_pid (pid),
  KEY k_oid (oid),
  KEY k_status (status),
  KEY k_owner (owner_oid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_sandbox_ops (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY,
  pid          VARCHAR(8) NOT NULL,
  op           ENUM('create','reset','purge') NOT NULL,
  step         VARCHAR(60) NOT NULL,
  status       ENUM('running','ok','failed','rolled_back','skipped') NOT NULL,
  detail       TEXT NULL,
  started_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  finished_at  DATETIME(3) NULL,
  KEY k_pid (pid, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_events (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY,
  pid          VARCHAR(8) NOT NULL,
  session_id   VARCHAR(64) NULL,
  ts           DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  type         VARCHAR(40) NOT NULL,
  feature_key  VARCHAR(60) NULL,
  page         VARCHAR(255) NULL,
  detail       JSON NULL,
  duration_ms  INT NULL,
  ip           VARCHAR(45) NULL,
  ua_hash      CHAR(16) NULL,
  KEY k_pid_ts (pid, ts),
  KEY k_type_ts (type, ts),
  KEY k_feature (feature_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_features (
  feature_key    VARCHAR(60) PRIMARY KEY,
  title          VARCHAR(120) NOT NULL,
  mode           ENUM('open','capped','pitch','hidden') NOT NULL,
  path_patterns  JSON NOT NULL,
  nav_group      VARCHAR(40) NULL,
  nav_label      VARCHAR(60) NULL,
  sort           INT NOT NULL DEFAULT 100,
  notes          TEXT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_pitch (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  feature_key  VARCHAR(60) NOT NULL,
  audience     VARCHAR(20) NOT NULL DEFAULT 'business',
  lang         CHAR(2) NOT NULL DEFAULT 'en',
  version      INT NOT NULL DEFAULT 1,
  status       ENUM('draft','verified','live','retired') NOT NULL DEFAULT 'draft',
  kicker       VARCHAR(120) NULL,
  headline     VARCHAR(200) NOT NULL,
  why_html     TEXT NULL,
  how_html     TEXT NULL,
  objections   JSON NULL,
  proof_html   TEXT NULL,
  cta          JSON NULL,
  verified_by  VARCHAR(120) NULL,
  verified_at  DATETIME NULL,
  updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  updated_by   VARCHAR(120) NULL,
  UNIQUE KEY uq_card (feature_key, audience, lang)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_moments (
  moment_key         VARCHAR(60) PRIMARY KEY,
  title              VARCHAR(120) NOT NULL,
  trigger_json       JSON NOT NULL,
  feature_key        VARCHAR(60) NOT NULL,
  once_per_prospect  TINYINT(1) NOT NULL DEFAULT 1,
  active             TINYINT(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_pitch_seen (
  pid        VARCHAR(8) NOT NULL,
  card_key   VARCHAR(80) NOT NULL,
  first_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  times      INT NOT NULL DEFAULT 1,
  PRIMARY KEY (pid, card_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_wishlist (
  pid          VARCHAR(8) NOT NULL,
  feature_key  VARCHAR(60) NOT NULL,
  added_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  note         VARCHAR(500) NULL,
  PRIMARY KEY (pid, feature_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_usage_day (
  pid        VARCHAR(8) NOT NULL,
  day        DATE NOT NULL,
  questions  INT NOT NULL DEFAULT 0,
  tokens     INT NOT NULL DEFAULT 0,
  asks       INT NOT NULL DEFAULT 0,
  uploads    INT NOT NULL DEFAULT 0,
  upload_mb  DECIMAL(10,2) NOT NULL DEFAULT 0,
  ingests    INT NOT NULL DEFAULT 0,
  PRIMARY KEY (pid, day)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_mail_log (
  id         BIGINT AUTO_INCREMENT PRIMARY KEY,
  pid        VARCHAR(8) NULL,
  template   VARCHAR(40) NOT NULL,
  to_email   VARCHAR(200) NOT NULL,
  subject    VARCHAR(250) NULL,
  sent_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status     VARCHAR(20) NOT NULL,
  error      VARCHAR(500) NULL,
  KEY k_pid (pid),
  KEY k_tpl (template, pid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_docs (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY,
  pid          VARCHAR(8) NOT NULL,
  orig_name    VARCHAR(255) NOT NULL,
  stored_name  VARCHAR(120) NOT NULL,
  size_bytes   BIGINT NOT NULL,
  uploaded_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ingest_state VARCHAR(20) NOT NULL DEFAULT 'queued',
  ingest_note  VARCHAR(500) NULL,
  deleted_at   DATETIME NULL,
  KEY k_pid (pid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
