<cfset activeTab = "console">
<cfinclude template="_ui.cfm">
<cfset pid = lCase(trim(request.addon.arg))>
<cfif NOT reFind("^p[0-9]{4}$", pid)><cfoutput><div class="note err">Unknown prospect.</div></div></cfoutput><cfexit></cfif>
<cfset p = demo.prospectBy("pid", pid)>
<cfif structIsEmpty(p)><cfoutput><div class="note err">No prospect #pid#.</div></div></cfoutput><cfexit></cfif>
<cfset msg = "">
<cfset msgKind = "ok">
<cfset shownLink = "">

<!--- ============================ actions ============================ --->
<cfif cgi.request_method EQ "POST" AND len(form.action ?: "")>
    <cftry>
    <cfswitch expression="#form.action#">
        <cfcase value="resend">
            <cfset r = demo.sendWelcome(pid)>
            <cfset msg = r.ok ? "Welcome e-mail sent to #p.email#." : "The e-mail failed: #r.error#">
            <cfset msgKind = r.ok ? "ok" : "err">
        </cfcase>
        <cfcase value="link">
            <cfset shownLink = demo.passwordLink(p)>
            <cfset demo.logEvent(pid, "password_link_shown", {detail: {by: op.oid}})>
            <cfset msg = "A new set-password link was made (valid #demo.setting('welcome_link_hours', '72')# hours). Give it to the prospect yourself.">
        </cfcase>
        <cfcase value="extend">
            <cfset d = int(val(form.days ?: 7))>
            <cfif d LT 1 OR d GT 60><cfthrow message="1 to 60 days"></cfif>
            <cfset newExp = dateAdd("d", d, (isDate(p.expires_at) AND p.expires_at GT now()) ? p.expires_at : now())>
            <cfset queryExecute("UPDATE cx_demo_prospects SET expires_at = :x, purge_after = NULL,
                                   status = IF(status IN ('expired','expiring'), IF(first_login_at IS NULL, 'invited', 'active'), status) WHERE pid = :p",
                {x: {value: newExp, cfsqltype: "cf_sql_timestamp"}, p: pid}, {datasource: "addon_demo"})>
            <cfif val(p.oid)>
                <cfset queryExecute("UPDATE ai_orbitix_users SET account_expires_at = :x WHERE oid = :o AND account_type = 'demo_user'",
                    {x: {value: newExp, cfsqltype: "cf_sql_timestamp"}, o: p.oid}, {datasource: "ai_data"})>
                <cfset queryExecute("UPDATE ai_orbitix_user_instances SET expires_at = :x WHERE oid = :o",
                    {x: {value: newExp, cfsqltype: "cf_sql_timestamp"}, o: p.oid}, {datasource: "ai_data"})>
            </cfif>
            <cfset demo.logEvent(pid, "extended", {detail: {days: d, by: op.oid, until: dateTimeFormat(newExp, "yyyy-mm-dd HH:nn")}})>
            <cfset msg = "Extended by #d# days, to #dateFormat(newExp, 'd mmm yyyy')#.">
        </cfcase>
        <cfcase value="suspend,resume">
            <cfset ns = form.action EQ "suspend" ? "suspended" : (isDate(p.first_login_at) ? "active" : "invited")>
            <cfset queryExecute("UPDATE cx_demo_prospects SET status = :s WHERE pid = :p", {s: ns, p: pid}, {datasource: "addon_demo"})>
            <cfset demo.logEvent(pid, form.action EQ "suspend" ? "suspended" : "resumed", {detail: {by: op.oid}})>
            <cfset msg = form.action EQ "suspend" ? "Suspended: the prospect is signed out within a minute and cannot sign in." : "Resumed.">
        </cfcase>
        <cfcase value="settings">
            <cfif NOT listFind("standard,generous", form.caps ?: "")><cfthrow message="bad limits"></cfif>
            <cfset queryExecute("UPDATE cx_demo_prospects SET caps_preset = :c, owner_oid = :o, notes = :n, audience = :a WHERE pid = :p", {
                c: form.caps, o: {value: val(form.owner_oid ?: 0), null: NOT val(form.owner_oid ?: 0)},
                n: form.notes ?: "", a: listFind("business,it,finance,hr,exec", form.audience ?: "") ? form.audience : p.audience, p: pid
            }, {datasource: "addon_demo"})>
            <cfset msg = "Saved.">
        </cfcase>
        <cfcase value="reset">
            <cfif (form.confirm ?: "") NEQ pid><cfthrow message="Type #pid# to confirm the reset."></cfif>
            <cfset r = new trlvaddons.demo.lib.Sandbox().reset(pid, op.oid)>
            <cfset msg = r.ok ? "The sandbox was rebuilt from the template. The prospect's uploads are gone; events and the account are kept." : "Reset failed: #r.error#">
            <cfset msgKind = r.ok ? "ok" : "err">
        </cfcase>
        <cfcase value="purge">
            <cfif lCase(trim(form.confirm ?: "")) NEQ lCase(p.email)><cfthrow message="Type the prospect's e-mail to confirm."></cfif>
            <cfset r = new trlvaddons.demo.lib.Sandbox().purge(pid, op.oid)>
            <cfset msg = r.ok ? "Purged: sandbox, account, documents and events are deleted; an anonymous summary is kept." : "Purge failed: #r.error#">
            <cfset msgKind = r.ok ? "ok" : "err">
        </cfcase>
        <cfcase value="convert">
            <cfset queryExecute("UPDATE cx_demo_prospects SET status = 'converted', converted_company_id = :c WHERE pid = :p",
                {c: {value: val(form.company_id ?: 0), null: NOT val(form.company_id ?: 0)}, p: pid}, {datasource: "addon_demo"})>
            <cfset demo.logEvent(pid, "converted", {detail: {by: op.oid, company_id: val(form.company_id ?: 0)}})>
            <cfset msg = "Marked as converted. The demo stays open until its end date.">
        </cfcase>
    </cfswitch>
    <cfcatch>
        <cfset msg = cfcatch.message><cfset msgKind = "err">
    </cfcatch>
    </cftry>
    <cfset p = demo.prospectBy("pid", pid)>
</cfif>

<!--- ============================ data ============================ --->
<cfset ev = queryExecute("SELECT id, ts, type, feature_key, page, detail, duration_ms, session_id FROM cx_demo_events WHERE pid = :p ORDER BY id DESC LIMIT 400", {p: pid}, {datasource: "addon_demo"})>
<cfset gates = queryExecute("SELECT feature_key, SUM(type='gate_shown') AS gates, SUM(type='objection_open') AS objections,
                                    SUM(type='cta_click') AS ctas, SUM(type='ask_question') AS asks
                             FROM cx_demo_events WHERE pid = :p AND feature_key IS NOT NULL
                               AND type IN ('gate_shown','objection_open','cta_click','ask_question')
                             GROUP BY feature_key ORDER BY gates DESC", {p: pid}, {datasource: "addon_demo"})>
<cfset wish = queryExecute("SELECT feature_key, added_at FROM cx_demo_wishlist WHERE pid = :p ORDER BY added_at", {p: pid}, {datasource: "addon_demo"})>
<cfset docs = queryExecute("SELECT * FROM cx_demo_docs WHERE pid = :p ORDER BY id DESC", {p: pid}, {datasource: "addon_demo"})>
<cfset mails = queryExecute("SELECT * FROM cx_demo_mail_log WHERE pid = :p ORDER BY id DESC LIMIT 50", {p: pid}, {datasource: "addon_demo"})>
<cfset jr = new trlvaddons.demo.lib.Sandbox().journal(pid)>
<cfset usage = queryExecute("SELECT * FROM cx_demo_usage_day WHERE pid = :p ORDER BY day DESC LIMIT 30", {p: pid}, {datasource: "addon_demo"})>
<cfset caps = demo.caps(p)>
<cfset tot = demo.usageTotal(pid)>
<cfset owner = val(p.owner_oid) ? demo.operator(p.owner_oid) : {name: "", email: ""}>
<cfscript>
    function evLine(required struct e) {
        var d = {};
        try { d = deserializeJSON(e.detail ?: "{}"); } catch (any x) {}
        switch (e.type) {
            case "chat_question":   return "asked: <i>" & encodeForHTML(left(d.text ?: "", 300)) & "</i>";
            case "chat_answer":     return "got an answer (" & (d.ragHits ?: 0) & " sources, " & (d.tokens ?: 0) & " tokens" & (val(e.duration_ms) ? ", " & numberFormat(e.duration_ms / 1000, "0.0") & " s" : "") & ")";
            case "ask_question":    return "asked about a feature: <i>" & encodeForHTML(left(d.text ?: "", 300)) & "</i>";
            case "gate_shown":      return "opened locked feature <b>" & encodeForHTML(e.feature_key) & "</b>";
            case "objection_open":  return "read objection <i>" & encodeForHTML(d.q ?: "") & "</i> (" & encodeForHTML(e.feature_key) & ")";
            case "cta_click":       return "clicked <b>" & encodeForHTML(d.cta ?: "") & "</b> on " & encodeForHTML(e.feature_key);
            case "wishlist_add":    return "added <b>" & encodeForHTML(e.feature_key) & "</b> to the pilot wish list";
            case "page_view":       return "opened " & encodeForHTML(e.page);
            case "page_time":       return "spent " & numberFormat(val(e.duration_ms) / 1000, "0") & " s on " & encodeForHTML(e.page);
            case "handoff_requested": return "<b>asked for a person</b>: " & encodeForHTML(left(d.summary ?: "", 300));
            case "talk_request":    return "<b>asked to talk to a person</b> about " & encodeForHTML(e.feature_key);
            case "tamper_blocked":  return "<b style='color:##c0392b'>blocked access attempt</b> (" & encodeForHTML(d.kind ?: "") & ": " & encodeForHTML(d.value ?: "") & ")";
            case "upload":          return "uploaded " & encodeForHTML(d.name ?: "");
            case "ingest_done":     return "document ready: " & encodeForHTML(d.name ?: "");
            case "cap_reached":     return "hit a limit: " & encodeForHTML(d.cap ?: "");
            case "moment_shown":    return "was shown the tip <i>" & encodeForHTML(e.feature_key) & "</i>";
        }
        return encodeForHTML(e.type) & (len(e.feature_key ?: "") ? " · " & encodeForHTML(e.feature_key) : "");
    }
</cfscript>
<cfoutput>
<cfif structKeyExists(url, "created")><div class="note ok">The demo for <b>#encodeForHTML(p.fname)#</b> is ready and the welcome e-mail was sent.</div></cfif>
<cfif len(msg)><div class="note #msgKind#">#encodeForHTML(msg)#</div></cfif>
<cfif len(shownLink)><div class="note"><b>Set-password link:</b><br><span class="mono">#encodeForHTML(shownLink)#</span></div></cfif>

<h1>#encodeForHTML(trim(p.fname & " " & p.lname))# <span class="muted" style="font-weight:400">· #encodeForHTML(p.company)#</span></h1>
<div class="grid">
    <div class="card"><div class="muted small">Status</div>#badge(p.status)#<div class="small muted" style="margin-top:4px">#p.pid# · #encodeForHTML(p.email)#</div></div>
    <div class="card"><div class="muted small">Engagement</div><div class="stat">#p.score#</div>#badge(p.score_band)#</div>
    <div class="card"><div class="muted small">Demo ends</div><b>#dateFormat(p.expires_at, "d mmm yyyy")#</b><div class="small muted">#p.daysLeft# days left</div></div>
    <div class="card"><div class="muted small">Timeline</div><div class="small">created #dateFormat(p.created_at, "d mmm")#<br>first sign-in #isDate(p.first_login_at) ? dateFormat(p.first_login_at, "d mmm") : "not yet"#<br>last seen #ago(p.last_seen_at)#<br>consent #isDate(p.consent_at) ? "given" : "not yet"#</div></div>
</div>

<div class="card">
    <h3 style="margin-top:0">Actions</h3>
    <div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center">
        <form method="post"><input type="hidden" name="action" value="resend"><button class="btn">Resend welcome e-mail</button></form>
        <form method="post"><input type="hidden" name="action" value="link"><button class="btn">Show a set-password link</button></form>
        <form method="post" style="display:flex;gap:6px"><input type="hidden" name="action" value="extend">
            <select name="days" style="width:auto"><option value="7">+7 days</option><option value="14">+14 days</option><option value="30">+30 days</option></select><button class="btn">Extend</button></form>
        <cfif p.status EQ "suspended">
            <form method="post"><input type="hidden" name="action" value="resume"><button class="btn">Resume</button></form>
        <cfelseif listFind("invited,active,expiring", p.status)>
            <form method="post"><input type="hidden" name="action" value="suspend"><button class="btn">Suspend now</button></form>
        </cfif>
        <cfif p.status NEQ "converted" AND p.status NEQ "purged">
            <form method="post" style="display:flex;gap:6px"><input type="hidden" name="action" value="convert">
                <input type="number" name="company_id" placeholder="fleet company id" style="width:150px"><button class="btn">Mark converted</button></form>
        </cfif>
    </div>
    <form method="post" class="grid" style="margin-top:10px;align-items:end"><input type="hidden" name="action" value="settings">
        <div><label>Owner</label><select name="owner_oid"><cfloop array="#demo.operators()#" item="o"><cfif o.role NEQ "system"><option value="#o.oid#" #p.owner_oid EQ o.oid ? "selected" : ""#>#encodeForHTML(o.display_name ?: o.email)#</option></cfif></cfloop></select></div>
        <div><label>Audience</label><select name="audience"><cfloop list="business,it,finance,hr,exec" item="a"><option #p.audience EQ a ? "selected" : ""#>#a#</option></cfloop></select></div>
        <div><label>Limits</label><select name="caps"><option #p.caps_preset EQ "standard" ? "selected" : ""#>standard</option><option #p.caps_preset EQ "generous" ? "selected" : ""#>generous</option></select></div>
        <div style="grid-column:1/-1"><label>Notes</label><textarea name="notes" rows="2">#encodeForHTML(p.notes ?: "")#</textarea></div>
        <div><button class="btn">Save</button></div>
    </form>
    <details style="margin-top:10px"><summary class="muted">Reset or purge</summary>
        <form method="post" style="display:flex;gap:6px;margin-top:8px" onsubmit="return confirm('Rebuild the sandbox? The prospect\'s uploads are deleted.')">
            <input type="hidden" name="action" value="reset"><input type="text" name="confirm" placeholder="type #p.pid#" style="width:160px"><button class="btn">Reset sandbox</button></form>
        <form method="post" style="display:flex;gap:6px;margin-top:8px" onsubmit="return confirm('Delete EVERYTHING of this prospect? This cannot be undone.')">
            <input type="hidden" name="action" value="purge"><input type="text" name="confirm" placeholder="type the prospect's e-mail" style="width:260px"><button class="btn danger">Purge now</button></form>
    </details>
</div>

<h2>Pitch interest</h2>
<cfif gates.recordCount OR wish.recordCount>
<table><tr><th>Feature</th><th>Opened</th><th>Objections read</th><th>Questions asked</th><th>Buttons</th><th>Wish list</th></tr>
<cfset wl = valueList(wish.feature_key)>
<cfloop query="gates"><tr><td><b>#encodeForHTML(gates.feature_key)#</b></td><td>#gates.gates#</td><td>#gates.objections#</td><td>#gates.asks#</td><td>#gates.ctas#</td><td>#listFind(wl, gates.feature_key) ? "★" : ""#</td></tr></cfloop>
</table>
<cfelse><p class="muted">No locked feature opened yet.</p></cfif>

<h2>Timeline</h2>
<div class="tl">
<cfset lastDay = "">
<cfloop query="ev">
    <cfif ev.type EQ "page_view" OR ev.type EQ "page_time"><cfcontinue></cfif>
    <cfset dday = dateFormat(ev.ts, "ddd d mmm")>
    <cfif dday NEQ lastDay><h3>#dday#</h3><cfset lastDay = dday></cfif>
    <div class="ev"><span class="t">#timeFormat(ev.ts, "HH:nn")#</span> #evLine(queryGetRow(ev, ev.currentRow))#</div>
</cfloop>
<cfif NOT ev.recordCount><p class="muted">Nothing yet.</p></cfif>
</div>
<details><summary class="muted">Pages opened (#ev.recordCount# latest events incl. page views)</summary>
<table><cfloop query="ev"><cfif ev.type EQ "page_view" OR ev.type EQ "page_time"><tr><td class="small">#dateTimeFormat(ev.ts, "d mmm HH:nn:ss")#</td><td class="small">#evLine(queryGetRow(ev, ev.currentRow))#</td></tr></cfif></cfloop></table>
</details>

<h2>Documents</h2>
<cfif docs.recordCount>
<table><tr><th>File</th><th>Size</th><th>Uploaded</th><th>State</th></tr>
<cfloop query="docs"><tr><td>#encodeForHTML(docs.orig_name)#</td><td>#numberFormat(docs.size_bytes / 1024, "0")# KB</td><td>#dateTimeFormat(docs.uploaded_at, "d mmm HH:nn")#</td><td>#isDate(docs.deleted_at) ? "deleted" : encodeForHTML(docs.ingest_state)#</td></tr></cfloop></table>
<cfelse><p class="muted">No own documents uploaded.</p></cfif>

<h2>Usage and limits</h2>
<p class="small">Total: #tot.questions# questions · #numberFormat(tot.tokens)# tokens (limit #numberFormat(caps.tokens_total ?: 0)#) · #tot.asks# feature questions · #tot.uploads# uploads.
   Per day: #caps.questions_day ?: "-"# questions, #caps.asks_day ?: "-"# feature questions, #caps.ingests_day ?: "-"# document loads.</p>
<cfif usage.recordCount><table><tr><th>Day</th><th>Questions</th><th>Tokens</th><th>Feature questions</th><th>Uploads</th></tr>
<cfloop query="usage"><tr><td>#dateFormat(usage.day, "d mmm")#</td><td>#usage.questions#</td><td>#numberFormat(usage.tokens)#</td><td>#usage.asks#</td><td>#usage.uploads#</td></tr></cfloop></table></cfif>

<h2>E-mails</h2>
<cfif mails.recordCount><table><tr><th>When</th><th>Template</th><th>To</th><th>Status</th></tr>
<cfloop query="mails"><tr><td>#dateTimeFormat(mails.sent_at, "d mmm HH:nn")#</td><td>#mails.template#</td><td>#encodeForHTML(mails.to_email)#</td><td>#badge(mails.status EQ "sent" ? "ok" : "failed")# <span class="small muted">#encodeForHTML(mails.error ?: "")#</span></td></tr></cfloop></table>
<cfelse><p class="muted">None.</p></cfif>

<h2>Sandbox log</h2>
<table><tr><th>Op</th><th>Step</th><th>Status</th><th>Time</th><th>Detail</th></tr>
<cfloop array="#jr#" item="j"><tr><td>#j.op#</td><td class="mono">#j.step#</td><td>#badge(j.status)#</td><td class="small">#val(j.ms) ? numberFormat(j.ms, "0") & " ms" : ""#</td><td class="small">#encodeForHTML(j.detail ?: "")#</td></tr></cfloop>
</table>
</div>
</cfoutput>
