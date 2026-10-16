/**
 * Demo add-on - shared library (2026-10-15).
 *
 * Settings, operators, prospects, the feature map, events, usage and the
 * engagement score. Everything the hooks and the pages need lives here so the
 * rules exist once. Database: addon_demo (datasource "addon_demo").
 */
component output="false" {

    variables.dsn = "addon_demo";

    public any function init() { return this; }

    // ------------------------------------------------------------------ names
    public string function companyCode() {
        return lCase(trim(application.env.OBTX_COMPANY_CODE ?: ""));
    }

    /** The sandbox names of one prospect - the ONLY place they are made. */
    public struct function names(required string pid) {
        if (!reFind("^p[0-9]{4}$", arguments.pid)) throw(type="Demo.BadPid", message="invalid prospect id");
        var code = companyCode();
        var db = "INST_" & code & "_vdem_" & arguments.pid;
        var root = reReplace(application.env.OBTX_PATH_INSTANCES ?: "/home/trilivyapp/containers/instances", "[/\\]+$", "");
        return {
            pid:      arguments.pid,
            instance: "vdem_" & arguments.pid,
            db:       db,
            dbLower:  lCase(db),
            base:     "ragt_vdem_" & arguments.pid,
            dir:      root & "/" & lCase(db)
        };
    }

    public string function publicHost() {
        var h = trim(setting("public_host", ""));
        if (len(h)) return reReplace(h, "/+$", "");
        return "https://panel." & (application.domain_name ?: cgi.server_name);
    }

    // ------------------------------------------------------------------ settings
    public struct function settingsAll(boolean fresh = false) {
        var c = application.demo_settings ?: {};
        if (!fresh && structKeyExists(c, "at") && dateDiff("s", c.at, now()) LT 120) return c.map;
        var q = queryExecute("SELECT k, v FROM cx_demo_settings", {}, {datasource: variables.dsn});
        var m = {};
        for (var r in q) m[r.k] = r.v;
        application.demo_settings = {at: now(), map: m};
        return m;
    }

    public string function setting(required string k, string dflt = "") {
        var m = settingsAll();
        return structKeyExists(m, arguments.k) && !isNull(m[arguments.k]) ? m[arguments.k] : arguments.dflt;
    }

    public void function setSetting(required string k, required string v, string by = "") {
        queryExecute("INSERT INTO cx_demo_settings (k, v, updated_by) VALUES (:k, :v, :by)
                      ON DUPLICATE KEY UPDATE v = VALUES(v), updated_by = VALUES(updated_by)",
            {k: arguments.k, v: {value: arguments.v, cfsqltype: "cf_sql_longvarchar"}, by: arguments.by},
            {datasource: variables.dsn});
        structDelete(application, "demo_settings");
    }

    public struct function jsonSetting(required string k) {
        try { var v = deserializeJSON(setting(arguments.k, "{}")); return isStruct(v) ? v : {}; }
        catch (any e) { return {}; }
    }

    public boolean function paused() { return setting("demo_paused", "0") == "1"; }

    // ------------------------------------------------------------------ operators
    public struct function operator(numeric oid = val(session.user_oid ?: 0)) {
        if (arguments.oid LTE 0) return {ok: false};
        var c = session.demo_op ?: {};
        if (structKeyExists(c, "oid") && c.oid == arguments.oid && dateDiff("s", c.at, now()) LT 60) return c;
        var q = queryExecute("SELECT oid, role, display_name, email FROM cx_demo_operators WHERE oid = :o AND active = 1",
            {o: {value: arguments.oid, cfsqltype: "cf_sql_integer"}}, {datasource: variables.dsn});
        var out = {oid: arguments.oid, at: now(), ok: q.recordCount GT 0 && (session.account_type ?: "") != "demo_user",
                   role: q.role ?: "", name: q.display_name ?: "", email: q.email ?: ""};
        if (arguments.oid == val(session.user_oid ?: 0)) session.demo_op = out;
        return out;
    }

    public boolean function isOperator() { return operator().ok; }

    public array function operators() {
        var q = queryExecute("SELECT oid, role, display_name, email, active FROM cx_demo_operators ORDER BY role, display_name",
            {}, {datasource: variables.dsn});
        var out = [];
        for (var r in q) arrayAppend(out, r);
        return out;
    }

    // ------------------------------------------------------------------ prospects
    public struct function prospectBy(required string col, required any val) {
        if (!listFind("oid,pid,seq,email", arguments.col)) throw(message="bad column");
        var q = queryExecute("SELECT * FROM cx_demo_prospects WHERE #arguments.col# = :v LIMIT 1",
            {v: arguments.val}, {datasource: variables.dsn});
        if (!q.recordCount) return {};
        var r = queryGetRow(q, 1);
        r.daysLeft = isDate(r.expires_at) ? max(0, ceiling(dateDiff("h", now(), r.expires_at) / 24)) : 0;
        return r;
    }

    /** session.demo for a signed-in demo_user, refreshed every 60 s. */
    public struct function sessionDemo(boolean fresh = false) {
        if ((session.account_type ?: "") != "demo_user") return {};
        var c = session.demo ?: {};
        if (!fresh && structKeyExists(c, "at") && dateDiff("s", c.at, now()) LT 60) return c;
        var p = prospectBy("oid", val(session.user_oid ?: 0));
        if (structIsEmpty(p)) { session.demo = {at: now(), missing: true}; return session.demo; }
        var n = names(p.pid);
        var se = trim(setting("sales_engineer_instance", ""));
        session.demo = {
            at: now(), missing: false, pid: p.pid, status: p.status, company: p.company ?: "",
            fname: p.fname ?: "", audience: p.audience, language: p.language,
            expires_at: p.expires_at, daysLeft: p.daysLeft, consent: isDate(p.consent_at ?: ""),
            instance: n.instance, db: n.db, dbLower: n.dbLower, base: n.base,
            seInstance: se, mode: p.mode ?: "guided",
            audit: setting("explorer_audit_pid", "") == p.pid
        };
        applyRights(session.demo.mode);
        return session.demo;
    }

    /**
     * Session rights of a prospect (never stored in ai_orbitix_users). Guided:
     * chat, knowledge pages, courses. Full platform: the platform's own areas
     * too, so its real menus and pages work; request_gate still decides page
     * by page (cx_demo_features.explorer_mode), so box-wide pages stay locked.
     */
    public void function applyRights(required string mode) {
        var full = arguments.mode == "explorer";
        session.ur_bot = 1; session.ur_kb = 1; session.ur_courses = 1;
        for (var k in ["ur_panel", "ur_rag", "ur_jumpstart", "ur_manage", "ur_quick", "ur_tips"]) session[k] = full ? 1 : 0;
        session.ur_resources = 1;   // Resources (documentation) is free to read in both experiences
    }

    /**
     * Guided <-> Full platform for one prospect; used by the operator (prospect
     * page) and by the prospect (the switch in the DEMO bar). Full platform makes
     * the prospect admin of the OWN sandbox grant only, never of any other assistant.
     */
    public string function setMode(required string pid, required string mode, any by = "") {
        var nm = arguments.mode == "explorer" ? "explorer" : "guided";
        var p = prospectBy("pid", arguments.pid);
        if (structIsEmpty(p)) throw(message="no such prospect");
        queryExecute("UPDATE cx_demo_prospects SET mode = :m WHERE pid = :p", {m: nm, p: arguments.pid}, {datasource: variables.dsn});
        if (val(p.oid ?: 0)) {
            queryExecute("UPDATE ai_orbitix_user_instances SET access_level = :l WHERE oid = :o AND instance_code = :i",
                {l: nm == "explorer" ? "admin" : "standard", o: p.oid, i: names(arguments.pid).instance}, {datasource: "ai_data"});
        }
        logEvent(arguments.pid, "mode_changed", {detail: {mode: nm, by: arguments.by}});
        return nm;
    }

    /** The prospect's Guided | Full platform switch (a tiny POST form to p=switch). */
    public string function switchHtml(required string mode, string cls = "demo-sw") {
        if (!len(session.demo_swtok ?: "")) session.demo_swtok = lCase(replace(createUUID(), "-", "", "all"));
        var full = arguments.mode == "explorer";
        return '<form method="post" action="/ain5py/addon.cfm?a=demo&p=switch" class="' & arguments.cls & '">'
             & '<input type="hidden" name="t" value="' & session.demo_swtok & '">'
             & '<button name="mode" value="guided" class="' & (full ? "" : "on") & '"' & (full ? "" : " disabled") & '>Guided</button>'
             & '<button name="mode" value="explorer" class="' & (full ? "on" : "") & '"' & (full ? " disabled" : "") & '>Full platform</button>'
             & '</form>';
    }

    public string function nextPid() {
        var q = queryExecute("SELECT COALESCE(MAX(seq), 0) + 1 AS n FROM cx_demo_prospects", {}, {datasource: variables.dsn});
        return "p" & numberFormat(q.n, "0000");
    }

    public struct function caps(required struct prospect) {
        var c = jsonSetting("caps_" & (prospect.caps_preset ?: "standard"));
        if (structIsEmpty(c)) c = jsonSetting("caps_standard");
        try {
            if (len(trim(prospect.caps_json ?: ""))) structAppend(c, deserializeJSON(prospect.caps_json), true);
        } catch (any e) {}
        return c;
    }

    // ------------------------------------------------------------------ feature map
    public array function features() {
        var c = application.demo_features ?: {};
        if (structKeyExists(c, "at") && dateDiff("s", c.at, now()) LT 120) return c.list;
        var q = queryExecute("SELECT feature_key, title, mode, COALESCE(explorer_mode, mode) AS explorer_mode, path_patterns, nav_group, nav_label, sort
                              FROM cx_demo_features ORDER BY sort, feature_key", {}, {datasource: variables.dsn});
        var list = [];
        for (var r in q) {
            var pats = [];
            try { pats = deserializeJSON(r.path_patterns); } catch (any e) {}
            r.rx = [];
            for (var p in pats) {
                // Paths hold letters, digits, / _ - . and the * wildcard only (anything
                // else is dropped), so escaping the dot is all the regex needs.
                p = reReplace(lCase(trim(p)), "[^a-z0-9/_.*-]", "", "all");
                arrayAppend(r.rx, "^" & replace(replace(p, ".", "\.", "all"), "*", ".*", "all") & "$");
            }
            arrayAppend(list, r);
        }
        application.demo_features = {at: now(), list: list};
        return list;
    }

    /** {key, mode, title} for a lower-case path, for the prospect's experience
        (guided | explorer = Full platform). Nothing matched = pitch "platform". */
    public struct function classify(required string path, string experience = "guided") {
        var p = lCase(arguments.path);
        var ex = arguments.experience == "explorer";
        var f = {key: "platform", mode: "pitch", title: "Everything else in the full platform"};
        var hit = false;
        for (var ft in features()) {
            for (var rx in ft.rx) {
                if (reFind(rx, p)) { f = {key: ft.feature_key, mode: ex ? ft.explorer_mode : ft.mode, title: ft.title}; hit = true; break; }
            }
            if (hit) break;
        }
        // The Access map (cx_demo_pages) decides page by page; an empty mode inherits
        // the feature map above. "guard" = open with an instructions popup.
        f.page = false; f.readonly = false; f.card = f.key; f.label = f.title; f.safety = ""; f.inherited = f.mode;
        var pg = pages()[p] ?: {};
        if (!structIsEmpty(pg)) {
            f.page = true; f.label = pg.label; f.safety = pg.safety; f.readonly = val(pg.readonly) == 1;
            var m = ex ? (pg.explorer_mode ?: "") : (pg.guided_mode ?: "");
            if (len(m)) f.mode = m;
            if (len(pg.card_key ?: "")) f.card = pg.card_key;
            // never open a page that shows other prospects' data or changes the server
            if (listFind("boxwide,server", pg.safety) && listFind("open,capped,guard", f.mode)) f.mode = "pitch";
        }
        if (f.mode != "guard") f.readonly = false;
        return f;
    }

    // ------------------------------------------------------------------ access map
    /** cx_demo_pages by lower-case path, cached 2 minutes. */
    public struct function pages() {
        var c = application.demo_pages ?: {};
        if (structKeyExists(c, "at") && dateDiff("s", c.at, now()) LT 120) return c.map;
        var m = {};
        try {
            var q = queryExecute("SELECT * FROM cx_demo_pages", {}, {datasource: variables.dsn});
            for (var r in q) m[r.path] = r;
        } catch (any e) {}
        application.demo_pages = {at: now(), map: m};
        return m;
    }

    public void function pagesChanged() {
        structDelete(application, "demo_pages");
        structDelete(application, "demo_clientmap");
        structDelete(application, "demo_features");
    }

    /** A menu link as a lower-case site path ("" for external links, anchors, expressions). */
    public string function normPath(required string href, string base = "/ain5py/") {
        var h = trim(arguments.href);
        if (!len(h) || find("##", h) || reFindNoCase("^(https?:|//|javascript:|mailto:)", h)) return "";
        h = listFirst(h, "?");
        if (left(h, 1) != "/") h = arguments.base & h;
        var parts = [];
        for (var s in listToArray(h, "/")) {
            if (s == "..") { if (arrayLen(parts)) arrayDeleteAt(parts, arrayLen(parts)); }
            else if (s != ".") arrayAppend(parts, s);
        }
        var p = lCase("/" & arrayToList(parts, "/"));
        if (!reFind("\.(cfm|html?)$", p)) return "";
        return left(p, 255);
    }

    /** Records the pages of a platform menu (menu_filter: manage, kb, quick); at most every 10 minutes per area. */
    public void function registerMenu(required string area, required array menu, required string base, boolean force = false) {
        var key = "demo_reg_" & arguments.area;
        if (!arguments.force && structKeyExists(application, key) && dateDiff("n", application[key], now()) LT 10) return;
        application[key] = now();
        var rows = [];
        walkMenu(arguments.menu, "", arguments.base, rows);
        upsertPages(arguments.area, rows, "menu");
    }

    private void function walkMenu(required array items, required string grp, required string base, required array rows) {
        for (var it in arguments.items) {
            if (!isStruct(it)) continue;
            var lbl = trim(it.label ?: (it.title ?: ""));
            if (len(it.url ?: "")) {
                var p = normPath(it.url, arguments.base);
                if (len(p)) arrayAppend(arguments.rows, {path: p, label: len(lbl) ? lbl : listLast(p, "/"), grp: arguments.grp});
            }
            if (isArray(it.children ?: "")) walkMenu(it.children, lbl, arguments.base, arguments.rows);
        }
    }

    public numeric function upsertPages(required string area, required array rows, string source = "menu") {
        var n = 0, i = 0;
        for (var r in arguments.rows) {
            i++;
            // A row first met as "seen" (a prospect opened it) takes the menu's label and place.
            queryExecute("INSERT INTO cx_demo_pages (path, area, grp, label, sort, source) VALUES (:p, :a, :g, :l, :s, :src)
                ON DUPLICATE KEY UPDATE
                  label = IF(source = 'seen', VALUES(label), label),
                  grp   = IF(source = 'seen' OR grp IS NULL, VALUES(grp), grp),
                  area  = IF(source = 'seen', VALUES(area), area),
                  sort  = IF(source = 'seen', VALUES(sort), sort),
                  source = IF(source = 'seen', VALUES(source), source)", {
                p: r.path, a: arguments.area, g: {value: left(r.grp ?: "", 80), null: !len(r.grp ?: "")},
                l: left(r.label, 120), s: {value: i, cfsqltype: "cf_sql_integer"}, src: arguments.source
            }, {datasource: variables.dsn, result: "local.res"});
            if (val(local.res.recordCount ?: 0) == 1) n++;
        }
        pagesChanged();
        return n;
    }

    /** A page a prospect opened that no menu lists yet: recorded so it shows in the Access map (it stays inherited). */
    public void function registerSeen(required string path) {
        if (structKeyExists(pages(), arguments.path)) return;
        try {
            queryExecute("INSERT IGNORE INTO cx_demo_pages (path, area, label, sort, source) VALUES (:p, 'other', :l, 9999, 'seen')",
                {p: left(arguments.path, 255), l: listLast(arguments.path, "/")}, {datasource: variables.dsn});
            pagesChanged();
        } catch (any e) {}
    }

    /**
     * Reads the menus that are plain pages (Main AI, JumpStart, RAG dashboard) and
     * the three menu_config areas, and records every link. Returns {area: count}.
     */
    public struct function scanMenus() {
        var out = {};
        for (var area in ["manage", "kb", "quick"]) {
            try {
                var rows = [];
                walkMenu(new trlvaddons.demo.lib.MenuProbe().menu(area), "", "/ain5py/" & area & "/", rows);
                upsertPages(area, rows, "menu");
                out[area] = arrayLen(rows);
            } catch (any e) { out[area] = "error: " & e.message; }
        }
        var srcs = [
            {area: "main_ai",   base: "/ain5py/frontmenu/",  files: ["frontmenu/menu.cfm", "frontmenu/menu_agents.cfm", "frontmenu/menu_rag_ingest.cfm", "frontmenu/menu_ragmgt.cfm", "frontmenu/menu_smart.cfm", "frontmenu/menu_training.cfm"]},
            {area: "jumpstart", base: "/ain5py/menucenter/", files: ["menucenter/index_V2.cfm", "menucenter/mc_appsbar.cfm", "menucenter/mc_nav_V2.cfm", "menucenter/mc_shell.cfm"]},
            {area: "rag",       base: "/ain5py/frontend/",   files: ["frontend/rag_dashboard.cfm"]}
        ];
        for (var s in srcs) {
            var rows = [];
            for (var fn in s.files) {
                var fp = expandPath("/ain5py/" & fn);
                if (!fileExists(fp)) continue;
                var src = fileRead(fp);
                var grp = reReplace(listLast(fn, "/"), "\.cfm$", "");
                for (var a in reMatchNoCase("<a\s[^>]*href\s*=\s*""[^""]+""[^>]*>[\s\S]*?</a>", src)) {
                    var href = reReplaceNoCase(a, "^[\s\S]*?href\s*=\s*""([^""]+)""[\s\S]*$", "\1");
                    var p = normPath(href, s.base);
                    if (!len(p)) continue;
                    var lbl = trim(reReplace(reReplace(reReplace(a, "<[^>]*>", " ", "all"), "&[a-z##0-9]+;", " ", "all"), "\s+", " ", "all"));
                    if (find("##", lbl) || !len(lbl)) lbl = listLast(p, "/");
                    arrayAppend(rows, {path: p, label: left(lbl, 120), grp: grp});
                }
            }
            upsertPages(s.area, rows, "menu");
            out[s.area] = arrayLen(rows);
        }
        return out;
    }

    /** What demo.js needs to mark links: the Access map rows' effective modes + the feature map's patterns. */
    public struct function clientMap(required string experience) {
        var c = application.demo_clientmap ?: {};
        if (structKeyExists(c, arguments.experience) && dateDiff("s", c[arguments.experience].at, now()) LT 120) return c[arguments.experience].m;
        var ex = arguments.experience == "explorer";
        var pg = {};
        for (var p in pages()) pg[p] = classify(p, arguments.experience).mode;
        var rx = [];
        for (var f in features()) {
            for (var r in f.rx) arrayAppend(rx, [r, ex ? f.explorer_mode : f.mode]);
        }
        var m = {pages: pg, rx: rx};
        c[arguments.experience] = {at: now(), m: m};
        application.demo_clientmap = c;
        return m;
    }

    /** The instructions popup of an "Open with guardrail" page. */
    public struct function guardInfo(required string path, string experience = "guided") {
        var f = classify(arguments.path, arguments.experience);
        if (f.mode != "guard") return {ok: false};
        var pg = pages()[lCase(arguments.path)] ?: {};
        var lbl = pg.label ?: f.label;
        var html = trim(pg.guard_html ?: "");
        if (!len(html)) {
            html = "<p>This is the real <b>" & encodeForHTML(lbl) & "</b> page, working on your own private copy of Trilivy. "
                 & "What you change here affects only your demo.</p>";
        }
        if (f.readonly) html &= "<p><b>Read-only in the demo:</b> you can look at everything here, but saving is turned off.</p>";
        return {ok: true, title: len(trim(pg.guard_title ?: "")) ? pg.guard_title : "You are using: " & lbl, html: html, label: lbl, readonly: f.readonly};
    }

    public array function navPitchItems(string experience = "guided") {
        var out = [];
        var ex = arguments.experience == "explorer";
        for (var f in features()) {
            if ((ex ? f.explorer_mode : f.mode) == "pitch" && len(f.nav_label ?: "")) arrayAppend(out, f);
        }
        return out;
    }

    // ------------------------------------------------------------------ events
    public void function logEvent(required string pid, required string type, struct opts = {}) {
        try {
            var detail = opts.detail ?: {};
            var ua = cgi.http_user_agent ?: "";
            queryExecute("INSERT INTO cx_demo_events (pid, session_id, type, feature_key, page, detail, duration_ms, ip, ua_hash)
                          VALUES (:pid, :sid, :type, :fk, :page, :detail, :dur, :ip, :ua)", {
                pid: arguments.pid,
                sid: {value: left(session.sessionid ?: "", 64), null: !len(session.sessionid ?: "")},
                type: left(arguments.type, 40),
                fk: {value: left(opts.feature ?: "", 60), null: !len(opts.feature ?: "")},
                page: {value: left(opts.page ?: "", 255), null: !len(opts.page ?: "")},
                detail: {value: toJson(detail), cfsqltype: "cf_sql_longvarchar"},   // keys lower case: SQL reads $.raghits, $.text ...
                dur: {value: val(opts.duration ?: 0), cfsqltype: "cf_sql_integer", null: !structKeyExists(opts, "duration")},
                ip: {value: left(application.clientIP ?: cgi.remote_addr, 45)},
                ua: {value: len(ua) ? left(lCase(hash(ua, "SHA-256")), 16) : "", null: !len(ua)}
            }, {datasource: variables.dsn});
            scoreEvent(arguments.pid, arguments.type, detail);
        } catch (any e) {
            cflog(file="addons", type="error", text="demo.logEvent #arguments.type#: #e.message#");
        }
    }

    public void function addUsage(required string pid, required string field, numeric n = 1) {
        if (!listFind("questions,tokens,asks,uploads,upload_mb,ingests", arguments.field)) return;
        queryExecute("INSERT INTO cx_demo_usage_day (pid, day, #arguments.field#) VALUES (:pid, CURDATE(), :n)
                      ON DUPLICATE KEY UPDATE #arguments.field# = #arguments.field# + VALUES(#arguments.field#)",
            {pid: arguments.pid, n: {value: arguments.n, cfsqltype: "cf_sql_decimal", scale: 2}}, {datasource: variables.dsn});
    }

    public struct function usageToday(required string pid) {
        var q = queryExecute("SELECT * FROM cx_demo_usage_day WHERE pid = :p AND day = CURDATE()", {p: arguments.pid}, {datasource: variables.dsn});
        return q.recordCount ? queryGetRow(q, 1) : {questions: 0, tokens: 0, asks: 0, uploads: 0, upload_mb: 0, ingests: 0};
    }

    public struct function usageTotal(required string pid) {
        var q = queryExecute("SELECT COALESCE(SUM(questions),0) questions, COALESCE(SUM(tokens),0) tokens, COALESCE(SUM(asks),0) asks,
                                     COALESCE(SUM(uploads),0) uploads, COALESCE(SUM(upload_mb),0) upload_mb, COALESCE(SUM(ingests),0) ingests
                              FROM cx_demo_usage_day WHERE pid = :p", {p: arguments.pid}, {datasource: variables.dsn});
        return queryGetRow(q, 1);
    }

    // ------------------------------------------------------------------ score
    private void function scoreEvent(required string pid, required string type, struct detail = {}) {
        var w = jsonSetting("score_weights");
        var pts = 0;
        var p = prospectBy("pid", arguments.pid);
        if (structIsEmpty(p)) return;
        var firstToday = !isDate(p.last_seen_at ?: "") || dateFormat(p.last_seen_at, "yyyy-mm-dd") != dateFormat(now(), "yyyy-mm-dd");
        switch (arguments.type) {
            case "login_ok":
                if (!isDate(p.first_login_at ?: "")) pts += val(w.first_login ?: 10);
                break;
            case "chat_question":
                if (usageToday(arguments.pid).questions LTE val(w.question_day_max ?: 20)) pts += val(w.question ?: 1);
                break;
            case "ingest_done":
                if (usageTotal(arguments.pid).ingests * val(w.upload ?: 10) LTE val(w.upload_max ?: 30)) pts += val(w.upload ?: 10);
                break;
            case "gate_shown":        pts += val(w.gate ?: 2); break;
            case "objection_open":    pts += val(w.objection ?: 3); break;
            case "ask_question":      pts += val(w.ask ?: 4); break;
            case "wishlist_add":      pts += val(w.wishlist ?: 8); break;
            case "handoff_requested": pts += val(w.handoff ?: 25); break;
        }
        if (firstToday && arguments.type != "login_failed") pts += val(w.active_day ?: 5);
        var score = p.score + pts;
        var band = score GTE val(w.hot ?: 60) ? "hot" : (score GTE val(w.warm ?: 25) ? "warm" : "cold");
        queryExecute("UPDATE cx_demo_prospects SET score = :s, score_band = :b,
                        last_seen_at = IF(:seen = 1, NOW(), last_seen_at),
                        first_login_at = IF(:login = 1 AND first_login_at IS NULL, NOW(), first_login_at),
                        status = IF(:login = 1 AND status = 'invited', 'active', status)
                      WHERE pid = :p", {
            s: score, b: band, p: arguments.pid,
            seen: arguments.type == "login_failed" ? 0 : 1,
            login: arguments.type == "login_ok" ? 1 : 0
        }, {datasource: variables.dsn});
        if (band == "hot" && p.score_band != "hot") {
            alert(p, "Hot prospect", "Engagement score reached #score#.");
        }
        if (arguments.type == "login_ok" && !isDate(p.first_login_at ?: "")) {
            alert(p, "First sign-in", "The prospect signed in to the demo for the first time.");
        }
    }

    // ------------------------------------------------------------------ alerts
    public void function alert(required struct prospect, required string what, string detail = "") {
        // Off by default (2026-10-15): the only demo e-mails are the invitation
        // and the platform's own Talk to a Person mails. Setting mail_alerts=1 restores them.
        if (setting("mail_alerts", "0") != "1") return;
        try {
            var to = "";
            if (val(prospect.owner_oid ?: 0)) {
                var o = queryExecute("SELECT email FROM cx_demo_operators WHERE oid = :o AND active = 1",
                    {o: prospect.owner_oid}, {datasource: variables.dsn});
                to = o.email ?: "";
            }
            if (!len(to)) {
                var a = queryExecute("SELECT email FROM cx_demo_operators WHERE role = 'admin' AND active = 1 AND email <> '' ORDER BY oid LIMIT 1",
                    {}, {datasource: variables.dsn});
                to = a.email ?: "";
            }
            if (!len(to)) return;
            var vars = mailVars(prospect);
            vars.what = arguments.what;
            vars.detail = arguments.detail;
            new trlvaddons.demo.lib.Mailer().sendTemplate("alert", to, vars, prospect.pid);
        } catch (any e) {
            cflog(file="addons", type="error", text="demo.alert: #e.message#");
        }
    }

    public struct function mailVars(required struct p) {
        var owner = {display_name: "The Trilivy team", email: ""};
        if (val(p.owner_oid ?: 0)) {
            var o = queryExecute("SELECT display_name, email FROM cx_demo_operators WHERE oid = :o", {o: p.owner_oid}, {datasource: variables.dsn});
            if (o.recordCount) owner = {display_name: o.display_name ?: "", email: o.email ?: ""};
        }
        var host = publicHost();
        return {
            fname: p.fname ?: "", lname: p.lname ?: "", email: p.email ?: "", company: p.company ?: "",
            pid: p.pid ?: "", score: p.score ?: 0, band: p.score_band ?: "",
            expires: isDate(p.expires_at ?: "") ? dateFormat(p.expires_at, "d mmmm yyyy") : "",
            purge_date: isDate(p.purge_after ?: "") ? dateFormat(p.purge_after, "d mmmm yyyy") : "",
            days: isDate(p.expires_at ?: "") && isDate(p.created_at ?: "") ? dateDiff("d", p.created_at, p.expires_at) : "",
            owner_name: len(owner.display_name) ? owner.display_name : "The Trilivy team",
            owner_email: owner.email,
            host: host & "/ain5py/login/login.cfm",
            console_link: host & "/ain5py/addon.cfm?a=demo&p=prospect&arg=" & (p.pid ?: ""),
            link_hours: setting("welcome_link_hours", "72")
        };
    }

    // ------------------------------------------------------------------ pitch cards
    /** The best card for a feature: exact audience+language, then business, then English; live only (drafts too while pitch_show_drafts=1). */
    public struct function card(required string feature, string audience = "business", string lang = "en", string fallback = "") {
        var statuses = setting("pitch_show_drafts", "0") == "1" ? "'live','verified','draft'" : "'live'";
        var q = queryExecute("SELECT * FROM cx_demo_pitch WHERE feature_key = :f AND status IN (#statuses#)
                              ORDER BY (audience = :a) DESC, (audience = 'business') DESC, (lang = :l) DESC, (lang = 'en') DESC,
                                       FIELD(status, 'live', 'verified', 'draft') LIMIT 1",
            {f: arguments.feature, a: arguments.audience, l: arguments.lang}, {datasource: variables.dsn});
        // a page's own card (Access map card_key) not written yet: the group's card
        if (!q.recordCount && len(arguments.fallback) && arguments.fallback != arguments.feature) return card(arguments.fallback, arguments.audience, arguments.lang);
        // "rag_maker__ex" (a Full-platform map entry) uses the card of "rag_maker"
        if (!q.recordCount && find("__", arguments.feature)) return card(reReplace(arguments.feature, "__.*$", ""), arguments.audience, arguments.lang);
        if (!q.recordCount && arguments.feature != "platform") return card("platform", arguments.audience, arguments.lang);
        if (!q.recordCount) return {};
        var c = queryGetRow(q, 1);
        try { c.objections = deserializeJSON(c.objections ?: "[]"); } catch (any e) { c.objections = []; }
        try { c.cta = deserializeJSON(c.cta ?: "[]"); } catch (any e) { c.cta = []; }
        c.isDraft = c.status != "live";
        c.key = c.feature_key & "/" & c.audience & "/" & c.lang;
        return c;
    }

    // ------------------------------------------------------------------ welcome
    /** A one-time set-password link through the platform's own reset page. */
    public string function passwordLink(required struct p) {
        if (!val(p.oid ?: 0)) throw(message="the prospect has no account yet");
        var token = lCase(hash(createUUID() & rand("SHA1PRNG") & createUUID(), "SHA-256"))
                  & lCase(left(hash(createUUID(), "SHA-256"), 16));
        var hours = val(setting("welcome_link_hours", "72"));
        queryExecute("INSERT INTO ai_orbitix_password_resets (oid, email, token_hash, expires_at, created_at)
                      VALUES (:o, :e, :h, DATE_ADD(NOW(), INTERVAL :hrs HOUR), NOW())", {
            o: p.oid, e: p.email, h: lCase(hash(token, "SHA-256")), hrs: {value: hours, cfsqltype: "cf_sql_integer"}
        }, {datasource: "ai_data"});
        return publicHost() & "/ain5py/login/reset_password.cfm?token=" & token;
    }

    public struct function sendWelcome(required string pid) {
        var p = prospectBy("pid", arguments.pid);
        var vars = mailVars(p);
        vars.link = passwordLink(p);
        var r = new trlvaddons.demo.lib.Mailer().sendTemplate("welcome", p.email, vars, p.pid);
        logEvent(p.pid, "mail_sent", {detail: {template: "welcome", ok: r.ok}});
        r.link = vars.link;
        return r;
    }

    // ------------------------------------------------------------------ talk to a person
    /** The inline datasource of an instance database, the way the platform builds it (ai_data account). */
    public struct function instanceDsn(required string db) {
        var sys = createObject("java", "java.lang.System");
        var host = sys.getenv("OBTX_DB_HOST") ?: "";
        if (!len(trim(host))) host = "localhost";
        return {
            class: "com.mysql.cj.jdbc.Driver", bundleName: "com.mysql.cj", bundleVersion: "8.0.33",
            connectionString: "jdbc:mysql://#host#:3306/#arguments.db#?characterEncoding=UTF-8&serverTimezone=America/Chicago&maxReconnects=3",
            username: "ai_data", password: application.env.OBTX_DB_MYSQL_PASS
        };
    }

    /**
     * "Talk to a person" from the demo, through the PLATFORM's own Talk to a
     * Person: a ticket in the sandbox's ai_handoff_requests (it shows in the
     * platform's handoff inbox of that assistant) and the platform's "new
     * ticket" e-mail (HandoffMail staff_new, edited in Talk to a Person >
     * Configuration) to the assistant's staff - the owner, via handoff_email_to.
     * No confirmation e-mail to the prospect (handoff_notify_user = 0).
     */
    public struct function talkToPerson(required string pid, string message = "", string about = "") {
        var p = prospectBy("pid", arguments.pid);
        var n = names(arguments.pid);
        var dsn = instanceDsn(n.db);
        var recent = queryExecute("SELECT COUNT(*) AS c FROM ai_handoff_requests WHERE contact_email = :e AND created_at > NOW() - INTERVAL 1 HOUR",
            {e: p.email}, {datasource: dsn});
        if (recent.c GTE 5) return {ok: false, message: "You have sent several messages in the last hour. Please try again later."};
        var look = queryExecute("SELECT bot_title, handoff_email_to FROM ai_instance_look LIMIT 1", {}, {datasource: dsn});
        var summary = left("Message from the demo" & (len(arguments.about) ? " (" & arguments.about & ")" : "") & ": "
                         & (len(trim(arguments.message)) ? trim(arguments.message) : "(no text, the prospect asked to talk to a person)"), 2000);
        var name = trim((p.fname ?: "") & " " & (p.lname ?: ""));
        queryExecute("INSERT INTO ai_handoff_requests (conversation_id, user_id, contact_name, contact_email, summary, trigger_source, status)
                      VALUES (:c, :u, :n, :e, :s, 'button', 'open')", {
            c: "demo-" & lCase(createUUID()), u: p.email, n: {value: left(name, 200), null: !len(name)}, e: p.email,
            s: {value: summary, cfsqltype: "cf_sql_longvarchar"}
        }, {datasource: dsn, result: "local.ins"});
        var id = local.ins.generatedKey;
        // staff = the assistant's operators + handoff_email_to, as the platform does
        var to = [];
        try {
            var ops = application.auth.getInstanceOperators(n.db);
            for (var o in ops) if (len(o.email ?: "") && !arrayFindNoCase(to, o.email)) arrayAppend(to, o.email);
        } catch (any e) {}
        for (var a in listToArray(look.handoff_email_to ?: "", ",;")) if (len(trim(a)) && !arrayFindNoCase(to, trim(a))) arrayAppend(to, trim(a));
        var sent = 0;
        if (arrayLen(to)) {
            try {
                var base = len(trim(application.env.OBTX_DOMAIN ?: "")) ? reReplace(trim(application.env.OBTX_DOMAIN), "/+$", "") : publicHost();
                var botName = len(trim(look.bot_title ?: "")) ? trim(look.bot_title) : n.db;
                var vars = {
                    "ticket": "H-" & id, "name": len(name) ? name : "(not given)", "email": p.email, "summary": summary,
                    "summary_short": left(reReplace(summary, "\s+", " ", "all"), 60),
                    "opened": dateTimeFormat(now(), "d mmm yyyy, HH:nn"), "bot_name": botName, "instance": n.db,
                    "link": base & "/ain5py/botinstances/handoff_inbox.cfm?wsDsn=" & urlEncodedFormat(n.db) & "&ticket=" & id,
                    "button_label": "Open the ticket", "transcript": [], "trigger": "Talk to a person (demo)"
                };
                var hm = createObject("component", "ain5py.platform.services.HandoffMail").init(dsn);
                savecontent variable="local.junk" { sent = hm.send("staff_new", arrayToList(to), vars, botName) == "sent" ? 1 : 0; }
            } catch (any e) {
                cflog(file="addons", type="error", text="demo talk #arguments.pid# H-#id#: #e.message#");
            }
        }
        queryExecute("UPDATE ai_handoff_requests SET staff_email_sent = :s, user_email_sent = 0 WHERE id = :i",
            {s: sent, i: id}, {datasource: dsn});
        logEvent(arguments.pid, "talk_request", {feature: arguments.about, detail: {message: left(arguments.message, 1000), ticket: "H-" & id, mailed: sent}});
        return {ok: true, ticket: "H-" & id, message: "Your message has been sent."};
    }

    // ------------------------------------------------------------------ helpers
    public string function h(any s) { return encodeForHTML(isSimpleValue(s) ? s : ""); }

    public void function json(required any data, numeric status = 200) {
        cfheader(statuscode = arguments.status);
        cfcontent(type = "application/json; charset=utf-8", reset = true);
        writeOutput(toJson(arguments.data));
        abort;
    }

    /** JSON with lower-case keys. Lucee upper-cases unquoted struct keys
        ("ok" -> "OK"); the browser side always reads lower case. */
    public string function toJson(required any data) {
        return serializeJSON(lowerKeys(arguments.data));
    }

    private any function lowerKeys(any v) {
        if (isStruct(arguments.v)) {
            var o = [:];
            for (var k in arguments.v) o[lCase(k)] = lowerKeys(arguments.v[k] ?: "");
            return o;
        }
        if (isArray(arguments.v)) {
            var a = [];
            for (var x in arguments.v) arrayAppend(a, lowerKeys(x ?: ""));
            return a;
        }
        return arguments.v;
    }
}
