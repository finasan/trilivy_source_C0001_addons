<cfset activeTab = "reports">
<cfinclude template="_ui.cfm">
<cfparam name="url.days" default="90">
<cfset days = isNumeric(url.days) AND url.days GT 0 AND url.days LTE 730 ? int(url.days) : 90>
<cfset prm = {d: {value: days, cfsqltype: "cf_sql_integer"}}>
<cfset funnel = queryExecute("
    SELECT COUNT(*) AS invited,
           SUM(first_login_at IS NOT NULL) AS signed_in,
           SUM(EXISTS(SELECT 1 FROM cx_demo_events e WHERE e.pid = p.pid AND e.type = 'chat_question')) AS asked,
           SUM(EXISTS(SELECT 1 FROM cx_demo_events e WHERE e.pid = p.pid AND e.type = 'ingest_done')) AS uploaded,
           SUM(EXISTS(SELECT 1 FROM cx_demo_events e WHERE e.pid = p.pid AND e.type IN ('talk_request','handoff_requested'))) AS talked,
           SUM(status = 'converted' OR converted_company_id IS NOT NULL) AS converted
    FROM cx_demo_prospects p WHERE p.created_at > NOW() - INTERVAL :d DAY AND p.status <> 'failed'", prm, {datasource: "addon_demo"})>
<cfset gates = queryExecute("SELECT feature_key, COUNT(*) AS n, COUNT(DISTINCT pid) AS people FROM cx_demo_events
    WHERE type = 'gate_shown' AND ts > NOW() - INTERVAL :d DAY GROUP BY feature_key ORDER BY people DESC, n DESC LIMIT 20", prm, {datasource: "addon_demo"})>
<cfset talks = queryExecute("SELECT feature_key, COUNT(*) AS n FROM cx_demo_events WHERE type = 'talk_request' AND ts > NOW() - INTERVAL :d DAY GROUP BY feature_key ORDER BY n DESC", prm, {datasource: "addon_demo"})>
<cfset objs = queryExecute("SELECT feature_key, JSON_UNQUOTE(JSON_EXTRACT(detail, '$.q')) AS q, COUNT(*) AS n FROM cx_demo_events
    WHERE type = 'objection_open' AND ts > NOW() - INTERVAL :d DAY GROUP BY feature_key, q ORDER BY n DESC LIMIT 25", prm, {datasource: "addon_demo"})>
<cfset asks = queryExecute("SELECT ts, pid, feature_key, JSON_UNQUOTE(JSON_EXTRACT(detail, '$.text')) AS q FROM cx_demo_events
    WHERE type = 'ask_question' AND ts > NOW() - INTERVAL :d DAY ORDER BY ts DESC LIMIT 50", prm, {datasource: "addon_demo"})>
<cfset weak = queryExecute("SELECT a.ts, a.pid, JSON_UNQUOTE(JSON_EXTRACT(a.detail, '$.text')) AS q FROM cx_demo_events a
    WHERE a.type = 'chat_question' AND a.ts > NOW() - INTERVAL :d DAY AND EXISTS (
      SELECT 1 FROM cx_demo_events b WHERE b.pid = a.pid AND b.type = 'chat_answer' AND b.ts BETWEEN a.ts AND a.ts + INTERVAL 3 MINUTE
        AND CAST(JSON_EXTRACT(b.detail, '$.raghits') AS SIGNED) = 0)
    ORDER BY a.ts DESC LIMIT 40", prm, {datasource: "addon_demo"})>
<cfset firstQ = queryExecute("SELECT ROUND(AVG(TIMESTAMPDIFF(MINUTE, p.first_login_at, (SELECT MIN(e.ts) FROM cx_demo_events e WHERE e.pid = p.pid AND e.type = 'chat_question')))) AS m
    FROM cx_demo_prospects p WHERE p.first_login_at IS NOT NULL AND p.created_at > NOW() - INTERVAL :d DAY", prm, {datasource: "addon_demo"})>
<cfset purged = queryExecute("SELECT COUNT(*) AS n FROM cx_demo_prospects WHERE status = 'purged' AND created_at > NOW() - INTERVAL :d DAY", prm, {datasource: "addon_demo"})>
<cfset f = queryGetRow(funnel, 1)>
<cfset maxN = max(1, val(f.invited))>
<cfoutput>
<h1>Reports</h1>
<form method="get" action="/ain5py/addon.cfm" style="margin-bottom:10px"><input type="hidden" name="a" value="demo"><input type="hidden" name="p" value="reports">
  Prospects created in the last <select name="days" onchange="this.form.submit()" style="width:auto"><cfloop list="30,90,180,365" item="x"><option #days EQ x ? "selected" : ""#>#x#</option></cfloop></select> days</form>
<h2>Funnel</h2>
<table><cfloop list="invited:Invited,signed_in:Signed in,asked:Asked a question,uploaded:Loaded own documents,talked:Asked for a person,converted:Converted" item="pair">
    <cfset k = listFirst(pair, ":")><cfset v = val(f[k])>
    <tr><td style="width:200px">#listLast(pair, ":")#</td><td style="width:60px"><b>#v#</b></td>
        <td><div style="background:##2457d6;height:12px;border-radius:6px;width:#round(v / maxN * 100)#%"></div></td></tr>
</cfloop></table>
<p class="small muted">Average time from first sign-in to first question: #len(firstQ.m) ? firstQ.m & " min" : "-"#. Purged (summaries kept): #purged.n#.</p>
<div class="grid">
    <div class="card"><h3 style="margin-top:0">What prospects wanted that the demo did not open</h3>
        <table><tr><th>Feature</th><th>People</th><th>Opens</th></tr><cfloop query="gates"><tr><td>#gates.feature_key#</td><td>#gates.people#</td><td>#gates.n#</td></tr></cfloop></table></div>
    <div class="card"><h3 style="margin-top:0">Talk to a person, by feature</h3>
        <table><tr><th>Asked from</th><th>Messages</th></tr><cfloop query="talks"><tr><td>#len(talks.feature_key) ? encodeForHTML(talks.feature_key) : "the demo bar"#</td><td>#talks.n#</td></tr></cfloop></table></div>
</div>
<h2>Objections read most</h2>
<table><tr><th>Feature</th><th>Objection</th><th>Opened</th></tr><cfloop query="objs"><tr><td>#objs.feature_key#</td><td>#encodeForHTML(objs.q)#</td><td>#objs.n#</td></tr></cfloop></table>
<h2>Questions to the Sales Engineer</h2>
<table><tr><th>When</th><th>Prospect</th><th>Feature</th><th>Question</th></tr><cfloop query="asks"><tr><td class="small">#dateTimeFormat(asks.ts, "d mmm HH:nn")#</td><td><a href="/ain5py/addon.cfm?a=demo&p=prospect&arg=#asks.pid#">#asks.pid#</a></td><td>#asks.feature_key#</td><td class="small">#encodeForHTML(asks.q)#</td></tr></cfloop></table>
<h2>Questions the assistant could not ground (no sources)</h2>
<p class="muted small">Candidates for new content or Answer Bank entries.</p>
<table><tr><th>When</th><th>Prospect</th><th>Question</th></tr><cfloop query="weak"><tr><td class="small">#dateTimeFormat(weak.ts, "d mmm HH:nn")#</td><td><a href="/ain5py/addon.cfm?a=demo&p=prospect&arg=#weak.pid#">#weak.pid#</a></td><td class="small">#encodeForHTML(weak.q)#</td></tr></cfloop></table>
</div>
</cfoutput>
