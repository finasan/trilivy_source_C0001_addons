<cfset activeTab = "handoffs">
<cfinclude template="_ui.cfm">
<!--- Requests for a person, from every sandbox: the popup's "Talk to a person"
      (talk_request events) and the assistant's own handoff tickets (each
      sandbox's ai_handoff_requests, answered in the platform's handoff inbox). --->
<!--- Contact us settings: who receives the e-mails, and the prospect's confirmation --->
<cfset cfgMsg = ""><cfset cfgKind = "ok">
<cfif cgi.request_method EQ "POST" AND (form.action ?: "") EQ "contactcfg">
    <cftry>
        <cfif NOT listFind("admin,se", op.role)><cfthrow message="Only operators with role admin or se can change who receives Contact us e-mails."></cfif>
        <cfset ex = []>
        <cfloop list="#form.extra_to ?: ''#" item="a" delimiters=",; #chr(10)##chr(13)#">
            <cfif NOT isValid("email", trim(a))><cfthrow message="Not an e-mail address: #trim(a)#"></cfif>
            <cfset arrayAppend(ex, lCase(trim(a)))>
        </cfloop>
        <cfset demo.setSetting("contact_extra_to", arrayToList(ex, ","), op.email ?: "")>
        <cfset demo.setSetting("mail_contact_confirm", (form.confirm ?: "") EQ "1" ? "1" : "0", op.email ?: "")>
        <cfloop list="#form.pids ?: ''#" item="pp">
            <cfif reFind("^p[0-9]{4}$", pp) AND structKeyExists(form, "to_" & pp) AND trim(form["to_" & pp]) NEQ demo.contactEmailTo(pp)>
                <cfset demo.setContactEmailTo(pp, form["to_" & pp])>
                <cfset demo.logEvent(pp, "contact_to_changed", {detail: {to: left(form["to_" & pp], 500), by: op.oid}})>
            </cfif>
        </cfloop>
        <cfset cfgMsg = "Saved.">
        <cfcatch><cfset cfgMsg = cfcatch.message><cfset cfgKind = "err"></cfcatch>
    </cftry>
</cfif>
<cfset cfgProspects = queryExecute("SELECT pid, fname, lname, company, email FROM cx_demo_prospects WHERE status IN ('invited','active','expiring','converted','suspended') ORDER BY seq DESC", {}, {datasource: "addon_demo"})>
<cfoutput>
<h1>Contact requests</h1>
<form method="post" class="card"><input type="hidden" name="action" value="contactcfg">
    <h2 style="margin-top:0">Contact us settings</h2>
    <cfif len(cfgMsg)><div class="note #cfgKind#">#encodeForHTML(cfgMsg)#</div></cfif>
    <label>Every prospect's Contact us messages also go to (comma-separated)</label>
    <input type="text" name="extra_to" value="#encodeForHTMLAttribute(demo.setting('contact_extra_to', ''))#" placeholder="sales@yourcompany.com, presales@yourcompany.com">
    <label style="font-weight:400;margin-top:10px"><input type="checkbox" name="confirm" value="1" #demo.setting('mail_contact_confirm', '1') EQ '1' ? 'checked' : ''#>
        Send the prospect a confirmation e-mail with the request number and a private link to follow it</label>
    <h3>Per prospect (starts as the sales owner)</h3>
    <table><tr><th>Prospect</th><th>Their Contact us messages go to</th></tr>
    <cfset pl = []>
    <cfloop query="cfgProspects">
        <cfset arrayAppend(pl, cfgProspects.pid)>
        <tr><td><b>#encodeForHTML(trim(cfgProspects.fname & " " & cfgProspects.lname))#</b> <span class="mono small">#cfgProspects.pid#</span><br><span class="small muted">#encodeForHTML(cfgProspects.company)#</span></td>
            <td><input type="text" name="to_#cfgProspects.pid#" value="#encodeForHTMLAttribute(demo.contactEmailTo(cfgProspects.pid))#" placeholder="nobody (only the addresses above)"></td></tr>
    </cfloop>
    </table>
    <input type="hidden" name="pids" value="#arrayToList(pl)#">
    <button class="btn primary">Save</button>
</form>
</cfoutput>
<cfset talks = queryExecute("
    SELECT e.ts, e.pid, e.feature_key, e.detail, p.fname, p.lname, p.company, p.email, p.status
    FROM cx_demo_events e JOIN cx_demo_prospects p ON p.pid = e.pid
    WHERE e.type IN ('talk_request','handoff_requested') AND e.ts > NOW() - INTERVAL 30 DAY
    ORDER BY e.ts DESC LIMIT 200", {}, {datasource: "addon_demo"})>
<cfset sb = new trlvaddons.demo.lib.Sandbox()>
<cfset live = queryExecute("SELECT pid, fname, lname, company FROM cx_demo_prospects WHERE status IN ('invited','active','expiring','converted','suspended')", {}, {datasource: "addon_demo"})>
<cfset tickets = []>
<cfloop query="live">
    <cfset n = demo.names(live.pid)>
    <cftry>
        <cfset q = queryExecute("SELECT id, status, contact_name, contact_email, summary, created_at FROM `#n.db#`.ai_handoff_requests ORDER BY id DESC LIMIT 20", {}, {datasource: sb.adminDS()})>
        <cfloop query="q">
            <cfset arrayAppend(tickets, {pid: live.pid, who: trim(live.fname & " " & live.lname), company: live.company, db: n.db,
                id: q.id, status: q.status, summary: q.summary, at: q.created_at})>
        </cfloop>
        <cfcatch></cfcatch>
    </cftry>
</cfloop>
<cfoutput>
<h2>From the demo popups and the assistant (last 30 days)</h2>
<table><tr><th>When</th><th>Prospect</th><th>About</th><th>Message</th><th></th></tr>
<cfloop query="talks">
    <cfset dt = {}><cftry><cfset dt = deserializeJSON(talks.detail)><cfcatch></cfcatch></cftry>
    <tr><td class="small">#dateTimeFormat(talks.ts, "d mmm HH:nn")#</td>
        <td><a href="/ain5py/addon.cfm?a=demo&p=prospect&arg=#talks.pid#">#encodeForHTML(trim(talks.fname & " " & talks.lname))#</a><br><span class="small muted">#encodeForHTML(talks.company)#</span></td>
        <td>#encodeForHTML(talks.feature_key ?: "")#</td>
        <td class="small">#encodeForHTML(left(dt.message ?: dt.summary ?: "", 400))#</td>
        <td><a class="btn" href="mailto:#encodeForHTMLAttribute(talks.email)#">E-mail</a></td></tr>
</cfloop>
<cfif NOT talks.recordCount><tr><td colspan="5" class="muted">None.</td></tr></cfif>
</table>
<h2>Tickets inside the prospects' assistants</h2>
<p class="muted small">Answer them in the platform's handoff inbox of that sandbox (the replies reach the prospect's chat).</p>
<table><tr><th>When</th><th>Prospect</th><th>Ticket</th><th>Status</th><th>Summary</th><th></th></tr>
<cfloop array="#tickets#" item="t">
    <tr><td class="small">#dateTimeFormat(t.at, "d mmm HH:nn")#</td><td>#encodeForHTML(t.who)#<br><span class="small muted">#encodeForHTML(t.company)#</span></td>
        <td class="mono">###t.id#</td><td>#badge(t.status)#</td><td class="small">#encodeForHTML(left(t.summary ?: "", 300))#</td>
        <td><a class="btn" href="/ain5py/botinstances/handoff_inbox.cfm?wsDsn=#urlEncodedFormat(t.db)#" target="_blank">Open inbox</a></td></tr>
</cfloop>
<cfif NOT arrayLen(tickets)><tr><td colspan="6" class="muted">None.</td></tr></cfif>
</table>
</div>
</cfoutput>
