/**
 * Demo add-on - the sandbox engine (2026-10-15).
 *
 * One prospect = one cloned assistant ("instance") of the template
 * (setting template_instance, the shipped Orvane Service Desk demo):
 *
 *   MySQL       INST_<box>_vdem_<pid>     every table of the template, rows
 *                                          copied except user-made ones
 *   PostgreSQL  ragt_vdem_<pid>_*         every knowledge table, rows AND
 *                                          embeddings copied (no AI cost)
 *   files       containers/instances/inst_<box>_vdem_<pid>/
 *   ai_data     ai_instance row, demo_user account, grants (own + sales engineer)
 *
 * Every step is journalled in cx_demo_sandbox_ops BEFORE it runs; a failure
 * undoes the finished steps in reverse. purge() removes everything by name
 * (it does not trust the journal) and then proves nothing is left.
 * Runs one at a time (named lock), so two creates never collide.
 */
component output="false" {

    variables.dsn = "addon_demo";
    // Rows made by people, never copied from the template into a sandbox.
    variables.NO_DATA = "ai_chat_sessions,ai_handoff_requests,ai_handoff_messages,ai_handoff_live,ai_handoff_live_messages,"
        & "action_registry_log,ai_users_smartprompts,ai_af_runs,ai_af_test_results,ai_answer_bank_history,"
        & "ws_enrollments,ws_progress,ws_quiz_results,ws_assessment_results,ws_handson_submissions";
    // Shared PostgreSQL tables that may hold a sandbox's rows: [table, column, match]
    // match "base" = the column holds the knowledge-base name (or a prefixed one),
    //       "db"   = the column holds the instance database name.
    variables.PG_SHARED = [
        ["rag_docvault", "target_rag_table", "base"],
        ["ingest_log", "tablename", "base"],
        ["document_relationships", "rag_table", "base"],
        ["rag_source_origin", "target_rag_table", "base"],
        ["rag_logs", "ragtablename", "base"],
        ["rag_logs", "instance", "inst"],
        ["rag_answer_feedback", "instance_db", "db"],
        ["quality_lab_case_sets", "rag_table", "base"],
        ["quality_lab_quick_runs", "rag_table", "base"],
        ["quality_lab_grading_runs", "target_table", "base"],
        ["quality_lab_eval_runs", "target_table", "base"],
        ["quality_lab_golden_set", "target_table", "base"],
        ["rag_purge_audit", "base_table", "base"]
    ];

    public any function init() {
        variables.demo = new trlvaddons.demo.lib.Demo();
        return this;
    }

    // =================================================================== create
    /** Builds the sandbox and the account of an existing cx_demo_prospects row (status building). */
    public struct function create(required string pid, numeric byOid = 0) {
        var out = {ok: false, pid: arguments.pid, steps: [], error: "", oid: 0};
        lock name="demo_sandbox" type="exclusive" timeout="300" {
            var p = demo.prospectBy("pid", arguments.pid);
            if (structIsEmpty(p)) throw(message="no prospect #arguments.pid#");
            var n = demo.names(arguments.pid);
            var t = template();
            var done = [];
            var ctx = {p: p, n: n, t: t, oid: 0, byOid: arguments.byOid};
            try {
                run(n.pid, "create", "check", function() {
                    var u = queryExecute("SELECT oid FROM ai_orbitix_users WHERE email = :e", {e: p.email}, {datasource: "ai_data"});
                    if (u.recordCount) throw(message="An account with #p.email# already exists on this server.");
                    var d = queryExecute("SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE LOWER(SCHEMA_NAME) = :d",
                        {d: n.dbLower}, {datasource: adminDS()});
                    if (d.recordCount) throw(message="Database #n.db# already exists.");
                    return "template #t.instance# (#t.db#, #t.base#)";
                });
                run(n.pid, "create", "mysql", function() { return cloneMysql(t, n, p); });
                arrayAppend(done, "mysql");
                run(n.pid, "create", "postgres", function() { return clonePg(t, n); });
                arrayAppend(done, "postgres");
                run(n.pid, "create", "files", function() { return cloneFiles(t, n); });
                arrayAppend(done, "files");
                run(n.pid, "create", "register", function() { return register(t, n, p); });
                arrayAppend(done, "register");
                run(n.pid, "create", "account", function() { ctx.oid = makeAccount(n, p, ctx.byOid); return "oid #ctx.oid#"; });
                arrayAppend(done, "account");
                run(n.pid, "create", "smoke", function() {
                    var c = queryExecute("SELECT COUNT(*) AS n FROM #n.base#_doc", {}, {datasource: "airrag2"});
                    if (c.n LT 1) throw(message="the cloned knowledge base is empty");
                    return "#c.n# passages ready";
                });
                queryExecute("UPDATE cx_demo_prospects SET oid = :o, status = 'invited', invited_at = NOW() WHERE pid = :p",
                    {o: ctx.oid, p: n.pid}, {datasource: variables.dsn});
                out.ok = true;
                out.oid = ctx.oid;
                demo.logEvent(n.pid, "sandbox_created", {detail: {by: arguments.byOid}});
            } catch (any e) {
                out.error = e.message;
                // undo in reverse
                for (var i = arrayLen(done); i GTE 1; i--) {
                    var what = done[i];
                    try {
                        run(n.pid, "create", "undo_" & what, function() { return undo(what, n, ctx); }, "rolled_back");
                    } catch (any e2) {}
                }
                queryExecute("UPDATE cx_demo_prospects SET status = 'failed', notes = CONCAT(COALESCE(notes,''), :m) WHERE pid = :p",
                    {m: chr(10) & "create failed: " & left(e.message, 400), p: n.pid}, {datasource: variables.dsn});
            }
            out.steps = journal(n.pid, "create");
        }
        return out;
    }

    // =================================================================== reset
    /** Fresh copy of the template; keeps the account, grants, events and the prospect row. */
    public struct function reset(required string pid, numeric byOid = 0) {
        var out = {ok: false, error: ""};
        lock name="demo_sandbox" type="exclusive" timeout="300" {
            var p = demo.prospectBy("pid", arguments.pid);
            if (structIsEmpty(p)) throw(message="no prospect #arguments.pid#");
            var n = demo.names(arguments.pid);
            var t = template();
            try {
                run(n.pid, "reset", "remove_old", function() { return removeData(n); });
                run(n.pid, "reset", "mysql", function() { return cloneMysql(t, n, p); });
                run(n.pid, "reset", "postgres", function() { return clonePg(t, n); });
                run(n.pid, "reset", "files", function() { return cloneFiles(t, n); });
                run(n.pid, "reset", "register", function() { return register(t, n, p); });
                queryExecute("UPDATE cx_demo_docs SET deleted_at = NOW() WHERE pid = :p AND deleted_at IS NULL", {p: n.pid}, {datasource: variables.dsn});
                out.ok = true;
                demo.logEvent(n.pid, "sandbox_reset", {detail: {by: arguments.byOid}});
            } catch (any e) {
                out.error = e.message;
            }
        }
        return out;
    }

    // =================================================================== purge
    /** Removes the sandbox, the account and the prospect's records; keeps an anonymous summary. */
    public struct function purge(required string pid, numeric byOid = 0, boolean keepRow = true) {
        var out = {ok: false, error: "", leftovers: []};
        lock name="demo_sandbox" type="exclusive" timeout="300" {
            var p = demo.prospectBy("pid", arguments.pid);
            if (structIsEmpty(p)) throw(message="no prospect #arguments.pid#");
            var n = demo.names(arguments.pid);
            try {
                var summary = summaryOf(p);
                run(n.pid, "purge", "account", function() { return removeAccount(n, p); });
                run(n.pid, "purge", "data", function() { return removeData(n); });
                run(n.pid, "purge", "records", function() {
                    for (var tbl in ["cx_demo_events", "cx_demo_usage_day", "cx_demo_wishlist", "cx_demo_pitch_seen", "cx_demo_docs"]) {
                        queryExecute("DELETE FROM #tbl# WHERE pid = :p", {p: n.pid}, {datasource: variables.dsn});
                    }
                    queryExecute("UPDATE cx_demo_mail_log SET to_email = '(purged)' WHERE pid = :p", {p: n.pid}, {datasource: variables.dsn});
                    return "events, usage, wish list and documents deleted";
                });
                out.leftovers = leftovers(n);
                if (arrayLen(out.leftovers)) throw(message="left behind: " & arrayToList(out.leftovers, "; "));
                queryExecute("UPDATE cx_demo_prospects SET status = 'purged', oid = NULL, email = CONCAT('purged-', pid),
                                fname = NULL, lname = NULL, notes = NULL, purged_summary_json = :s WHERE pid = :p",
                    {s: serializeJSON(summary), p: n.pid}, {datasource: variables.dsn});
                out.ok = true;
            } catch (any e) {
                out.error = e.message;
            }
        }
        return out;
    }

    // =================================================================== pieces
    public struct function template() {
        var name = demo.setting("template_instance", "demo_servicedesk");
        var q = queryExecute("SELECT instance_name, db_name FROM ai_instance WHERE instance_name = :n", {n: name}, {datasource: "ai_data"});
        if (!q.recordCount) throw(message="The template assistant '#name#' does not exist on this server.");
        var look = queryExecute("SELECT rag_table FROM `#q.db_name#`.ai_instance_look LIMIT 1", {}, {datasource: adminDS()});
        if (!look.recordCount || !len(look.rag_table)) throw(message="The template has no knowledge base (ai_instance_look.rag_table).");
        var root = reReplace(application.env.OBTX_PATH_INSTANCES ?: "/home/trilivyapp/containers/instances", "[/\\]+$", "");
        return {instance: q.instance_name, db: q.db_name, base: look.rag_table, dir: root & "/" & lCase(q.db_name)};
    }

    private string function cloneMysql(required struct t, required struct n, required struct p) {
        var ds = adminDS();
        queryExecute("CREATE DATABASE `#n.db#` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci", {}, {datasource: ds});
        for (var host in ["localhost", "127.0.0.1"]) {
            queryExecute("GRANT ALL PRIVILEGES ON `#n.db#`.* TO 'ai_data'@'#host#'", {}, {datasource: ds});
        }
        var tabs = queryExecute("SELECT TABLE_NAME AS t FROM information_schema.TABLES WHERE TABLE_SCHEMA = :s AND TABLE_TYPE = 'BASE TABLE' ORDER BY 1",
            {s: t.db}, {datasource: ds});
        var copied = 0;
        for (var r in tabs) {
            queryExecute("CREATE TABLE `#n.db#`.`#r.t#` LIKE `#t.db#`.`#r.t#`", {}, {datasource: ds});
            if (!listFindNoCase(variables.NO_DATA, r.t)) {
                queryExecute("INSERT INTO `#n.db#`.`#r.t#` SELECT * FROM `#t.db#`.`#r.t#`", {}, {datasource: ds});
                copied++;
            }
        }
        // Make it the prospect's own assistant.
        var owner = len(p.owner_oid ?: "") ? queryExecute("SELECT email FROM cx_demo_operators WHERE oid = :o", {o: p.owner_oid}, {datasource: variables.dsn}) : {email: ""};
        var title = left((len(p.company ?: "") ? p.company & " · " : "") & "Trilivy demo", 200);
        // instance_name: the platform looks the user's clearance up by it
        // (AgentSup_config -> getUserClearance); left as the template's name,
        // the prospect has no grant on it and is capped at "public".
        queryExecute("UPDATE `#n.db#`.ai_instance_look SET instance_name = :inst, rag_table = :b, rag_background_tables = '',
                        web_search_enabled = 0, upload_enabled = 0, bot_title = :title, handoff_email_to = :he", {
            inst: n.instance, b: n.base, title: title, he: {value: owner.email ?: "", null: !len(owner.email ?: "")}
        }, {datasource: ds});
        return "#tabs.recordCount# tables, #copied# with rows";
    }

    private string function clonePg(required struct t, required struct n) {
        var src = queryExecute("SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE :l ORDER BY 1",
            {l: replace(t.base, "_", "\_", "all") & "\_%"}, {datasource: "airrag2"});
        var made = [];
        for (var r in src) {
            var suffix = mid(r.tablename, len(t.base) + 1, 100);
            if (!reFind("^_[a-z]+$", suffix)) continue;          // only the base's own tables (_doc, _summary, ...)
            var dst = n.base & suffix;
            queryExecute("CREATE TABLE #dst# (LIKE #r.tablename# INCLUDING ALL)", {}, {datasource: "airrag2"});
            // LIKE copies defaults that call the TEMPLATE's sequences: give each its own.
            var seqCols = queryExecute("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public'
                                        AND table_name = :t AND column_default LIKE 'nextval(%'", {t: dst}, {datasource: "airrag2"});
            for (var c in seqCols) {
                var sq = dst & "_" & c.column_name & "_seq";
                queryExecute("CREATE SEQUENCE #sq# OWNED BY #dst#.#c.column_name#", {}, {datasource: "airrag2"});
                queryExecute("ALTER TABLE #dst# ALTER COLUMN #c.column_name# SET DEFAULT nextval('#sq#')", {}, {datasource: "airrag2"});
            }
            queryExecute("INSERT INTO #dst# SELECT * FROM #r.tablename#", {}, {datasource: "airrag2"});
            for (var c2 in seqCols) {
                queryExecute("SELECT setval('#dst#_#c2.column_name#_seq', COALESCE((SELECT MAX(#c2.column_name#) FROM #dst#), 0) + 1, false)",
                    {}, {datasource: "airrag2"});
            }
            arrayAppend(made, dst);
        }
        if (!arrayLen(made)) throw(message="no knowledge tables found for #t.base#");
        // The template's source documents, so My documents lists them too (same files, read-only).
        var vault = 0;
        try {
            var cols = queryExecute("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public'
                                     AND table_name = 'rag_docvault' AND (column_default IS NULL OR column_default NOT LIKE 'nextval(%')
                                     ORDER BY ordinal_position", {}, {datasource: "airrag2"});
            var list = valueList(cols.column_name);
            var sel = reReplace("," & list & ",", ",target_rag_table,", ",'" & n.base & "',", "one");
            sel = mid(sel, 2, len(sel) - 2);
            var res = queryExecute("INSERT INTO rag_docvault (#list#) SELECT #sel# FROM rag_docvault WHERE target_rag_table = :b",
                {b: t.base}, {datasource: "airrag2", result: "local.ins"});
            vault = local.ins.recordCount ?: 0;
        } catch (any e) {
            cflog(file="addons", type="warning", text="demo sandbox #n.pid#: document vault rows not copied: #e.message#");
        }
        return arrayLen(made) & " knowledge tables, #vault# vault rows";
    }

    private string function cloneFiles(required struct t, required struct n) {
        if (directoryExists(n.dir)) throw(message="folder #n.dir# already exists");
        if (directoryExists(t.dir)) directoryCopy(t.dir, n.dir, true);
        else directoryCreate(n.dir);
        directoryCreate(n.dir & "/demo_uploads", true, true);
        return "folder ready";
    }

    private string function register(required struct t, required struct n, required struct p) {
        queryExecute("INSERT INTO ai_instance (instance_name, db_name, db_host, is_active, txt_title, txt_header, description, pallete, datein, addr_chat, addr_lms)
                      SELECT :inst, :db, db_host, 1, :title, txt_header, :descr, pallete, NOW(), 0, 0
                      FROM ai_instance WHERE instance_name = :tmpl", {
            inst: n.instance, db: n.db, tmpl: t.instance,
            title: left((p.company ?: "") & " demo", 100),
            descr: "Demo sandbox of prospect #n.pid#"
        }, {datasource: "ai_data"});
        var prov = createObject("component", "ain5py.platform.services.InstanceProvisioner");
        prov.registerDatasource(n.db);
        var rr = prov.reloadRegistry(n.db);
        return "instance registered, registry reload HTTP #rr.statusCode#";
    }

    private numeric function makeAccount(required struct n, required struct p, numeric byOid = 0) {
        var salt = lCase(hash(createUUID() & rand("SHA1PRNG"), "SHA-256"));
        var pw = hash(createUUID() & createUUID(), "SHA-512");        // unusable; the prospect sets one by link
        // Clearance "internal": the template's passages are internal; without a
        // clearance the search caps the prospect at "public" and finds nothing.
        queryExecute("INSERT INTO ai_orbitix_users (email, fname, lname, password_hash, password_salt, password_must_reset, company,
                        account_type, default_instance_code, default_clearance, account_expires_at,
                        ur_bot, ur_panel, ur_kb, ur_tips, ur_courses, ur_quick, ur_manage, ur_jumpstart, ur_rag, ur_resources, ur_support,
                        date_in, active)
                      VALUES (:e, :f, :l, :h, :s, 0, :c, 'demo_user', :inst, 'internal', :exp, 1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, NOW(), 1)", {
            e: p.email, f: left(p.fname ?: "", 50), l: left(p.lname ?: "", 50),
            h: lCase(hash(pw & ":" & salt, "SHA-256")), s: salt, c: left(p.company ?: "", 100),
            inst: n.instance, exp: {value: p.expires_at, cfsqltype: "cf_sql_timestamp"}
        }, {datasource: "ai_data", result: "local.r"});
        var oid = local.r.generatedKey;
        var grants = [n.instance];
        var se = trim(demo.setting("sales_engineer_instance", ""));
        if (len(se)) arrayAppend(grants, se);
        for (var g in grants) {
            queryExecute("INSERT INTO ai_orbitix_user_instances (oid, instance_code, access_level, clearance, is_operator, granted_by, granted_at, expires_at, flag_active)
                          VALUES (:o, :i, 'standard', 'internal', 0, :by, NOW(), :exp, 1)",
                {o: oid, i: g, by: {value: arguments.byOid, null: arguments.byOid LTE 0}, exp: {value: p.expires_at, cfsqltype: "cf_sql_timestamp"}},
                {datasource: "ai_data"});
        }
        return oid;
    }

    private string function undo(required string what, required struct n, required struct ctx) {
        switch (arguments.what) {
            case "account":  return removeAccount(n, {oid: ctx.oid, email: ctx.p.email});
            case "register": removeRegistration(n); return "registration removed";
            case "files":    if (directoryExists(n.dir)) directoryDelete(n.dir, true); return "folder removed";
            case "postgres": return dropPg(n);
            case "mysql":    queryExecute("DROP DATABASE IF EXISTS `#n.db#`", {}, {datasource: adminDS()}); return "database dropped";
        }
        return "";
    }

    private string function removeAccount(required struct n, required struct p) {
        var oid = val(p.oid ?: 0);
        if (oid LTE 0 && len(p.email ?: "")) {
            var u = queryExecute("SELECT oid FROM ai_orbitix_users WHERE email = :e AND account_type = 'demo_user'", {e: p.email}, {datasource: "ai_data"});
            oid = val(u.oid ?: 0);
        }
        if (oid LTE 0) return "no account";
        var acct = queryExecute("SELECT account_type FROM ai_orbitix_users WHERE oid = :o", {o: oid}, {datasource: "ai_data"});
        if (acct.recordCount && acct.account_type != "demo_user") throw(message="refusing to delete oid #oid#: not a demo account");
        queryExecute("DELETE FROM ai_orbitix_user_instances WHERE oid = :o", {o: oid}, {datasource: "ai_data"});
        queryExecute("DELETE FROM ai_orbitix_password_resets WHERE oid = :o", {o: oid}, {datasource: "ai_data"});
        queryExecute("DELETE FROM ai_orbitix_users WHERE oid = :o AND account_type = 'demo_user'", {o: oid}, {datasource: "ai_data"});
        return "account #oid# deleted";
    }

    private void function removeRegistration(required struct n) {
        queryExecute("DELETE FROM ai_instance WHERE instance_name = :i", {i: n.instance}, {datasource: "ai_data"});
        try { createObject("component", "ain5py.platform.services.InstanceProvisioner").unregisterDatasource(n.db); } catch (any e) {}
    }

    private string function dropPg(required struct n) {
        var tabs = queryExecute("SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE :l",
            {l: replace(n.base, "_", "\_", "all") & "\_%"}, {datasource: "airrag2"});
        for (var r in tabs) queryExecute("DROP TABLE IF EXISTS #r.tablename# CASCADE", {}, {datasource: "airrag2"});
        var rows = 0;
        for (var s in variables.PG_SHARED) {
            try {
                var has = queryExecute("SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = :t AND column_name = :c",
                    {t: s[1], c: s[2]}, {datasource: "airrag2"});
                if (!has.recordCount) continue;
                var v = s[3] == "db" ? n.db : (s[3] == "inst" ? n.instance : n.base);
                // ingest_log stores "public.<base>", others the bare base or a variant table.
                var where = s[3] == "base"
                    ? "(#s[2]# = :v OR #s[2]# LIKE :vl OR #s[2]# = :pv OR #s[2]# LIKE :pvl)"
                    : "LOWER(#s[2]#::text) IN (LOWER(:v), LOWER(:v2))";
                var prm = s[3] == "base"
                    ? {v: v, vl: replace(n.base, "_", "\_", "all") & "\_%", pv: "public." & n.base,
                       pvl: "public." & replace(n.base, "_", "\_", "all") & "\_%"}
                    : {v: v, v2: n.db};
                queryExecute("DELETE FROM #s[1]# WHERE " & where, prm, {datasource: "airrag2", result: "local.del"});
                rows += local.del.recordCount ?: 0;
            } catch (any e) {
                cflog(file="addons", type="warning", text="demo purge #n.pid# #s[1]#.#s[2]#: #e.message#");
            }
        }
        return tabs.recordCount & " knowledge tables dropped, #rows# shared rows deleted";
    }

    private string function removeData(required struct n) {
        removeRegistration(n);
        var pgMsg = dropPg(n);
        queryExecute("DROP DATABASE IF EXISTS `#n.db#`", {}, {datasource: adminDS()});
        if (directoryExists(n.dir)) directoryDelete(n.dir, true);
        return "database, folder and registration removed; " & pgMsg;
    }

    /** Anything still named after the sandbox. Empty = clean. */
    public array function leftovers(required struct n) {
        var out = [];
        var d = queryExecute("SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE LOWER(SCHEMA_NAME) = :d", {d: n.dbLower}, {datasource: adminDS()});
        if (d.recordCount) arrayAppend(out, "MySQL " & n.db);
        var t = queryExecute("SELECT tablename FROM pg_tables WHERE tablename LIKE :l", {l: replace(n.base, "_", "\_", "all") & "%"}, {datasource: "airrag2"});
        for (var r in t) arrayAppend(out, "PostgreSQL " & r.tablename);
        if (directoryExists(n.dir)) arrayAppend(out, "folder " & n.dir);
        var i = queryExecute("SELECT instance_name FROM ai_instance WHERE instance_name = :i", {i: n.instance}, {datasource: "ai_data"});
        if (i.recordCount) arrayAppend(out, "ai_instance " & n.instance);
        var g = queryExecute("SELECT COUNT(*) AS c FROM ai_orbitix_user_instances WHERE instance_code = :i", {i: n.instance}, {datasource: "ai_data"});
        if (g.c) arrayAppend(out, "#g.c# grant(s) on #n.instance#");
        var v = queryExecute("SELECT COUNT(*) AS c FROM rag_docvault WHERE target_rag_table = :b", {b: n.base}, {datasource: "airrag2"});
        if (v.c) arrayAppend(out, "#v.c# rag_docvault row(s)");
        return out;
    }

    private struct function summaryOf(required struct p) {
        var ev = queryExecute("SELECT type, COUNT(*) AS c FROM cx_demo_events WHERE pid = :p GROUP BY type", {p: p.pid}, {datasource: variables.dsn});
        var counts = {};
        for (var r in ev) counts[r.type] = r.c;
        var top = queryExecute("SELECT feature_key, COUNT(*) AS c FROM cx_demo_events WHERE pid = :p AND type = 'gate_shown'
                                GROUP BY feature_key ORDER BY c DESC LIMIT 5", {p: p.pid}, {datasource: variables.dsn});
        var feats = [];
        for (var r2 in top) arrayAppend(feats, r2.feature_key);
        return {audience: p.audience, industry: p.industry ?: "", score: p.score, band: p.score_band,
                created: p.created_at, first_login: p.first_login_at ?: "", last_seen: p.last_seen_at ?: "",
                events: counts, top_gates: feats};
    }

    // =================================================================== plumbing
    public struct function adminDS() {
        var sys = createObject("java", "java.lang.System");
        var host = sys.getenv("OBTX_DB_HOST") ?: "";
        if (!len(trim(host))) host = "localhost";
        var user = sys.getenv("OBTX_DB_USER") ?: "";
        var pass = sys.getenv("OBTX_DB_PASS") ?: "";
        if (!len(user) || !len(pass)) throw(message="OBTX_DB_USER / OBTX_DB_PASS are not available to Lucee");
        return {
            class: "com.mysql.cj.jdbc.Driver", bundleName: "com.mysql.cj", bundleVersion: "8.0.33",
            connectionString: "jdbc:mysql://#host#:3306/?characterEncoding=UTF-8&serverTimezone=America/Chicago",
            username: user, password: pass
        };
    }

    private void function run(required string pid, required string op, required string step, required any fn, string okStatus = "ok") {
        queryExecute("INSERT INTO cx_demo_sandbox_ops (pid, op, step, status) VALUES (:p, :o, :s, 'running')",
            {p: arguments.pid, o: arguments.op, s: arguments.step}, {datasource: variables.dsn, result: "local.ins"});
        var id = local.ins.generatedKey;
        try {
            var msg = arguments.fn();
            queryExecute("UPDATE cx_demo_sandbox_ops SET status = :st, detail = :d, finished_at = NOW(3) WHERE id = :i",
                {st: arguments.okStatus, d: left(isSimpleValue(msg ?: "") ? (msg ?: "") : "", 2000), i: id}, {datasource: variables.dsn});
        } catch (any e) {
            queryExecute("UPDATE cx_demo_sandbox_ops SET status = 'failed', detail = :d, finished_at = NOW(3) WHERE id = :i",
                {d: left(e.message & " " & (e.detail ?: ""), 2000), i: id}, {datasource: variables.dsn});
            rethrow;
        }
    }

    public array function journal(required string pid, string op = "") {
        var q = queryExecute("SELECT op, step, status, detail, started_at, finished_at,
                                     TIMESTAMPDIFF(MICROSECOND, started_at, finished_at) / 1000 AS ms
                              FROM cx_demo_sandbox_ops WHERE pid = :p" & (len(arguments.op) ? " AND op = :o" : "") & " ORDER BY id",
            {p: arguments.pid, o: arguments.op}, {datasource: variables.dsn});
        var out = [];
        for (var r in q) arrayAppend(out, r);
        return out;
    }
}
