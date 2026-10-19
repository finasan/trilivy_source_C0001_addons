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
- `seed/`        features, pitch cards, settings, operators, Access map pages, menu codes (nodes.json),
                 stories (stories.json) - Export to package refreshes them
- `assets/samples/` the Quick Start's sample documents (served zipped: asset f=sample_docs.zip)

## Stories and menu codes (0.6, 2026-10-19)

- **Stories** (`cx_demo_story*`, Console > Stories, `pages/story.cfm`): a guided flow that alternates
  full-page slides with the real platform page plus a coach panel (demo.js). While a live step runs,
  its page gets a "story pass" in `request_gate` (also in Guided); a box-wide or server page never
  opens - the step is then shown as a slide with its card. The Quick Start is the first story.
- **Menu codes** (`cx_demo_nodes`, Console > Menu codes): per place in a menugen menu (Manage, KB,
  Quick) and the Instance menu, Full platform only. SPT group card inherited downwards, SPS own card,
  SPO own card + "Open it now", OPE open, HID removed. No code = the nearest group's code and card.
  A page's address follows the most open of its places; codes win over the Access map's Full-platform
  choice; the safety label still wins over everything.
- `install/`     bootstrap.sh (every install), backup.sh, restore.sh
- `py/`          seed.py, cron_call.py
- `systemd/`     hourly + daily timers
- `tests/`       safety tests (leak, tamper, path sweep)

Rule: no hand edits on a demo box. Change the source here, commit, dev-push.

## Where things live

This folder is replaced on every deploy (the previous copy is moved to
`addons/.demo.prev`). So anything that must survive a deploy, hold a secret, or
belong to another service lives outside it.

| Path | What | Owner / mode | Created by | Why it is outside |
|---|---|---|---|---|
| `/home/trilivyapp/addons/demo/` | this code (live copy) | trilivy | playbook 19 | - |
| `/home/trilivyapp/addons/.demo.prev/` | the previous version, for rollback | trilivy | playbook 19 / dev-push | kept apart from the live copy |
| `/root/addon-packages/demo-*.tar.gz` | built packages (install input) | root | `trlv_addon.py build\|dev-push` | the input that replaces this folder |
| `/etc/trilivy/addon_demo.env` | `OBTX_ADDON_DEMO_DB_PASS`, the DB password | root, 0600 | playbook 19 | secret: kept away from the web app user and out of git |
| `/etc/trilivy/addon_demo_svc.env` | `DEMO_SVC_EMAIL` / `DEMO_SVC_PASSWORD`, the timers' account | root, 0600 | `py/seed.py` | secret, same reasons |
| `/etc/systemd/system/lucee.service.d/30-trilivy-addon-demo.conf` | loads `addon_demo.env` into Lucee | root | playbook 19 | systemd reads drop-ins only from there |
| `/etc/systemd/system/trilivy-addon-demo-{hourly,daily}.{service,timer}` | installed copies of `systemd/` (hourly at :07, daily at 05:30 UTC) | root | playbook 19 | systemd reads units only from there |
| MySQL `addon_demo` (`/var/lib/mysql/addon_demo`) | runtime data: prospects, events, settings | mysql | playbook 19, `sql/` migrations | owned by mysqld; must survive deploys |
| MySQL `inst_*_vdem_p*`, Postgres `ragt_vdem_p*`, `ai_data` rows (`demo_user`, `vdem_p*`) | the per-prospect sandboxes | mysql / postgres | `lib/Sandbox.cfc` | platform data, not add-on files |
| `/home/trilivyapp/containers/instances/inst_*_vdem_p*` | sandbox upload folders | trilivy | `lib/Sandbox.cfc` | platform instance layout |
| `/home/trilivy_backups/demo/<YYYYMMDD>/` | nightly backup of all of the above runtime data, 7 days | root, 0700 | `install/backup.sh` (daily timer) | must survive a deploy or a rebuild |
| `/var/lib/trilivy/addon-exports/demo/` | "Export to package" output (read by the fleet seed-pull) | trilivy, 2770 | `install/bootstrap.sh`, `pages/package.cfm` | runtime output, not source |

Restore after a rebuild: `playbook 19 -e addon_restore=latest` (runs `install/restore.sh`).
