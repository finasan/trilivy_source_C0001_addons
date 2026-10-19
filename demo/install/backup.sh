#!/bin/bash
# Demo add-on - nightly backup of the runtime data (prospects, events, sandboxes).
# /home/trilivy_backups/demo/<date>/ : addon_demo.sql, one .sql per sandbox
# database, the sandboxes' knowledge tables (pg_dump), and their upload folders.
# Kept 7 days. install/restore.sh brings the latest one back (playbook 19
# addon_restore=latest).
set -euo pipefail
OUT=/home/trilivy_backups/demo/$(date -u +%Y%m%d)
install -d -m 0700 "$OUT"
mysqldump --single-transaction --no-tablespaces addon_demo > "$OUT/addon_demo.sql"
# The platform rows that make a sandbox usable: prospect accounts, the sandbox
# instances and their grants (ai_data is rebuilt from the release on a new box).
mysqldump --single-transaction --no-tablespaces --no-create-info --insert-ignore ai_data ai_orbitix_users \
    --where="account_type='demo_user'" > "$OUT/ai_data_demo_rows.sql"
mysqldump --single-transaction --no-tablespaces --no-create-info --insert-ignore ai_data ai_instance \
    --where="instance_name LIKE 'vdem\\_p%'" >> "$OUT/ai_data_demo_rows.sql"
mysqldump --single-transaction --no-tablespaces --no-create-info --insert-ignore ai_data ai_orbitix_user_instances \
    --where="oid IN (SELECT oid FROM ai_orbitix_users WHERE account_type='demo_user')" >> "$OUT/ai_data_demo_rows.sql" 2>/dev/null || \
mysqldump --single-transaction --no-tablespaces --no-create-info --insert-ignore ai_data ai_orbitix_user_instances \
    --where="instance_code LIKE 'vdem\\_p%'" >> "$OUT/ai_data_demo_rows.sql"
for db in $(mysql -N -e "SELECT schema_name FROM information_schema.schemata WHERE LOWER(schema_name) LIKE 'inst\\_%\\_vdem\\_p%'"); do
    mysqldump --single-transaction --no-tablespaces "$db" > "$OUT/$db.sql"
done
TABLES=$(sudo -u postgres psql -d postgres -tAc "SELECT string_agg('-t ' || tablename, ' ') FROM pg_tables WHERE tablename LIKE 'ragt\\_vdem\\_p%'")
if [ -n "$TABLES" ]; then
    # shellcheck disable=SC2086
    sudo -u postgres pg_dump -Fc -d postgres $TABLES > "$OUT/sandboxes_pg.dump"
fi
ls -d /home/trilivyapp/containers/instances/inst_*_vdem_p* >/dev/null 2>&1 && \
    tar czf "$OUT/sandbox_folders.tgz" -C /home/trilivyapp/containers/instances $(cd /home/trilivyapp/containers/instances && ls -d inst_*_vdem_p*)
find /home/trilivy_backups/demo -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} +
echo "backup ok: $OUT"
