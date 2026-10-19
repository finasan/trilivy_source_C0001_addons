#!/bin/bash
# Demo add-on - put the runtime data of the latest backup back (prospects,
# events, sandboxes). Used after a rebuild: playbook 19 -e addon_restore=latest.
# The backup folder must be on this box (/home/trilivy_backups/demo/<date>/);
# after a move to a NEW server, copy it there first.
# ai_data is rebuilt from the release on a new box, so the prospect accounts,
# sandbox instances and grants come back from ai_data_demo_rows.sql (INSERT
# IGNORE: a row whose id is already taken on the new box is skipped and
# reported). Lucee is restarted by playbook 19 afterwards / at the next reinit,
# which registers the sandbox datasources again.
set -euo pipefail
B=$(ls -1d /home/trilivy_backups/demo/2* 2>/dev/null | tail -1 || true)
[ -n "$B" ] || { echo "no backup to restore"; exit 0; }
echo "restoring from $B"
mysql addon_demo < "$B/addon_demo.sql"
for f in "$B"/inst_*_vdem_p*.sql "$B"/INST_*_vdem_p*.sql; do
    [ -f "$f" ] || continue
    db=$(basename "$f" .sql)
    mysql -e "CREATE DATABASE IF NOT EXISTS \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
    mysql "$db" < "$f"
    mysql -e "GRANT ALL PRIVILEGES ON \`$db\`.* TO 'ai_data'@'localhost'; GRANT ALL PRIVILEGES ON \`$db\`.* TO 'ai_data'@'127.0.0.1'"
done
[ -f "$B/sandboxes_pg.dump" ] && sudo -u postgres pg_restore --clean --if-exists -d postgres "$B/sandboxes_pg.dump" || true
[ -f "$B/sandbox_folders.tgz" ] && tar xzf "$B/sandbox_folders.tgz" -C /home/trilivyapp/containers/instances && \
    chown -R trilivy:trilivy /home/trilivyapp/containers/instances/inst_*_vdem_p* || true
if [ -f "$B/ai_data_demo_rows.sql" ]; then
    before=$(mysql -N -e "SELECT COUNT(*) FROM ai_data.ai_orbitix_users WHERE account_type='demo_user'")
    mysql ai_data < "$B/ai_data_demo_rows.sql"
    after=$(mysql -N -e "SELECT COUNT(*) FROM ai_data.ai_orbitix_users WHERE account_type='demo_user'")
    want=$(mysql -N -e "SELECT COUNT(*) FROM addon_demo.cx_demo_prospects WHERE oid IS NOT NULL AND status NOT IN ('purged','failed')")
    echo "prospect accounts: $before before, $after after, $want expected"
fi
echo "restore done"
