<cfinclude template="_brand.cfm">
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset d = demo.sessionDemo(true)>
<cfset p = (structIsEmpty(d) OR (d.missing ?: true)) ? {} : demo.prospectBy("pid", d.pid)>
<cfset v = structIsEmpty(p) ? {owner_email: "", owner_name: "The Trilivy team"} : demo.mailVars(p)>
<cfset paused = NOT structIsEmpty(p) AND p.status EQ "suspended">
<cfoutput>
<div style="font:15px/1.6 var(--fs);color:##1b2333;max-width:600px;margin:50px auto;padding:26px 28px;border:1px solid ##e3e7ef;border-radius:14px;background:##fff;text-align:center">
    <h1 style="font-size:24px;margin:0 0 10px">#paused ? "Your demo is paused" : "Your demo has ended"#</h1>
    <p>#paused ? "Our team has paused this demo for the moment." : "Thank you for trying Trilivy."#
       To continue#paused ? "" : ", extend the demo or talk about a pilot on your own data"#, contact
       #len(v.owner_email) ? '<a href="mailto:' & encodeForHTMLAttribute(v.owner_email) & '">' & encodeForHTML(v.owner_name) & '</a>' : "the Trilivy team"#.</p>
    <p><a href="/ain5py/login/logout.cfm" style="display:inline-block;margin-top:8px;padding:9px 20px;border-radius:999px;border:1px solid ##c9d2e3;color:##1b2333;text-decoration:none">Sign out</a></p>
</div>
</cfoutput>
