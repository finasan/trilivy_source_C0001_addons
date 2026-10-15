<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset d = demo.sessionDemo(true)>
<cfif structIsEmpty(d) OR (d.missing ?: true)><cflocation url="/ain5py/index.cfm" addtoken="false"></cfif>
<cfif cgi.request_method EQ "POST">
    <cfif (form.answer ?: "") EQ "agree">
        <cfset queryExecute("UPDATE cx_demo_prospects SET consent_at = NOW(), consent_version = :v WHERE pid = :p",
            {v: demo.setting("consent_version", "1"), p: d.pid}, {datasource: "addon_demo"})>
        <cfset demo.logEvent(d.pid, "consent_given", {detail: {version: demo.setting("consent_version", "1")}})>
        <cfset demo.sessionDemo(true)>
        <cflocation url="/ain5py/addon.cfm?a=demo&p=welcome" addtoken="false">
    <cfelse>
        <cfset demo.logEvent(d.pid, "consent_declined")>
        <cfset demo.alert(demo.prospectBy("pid", d.pid), "Consent declined", "The prospect did not accept the demo recording notice and was signed out.")>
        <cflocation url="/ain5py/login/logout.cfm" addtoken="false">
    </cfif>
</cfif>
<cfoutput>
<div style="font:15px/1.6 system-ui,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;color:##1b2333;max-width:640px;margin:40px auto;padding:26px 28px;border:1px solid ##e3e7ef;border-radius:14px;background:##fff">
    <h1 style="font-size:24px;margin:0 0 12px">Before you start#len(d.fname) ? ", " & encodeForHTML(d.fname) : ""#</h1>
    #demo.setting("consent_html", "<p>This demo records your activity so our team can help you.</p>")#
    <form method="post" style="display:flex;gap:10px;flex-wrap:wrap;margin-top:18px">
        <button name="answer" value="agree" style="background:##2457d6;color:##fff;border:0;border-radius:999px;padding:10px 22px;font-weight:700;cursor:pointer">I agree, start the demo</button>
        <button name="answer" value="decline" style="background:##fff;color:##5d6779;border:1px solid ##c9d2e3;border-radius:999px;padding:10px 22px;cursor:pointer">No thanks, sign me out</button>
    </form>
</div>
</cfoutput>
