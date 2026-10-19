-- 2026-10-19: stories - a guided flow that alternates full-page slides (the
-- benefits of a step) with the real platform page (live, with a coach panel:
-- the task, Back / Next). The Quick Start is the first story. Content is data:
-- edited in the Demo Console (Stories), exported to seed/stories.json.
CREATE TABLE IF NOT EXISTS cx_demo_story (
  story_key   VARCHAR(40)  NOT NULL PRIMARY KEY,
  title       VARCHAR(160) NOT NULL,
  subtitle    VARCHAR(255) NULL,
  minutes     INT          NOT NULL DEFAULT 8,
  status      ENUM('draft','live','retired') NOT NULL DEFAULT 'draft',
  sort        INT          NOT NULL DEFAULT 100,
  updated_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  updated_by  VARCHAR(120) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- kind slide: a full page (p=story). kind live: target_path opens for real, with
-- the coach panel; {wsDsn} = the prospect's own sandbox. While the step is
-- active, the target (and allow_paths, * = wildcard) gets a "story pass": a
-- Locked / Hidden page opens, a box-wide or server page never does.
-- done_when {"event":"chat_answer","count":1}: the coach panel lights up Next.
CREATE TABLE IF NOT EXISTS cx_demo_story_step (
  id           INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
  story_key    VARCHAR(40)  NOT NULL,
  step_no      INT          NOT NULL,
  kind         ENUM('slide','live') NOT NULL DEFAULT 'slide',
  kicker       VARCHAR(120) NULL,
  title        VARCHAR(200) NOT NULL,
  body_html    MEDIUMTEXT   NULL,
  benefits     JSON         NULL,
  task_html    TEXT         NULL,
  target_path  VARCHAR(500) NULL,
  allow_paths  JSON         NULL,
  card_key     VARCHAR(60)  NULL,
  done_when    JSON         NULL,
  buttons      JSON         NULL,
  status       ENUM('draft','live','retired') NOT NULL DEFAULT 'live',
  updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  updated_by   VARCHAR(120) NULL,
  UNIQUE KEY uq_step (story_key, step_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cx_demo_story_progress (
  pid         VARCHAR(10)  NOT NULL,
  story_key   VARCHAR(40)  NOT NULL,
  step_no     INT          NOT NULL DEFAULT 1,
  started_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  step_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  done_at     DATETIME     NULL,
  PRIMARY KEY (pid, story_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
