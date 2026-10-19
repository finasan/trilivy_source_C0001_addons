<!--- beacon - small browser-side events (navigator.sendBeacon from demo.js):
      time on page, welcome tour, nav clicks. Prospects only, at most 60 a minute. --->
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset d = demo.sessionDemo()>
<cfif structIsEmpty(d) OR (d.missing ?: true)><cfset demo.json({ok: false}, 403)></cfif>
<cfset rl = session.demo_beacon ?: {at: now(), n: 0}>
<cfif dateDiff("s", rl.at, now()) GTE 60><cfset rl = {at: now(), n: 0}></cfif>
<cfset body = "">
<cftry><cfset body = toString(getHttpRequestData().content)><cfcatch></cfcatch></cftry>
<cfset events = []>
<cftry>
    <cfset parsed = deserializeJSON(len(body) ? body : (form.events ?: "[]"))>
    <cfset events = isArray(parsed) ? parsed : [parsed]>
    <cfcatch><cfset demo.json({ok: false, error: "bad body"}, 400)></cfcatch>
</cftry>
<cfset taken = 0>
<cfloop array="#events#" item="e">
    <cfif rl.n GTE 60 OR taken GTE 20 OR NOT isStruct(e)><cfbreak></cfif>
    <cfset t = lCase(e.type ?: "")>
    <cfif NOT listFind("page_time,tour_step,tour_skip,tour_done,nav_click", t)><cfcontinue></cfif>
    <cfset opts = {page: left(reReplace(e.page ?: "", "[^\x20-\x7E]", "", "all"), 255),
                   feature: left(reReplace(lCase(e.feature ?: ""), "[^a-z0-9_]", "", "all"), 60),
                   detail: {step: left(e.step ?: "", 40)}}>
    <cfif isNumeric(e.ms ?: "") AND e.ms GT 0><cfset opts.duration = min(int(e.ms), 86400000)></cfif>
    <cfset demo.logEvent(d.pid, t, opts)>
    <cfset rl.n++><cfset taken++>
</cfloop>
<cfset session.demo_beacon = rl>
<cfset demo.json({ok: true, taken: taken})>
