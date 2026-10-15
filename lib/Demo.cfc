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
            seInstance: se
        };
        return session.demo;
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
        var q = queryExecute("SELECT feature_key, title, mode, path_patterns, nav_group, nav_label, sort
                              FROM cx_demo_features ORDER BY sort, feature_key", {}, {datasource: variables.dsn});
        var list = [];
        for (var r in q) {
            var pats = [];
            try { pats = deserializeJSON(r.path_patterns); } catch (any e) {}
            r.rx = [];
            for (var p in pats) {
                p = lCase(trim(p));
                var rx = "^" & reReplace(reReplace(p, "([.\[\]()^$+?{}|\\])", "\\\1", "all"), "\*", ".*", "all") & "$";
                arrayAppend(r.rx, rx);
            }
            arrayAppend(list, r);
        }
        application.demo_features = {at: now(), list: list};
        return list;
    }

    /** {key, mode, title} for a lower-case path. Nothing matched = pitch "platform". */
    public struct function classify(required string path) {
        var p = lCase(arguments.path);
        for (var f in features()) {
            for (var rx in f.rx) {
                if (reFind(rx, p)) return {key: f.feature_key, mode: f.mode, title: f.title};
            }
        }
        return {key: "platform", mode: "pitch", title: "Everything else in the full platform"};
    }

    public array function navPitchItems() {
        var out = [];
        for (var f in features()) {
            if (f.mode == "pitch" && len(f.nav_label ?: "")) arrayAppend(out, f);
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
                detail: {value: serializeJSON(detail), cfsqltype: "cf_sql_longvarchar"},
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
    public struct function card(required string feature, string audience = "business", string lang = "en") {
        var statuses = setting("pitch_show_drafts", "0") == "1" ? "'live','verified','draft'" : "'live'";
        var q = queryExecute("SELECT * FROM cx_demo_pitch WHERE feature_key = :f AND status IN (#statuses#)
                              ORDER BY (audience = :a) DESC, (audience = 'business') DESC, (lang = :l) DESC, (lang = 'en') DESC,
                                       FIELD(status, 'live', 'verified', 'draft') LIMIT 1",
            {f: arguments.feature, a: arguments.audience, l: arguments.lang}, {datasource: variables.dsn});
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

    // ------------------------------------------------------------------ helpers
    public string function h(any s) { return encodeForHTML(isSimpleValue(s) ? s : ""); }

    public void function json(required any data, numeric status = 200) {
        cfheader(statuscode = arguments.status);
        cfcontent(type = "application/json; charset=utf-8", reset = true);
        writeOutput(serializeJSON(arguments.data));
        abort;
    }
}
