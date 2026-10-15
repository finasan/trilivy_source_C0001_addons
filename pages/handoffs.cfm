<cfset activeTab = "handoffs">
<cfinclude template="_ui.cfm">
<!--- Requests for a person, from every sandbox: the popup's "Talk to a person"
      (talk_request events) and the assistant's own handoff tickets (each
      sandbox's ai_handoff_requests, answered in the platform's handoff inbox). --->
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
<h1>Talk to a person</h1>
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
