# Trilivy Demo add-on

Turns a Trilivy server into the Demo Box: operator-created prospects, one private
sandbox (cloned assistant) per prospect, default-deny access, pitch popups for
locked features, full activity logging, expiry and purge.

Never part of a platform release. Built from this git repository by the fleet
(`fleet_ops/trlv_addon.py build|dev-push demo`) and installed by playbook 19.

- `addon.json`   name, version, hooks, pages (hook_api 1)
- `Hooks.cfc`    the hook answers (request_gate is the enforcement point)
- `lib/`         Demo (settings, prospects, features, events, score), Sandbox, Mailer
- `pages/`       Demo Console (operators) and the prospect pages
- `assets/`      demo.js / demo.css (popups, tour, beacon)
- `sql/`         migrations (never edit a shipped one)
- `seed/`        features, pitch cards, settings, operators (Export to package refreshes them)
- `install/`     bootstrap.sh (every install), backup.sh, restore.sh
- `py/`          seed.py, cron_call.py
- `systemd/`     hourly + daily timers
- `tests/`       safety tests (leak, tamper, path sweep)

Rule: no hand edits on a demo box. Change the source here, commit, dev-push.
