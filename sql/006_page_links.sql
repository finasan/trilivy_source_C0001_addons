-- 2026-10-16: which menus link to which page. One page (cx_demo_pages, one row per
-- path = one setting) can sit in several menus; the Access map shows it in every
-- section that links to it, under that menu's own group and label. Rebuilt by the
-- menu scans; seen_at older than the section's last scan = no longer in that menu.
CREATE TABLE IF NOT EXISTS cx_demo_page_links (
  area     VARCHAR(30)  NOT NULL,
  path     VARCHAR(255) NOT NULL,
  grp      VARCHAR(160) NULL,
  label    VARCHAR(120) NOT NULL,
  sort     INT          NOT NULL DEFAULT 1000,
  seen_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (area, path),
  KEY k_path (path)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
