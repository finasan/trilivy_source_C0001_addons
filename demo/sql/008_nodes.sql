-- 2026-10-19: menu codes. Every item of a menu_config menu (Manage, KB, Quick,
-- Instance) - groups AND links - is a node, keyed by its full trail
-- ("RAG › Core Workflow › Maker"), so the same page can behave differently
-- in two places of the menu. Structure comes from the menu scan; operators set
-- the code (Full platform only):
--   SPT  sales card on this group, the same card on everything below it that has no code of its own
--   SPS  this item's own card (locked)
--   SPO  this item's own card with "Open it now" (the real page then works)
--   OPE  open, no card
--   HID  removed from the menu; its address says "not part of the demo"
-- An item without a code takes its nearest ancestor's code (and that ancestor's card).
CREATE TABLE IF NOT EXISTS cx_demo_nodes (
  id          INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
  area        VARCHAR(30)  NOT NULL,
  trail       VARCHAR(255) NOT NULL,
  label       VARCHAR(120) NOT NULL,
  kind        ENUM('group','link') NOT NULL DEFAULT 'link',
  path        VARCHAR(255) NULL,
  depth       INT          NOT NULL DEFAULT 1,
  sort        INT          NOT NULL DEFAULT 1000,
  code        ENUM('SPT','SPS','SPO','OPE','HID') NULL,
  card_key    VARCHAR(60)  NULL,
  seen_at     DATETIME     NULL,
  updated_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  updated_by  VARCHAR(120) NULL,
  UNIQUE KEY uq_node (area, trail),
  KEY k_path (path)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
