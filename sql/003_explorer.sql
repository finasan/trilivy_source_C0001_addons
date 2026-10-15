-- 2026-10-15: "Full platform" experience. explorer_mode = what the feature is
-- for a prospect in Full platform mode; NULL = the same as mode (Guided).
ALTER TABLE cx_demo_features
  ADD COLUMN explorer_mode ENUM('open','capped','pitch','hidden') NULL AFTER mode;
