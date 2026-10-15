<cfset activeTab = "new">
<cfinclude template="_ui.cfm">
<cfset err = "">
<cfset result = {}>
<cfparam name="form.fname" default="">
<cfparam name="form.lname" default="">
<cfparam name="form.email" default="">
<cfparam name="form.company" default="">
<cfparam name="form.audience" default="business">
<cfparam name="form.industry" default="">
<cfparam name="form.language" default="en">
<cfparam name="form.owner_oid" default="#op.oid#">
<cfparam name="form.days" default="#demo.setting('default_days', '14')#">
<cfparam name="form.caps" default="standard">
<cfparam name="form.notes" default="">
<cfparam name="form.send" default=""><!--- unticked box = not posted at all --->
<cfset doSend = (cgi.request_method EQ "GET") OR (form.send EQ "1")>

<cfif cgi.request_method EQ "POST">
    <cfset em = lCase(trim(form.email))>
    <cfif NOT isValid("email", em)><cfset err = "Enter a valid e-mail address.">
    <cfelseif NOT len(trim(form.fname))><cfset err = "Enter the first name.">
    <cfelseif NOT len(trim(form.company))><cfset err = "Enter the company.">
    <cfelseif NOT listFind("business,it,finance,hr,exec", form.audience)><cfset err = "Choose an audience.">
    <cfelseif NOT isNumeric(form.days) OR form.days LT 1 OR form.days GT 90><cfset err = "Days must be between 1 and 90.">
    <cfelseif NOT listFind("standard,generous", form.caps)><cfset err = "Choose limits.">
    </cfif>
    <cfif NOT len(err)>
        <cfset dup = queryExecute("SELECT pid, status FROM cx_demo_prospects WHERE email = :e AND status NOT IN ('purged','failed')", {e: em}, {datasource: "addon_demo"})>
        <cfif dup.recordCount><cfset err = "#em# already has a demo (#dup.pid#, #dup.status#)."></cfif>
    </cfif>
    <cfif NOT len(err)>
        <cflock name="demo_new_pid" type="exclusive" timeout="30">
            <cfset pid = demo.nextPid()>
            <cfset queryExecute("
                INSERT INTO cx_demo_prospects (pid, email, fname, lname, company, audience, industry, language, owner_oid,
                                               status, expires_at, caps_preset, notes, created_by)
                VALUES (:pid, :e, :f, :l, :c, :a, :i, :lang, :ow, 'building', DATE_ADD(NOW(), INTERVAL :d DAY), :caps, :n, :by)", {
                pid: pid, e: em, f: left(trim(form.fname), 50), l: left(trim(form.lname), 50), c: left(trim(form.company), 100),
                a: form.audience, i: left(trim(form.industry), 80), lang: left(form.language, 2),
                ow: {value: val(form.owner_oid), null: NOT val(form.owner_oid)}, d: {value: int(form.days), cfsqltype: "cf_sql_integer"},
                caps: form.caps, n: trim(form.notes), by: op.oid
            }, {datasource: "addon_demo"})>
        </cflock>
        <cfset sb = new trlvaddons.demo.lib.Sandbox()>
        <cfset result = sb.create(pid, op.oid)>
        <cfset result.mail = {}>
        <cfif result.ok AND doSend>
            <cftry>
                <cfset result.mail = demo.sendWelcome(pid)>
                <cfcatch><cfset result.mail = {ok: false, error: cfcatch.message}></cfcatch>
            </cftry>
        </cfif>
        <cfif result.ok AND (NOT doSend OR (result.mail.ok ?: false))>
            <cflocation url="/ain5py/addon.cfm?a=demo&p=prospect&arg=#pid#&created=1" addtoken="false">
        </cfif>
    </cfif>
</cfif>

<cfoutput>
<h1>New prospect</h1>
<cfif len(err)><div class="note err">#encodeForHTML(err)#</div></cfif>
<cfif NOT structIsEmpty(result)>
    <cfif result.ok>
        <div class="note warn">The sandbox was built, but the welcome e-mail was not sent: #encodeForHTML(result.mail.error ?: "")#.
            Open the <a href="/ain5py/addon.cfm?a=demo&p=prospect&arg=#result.pid#">prospect</a> and use <b>Resend welcome</b> or copy the link.</div>
    <cfelse>
        <div class="note err"><b>The sandbox could not be built, and everything was undone.</b><br>#encodeForHTML(result.error)#</div>
        <table><tr><th>Step</th><th>Status</th><th>Detail</th></tr>
        <cfloop array="#result.steps#" item="s"><tr><td class="mono">#s.step#</td><td>#badge(s.status)#</td><td class="small">#encodeForHTML(s.detail ?: "")#</td></tr></cfloop>
        </table>
    </cfif>
</cfif>
<form method="post" class="card" style="max-width:760px">
    <div class="grid">
        <div><label>First name *</label><input type="text" name="fname" value="#encodeForHTMLAttribute(form.fname)#" required maxlength="50"></div>
        <div><label>Last name</label><input type="text" name="lname" value="#encodeForHTMLAttribute(form.lname)#" maxlength="50"></div>
    </div>
    <div class="grid">
        <div><label>E-mail *</label><input type="email" name="email" value="#encodeForHTMLAttribute(form.email)#" required></div>
        <div><label>Company *</label><input type="text" name="company" value="#encodeForHTMLAttribute(form.company)#" required maxlength="100"></div>
    </div>
    <div class="grid">
        <div><label>Audience (decides the wording of the popups)</label><select name="audience">
            <cfloop list="business,it,finance,hr,exec" item="a"><option value="#a#" #form.audience EQ a ? "selected" : ""#>#a#</option></cfloop></select></div>
        <div><label>Industry</label><input type="text" name="industry" value="#encodeForHTMLAttribute(form.industry)#" maxlength="80" placeholder="e.g. logistics"></div>
        <div><label>Language</label><select name="language"><option value="en">English</option></select></div>
    </div>
    <div class="grid">
        <div><label>Sales owner (gets the alerts)</label><select name="owner_oid">
            <cfloop array="#demo.operators()#" item="o"><cfif o.role NEQ "system" AND o.active><option value="#o.oid#" #form.owner_oid EQ o.oid ? "selected" : ""#>#encodeForHTML(o.display_name ?: o.email)#</option></cfif></cfloop></select></div>
        <div><label>Days</label><input type="number" name="days" value="#encodeForHTMLAttribute(form.days)#" min="1" max="90"></div>
        <div><label>Limits</label><select name="caps"><option value="standard" #form.caps EQ "standard" ? "selected" : ""#>standard</option><option value="generous" #form.caps EQ "generous" ? "selected" : ""#>generous</option></select></div>
    </div>
    <label>Notes (only operators see these)</label><textarea name="notes" rows="2">#encodeForHTML(form.notes)#</textarea>
    <label style="font-weight:400"><input type="checkbox" name="send" value="1" #doSend ? "checked" : ""#> Send the welcome e-mail with a set-password link now</label>
    <p class="muted small">Creating builds a private copy of the demo assistant for this prospect (about 10-30 seconds) and an account that can only see it.</p>
    <button class="btn primary" onclick="this.disabled=true;this.textContent='Building the sandbox…';this.form.submit()">Create the demo</button>
</form>
</div>
</cfoutput>
