/**
 * Demo add-on - shared library (2026-10-15).
 *
 * Settings, operators, prospects, the feature map, events, usage and the
 * engagement score. Everything the hooks and the pages need lives here so the
 * rules exist once. Database: addon_demo (datasource "addon_demo").
 */
component output="false" {

    variables.dsn = "addon_demo";
    // Pages that are several menu items, told apart by URL parameters (the
    // Instance Control Panel's built-in sections): the Access map keys them as
    // path?section=x[&lms_tab=y]. dflt = the section the bare page shows.
    variables.SECTIONED = {"/ain5py/menuinst/icp_menu.cfm": {params: ["section", "lms_tab"], dflt: "overview"}};
    // The Access map's sections, in menu order: key, label, where the pages come from
    variables.AREAS = [
        {key: "main_ai",   label: "Main AI",          src: "frontmenu/menu*.cfm"},
        {key: "jumpstart", label: "JumpStart",        src: "menucenter/index_V2.cfm, mc_nav_V2.cfm + the Build / Use / Agents centers"},
        {key: "rag",       label: "RAG dashboard",    src: "frontend/rag_dashboard.cfm (its tool list)"},
        {key: "manage",    label: "Manage menu",      src: "manage/menu_config.cfm"},
        {key: "instance",  label: "Instance menu",    src: "menuinst/icp_menu_config.cfm (Instance Control Panel)"},
        {key: "kb",        label: "Knowledge menu",   src: "kb/menu_config.cfm"},
        {key: "quick",     label: "Quick menu",       src: "quick/menu_config.cfm"},
        {key: "other",     label: "Other pages",      src: "pages prospects opened that no menu lists"}
    ];

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

    /**
     * The platform's "current instance" (session.instanceContext) for a prospect is
     * always their own sandbox. The header's AGENT button (the support chat) opens
     * the instance named there, else the box's default instance, which the instance
     * guard refuses for a prospect.
     */
    public void function ensureInstanceContext(required struct d) {
        if (lCase(session.instanceContext.db_name ?: "") == d.dbLower) return;
        var q = queryExecute("SELECT inst_id, instance_name, db_name, db_host, txt_title FROM ai_instance WHERE instance_name = :n",
            {n: d.instance}, {datasource: "ai_data"});
        if (!q.recordCount) return;
        session.instanceContext = {inst_id: q.inst_id, instance_name: q.instance_name, db_name: q.db_name, db_host: q.db_host, txt_title: q.txt_title};
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
        var key = lCase(arguments.path);
        var p = listFirst(key, "?");          // the feature map matches the bare path
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
        // most specific row first: path?section=x&lms_tab=y, path?section=x, path
        var pg = {};
        var all = pages();
        var cand = key;
        while (true) {
            if (structKeyExists(all, cand)) { pg = all[cand]; break; }
            if (!find("?", cand)) break;
            cand = find("&", cand) ? reReplace(cand, "&[^&]*$", "") : listFirst(cand, "?");
        }
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

    public array function areas() { return variables.AREAS; }
    public struct function sectioned() { return variables.SECTIONED; }

    /** The Access map key of a sectioned page: path + its section parameters (lower case, in order). */
    public string function sectionKey(required string path, required struct params) {
        var sp = variables.SECTIONED[arguments.path] ?: {};
        if (structIsEmpty(sp)) return arguments.path;
        var parts = [];
        for (var k in sp.params) {
            var v = lCase(reReplace(arguments.params[k] ?: "", "[^A-Za-z0-9_-]", "", "all"));
            if (!len(v)) break;
            if (k == sp.params[1] && v == sp.dflt) break;   // the default section = the bare page
            arrayAppend(parts, k & "=" & v);
        }
        return arrayLen(parts) ? arguments.path & "?" & arrayToList(parts, "&") : arguments.path;
    }

    /** The key of the page being requested (request_gate). */
    public string function requestKey(required string path) {
        return sectionKey(lCase(arguments.path), url);
    }

    /** A menu link as a lower-case site path ("" for external links, anchors, expressions). */
    public string function normPath(required string href, string base = "/ain5py/") {
        var h = trim(arguments.href);
        if (!len(h) || reFindNoCase("^(https?:|//|javascript:|mailto:)", h)) return "";
        // an anchor or a CF expression in the PATH is not a page; one in the query
        // string (?wsDsn=#encodeForUrl(x)#) is just the instance and is dropped
        if (find("##", listFirst(h, "?")) || left(h, 1) == "?") return "";
        var qs = {};
        if (find("?", h)) {
            for (var pair in listToArray(listRest(h, "?"), "&")) qs[lCase(listFirst(pair, "="))] = listRest(pair, "=");
        }
        h = listFirst(h, "?");
        if (left(h, 1) != "/") h = arguments.base & h;
        var parts = [];
        for (var s in listToArray(h, "/")) {
            if (s == "..") { if (arrayLen(parts)) arrayDeleteAt(parts, arrayLen(parts)); }
            else if (s != ".") arrayAppend(parts, s);
        }
        var p = lCase("/" & arrayToList(parts, "/"));
        if (!reFind("\.(cfm|html?)$", p)) return "";
        return left(sectionKey(p, qs), 255);
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
            // groups keep their whole trail ("Controls › Agents"), so the Access map shows the menu's own tree
            if (isArray(it.children ?: "")) walkMenu(it.children, len(arguments.grp) ? arguments.grp & " › " & lbl : lbl, arguments.base, arguments.rows);
        }
    }

    public numeric function upsertPages(required string area, required array rows, string source = "menu") {
        var n = 0;
        var i = 0;
        var done = {};
        for (var r in arguments.rows) {
            i++;
            // a page linked twice in one menu keeps its first label and place
            if (structKeyExists(done, r.path)) continue;
            done[r.path] = 1;
            // A row first met as "seen" (a prospect opened it) takes the menu's label and place.
            // A row of the same menu follows the menu (label, group, order); one listed by an
            // other menu too keeps its first place. Operators never edit these columns, and
            // updated_at is kept so a scan is not "changed here since the last export".
            // MySQL applies the SET list left to right: the IFs read area/source before they change.
            var prm = {p: r.path, a: arguments.area, g: {value: left(r.grp ?: "", 80), null: !len(r.grp ?: "")},
                       l: left(r.label, 120), s: {value: i, cfsqltype: "cf_sql_integer"}, src: arguments.source};
            queryExecute("INSERT INTO cx_demo_pages (path, area, grp, label, sort, source, menu_seen_at) VALUES (:p, :a, :g, :l, :s, :src, NOW())
                ON DUPLICATE KEY UPDATE
                  label = IF(source = 'seen' OR area = VALUES(area), VALUES(label), label),
                  grp   = IF(source = 'seen' OR area = VALUES(area) OR grp IS NULL, VALUES(grp), grp),
                  sort  = IF(source = 'seen' OR area = VALUES(area), VALUES(sort), sort),
                  menu_seen_at = NOW(),
                  area  = IF(source = 'seen', VALUES(area), area),
                  source = IF(source = 'seen', VALUES(source), source),
                  updated_at = updated_at", prm, {datasource: variables.dsn, result: "local.res"});
            if (val(local.res.recordCount ?: 0) == 1) n++;
            // this menu links to the page (the Access map shows it in every section that does)
            prm.g = {value: left(r.grp ?: "", 160), null: !len(r.grp ?: "")};
            structDelete(prm, "src");
            queryExecute("INSERT INTO cx_demo_page_links (area, path, grp, label, sort, seen_at) VALUES (:a, :p, :g, :l, :s, NOW())
                ON DUPLICATE KEY UPDATE grp = VALUES(grp), label = VALUES(label), sort = VALUES(sort), seen_at = NOW()",
                prm, {datasource: variables.dsn});
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
    public struct function scanMenus(string only = "") {
        var out = {};
        var bases = {manage: "/ain5py/manage/", kb: "/ain5py/kb/", quick: "/ain5py/quick/", instance: "/ain5py/menuinst/"};
        for (var area in ["manage", "instance", "kb", "quick"]) {
            if (len(arguments.only) && arguments.only != area) continue;
            try {
                var rows = [];
                walkMenu(new trlvaddons.demo.lib.MenuProbe().menu(area), "", bases[area], rows);
                if (!arrayLen(rows)) throw(message="the menu came back empty");
                upsertPages(area, rows, "menu");
                out[area] = arrayLen(rows);
                scanned(area, arrayLen(rows));
            } catch (any e) { out[area] = "error: " & e.message; }
        }
        var srcs = [
            {area: "main_ai",   base: "/ain5py/frontmenu/",  files: ["frontmenu/menu.cfm", "frontmenu/menu_agents.cfm", "frontmenu/menu_rag_ingest.cfm", "frontmenu/menu_ragmgt.cfm", "frontmenu/menu_smart.cfm", "frontmenu/menu_training.cfm"]},
            // JumpStart is a hub: its tools sit in the three Centers it opens (Build, Use, Agents)
            {area: "jumpstart", base: "/ain5py/menucenter/", files: ["menucenter/mc_nav_V2.cfm", "menucenter/index_V2.cfm", "menucenter/mc_appsbar.cfm", "menucenter/mc_shell.cfm",
                                                                     "menucenter/ingestion_center_V2.cfm", "menucenter/retrieve_center_V2.cfm", "menucenter/agent_center.cfm", "menucenter/examples_center.cfm"]},
            {area: "rag",       base: "/ain5py/frontend/",   files: [], tools: "frontend/rag_dashboard.cfm"}
        ];
        // the group each source file stands for, in the words of its menu
        var fileGroups = {
            "menu": "Main AI home", "menu_agents": "Agents & Prompts", "menu_rag_ingest": "RAG Maker · Ingestion", "menu_ragmgt": "RAG management tools",
            "menu_smart": "Smart Prompts", "menu_training": "Training Hub",
            "mc_nav_v2": "Top bar", "index_v2": "Platform home", "mc_appsbar": "Apps bar", "mc_shell": "Shell",
            "ingestion_center_v2": "1 · Build (Ingestion Center)", "retrieve_center_v2": "2 · Use (Retrieve Center)",
            "agent_center": "Agents (Agent Center)", "examples_center": "Examples"
        };
        for (var s in srcs) {
            if (len(arguments.only) && arguments.only != s.area) continue;
            var rows = [];
            if (len(s.tools ?: "")) rows = dashboardTools(expandPath("/ain5py/" & s.tools), s.base);
            for (var fn in s.files) {
                var fp = expandPath("/ain5py/" & fn);
                if (!fileExists(fp)) continue;
                var src = fileRead(fp);
                var grp = lCase(reReplace(listLast(fn, "/"), "\.cfm$", ""));
                grp = fileGroups[grp] ?: grp;
                for (var a in reMatchNoCase("<a\s[^>]*href\s*=\s*""[^""]+""[^>]*>[\s\S]*?</a>", src)) {
                    var href = reReplaceNoCase(a, "^[\s\S]*?href\s*=\s*""([^""]+)""[\s\S]*$", "\1");
                    var p = normPath(href, s.base);
                    if (!len(p)) continue;
                    var lbl = trim(reReplace(reReplace(reReplace(a, "<[^>]*>", " ", "all"), "&[a-z##0-9]+;", " ", "all"), "\s+", " ", "all"));
                    // drop the arrows cards end with ("Open Explorer →")
                    lbl = trim(reReplace(lbl, "\s*(→|»|›)\s*$", ""));
                    if (find("##", lbl) || find("' +", lbl) || !len(lbl)) lbl = listLast(listFirst(p, "?"), "/");
                    // a whole card is often one link: keep its first words
                    if (len(lbl) GT 60) lbl = reReplace(left(lbl, 60), "\s+\S*$", "") & "…";
                    arrayAppend(rows, {path: p, label: left(lbl, 120), grp: grp});
                }
            }
            upsertPages(s.area, rows, "menu");
            out[s.area] = arrayLen(rows);
            if (arrayLen(rows)) scanned(s.area, arrayLen(rows));
        }
        return out;
    }

    /**
     * The RAG dashboard draws its cards from a list in its own source
     * (tools.essential = [ { name="RAG Maker", file="ragw_maker.cfm", ... } ]), so its
     * links are read from that list; the groups are the dashboard's section titles.
     */
    private array function dashboardTools(required string fp, required string base) {
        var rows = [];
        if (!fileExists(arguments.fp)) return rows;
        var src = fileRead(arguments.fp);
        var titles = {essential: "Essential · Core workflow", management: "Frequent · Table management", qa: "Quality Lab · Quality", analysis: "Quality Lab · Corpus & capacity"};
        for (var blk in reMatchNoCase("tools\.[a-z_]+\s*=\s*\[[\s\S]*?\];", src)) {
            var k = lCase(reReplaceNoCase(blk, "^tools\.([a-z_]+)[\s\S]*$", "\1"));
            for (var it in reMatchNoCase("\{[^{}]*\}", blk)) {
                if (!reFindNoCase("\bfile\s*=\s*""", it)) continue;
                var p = normPath(reReplaceNoCase(it, "^[\s\S]*?\bfile\s*=\s*""([^""]+)""[\s\S]*$", "\1"), arguments.base);
                if (!len(p)) continue;
                var nm = reFindNoCase("\bname\s*=\s*""", it) ? reReplaceNoCase(it, "^[\s\S]*?\bname\s*=\s*""([^""]+)""[\s\S]*$", "\1") : listLast(p, "/");
                arrayAppend(rows, {path: p, label: left(nm, 120), grp: titles[k] ?: k});
            }
        }
        return rows;
    }

    /** When a section was last scanned and how many links it had (state_scan_<area> = "yyyy-mm-dd HH:nn:ss|n"). */
    private void function scanned(required string area, required numeric n) {
        // the database's clock, the same one that wrote menu_seen_at
        var t = queryExecute("SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s') AS t", {}, {datasource: variables.dsn}).t;
        setSetting("state_scan_" & arguments.area, t & "|" & arguments.n, operator().email ?: "");
    }

    /** {ok, n, mins}: when a section was last scanned (minutes ago, by the database's clock) and how many links it had. */
    public struct function lastScan(required string area) {
        var v = setting("state_scan_" & arguments.area, "");
        if (!len(v)) return {ok: false, n: 0, mins: 0};
        var q = queryExecute("SELECT TIMESTAMPDIFF(MINUTE, STR_TO_DATE(:t, '%Y-%m-%d %H:%i:%s'), NOW()) AS m",
            {t: listFirst(v, "|")}, {datasource: variables.dsn});
        return {ok: true, n: val(listLast(v, "|")), mins: val(q.m)};
    }

    /** What demo.js needs to mark links: the Access map rows' effective modes + the feature map's patterns. */
    public struct function clientMap(required string experience) {
        var c = application.demo_clientmap ?: {};
        if (structKeyExists(c, arguments.experience) && dateDiff("s", c[arguments.experience].at, now()) LT 120) return c[arguments.experience].m;
        var ex = arguments.experience == "explorer";
        var pg = {};
        // Full platform keeps every menu item: "hidden" is shown as locked there
        for (var p in pages()) {
            var md = classify(p, arguments.experience).mode;
            pg[p] = (ex && md == "hidden") ? "pitch" : md;
        }
        var rx = [];
        for (var f in features()) {
            var fm = ex ? f.explorer_mode : f.mode;
            for (var r in f.rx) arrayAppend(rx, [r, (ex && fm == "hidden") ? "pitch" : fm]);
        }
        var m = {pages: pg, rx: rx, sect: variables.SECTIONED};
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

    /** The card a prospect sees (2026-10-16): business prospects the business card only;
        IT prospects the business card with the IT card in c.it, shown under "For IT teams". */
    public struct function cardFor(required string feature, string audience = "business", string lang = "en", string fallback = "") {
        if (arguments.audience != "it") return card(arguments.feature, "business", arguments.lang, arguments.fallback);
        var c = card(arguments.feature, "it", arguments.lang, arguments.fallback);
        if (structIsEmpty(c) || c.audience != "it") return c;          // no IT card: the business one alone
        var b = card(c.feature_key, "business", arguments.lang);
        if (structIsEmpty(b) || b.audience != "business") return c;    // IT card only: show it as the card
        b.it = c;
        return b;
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
        var look = queryExecute("SELECT * FROM ai_instance_look LIMIT 1", {}, {datasource: dsn});
        var subject = "Message from the demo" & (len(arguments.about) ? ": " & arguments.about : "");
        var msg = len(trim(arguments.message)) ? trim(arguments.message) : "(no text)";
        var name = trim((p.fname ?: "") & " " & (p.lname ?: ""));
        // The platform's own "Contact us" ticket (2026-10-16): the same shape as its
        // website contact form (trigger_source from_contact), so the Handoff Inbox of
        // the sandbox answers it by e-mail (contact_reply) and the prospect can follow
        // and answer it on its private request page.
        queryExecute("INSERT INTO ai_handoff_requests (conversation_id, user_id, contact_name, contact_email, summary, trigger_source, status)
                      VALUES (:c, :u, :n, :e, :s, 'from_contact', 'open')", {
            c: "contact-" & lCase(createUUID()), u: "contact:" & left(lCase(p.email), 240), n: {value: left(name, 200), null: !len(name)}, e: p.email,
            s: {value: left(subject & chr(10) & chr(10) & msg, 4000), cfsqltype: "cf_sql_longvarchar"}
        }, {datasource: dsn, result: "local.ins"});
        var id = local.ins.generatedKey;
        var label = "H-" & id;
        var to = contactRecipients(arguments.pid);
        var botName = len(trim(look.bot_title ?: "")) ? trim(look.bot_title) : "Trilivy demo";
        var cf = createObject("component", "ain5py.platform.services.ContactForm").init();
        var vars = {
            "ticket": label, "name": len(name) ? name : "(not given)", "email": p.email, "subject": subject,
            "summary": msg, "summary_short": left(reReplace(subject, "\s+", " ", "all"), 60),
            "opened": dateTimeFormat(now(), "d mmm yyyy, HH:nn"), "website": "Trilivy demo (" & p.pid & ", " & (p.company ?: "") & ")",
            "bot_name": botName, "instance": botName,
            "custom_message": len(trim(look.handoff_message ?: "")) ? trim(look.handoff_message) : setting("contact_confirm_message", "")
        };
        var hm = createObject("component", "ain5py.platform.services.HandoffMail").init(dsn);
        var sent = 0;
        var userSent = 0;
        if (arrayLen(to)) {
            try {
                var sv = duplicate(vars);
                sv.link = cf.baseUrl() & "/ain5py/botinstances/handoff_inbox.cfm?wsDsn=" & urlEncodedFormat(n.db) & "&ticket=" & id;
                sv.button_label = "Open the ticket";
                savecontent variable="local.junk" { sent = hm.send("contact_staff_new", arrayToList(to), sv, botName) == "sent" ? 1 : 0; }
            } catch (any e) {
                cflog(file="addons", type="error", text="demo contact #arguments.pid# #label# staff mail: #e.message#");
            }
        }
        // the prospect's confirmation with the ticket number and the private link (setting mail_contact_confirm)
        if (setting("mail_contact_confirm", "1") == "1") {
            try {
                var uv = duplicate(vars);
                uv.link = cf.ticketUrl(n.db, id);
                uv.button_label = "View your request";
                uv.footer_hint = "To answer, use the link to your request in this email.";
                savecontent variable="local.junk2" { userSent = hm.send("contact_confirm", p.email, uv, botName) == "sent" ? 1 : 0; }
            } catch (any e) {
                cflog(file="addons", type="error", text="demo contact #arguments.pid# #label# confirmation: #e.message#");
            }
        }
        queryExecute("UPDATE ai_handoff_requests SET staff_email_sent = :s, user_email_sent = :u WHERE id = :i",
            {s: sent, u: userSent, i: id}, {datasource: dsn});
        logEvent(arguments.pid, "talk_request", {feature: arguments.about, detail: {message: left(arguments.message, 1000), ticket: label, mailed: sent, confirmed: userSent, to: arrayToList(to)}});
        return {ok: true, ticket: label, message: "Your message has been sent. Your request number is " & label
            & (userSent ? "; a confirmation is on its way to " & p.email & "." : ".")};
    }

    /**
     * Who gets a prospect's Contact us messages: the operators of the sandbox, its
     * Talk to a Person "extra staff addresses" (handoff_email_to: the sales owner by
     * default, editable on the prospect page) and the setting contact_extra_to
     * (Package & settings), for every prospect.
     */
    public array function contactRecipients(required string pid) {
        var n = names(arguments.pid);
        var to = [];
        try {
            var ops = application.auth.getInstanceOperators(n.db);
            for (var o in ops) if (len(o.email ?: "") && !arrayFindNoCase(to, o.email)) arrayAppend(to, o.email);
        } catch (any e) {}
        var extra = "";
        try {
            extra = queryExecute("SELECT handoff_email_to FROM ai_instance_look LIMIT 1", {}, {datasource: instanceDsn(n.db)}).handoff_email_to ?: "";
        } catch (any e) {}
        extra &= "," & setting("contact_extra_to", "");
        for (var a in listToArray(extra, ",; ")) {
            a = trim(a);
            if (isValid("email", a) && !arrayFindNoCase(to, a)) arrayAppend(to, a);
        }
        return to;
    }

    /** The sandbox's extra staff addresses for Contact us (prospect page). */
    public string function contactEmailTo(required string pid) {
        try {
            return queryExecute("SELECT handoff_email_to FROM ai_instance_look LIMIT 1", {}, {datasource: instanceDsn(names(arguments.pid).db)}).handoff_email_to ?: "";
        } catch (any e) { return ""; }
    }

    public void function setContactEmailTo(required string pid, required string emails) {
        var ok = [];
        for (var a in listToArray(arguments.emails, ",; " & chr(10) & chr(13))) {
            a = trim(a);
            if (!isValid("email", a)) throw(message="Not an e-mail address: " & a);
            if (!arrayFindNoCase(ok, a)) arrayAppend(ok, lCase(a));
        }
        queryExecute("UPDATE `#names(arguments.pid).db#`.ai_instance_look SET handoff_email_to = :e", {e: {value: left(arrayToList(ok, ","), 500), null: !arrayLen(ok)}},
            {datasource: new trlvaddons.demo.lib.Sandbox().adminDS()});
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
