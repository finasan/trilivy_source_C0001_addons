/**
 * Demo add-on - hook answers (hook_api 1, platform/services/AddonService.cfc).
 *
 * Applies ONLY to demo_user accounts (prospects). Operators and every other
 * account pass through untouched, except that operators see a small
 * "Demo Console" link.
 *
 * For a prospect, request_gate is the enforcement point (it runs for every
 * page, API and chat call included):
 *   1. paused demo / ended demo / missing consent   -> the matching demo page
 *   2. instance guard: any instance named in the request must be the
 *      prospect's own sandbox or the sales-engineer assistant     -> else 403
 *   3. table guard: any knowledge-base name must be the sandbox's -> else 403
 *   4. feature map (default deny): open/capped run; pitch -> pitch page;
 *      hidden -> 403
 */
component output="false" {

    variables.INST_KEYS  = "wsdsn,ws_dsn,db_name,dbname,instance,instance_code,instancecode,dsn,botyinstancedsn";
    variables.TABLE_KEYS = "table_name,tablename,rag_table,ragtable,ragtablename,target_table,targettable,target_rag_table";

    public any function init(struct meta = {}) {
        variables.meta = arguments.meta;
        variables.demo = new trlvaddons.demo.lib.Demo();
        return this;
    }

    private boolean function isProspect() {
        return structKeyExists(session, "userLoggedIn") && session.userLoggedIn
            && (session.account_type ?: "") == "demo_user";
    }

    public boolean function isOperator() {
        return structKeyExists(session, "userLoggedIn") && session.userLoggedIn && demo.isOperator();
    }

    // ------------------------------------------------------------- login_check
    public struct function login_check(required struct ctx) {
        var u = ctx.user ?: {};
        if ((u.account_type ?: "") != "demo_user") return {allow: true};
        var p = demo.prospectBy("oid", val(u.oid ?: 0));
        if (structIsEmpty(p)) return {allow: false, message: "This demo account is not set up. Please contact the Trilivy team."};
        if (listFind("suspended,expired,purged,failed,building", p.status)) {
            return {allow: false, message: p.status == "suspended"
                ? "This demo is paused. Please contact the Trilivy team."
                : "This demo has ended. Thank you for trying Trilivy; contact us to continue."};
        }
        return {allow: true};
    }

    // ------------------------------------------------------------- session_init
    public void function session_init(required struct ctx) {
        structDelete(session, "demo");
        structDelete(session, "demo_op");
        if ((ctx.user.account_type ?: "") == "demo_user") demo.sessionDemo(true);
    }

    // ------------------------------------------------------------- request_gate
    public struct function request_gate(required struct ctx) {
        if (!isProspect()) return {action: "continue"};
        var path = ctx.path;
        var d = demo.sessionDemo();
        var onLogin = left(path, 14) == "/ain5py/login/";
        if (d.missing ?: true) {
            return onLogin ? {action: "continue"} : {action: "deny", message: "This demo account is not set up."};
        }
        // The temporary-keys notice is for administrators; a prospect goes on to the demo.
        if (path == "/ain5py/login/keys_notice.cfm") return {action: "redirect", url: "/ain5py/addon.cfm?a=demo&p=welcome"};
        if (onLogin) return {action: "continue"};                       // sign out / passwords always work

        var isAddon = path == "/ain5py/addon.cfm" || path == "/ain5py/addon_api.cfm";
        var page = lCase(url.p ?: "");
        var isAsset = isAddon && page == "asset";

        if (demo.paused() && !isAsset) {
            return {action: "deny", message: "The demo is being updated and will be back in a few minutes."};
        }
        if (!listFind("invited,active,expiring,converted", d.status) && !(isAddon && listFind("ended,asset", page))) {
            return {action: "redirect", url: "/ain5py/addon.cfm?a=demo&p=ended"};
        }
        if (!d.consent && !(isAddon && listFind("consent,asset", page))) {
            return {action: "redirect", url: "/ain5py/addon.cfm?a=demo&p=consent"};
        }

        // instance guard
        // The same sandbox can be named three ways: vdem_p0007, INST_c0002_vdem_p0007,
        // and c0002_vdem_p0007 (what WsDsnResolver sends).
        var allowedInst = [lCase(d.instance), d.dbLower, lCase(demo.companyCode() & "_" & d.instance)];
        if (len(d.seInstance)) {
            arrayAppend(allowedInst, lCase(d.seInstance));
        }
        var bad = scanParams(variables.INST_KEYS, function(v) {
            var x = lCase(trim(v));
            if (arrayFind(allowedInst, x)) return true;
            if (len(d.seInstance) && x == lCase(seDb())) return true;
            return false;
        });
        if (len(bad)) return tamper(d, path, "instance", bad);

        // table guard
        bad = scanParams(variables.TABLE_KEYS, function(v) {
            var x = lCase(trim(v));
            return left(x, len(d.base)) == d.base;
        });
        if (len(bad)) return tamper(d, path, "table", bad);

        // the front door
        if (path == "/ain5py/index.cfm" || path == "/ain5py/" || path == "/ain5py/menu.cfm") {
            return {action: "redirect", url: "/ain5py/addon.cfm?a=demo&p=welcome"};
        }

        var f = demo.classify(path, d.mode);
        // Safety audit of the Full platform map (setting explorer_audit_pid, set
        // only while an operator runs it): that one prospect may OPEN any page,
        // read-only, so the crawl can see what each page would show.
        if (d.audit && cgi.request_method == "GET" && f.mode != "hidden") {
            demo.logEvent(d.pid, "audit_view", {feature: f.key, page: left(path, 255)});
            return {action: "continue"};
        }
        if (f.mode == "open" || f.mode == "capped") {
            if (!isAddon && !isApiPath(path) && cgi.request_method == "GET") {
                demo.logEvent(d.pid, "page_view", {feature: f.key, page: left(path & (len(cgi.query_string) ? "?" & cgi.query_string : ""), 255)});
            }
            return {action: "continue"};
        }
        if (f.mode == "pitch") {
            demo.logEvent(d.pid, "gate_shown", {feature: f.key, page: path, detail: {via: "url"}});
            if (isApiPath(path) || cgi.request_method != "GET") {
                return {action: "deny", message: "This feature is not part of the demo."};
            }
            // Inside a frame (the Manage / JumpStart menus) keep embed=1, or the card
            // page brings its own platform header and the frame shows a second one.
            var framed = (url.embed ?: "") == "1" || (form.embed ?: "") == "1" || lCase(cgi.http_sec_fetch_dest ?: "") == "iframe";
            return {action: "redirect", url: "/ain5py/addon.cfm?a=demo&p=pitch_page&arg=" & urlEncodedFormat(f.key) & (framed ? "&embed=1" : "")};
        }
        demo.logEvent(d.pid, "page_denied", {feature: f.key, page: path});
        return {action: "deny", message: "This page is not part of the demo."};
    }

    // ------------------------------------------------------------- nav_items
    public void function nav_items(required struct ctx) {
        if (isOperator()) {
            arrayAppend(ctx.nav, {on: 1, label: "Demo Console", emoji: "🎯", href: "/ain5py/addon.cfm?a=demo&p=console", target: "", attrs: ""});
            return;
        }
        if (!isProspect()) return;
        var d = demo.sessionDemo();
        if (d.missing ?: true) return;
        var ws = urlEncodedFormat(d.db);
        if (d.mode == "explorer") {
            // Full platform: the platform's own menu (its items follow the session
            // rights), with the demo home in front and the account menu trimmed.
            arrayPrepend(ctx.nav, {on: 1, label: "Demo home", emoji: "🏠", href: "/ain5py/addon.cfm?a=demo&p=welcome", target: "", attrs: ""});
            for (var it in ctx.nav) {
                if (findNoCase("wsDsn=", it.href ?: "")) it.href = reReplaceNoCase(it.href, "wsDsn=[^&]*", "wsDsn=" & ws);
            }
            ctx.res = [];
            ctx.acct = [{label: "📝 Change Password", href: "/ain5py/manage/changepass.cfm"}];
            ctx.flags.resources = 0;
            ctx.flags.supportChat = 0;
            return;
        }
        var nav = [
            {on: 1, label: "Home", emoji: "🏠", href: "/ain5py/addon.cfm?a=demo&p=welcome", target: "", attrs: ""},
            {on: 1, label: "Assistant", emoji: "💬", href: "/ain5py/boty/boty_full.cfm?wsDsn=" & ws, target: "_blank", attrs: ""},
            {on: 1, label: "My documents", emoji: "📄", href: "/ain5py/addon.cfm?a=demo&p=my_docs", target: "", attrs: ""},
            {on: 1, label: "Courses", emoji: "📚", href: "/ain5py/lms_workshop/player/player_launch.cfm?wsDsn=" & ws, target: "", attrs: ""}
        ];
        // The locked (greyed) features are NOT in this header row: nine extra
        // buttons wrapped it onto two lines and hid the account menu. They are
        // drawn in the DEMO bar under the header (page_top), each opening its popup.
        ctx.nav = nav;
        ctx.res = [];
        ctx.acct = [{label: "📝 Change Password", href: "/ain5py/manage/changepass.cfm"}];
        ctx.flags.resources = 0;
        ctx.flags.supportChat = 0;
    }

    // ------------------------------------------------------------- page_top
    public string function page_top(required struct ctx) {
        if (isOperator()) {
            return '<div style="position:fixed;right:12px;bottom:12px;z-index:9999;font:13px Arial,sans-serif">'
                 & '<a href="/ain5py/addon.cfm?a=demo&p=console" style="background:##0d47a1;color:##fff;padding:6px 12px;border-radius:999px;text-decoration:none;box-shadow:0 2px 8px rgba(0,0,0,.25)">Demo Console</a></div>';
        }
        if (!isProspect()) return "";
        var d = demo.sessionDemo();
        if ((d.missing ?: true) || !d.consent) return "";
        var cfg = {
            pid: d.pid, audience: d.audience, lang: d.language, daysLeft: d.daysLeft,
            company: d.company, where: ctx.where ?: "header", wsDsn: d.db,
            api: "/ain5py/addon_api.cfm?a=demo&p=pitch_api", beacon: "/ain5py/addon_api.cfm?a=demo&p=beacon"
        };
        var left_ = d.daysLeft == 1 ? "1 day left" : d.daysLeft & " days left";
        var locked = "";
        for (var f in demo.navPitchItems(d.mode)) {
            locked &='<a href="/ain5py/addon.cfm?a=demo&p=pitch_page&arg=' & encodeForURL(f.feature_key) & '" class="demo-lock" data-demo-feature="'
                    & encodeForHTMLAttribute(f.feature_key) & '">🔒 ' & encodeForHTML(f.nav_label) & '</a>';
        }
        return '<link rel="stylesheet" href="/ain5py/addon_api.cfm?a=demo&p=asset&f=demo.css">'
             & '<div id="demoBar" class="demo-bar"><span class="demo-tag">DEMO</span> '
             & '<span class="demo-co">' & encodeForHTML(d.company) & '</span>'
             & '<span class="demo-left">' & encodeForHTML(left_) & '</span>'
             & demo.switchHtml(d.mode)
             & '<span class="demo-locks">' & locked & '</span>'
             & '<a href="##" class="demo-talk" data-demo-action="talk">Contact us</a></div>'
             & '<script>window.TRLV_DEMO = ' & demo.toJson(cfg) & ';</script>'
             & '<script src="/ain5py/addon_api.cfm?a=demo&p=asset&f=demo.js" defer></script>';
    }

    /** The popup script without the DEMO bar, for pages shown inside a frame (embed=1). */
    public string function frameScripts() {
        if (!isProspect()) return "";
        var d = demo.sessionDemo();
        if ((d.missing ?: true) || !d.consent) return "";
        var cfg = {
            pid: d.pid, audience: d.audience, lang: d.language, daysLeft: d.daysLeft,
            company: d.company, where: "frame", wsDsn: d.db,
            api: "/ain5py/addon_api.cfm?a=demo&p=pitch_api", beacon: "/ain5py/addon_api.cfm?a=demo&p=beacon"
        };
        return '<link rel="stylesheet" href="/ain5py/addon_api.cfm?a=demo&p=asset&f=demo.css">'
             & '<script>window.TRLV_DEMO = ' & demo.toJson(cfg) & ';</script>'
             & '<script src="/ain5py/addon_api.cfm?a=demo&p=asset&f=demo.js" defer></script>';
    }

    // ------------------------------------------------------------- chat_pre
    public struct function chat_pre(required struct ctx) {
        if (!isProspect()) return {allow: true};
        var d = demo.sessionDemo();
        if (d.missing ?: true) return {allow: false, message: "This demo account is not set up."};
        var ws = dbOf(ctx.wsDsn ?: "");
        var isSe = len(d.seInstance) && ws == lCase(seDb());
        var rt = lCase(ctx.ragTable ?: "");
        if ((ws != d.dbLower && !isSe) || (!isSe && len(rt) && left(rt, len(d.base)) != d.base)) {
            tamper(d, "/chat", "instance", ws & " / " & rt);
            return {allow: false, message: "This assistant is not part of your demo."};
        }
        if (demo.paused()) return {allow: false, message: "The demo is being updated and will be back in a few minutes."};
        var p = demo.prospectBy("pid", d.pid);
        var caps = demo.caps(p);
        var today = demo.usageToday(d.pid);
        var total = demo.usageTotal(d.pid);
        if (isSe) {
            if (today.asks GTE val(caps.asks_day ?: 40)) return capHit(d, "asks_day", "You have reached today's limit for questions about features. Use Contact us for more.");
            return {allow: true};
        }
        if (today.questions GTE val(caps.questions_day ?: 150)) return capHit(d, "questions_day", "You have reached today's question limit for the demo. It resets tomorrow, or use Contact us to raise it.");
        if (total.tokens GTE val(caps.tokens_total ?: 2000000)) return capHit(d, "tokens_total", "Your demo has used its AI allowance. Use Contact us and we will extend it.");
        var month = queryExecute("SELECT COALESCE(SUM(tokens),0) AS t FROM cx_demo_usage_day WHERE day >= DATE_FORMAT(CURDATE(), '%Y-%m-01')", {}, {datasource: "addon_demo"});
        if (month.t GTE val(demo.setting("monthly_token_budget", "60000000"))) return capHit(d, "monthly_budget", "The demo is very busy this month. Please use Contact us.");
        return {allow: true};
    }

    // ------------------------------------------------------------- event
    public void function event(required struct ctx) {
        var t = ctx.type;
        var data = ctx.data ?: {};
        if (t == "login_failed") {
            if ((data.account_type ?: "") != "demo_user") return;
            var pf = demo.prospectBy("oid", val(data.oid ?: 0));
            if (!structIsEmpty(pf)) demo.logEvent(pf.pid, "login_failed", {detail: {reason: data.reason ?: ""}});
            return;
        }
        if (!isProspect()) return;
        var d = demo.sessionDemo();
        if (d.missing ?: true) return;
        var isSe = len(d.seInstance) && dbOf(data.wsDsn ?: "") == lCase(seDb());
        switch (t) {
            case "login_ok":
                demo.logEvent(d.pid, "login_ok");
                break;
            case "chat_question":
                demo.addUsage(d.pid, isSe ? "asks" : "questions", 1);
                demo.logEvent(d.pid, isSe ? "ask_question" : "chat_question", {feature: isSe ? "sales_engineer" : "chat",
                    detail: {text: left(data.text ?: "", 4000), conversation: data.conversationId ?: ""}});
                break;
            case "chat_answer":
                demo.addUsage(d.pid, "tokens", val(data.inputTokens ?: 0) + val(data.outputTokens ?: 0));
                demo.logEvent(d.pid, isSe ? "ask_answer" : "chat_answer", {feature: isSe ? "sales_engineer" : "chat",
                    duration: val(data.totalMs ?: 0),
                    detail: {text: left(data.text ?: "", 6000), ragHits: val(data.ragHits ?: 0),
                             tokens: val(data.inputTokens ?: 0) + val(data.outputTokens ?: 0), conversation: data.conversationId ?: ""}});
                break;
            case "handoff_requested":
                demo.logEvent(d.pid, "handoff_requested", {feature: "handoff", detail: {kind: data.kind ?: "", id: data.id ?: "", summary: left(data.summary ?: "", 1000)}});
                demo.alert(demo.prospectBy("pid", d.pid), "Talk to a person", "The prospect asked for a person (#data.kind ?: ''#): " & left(data.summary ?: "", 500));
                break;
        }
    }

    // ------------------------------------------------------------- helpers
    /** The database name of a chat's instance: the core passes either a name or
        the inline datasource struct (jdbc:mysql://host:3306/<db>?...). Lower case. */
    private string function dbOf(any v) {
        if (isStruct(arguments.v)) {
            var cs = arguments.v.connectionString ?: "";
            return lCase(reReplace(cs, "^jdbc:mysql://[^/]+/([^?;]+).*$", "\1"));
        }
        return isSimpleValue(arguments.v) ? lCase(trim(arguments.v)) : "";
    }

    private string function seDb() {
        var se = demo.setting("sales_engineer_instance", "");
        if (!len(se)) return "";
        var c = application.demo_se_db ?: {};
        if (structKeyExists(c, "name") && c.name == se && dateDiff("s", c.at, now()) LT 300) return c.db;
        var q = queryExecute("SELECT db_name FROM ai_instance WHERE instance_name = :n", {n: se}, {datasource: "ai_data"});
        application.demo_se_db = {name: se, db: q.db_name ?: "", at: now()};
        return q.db_name ?: "";
    }

    /** The first parameter (url or form) named in keys whose value fails ok(); "" when all pass. */
    private string function scanParams(required string keys, required any ok) {
        for (var sc in [url, form]) {
            for (var k in sc) {
                if (!listFindNoCase(arguments.keys, k)) continue;
                var v = sc[k];
                if (!isSimpleValue(v) || !len(trim(v))) continue;
                for (var item in listToArray(v, ",")) {
                    if (len(trim(item)) && !ok(item)) return k & "=" & left(item, 80);
                }
            }
        }
        return "";
    }

    private struct function tamper(required struct d, required string path, required string kind, required string what) {
        demo.logEvent(d.pid, "tamper_blocked", {page: path, detail: {kind: kind, value: what}});
        var c = session.demo_tamper_alerted ?: 0;
        if (!c) {
            session.demo_tamper_alerted = 1;
            demo.alert(demo.prospectBy("pid", d.pid), "Blocked access attempt", "#kind# guard on #path#: #what#");
        }
        return {action: "deny", message: "This is outside your demo."};
    }

    private struct function capHit(required struct d, required string cap, required string msg) {
        demo.logEvent(d.pid, "cap_reached", {detail: {cap: cap}});
        return {allow: false, message: msg};
    }

    private boolean function isApiPath(required string path) {
        return path contains "/api/" || path contains "_api" || left(listLast(path, "/"), 4) == "api_"
            || structKeyExists(url, "api_action") || path contains "/boty/support/";
    }
}
