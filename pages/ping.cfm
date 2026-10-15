<cfset _rows = -1>
<cftry>
    <cfquery name="_q" datasource="addon_hello">SELECT COUNT(*) AS n FROM hello_ping</cfquery>
    <cfset _rows = _q.n>
    <cfcatch type="any"><cfset _rows = "error: " & cfcatch.message></cfcatch>
</cftry>
<cfcontent type="application/json; charset=utf-8" reset="true"><cfoutput>#serializeJSON({ ok: true, addon: request.addon.name, page: request.addon.page, arg: request.addon.arg, loaded: application.addons.listLoaded(), db_rows: _rows })#</cfoutput>
