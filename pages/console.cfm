<cfset activeTab = "console">
<cfinclude template="_ui.cfm">
<cfparam name="url.status" default="current">
<cfparam name="url.owner" default="">
<cfparam name="url.q" default="">
<cfset where = "1=1">
<cfset prm = {}>
<cfif url.status EQ "current">
    <cfset where &= " AND p.status IN ('building','invited','active','expiring','suspended','failed')">
<cfelseif url.status EQ "hot">
    <cfset where &= " AND p.score_band = 'hot' AND p.status IN ('invited','active','expiring')">
<cfelseif listFind("invited,active,expiring,expired,suspended,purged,converted,failed", url.status)>
    <cfset where &= " AND p.status = :st"><cfset prm.st = url.status>
</cfif>
<cfif isNumeric(url.owner) AND url.owner GT 0>
    <cfset where &= " AND p.owner_oid = :ow"><cfset prm.ow = url.owner>
</cfif>
<cfif len(trim(url.q))>
    <cfset where &= " AND (p.email LIKE :q OR p.company LIKE :q OR p.fname LIKE :q OR p.lname LIKE :q OR p.pid = :qq)">
    <cfset prm.q = "%" & trim(url.q) & "%"><cfset prm.qq = trim(url.q)>
</cfif>
<cfset rows = queryExecute("
    SELECT p.*, o.display_name AS owner_name,
           (SELECT COUNT(*) FROM cx_demo_events e WHERE e.pid = p.pid AND e.type = 'chat_question') AS questions,
           (SELECT COUNT(*) FROM cx_demo_events e WHERE e.pid = p.pid AND e.type = 'gate_shown') AS gates,
           (SELECT COUNT(*) FROM cx_demo_wishlist w WHERE w.pid = p.pid) AS wishes
    FROM cx_demo_prospects p LEFT JOIN cx_demo_operators o ON o.oid = p.owner_oid
    WHERE #where# ORDER BY FIELD(p.score_band,'hot','warm','cold'), p.last_seen_at DESC, p.seq DESC LIMIT 300", prm, {datasource: "addon_demo"})>
<cfset stats = queryExecute("SELECT status, COUNT(*) AS n FROM cx_demo_prospects GROUP BY status", {}, {datasource: "addon_demo"})>
<cfset st = {}><cfloop query="stats"><cfset st[stats.status] = stats.n></cfloop>
<cfoutput>
<h1>Demo prospects</h1>
<div class="grid" style="margin-bottom:14px">
    <div class="card"><div class="stat">#(st.active ?: 0) + (st.expiring ?: 0)#</div><div class="muted">active</div></div>
    <div class="card"><div class="stat">#st.invited ?: 0#</div><div class="muted">invited, not signed in yet</div></div>
    <div class="card"><div class="stat">#st.expiring ?: 0#</div><div class="muted">ending in the next days</div></div>
    <div class="card"><div class="stat">#(st.expired ?: 0) + (st.purged ?: 0)#</div><div class="muted">ended</div></div>
</div>
<form method="get" action="/ain5py/addon.cfm" class="card" style="display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end">
    <input type="hidden" name="a" value="demo"><input type="hidden" name="p" value="console">
    <div style="flex:1;min-width:180px"><label>Search</label><input type="text" name="q" value="#encodeForHTMLAttribute(url.q)#" placeholder="name, e-mail, company, p0007"></div>
    <div><label>Status</label><select name="status">
        <cfloop list="current,hot,invited,active,expiring,expired,suspended,converted,purged,failed,all" item="s"><option value="#s#" #url.status EQ s ? "selected" : ""#>#s#</option></cfloop>
    </select></div>
    <div><label>Owner</label><select name="owner"><option value="">anyone</option>
        <cfloop array="#demo.operators()#" item="o"><cfif o.role NEQ "system"><option value="#o.oid#" #url.owner EQ o.oid ? "selected" : ""#>#encodeForHTML(o.display_name ?: o.email)#</option></cfif></cfloop>
    </select></div>
    <button class="btn">Filter</button>
    <a class="btn primary" href="/ain5py/addon.cfm?a=demo&p=new">+ New prospect</a>
</form>
<table>
<thead><tr><th>Prospect</th><th>Company</th><th>Status</th><th>Score</th><th>Days left</th><th>Last seen</th><th>Questions</th><th>Locked clicks</th><th>Wish list</th><th>Owner</th></tr></thead>
<tbody>
<cfloop query="rows">
    <cfset daysLeft = isDate(rows.expires_at) ? max(0, ceiling(dateDiff("h", now(), rows.expires_at) / 24)) : "">
    <tr>
        <td><a href="/ain5py/addon.cfm?a=demo&p=prospect&arg=#rows.pid#"><b>#encodeForHTML(trim(rows.fname & " " & rows.lname))#</b></a><br><span class="muted small mono">#rows.pid# · #encodeForHTML(rows.email)#</span></td>
        <td>#encodeForHTML(rows.company)#<br><span class="muted small">#encodeForHTML(rows.audience)##len(rows.industry) ? " · " & encodeForHTML(rows.industry) : ""#</span></td>
        <td>#badge(rows.status)#</td>
        <td>#badge(rows.score_band)# <span class="small">#rows.score#</span></td>
        <td>#listFind("invited,active,expiring", rows.status) ? daysLeft : "-"#</td>
        <td>#ago(rows.last_seen_at)#</td>
        <td>#rows.questions#</td><td>#rows.gates#</td><td>#rows.wishes#</td>
        <td class="small">#encodeForHTML(rows.owner_name)#</td>
    </tr>
</cfloop>
<cfif NOT rows.recordCount><tr><td colspan="10" class="muted">No prospects here yet. Create one with <b>+ New prospect</b>.</td></tr></cfif>
</tbody></table>
</div>
</cfoutput>
