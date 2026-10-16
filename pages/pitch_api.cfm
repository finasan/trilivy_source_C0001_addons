<!--- pitch_api - what the demo popups (assets/demo.js) talk to. Prospects only. --->
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset d = demo.sessionDemo()>
<cfif structIsEmpty(d) OR (d.missing ?: true)><cfset demo.json({ok: false, error: "not a demo account"}, 403)></cfif>
<cfset opn = lCase(url.op ?: form.op ?: "")>
<cfset feature = reReplace(lCase(url.feature ?: form.feature ?: ""), "[^a-z0-9_]", "", "all")>

<cfswitch expression="#opn#">
    <cfcase value="card">
        <cfset c = demo.cardFor(feature, d.audience, d.language, reReplace(lCase(url.fb ?: ""), "[^a-z0-9_]", "", "all"))>
        <cfif structIsEmpty(c)><cfset demo.json({ok: false, error: "no card"}, 404)></cfif>
        <cfset via = reReplace(url.via ?: "popup", "[^a-z_]", "", "all")>
        <cfif left(feature, 7) EQ "moment_">
            <cfset demo.logEvent(d.pid, "moment_shown", {feature: feature})>
        <cfelse>
            <cfset demo.logEvent(d.pid, "gate_shown", {feature: feature, detail: {via: via}})>
        </cfif>
        <cfset queryExecute("INSERT INTO cx_demo_pitch_seen (pid, card_key) VALUES (:p, :k)
                             ON DUPLICATE KEY UPDATE last_at = NOW(), times = times + 1", {p: d.pid, k: c.key}, {datasource: "addon_demo"})>
        <!--- IT prospects: the IT card rides along under "For IT teams" (2026-10-16) --->
        <cfset itPart = {}>
        <cfif structKeyExists(c, "it")>
            <cfset queryExecute("INSERT INTO cx_demo_pitch_seen (pid, card_key) VALUES (:p, :k)
                                 ON DUPLICATE KEY UPDATE last_at = NOW(), times = times + 1", {p: d.pid, k: c.it.key}, {datasource: "addon_demo"})>
            <cfset itPart = {headline: c.it.headline, why: c.it.why_html ?: "", how: c.it.how_html ?: "",
                             objections: c.it.objections, proof: c.it.proof_html ?: "", draft: c.it.isDraft}>
        </cfif>
        <!--- the only button is Talk to a person (2026-10-15) --->
        <cfset demo.json({ok: true, card: {
            feature: feature, kicker: c.kicker ?: "", headline: c.headline, why: c.why_html ?: "", how: c.how_html ?: "",
            objections: c.objections, proof: c.proof_html ?: "", cta: ["talk"], draft: c.isDraft,
            canAsk: len(trim(demo.setting("sales_engineer_instance", ""))) GT 0, it: itPart
        }})>
    </cfcase>

    <cfcase value="guard">
        <!--- the instructions popup of an "Open with guardrail" page (Access map) --->
        <!--- ? = & stay: a sectioned page's key is path?section=x[&lms_tab=y] --->
        <cfset pth = lCase(left(reReplace(url.path ?: "", "[^A-Za-z0-9/_.?=&-]", "", "all"), 255))>
        <cfset g = demo.guardInfo(pth, d.mode)>
        <cfif NOT g.ok><cfset demo.json({ok: false}, 404)></cfif>
        <cfset demo.logEvent(d.pid, (url.via ?: "") EQ "help" ? "guard_help" : "guard_shown", {page: pth})>
        <cfset demo.json({ok: true, title: g.title, html: g.html, label: g.label, readonly: g.readonly})>
    </cfcase>

    <cfcase value="event">
        <cfset t = lCase(form.type ?: "")>
        <cfif NOT listFind("pitch_tab,objection_open,cta_click,popup_closed", t)><cfset demo.json({ok: false, error: "type"}, 400)></cfif>
        <cfset det = {}>
        <cfloop list="tab,q,cta,ms,where" item="k"><cfif structKeyExists(form, k)><cfset det[k] = left(form[k], 300)></cfif></cfloop>
        <cfset evOpts = {feature: feature, detail: det}>
        <cfif t EQ "popup_closed" AND isNumeric(form.ms ?: "")><cfset evOpts.duration = int(form.ms)></cfif>
        <cfset demo.logEvent(d.pid, t, evOpts)>
        <cfset demo.json({ok: true})>
    </cfcase>

    <cfcase value="talk">
        <cfif cgi.request_method NEQ "POST"><cfset demo.json({ok: false, error: "POST"}, 405)></cfif>
        <cfset about = "">
        <cfif len(feature)>
            <cfset fq = queryExecute("SELECT title FROM cx_demo_features WHERE feature_key = :f", {f: feature}, {datasource: "addon_demo"})>
            <cfset about = fq.recordCount ? fq.title : feature>
        </cfif>
        <cfset r = demo.talkToPerson(d.pid, left(trim(form.message ?: ""), 1000), about)>
        <cfset demo.json({ok: r.ok, message: r.message})>
    </cfcase>

    <cfcase value="moment">
        <!--- At most one tip, never twice, at least 5 minutes after the last one. --->
        <cfset last = queryExecute("SELECT MAX(ts) AS t FROM cx_demo_events WHERE pid = :p AND type = 'moment_shown'", {p: d.pid}, {datasource: "addon_demo"})>
        <cfif isDate(last.t) AND dateDiff("n", last.t, now()) LT 5><cfset demo.json({ok: true, moment: ""})></cfif>
        <cfset ms = queryExecute("SELECT m.moment_key, m.feature_key, m.trigger_json FROM cx_demo_moments m
                                  WHERE m.active = 1 AND NOT EXISTS (SELECT 1 FROM cx_demo_events e WHERE e.pid = :p AND e.type = 'moment_shown' AND e.feature_key = m.feature_key)
                                  ORDER BY m.moment_key", {p: d.pid}, {datasource: "addon_demo"})>
        <cfset due = "">
        <cfloop query="ms">
            <cfset tr = deserializeJSON(ms.trigger_json)>
            <cfif structKeyExists(tr, "days_left_max")>
                <cfif d.daysLeft LTE tr.days_left_max><cfset due = ms.feature_key><cfbreak></cfif>
            <cfelseif structKeyExists(tr, "event")>
                <cfset sql = "SELECT COUNT(*) AS n FROM cx_demo_events WHERE pid = :p AND type = :t">
                <cfif structKeyExists(tr, "min_rag_hits")>
                    <cfset sql &= " AND CAST(JSON_EXTRACT(detail, '$.raghits') AS SIGNED) >= #int(tr.min_rag_hits)#">
                </cfif>
                <cfset c = queryExecute(sql, {p: d.pid, t: tr.event}, {datasource: "addon_demo"})>
                <cfif c.n GTE val(tr.count ?: tr.nth ?: 1)><cfset due = ms.feature_key><cfbreak></cfif>
            </cfif>
        </cfloop>
        <cfset demo.json({ok: true, moment: due})>
    </cfcase>

    <cfcase value="ask">
        <cfset se = trim(demo.setting("sales_engineer_instance", ""))>
        <cfif NOT len(se)><cfset demo.json({ok: false, error: "not available"}, 404)></cfif>
        <cfset q = queryExecute("SELECT db_name FROM ai_instance WHERE instance_name = :n", {n: se}, {datasource: "ai_data"})>
        <cfset question = left(trim(form.question ?: ""), 1000)>
        <cfset demo.logEvent(d.pid, "ask_opened", {feature: feature, detail: {question: question}})>
        <cfset demo.json({ok: true, url: "/ain5py/boty/boty_full.cfm?wsDsn=" & urlEncodedFormat(q.db_name) & "&embed=1"})>
    </cfcase>

    <cfdefaultcase>
        <cfset demo.json({ok: false, error: "unknown op"}, 400)>
    </cfdefaultcase>
</cfswitch>
