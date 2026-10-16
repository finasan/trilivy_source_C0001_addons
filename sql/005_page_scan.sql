-- 2026-10-16: the Access map by section. menu_seen_at = the last time a menu scan
-- (or a menu render) found this page in its menu; a page a later scan of its
-- section did not find any more is shown as "no longer in the menu".
ALTER TABLE cx_demo_pages
  ADD COLUMN menu_seen_at DATETIME NULL AFTER source;
