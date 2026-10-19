<cfset activeTab = "operators">
<cfinclude template="_ui.cfm">
<cfset msg = ""><cfset msgKind = "ok">
<cfif cgi.request_method EQ "POST">
    <cftry>
        <cfif op.role NEQ "admin"><cfthrow message="Only an operator with role admin can change operators."></cfif>
        <cfif (form.action ?: "") EQ "add">
            <cfset em = lCase(trim(form.email ?: ""))>
            <cfset u = queryExecute("SELECT oid, fname, lname, email, account_type FROM ai_orbitix_users WHERE email = :e AND active = 1", {e: em}, {datasource: "ai_data"})>
            <cfif NOT u.recordCount><cfthrow message="No active account #em# on this server. Create the account first (Manage › Users)."></cfif>
            <cfif u.account_type EQ "demo_user"><cfthrow message="A prospect account cannot be an operator."></cfif>
            <cfif NOT listFind("admin,sales,se", form.role ?: "")><cfthrow message="Choose a role."></cfif>
            <cfset queryExecute("INSERT INTO cx_demo_operators (oid, role, display_name, email, active) VALUES (:o, :r, :n, :e, 1)
                                 ON DUPLICATE KEY UPDATE role = VALUES(role), display_name = VALUES(display_name), email = VALUES(email), active = 1",
                {o: u.oid, r: form.role, n: left(len(trim(form.name ?: "")) ? trim(form.name) : trim(u.fname & " " & u.lname), 120), e: u.email}, {datasource: "addon_demo"})>
            <cfset msg = "#u.email# is an operator (#form.role#).">
        <cfelseif (form.action ?: "") EQ "toggle">
            <cfif val(form.oid) EQ op.oid><cfthrow message="You cannot switch yourself off."></cfif>
            <cfset queryExecute("UPDATE cx_demo_operators SET active = 1 - active WHERE oid = :o AND role <> 'system'", {o: val(form.oid)}, {datasource: "addon_demo"})>
            <cfset msg = "Changed.">
        </cfif>
        <cfcatch><cfset msg = cfcatch.message><cfset msgKind = "err"></cfcatch>
    </cftry>
</cfif>
<cfoutput>
<h1>Operators</h1>
<cfif len(msg)><div class="note #msgKind#">#encodeForHTML(msg)#</div></cfif>
<p class="muted">Trilivy staff who may use the Demo Console. <b>admin</b>: everything; <b>se</b>: may verify and publish pitch cards; <b>sales</b>: prospects only.
   The <b>system</b> account runs the timers (expiry e-mails, purge, digest).</p>
<table><tr><th>Name</th><th>E-mail</th><th>Role</th><th>Active</th><th></th></tr>
<cfloop array="#demo.operators()#" item="o">
    <tr><td>#encodeForHTML(o.display_name ?: "")#</td><td>#encodeForHTML(o.email ?: "")#</td><td>#o.role#</td><td>#o.active ? "yes" : "no"#</td>
        <td><cfif o.role NEQ "system" AND op.role EQ "admin"><form method="post"><input type="hidden" name="action" value="toggle"><input type="hidden" name="oid" value="#o.oid#"><button class="btn">#o.active ? "Switch off" : "Switch on"#</button></form></cfif></td></tr>
</cfloop></table>
<cfif op.role EQ "admin">
<form method="post" class="card" style="max-width:640px"><input type="hidden" name="action" value="add">
    <h3 style="margin-top:0">Add an operator</h3>
    <div class="grid"><div><label>E-mail of an existing account</label><input type="email" name="email" required></div>
        <div><label>Name shown to prospects</label><input type="text" name="name" placeholder="e.g. Anna from Trilivy"></div>
        <div><label>Role</label><select name="role"><option>sales</option><option>se</option><option>admin</option></select></div></div>
    <button class="btn primary" style="margin-top:10px">Add</button>
</form>
</cfif>
</div>
</cfoutput>
