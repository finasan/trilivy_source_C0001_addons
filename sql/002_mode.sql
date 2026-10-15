-- 2026-10-15: per-prospect experience. guided = the curated demo (default);
-- explorer = the real platform pages that are safe on a shared box.
ALTER TABLE cx_demo_prospects
  ADD COLUMN mode ENUM('guided','explorer') NOT NULL DEFAULT 'guided' AFTER caps_preset;
