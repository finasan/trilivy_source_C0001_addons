#!/usr/bin/env python3
"""Demo add-on - load the seed into addon_demo (run by install/bootstrap.sh as root).

Idempotent; runs on every install and update:
  features   replaced by the seed (the feature map is code: it changes by package)
  moments    upserted
  settings   missing keys added; a key still holding the seed's value (updated_by
             'seed') follows the seed; a key an operator changed is kept
  pitch      missing cards added; a card nobody edited since the seed (updated_by
             'seed') follows the seed; an edited card is kept
  operators  seed/operators.json linked by e-mail; when there is no operator at
             all yet, every active admin account becomes one (role admin)
  system     the timers' service account (cx_demo_operators role 'system') and
             its password in /etc/trilivy/addon_demo_svc.env (0600 root)
  nodes      menu codes (seed/nodes.json): a node nobody changed on the box
             (updated_by NULL or 'seed') follows the seed; a node not scanned yet
             is added (the next menu scan fills in its kind and page)
  stories    seed/stories.json: a story or step nobody changed on the box follows the seed

  --only nodes,stories,...   load just those parts (the dev loop on a demo box)
"""
import hashlib
import json
import os
import secrets
import sys

import pymysql

ADDON_DIR = os.environ.get("ADDON_DIR", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB = os.environ.get("ADDON_DB", "addon_demo")
SVC_ENV = "/etc/trilivy/addon_demo_svc.env"
SVC_EMAIL = "demo-system@addon.invalid"


def load(name):
    p = os.path.join(ADDON_DIR, "seed", name)
    if not os.path.isfile(p):
        return {}
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)


def conn(db=None):
    return pymysql.connect(unix_socket="/var/run/mysqld/mysqld.sock", user="root", database=db,
                           charset="utf8mb4", autocommit=False, cursorclass=pymysql.cursors.DictCursor)


def seed_cards(cur):
    added = updated = 0
    for k in load("pitch.json").get("cards", []):
        # Only "talk" exists (2026-10-15: no booking, no wish list).
        cta = [c for c in k.get("cta", []) if c == "talk"]
        vals = (k.get("kicker", ""), k["headline"], k.get("why_html", ""), k.get("how_html", ""),
                json.dumps(k.get("objections", [])), k.get("proof_html", ""), json.dumps(cta),
                k.get("status", "draft"))
        key = (k["feature_key"], k.get("audience", "business"), k.get("lang", "en"))
        cur.execute("SELECT id, updated_by FROM cx_demo_pitch WHERE feature_key=%s AND audience=%s AND lang=%s", key)
        row = cur.fetchone()
        if not row:
            cur.execute("INSERT INTO cx_demo_pitch (kicker, headline, why_html, how_html, objections, proof_html, cta, status, "
                        "feature_key, audience, lang, updated_by, verified_by) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'seed',%s)",
                        vals + key + (k.get("verified_by") or None,))
            added += 1
        elif row["updated_by"] == "seed":
            cur.execute("UPDATE cx_demo_pitch SET kicker=%s, headline=%s, why_html=%s, how_html=%s, objections=%s, proof_html=%s, "
                        "cta=%s, status=%s WHERE id=%s", vals + (row["id"],))
            updated += cur.rowcount
    return added, updated


def seed_nodes(cur):
    added = updated = 0
    for n in load("nodes.json").get("nodes", []):
        area, trail = n["area"], n["trail"][:255]
        code = (n.get("code") or "").upper() or None
        key = n.get("card_key") or None
        cur.execute("SELECT id, updated_by FROM cx_demo_nodes WHERE area=%s AND trail=%s", (area, trail))
        row = cur.fetchone()
        if not row:
            label = trail.split(" › ")[-1][:120]
            depth = trail.count(" › ") + 1
            cur.execute("INSERT INTO cx_demo_nodes (area, trail, label, kind, depth, code, card_key, updated_by) "
                        "VALUES (%s,%s,%s,%s,%s,%s,%s,'seed')", (area, trail, label, n.get("kind", "link"), depth, code, key))
            added += 1
        elif row["updated_by"] in (None, "", "seed"):
            cur.execute("UPDATE cx_demo_nodes SET code=%s, card_key=%s, updated_by='seed' WHERE id=%s", (code, key, row["id"]))
            updated += cur.rowcount
    return added, updated


def seed_stories(cur):
    s_n = t_n = 0
    for s in load("stories.json").get("stories", []):
        cur.execute("SELECT updated_by FROM cx_demo_story WHERE story_key=%s", (s["story_key"],))
        row = cur.fetchone()
        vals = (s["title"], s.get("subtitle"), int(s.get("minutes", 8)), s.get("status", "draft"), int(s.get("sort", 100)))
        if not row:
            cur.execute("INSERT INTO cx_demo_story (title, subtitle, minutes, status, sort, story_key, updated_by) "
                        "VALUES (%s,%s,%s,%s,%s,%s,'seed')", vals + (s["story_key"],))
            s_n += 1
        elif row["updated_by"] in (None, "", "seed"):
            cur.execute("UPDATE cx_demo_story SET title=%s, subtitle=%s, minutes=%s, status=%s, sort=%s, updated_by='seed' "
                        "WHERE story_key=%s", vals + (s["story_key"],))
            s_n += cur.rowcount
        else:
            continue  # an operator changed the story here: its steps are theirs too
        # the steps of a seed-owned story follow the seed (a step an operator edited is kept)
        cur.execute("SELECT id, step_no, updated_by FROM cx_demo_story_step WHERE story_key=%s", (s["story_key"],))
        have = {r["step_no"]: r for r in cur.fetchall()}
        if any(r["updated_by"] not in (None, "", "seed") for r in have.values()):
            continue
        cur.execute("DELETE FROM cx_demo_story_step WHERE story_key=%s", (s["story_key"],))
        for i, st in enumerate(s.get("steps", []), start=1):
            js = lambda k: json.dumps(st[k]) if st.get(k) else None  # noqa: E731
            cur.execute("INSERT INTO cx_demo_story_step (story_key, step_no, kind, kicker, title, body_html, benefits, task_html, "
                        "target_path, allow_paths, card_key, done_when, buttons, status, updated_by) "
                        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'seed')",
                        (s["story_key"], i, st.get("kind", "slide"), st.get("kicker"), st["title"], st.get("body_html"),
                         js("benefits"), st.get("task_html"), st.get("target_path"), js("allow_paths"), st.get("card_key"),
                         js("done_when"), js("buttons"), st.get("status", "live")))
            t_n += 1
    return s_n, t_n


def main():
    out = {}
    only = set()
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    c = conn(DB)
    cur = c.cursor()
    if only:
        if "nodes" in only:
            out["nodes_added"], out["nodes_updated"] = seed_nodes(cur)
        if "stories" in only:
            out["stories"], out["story_steps"] = seed_stories(cur)
        if "pitch" in only:
            out["cards_added"], out["cards_updated"] = seed_cards(cur)
        c.commit()
        c.close()
        print(json.dumps(out))
        return

    # features
    feats = load("features.json").get("features", [])
    if feats:
        cur.execute("DELETE FROM cx_demo_features")
        for f in feats:
            cur.execute("INSERT INTO cx_demo_features (feature_key, title, mode, explorer_mode, path_patterns, nav_group, nav_label, sort, notes) "
                        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                        (f["feature_key"], f["title"], f["mode"], f.get("explorer_mode"), json.dumps(f.get("path_patterns", [])),
                         f.get("nav_group"), f.get("nav_label"), int(f.get("sort", 100)), f.get("notes")))
    out["features"] = len(feats)

    pitch = load("pitch.json")
    # moments
    for m in pitch.get("moments", []):
        cur.execute("INSERT INTO cx_demo_moments (moment_key, title, trigger_json, feature_key, once_per_prospect, active) "
                    "VALUES (%s,%s,%s,%s,%s,%s) ON DUPLICATE KEY UPDATE title=VALUES(title), trigger_json=VALUES(trigger_json), "
                    "feature_key=VALUES(feature_key), once_per_prospect=VALUES(once_per_prospect), active=VALUES(active)",
                    (m["moment_key"], m["title"], json.dumps(m["trigger_json"]), m["feature_key"],
                     int(m.get("once_per_prospect", 1)), int(m.get("active", 1))))
    out["moments"] = len(pitch.get("moments", []))

    out["cards_added"], out["cards_updated"] = seed_cards(cur)
    out["nodes_added"], out["nodes_updated"] = seed_nodes(cur)
    out["stories"], out["story_steps"] = seed_stories(cur)

    # settings
    s_added = s_updated = 0
    for key, val in load("settings.json").get("settings", {}).items():
        cur.execute("SELECT v, updated_by FROM cx_demo_settings WHERE k=%s", (key,))
        row = cur.fetchone()
        if not row:
            cur.execute("INSERT INTO cx_demo_settings (k, v, updated_by) VALUES (%s,%s,'seed')", (key, val))
            s_added += 1
        elif row["updated_by"] == "seed" and row["v"] != val:
            cur.execute("UPDATE cx_demo_settings SET v=%s WHERE k=%s", (val, key))
            s_updated += 1
    out["settings_added"], out["settings_updated"] = s_added, s_updated

    # access map (cx_demo_pages): missing pages added; a page nobody changed on
    # this box since the seed (updated_by NULL or 'seed') follows the seed
    p_added = p_updated = 0
    cols = ("area", "grp", "label", "sort", "guided_mode", "explorer_mode", "readonly", "safety",
            "guard_title", "guard_html", "card_key", "source")
    for pg in load("pages.json").get("pages", []):
        vals = tuple(pg.get(k) for k in cols)
        vals = vals[:3] + (int(pg.get("sort", 1000)),) + vals[4:6] + (int(pg.get("readonly", 0)), pg.get("safety", "unknown")) \
            + vals[8:11] + (pg.get("source", "menu"),)
        cur.execute("SELECT id, updated_by FROM cx_demo_pages WHERE path=%s", (pg["path"],))
        row = cur.fetchone()
        if not row:
            cur.execute("INSERT INTO cx_demo_pages (" + ", ".join(cols) + ", path, updated_by) VALUES ("
                        + ", ".join(["%s"] * len(cols)) + ", %s, 'seed')", vals + (pg["path"],))
            p_added += 1
        elif row["updated_by"] in (None, "", "seed"):
            cur.execute("UPDATE cx_demo_pages SET " + ", ".join(k + "=%s" for k in cols) + ", updated_by='seed' WHERE id=%s",
                        vals + (row["id"],))
            p_updated += cur.rowcount
    out["pages_added"], out["pages_updated"] = p_added, p_updated
    c.commit()

    # operators (accounts live in ai_data)
    linked = 0
    for o in load("operators.json").get("operators", []):
        cur.execute("SELECT oid, fname, lname, email FROM ai_data.ai_orbitix_users WHERE email=%s AND active=1 "
                    "AND account_type <> 'demo_user'", (o["email"],))
        u = cur.fetchone()
        if u:
            cur.execute("INSERT INTO cx_demo_operators (oid, role, display_name, email) VALUES (%s,%s,%s,%s) "
                        "ON DUPLICATE KEY UPDATE role=VALUES(role), display_name=VALUES(display_name), email=VALUES(email)",
                        (u["oid"], o.get("role", "sales"), o.get("display_name") or f"{u['fname'] or ''} {u['lname'] or ''}".strip(), u["email"]))
            linked += 1
    cur.execute("SELECT COUNT(*) AS n FROM cx_demo_operators WHERE role <> 'system'")
    if cur.fetchone()["n"] == 0:
        cur.execute("SELECT oid, fname, lname, email FROM ai_data.ai_orbitix_users WHERE account_type='admin' AND active=1")
        for u in cur.fetchall():
            cur.execute("INSERT IGNORE INTO cx_demo_operators (oid, role, display_name, email) VALUES (%s,'admin',%s,%s)",
                        (u["oid"], f"{u['fname'] or ''} {u['lname'] or ''}".strip() or u["email"], u["email"]))
            linked += 1
    out["operators_linked"] = linked

    # the timers' service account
    cur.execute("SELECT oid FROM ai_data.ai_orbitix_users WHERE email=%s", (SVC_EMAIL,))
    u = cur.fetchone()
    if not u or not os.path.isfile(SVC_ENV):
        pw = secrets.token_hex(24)
        salt = secrets.token_hex(32)
        h = hashlib.sha256(f"{pw}:{salt}".encode()).hexdigest()
        if u:
            cur.execute("UPDATE ai_data.ai_orbitix_users SET password_hash=%s, password_salt=%s, active=1 WHERE oid=%s",
                        (h, salt, u["oid"]))
            oid = u["oid"]
        else:
            cur.execute("INSERT INTO ai_data.ai_orbitix_users (email, fname, lname, password_hash, password_salt, password_must_reset, "
                        "company, account_type, default_instance_code, ur_bot, ur_panel, ur_kb, ur_tips, ur_courses, ur_quick, "
                        "ur_manage, ur_jumpstart, ur_rag, ur_resources, ur_support, date_in, active) "
                        "VALUES (%s,'Demo','System',%s,%s,0,'Trilivy','user','basic',0,0,0,0,0,0,0,0,0,0,0,NOW(),1)",
                        (SVC_EMAIL, h, salt))
            oid = cur.lastrowid
        old = os.umask(0o077)
        try:
            with open(SVC_ENV, "w") as fh:
                fh.write(f"DEMO_SVC_EMAIL={SVC_EMAIL}\nDEMO_SVC_PASSWORD={pw}\n")
        finally:
            os.umask(old)
        os.chmod(SVC_ENV, 0o600)
        out["service_account"] = "created" if not u else "password reset"
    else:
        oid = u["oid"]
        out["service_account"] = "kept"
    cur.execute("INSERT INTO cx_demo_operators (oid, role, display_name, email) VALUES (%s,'system','Demo timers',%s) "
                "ON DUPLICATE KEY UPDATE role='system', active=1", (oid, SVC_EMAIL))
    c.commit()
    c.close()
    print(json.dumps(out))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"seed failed: {exc}", file=sys.stderr)
        sys.exit(1)
