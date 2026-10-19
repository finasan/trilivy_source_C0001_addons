-- 2026-10-16: the Access map. One row per platform page (menu item), chosen
-- page by page for each experience:
--   open    the page works
--   guard   the page works, with an instructions popup (guard_html) on the first
--           open per session and a "What can I do here?" button; readonly=1
--           also refuses anything but GET on that page
--   pitch   locked: the sales card (card_key, else the feature map's card)
--   hidden  removed from the menus; opening it says "not part of the demo"
-- NULL = inherit from the feature map (cx_demo_features, by path pattern).
-- safety comes from the two-marker audit: a page that shows other prospects'
-- data ('boxwide') or changes the server ('server') is never opened, whatever
-- the mode says.
CREATE TABLE IF NOT EXISTS cx_demo_pages (
  id             INT AUTO_INCREMENT PRIMARY KEY,
  path           VARCHAR(255) NOT NULL,
  area           VARCHAR(30)  NOT NULL DEFAULT 'other',
  grp            VARCHAR(80)  NULL,
  label          VARCHAR(120) NOT NULL,
  sort           INT          NOT NULL DEFAULT 1000,
  guided_mode    ENUM('open','guard','pitch','hidden') NULL,
  explorer_mode  ENUM('open','guard','pitch','hidden') NULL,
  readonly       TINYINT(1)   NOT NULL DEFAULT 0,
  safety         ENUM('sandbox','boxwide','server','unknown') NOT NULL DEFAULT 'unknown',
  guard_title    VARCHAR(160) NULL,
  guard_html     TEXT         NULL,
  card_key       VARCHAR(60)  NULL,
  source         VARCHAR(20)  NOT NULL DEFAULT 'menu',
  first_seen     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME     NULL ON UPDATE CURRENT_TIMESTAMP,
  updated_by     VARCHAR(120) NULL,
  UNIQUE KEY uk_path (path)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
