<!--- test_switch - TESTING ONLY (2026-10-20, the user): one click from a TEST
      prospect's demo home to the Demo Console as the box's demo admin, and back.
      Off unless the setting test_switch_pids lists the prospect (empty in the
      package: no real box shows it). test_switch_oid = the admin account to
      become (empty = the first active admin operator). POST only, with a
      session token; every switch is logged on the prospect's timeline. --->
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset pids = listToArray(replace(demo.setting("test_switch_pids", ""), " ", "", "all"))>
<cfif cgi.request_method NEQ "POST" OR NOT arrayLen(pids)>
    <cflocation url="/ain5py/addon.cfm?a=demo&p=welcome" addtoken="false">
</cfif>
<cfif NOT len(session.demo_testtok ?: "") OR (form.t ?: "") NEQ session.demo_testtok>
    <cfheader statuscode="403"><cfoutput>Expired. Go back and try again.</cfoutput><cfabort>
</cfif>

<cfif (form.go ?: "") EQ "admin">
    <!--- a listed test prospect becomes the demo admin --->
    <cfset d = demo.sessionDemo()>
    <cfif structIsEmpty(d) OR (d.missing ?: true) OR NOT arrayFind(pids, d.pid)>
        <cfheader statuscode="403"><cfoutput>Not available.</cfoutput><cfabort>
    </cfif>
    <cfset oid = val(demo.setting("test_switch_oid", ""))>
    <cfif NOT oid>
        <cfset oid = val(queryExecute("SELECT oid FROM cx_demo_operators WHERE role = 'admin' AND active = 1 ORDER BY oid LIMIT 1", {}, {datasource: "addon_demo"}).oid)>
    </cfif>
    <cfset u = queryExecute("SELECT * FROM ai_orbitix_users WHERE oid = :o AND active = 1 AND account_type <> 'demo_user'",
        {o: {value: oid, cfsqltype: "cf_sql_integer"}}, {datasource: "ai_data"})>
    <cfif NOT u.recordCount><cfheader statuscode="409"><cfoutput>No admin account to switch to (setting test_switch_oid).</cfoutput><cfabort></cfif>
    <cfset back = d.pid>
    <cfset demo.logEvent(back, "test_switch", {detail: {to: "admin", oid: oid}})>
    <cfset structClear(session)>
    <cfset application.auth.populateSession(queryGetRow(u, 1))>
    <cfset session.demo_test_back = back>
    <cflocation url="/ain5py/addon.cfm?a=demo&p=console" addtoken="false">
</cfif>

<cfif (form.go ?: "") EQ "back" AND len(session.demo_test_back ?: "")>
    <!--- the admin goes back to the test prospect it came from --->
    <cfset back = session.demo_test_back>
    <cfset p = demo.prospectBy("pid", back)>
    <cfif structIsEmpty(p) OR NOT arrayFind(pids, back) OR NOT val(p.oid ?: 0)>
        <cfheader statuscode="409"><cfoutput>That test prospect is not available any more.</cfoutput><cfabort>
    </cfif>
    <cfset u = queryExecute("SELECT * FROM ai_orbitix_users WHERE oid = :o", {o: {value: p.oid, cfsqltype: "cf_sql_integer"}}, {datasource: "ai_data"})>
    <cfset structClear(session)>
    <cfset application.auth.populateSession(queryGetRow(u, 1))>
    <cfset demo.logEvent(back, "test_switch", {detail: {to: "prospect"}})>
    <cflocation url="/ain5py/addon.cfm?a=demo&p=welcome" addtoken="false">
</cfif>
<cflocation url="/ain5py/addon.cfm?a=demo&p=welcome" addtoken="false">
