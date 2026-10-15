<cfset activeTab = "package">
<cfinclude template="_ui.cfm">
<!--- Package & settings: what is installed, whether the box still matches it
      (drift), what changed here since the last export, Export to package, and
      the settings. "No hand edits on the demo box": anything changed here must
      be exported (and committed by the fleet: trlv_addon.py seed-pull) or a
      rebuild loses it. --->
<cfset root = expandPath("/trlvaddons/demo")>
<cfset exportRoot = "/var/lib/trilivy/addon-exports/demo">
<cfset msg = ""><cfset msgKind = "ok">
<cfset meta = deserializeJSON(fileRead(root & "/addon.json"))>
<cfset manifest = fileExists(root & "/MANIFEST.json") ? deserializeJSON(fileRead(root & "/MANIFEST.json")) : {files: {}}>

<cfscript>
    function exportData() {
        var out = {};
        var f = queryExecute("SELECT feature_key, title, mode, path_patterns, nav_group, nav_label, sort FROM cx_demo_features ORDER BY sort, feature_key", {}, {datasource: "addon_demo"});
        var feats = [];
        for (var r in f) {
            var row = {feature_key: r.feature_key, title: r.title, mode: r.mode, sort: r.sort, path_patterns: deserializeJSON(r.path_patterns)};
            if (len(r.nav_group ?: "")) row.nav_group = r.nav_group;
            if (len(r.nav_label ?: "")) row.nav_label = r.nav_label;
            arrayAppend(feats, row);
        }
        out.features = {"_comment": "Exported from the Demo Console #dateTimeFormat(now(), 'yyyy-mm-dd HH:nn')#", features: feats};
        var c = queryExecute("SELECT * FROM cx_demo_pitch WHERE status <> 'retired' ORDER BY feature_key, audience, lang", {}, {datasource: "addon_demo"});
        var cards = [];
        for (var r2 in c) {
            arrayAppend(cards, {feature_key: r2.feature_key, audience: r2.audience, lang: r2.lang, status: r2.status, kicker: r2.kicker ?: "",
                headline: r2.headline, why_html: r2.why_html ?: "", how_html: r2.how_html ?: "", objections: deserializeJSON(r2.objections ?: "[]"),
                proof_html: r2.proof_html ?: "", cta: deserializeJSON(r2.cta ?: "[]"), verified_by: r2.verified_by ?: ""});
        }
        var m = queryExecute("SELECT * FROM cx_demo_moments ORDER BY moment_key", {}, {datasource: "addon_demo"});
        var moms = [];
        for (var r3 in m) arrayAppend(moms, {moment_key: r3.moment_key, title: r3.title, feature_key: r3.feature_key,
            trigger_json: deserializeJSON(r3.trigger_json), once_per_prospect: r3.once_per_prospect, active: r3.active});
        out.pitch = {"_comment": "Exported from the Demo Console", cards: cards, moments: moms};
        var s = queryExecute("SELECT k, v FROM cx_demo_settings WHERE k NOT LIKE 'state\_%' ORDER BY k", {}, {datasource: "addon_demo"});
        var st = {};
        for (var r4 in s) st[r4.k] = r4.v;
        out.settings = {"_comment": "Exported from the Demo Console", settings: st};
        var o = queryExecute("SELECT email, role, display_name FROM cx_demo_operators WHERE role <> 'system' AND active = 1 ORDER BY email", {}, {datasource: "addon_demo"});
        var ops = [];
        for (var r5 in o) arrayAppend(ops, {email: r5.email, role: r5.role, display_name: r5.display_name ?: ""});
        out.operators = {"_comment": "Accounts must exist on the box; bootstrap links them by e-mail.", operators: ops};
        return out;
    }
</cfscript>

<cfif cgi.request_method EQ "POST">
    <cftry>
        <cfif op.role NEQ "admin"><cfthrow message="Only an operator with role admin can change settings or export."></cfif>
        <cfswitch expression="#form.action ?: ''#">
            <cfcase value="export">
                <cfset stamp = dateTimeFormat(now(), "yyyymmdd-HHnnss")>
                <cfset dir = exportRoot & "/" & stamp>
                <cfdirectory action="create" directory="#dir#" recurse="true">
                <cfset data = exportData()>
                <cfloop list="features,pitch,settings,operators" item="k">
                    <cffile action="write" file="#dir#/#k#.json" output="#demo.toJson(data[k])#" charset="utf-8">
                </cfloop>
                <cffile action="write" file="#dir#/EXPORT.json" output="#demo.toJson({addon: 'demo', from_version: meta.version, at: dateTimeFormat(now(), 'yyyy-mm-dd HH:nn:ss'), by: op.email ?: op.oid, host: cgi.server_name})#">
                <cfset demo.setSetting("state_last_export", dateTimeFormat(now(), "yyyy-mm-dd HH:nn:ss"), op.email ?: "")>
                <cfset msg = "Exported to #dir#. On the fleet box run: trlv_addon.py seed-pull demo #lCase(application.env.OBTX_COMPANY_CODE ?: '')# - it commits this export to the add-on source, and the next package carries it.">
            </cfcase>
            <cfcase value="settings">
                <cfset current = demo.settingsAll(true)>
                <cfset changed = 0>
                <cfloop collection="#form#" item="fk">
                    <cfif left(fk, 4) EQ "SET_">
                        <cfset key = lCase(mid(fk, 5, 80))>
                        <!--- textareas post CRLF: compare and store with LF --->
                        <cfset val_ = replace(form[fk], chr(13) & chr(10), chr(10), "all")>
                        <cfif reFind("^[a-z0-9_]{1,80}$", key) AND left(key, 6) NEQ "state_"
                              AND compare(val_, current[key] ?: "") NEQ 0>
                            <cfset demo.setSetting(key, val_, op.email ?: "")>
                            <cfset changed++>
                        </cfif>
                    </cfif>
                </cfloop>
                <cfset msg = changed ? "#changed# setting(s) saved." : "Nothing changed.">
                <cfset structDelete(application, "demo_features")>
            </cfcase>
            <cfcase value="pause,resume">
                <cfset demo.setSetting("demo_paused", form.action EQ "pause" ? "1" : "0", op.email ?: "")>
                <cfset msg = form.action EQ "pause" ? "The demo is paused for prospects." : "The demo is open again.">
            </cfcase>
        </cfswitch>
        <cfcatch><cfset msg = cfcatch.message><cfset msgKind = "err"></cfcatch>
    </cftry>
</cfif>

<!--- drift: every installed file against the package manifest --->
<cfset drift = []>
<cfloop collection="#manifest.files#" item="rel">
    <cfset fp = root & "/" & rel>
    <cfif NOT fileExists(fp)><cfset arrayAppend(drift, "missing: " & rel)>
    <cfelseif lCase(hash(fileReadBinary(fp), "SHA-256")) NEQ manifest.files[rel]><cfset arrayAppend(drift, "changed: " & rel)></cfif>
</cfloop>
<cfdirectory action="list" directory="#root#" recurse="true" type="file" name="allFiles">
<cfloop query="allFiles">
    <cfset rel = replace(replace(allFiles.directory & "/" & allFiles.name, root & "/", ""), "\", "/", "all")>
    <cfif rel NEQ "MANIFEST.json" AND NOT structKeyExists(manifest.files, rel)><cfset arrayAppend(drift, "added: " & rel)></cfif>
</cfloop>
<!--- unexported: rows changed by people since the last export --->
<cfset lastExport = demo.setting("state_last_export", "1970-01-01 00:00:00")>
<cfset unexp = queryExecute("
    SELECT 'pitch card' AS what, CONCAT(feature_key,'/',audience,'/',lang) AS name, updated_at FROM cx_demo_pitch WHERE COALESCE(updated_by,'') NOT IN ('seed','') AND updated_at > :t
    UNION ALL SELECT 'setting', k, updated_at FROM cx_demo_settings WHERE COALESCE(updated_by,'') NOT IN ('seed','') AND k NOT LIKE 'state\_%' AND updated_at > :t
    UNION ALL SELECT 'operator', email, created_at FROM cx_demo_operators WHERE role <> 'system' AND created_at > :t
    ORDER BY 3 DESC", {t: {value: lastExport, cfsqltype: "cf_sql_timestamp"}}, {datasource: "addon_demo"})>
<cfset settings = queryExecute("SELECT k, v, updated_at, updated_by FROM cx_demo_settings WHERE k NOT LIKE 'state\_%' ORDER BY k", {}, {datasource: "addon_demo"})>

<cfoutput>
<h1>Package &amp; settings</h1>
<cfif len(msg)><div class="note #msgKind#">#encodeForHTML(msg)#</div></cfif>
<div class="grid">
    <div class="card"><div class="muted small">Installed add-on</div><b class="mono">demo #encodeForHTML(meta.version)#</b>
        <div class="small muted">git #encodeForHTML(left(manifest.git_sha ?: "", 10))# · built #encodeForHTML(manifest.built_at ?: "")#</div></div>
    <div class="card"><div class="muted small">Files vs package</div>
        <cfif arrayLen(drift)>#badge("failed")# #arrayLen(drift)# difference(s)<cfelse>#badge("ok")# identical</cfif></div>
    <div class="card"><div class="muted small">Changed here since last export</div>
        <cfif unexp.recordCount>#badge("draft")# #unexp.recordCount# change(s)<cfelse>#badge("ok")# nothing</cfif>
        <div class="small muted">last export #encodeForHTML(lastExport EQ "1970-01-01 00:00:00" ? "never" : lastExport)#</div></div>
    <div class="card"><div class="muted small">Demo for prospects</div>
        <form method="post"><cfif demo.paused()>#badge("suspended")# <input type="hidden" name="action" value="resume"><button class="btn">Open again</button>
            <cfelse>#badge("active")# <input type="hidden" name="action" value="pause"><button class="btn danger">Pause for everyone</button></cfif></form></div>
</div>
<cfif arrayLen(drift)><div class="note err"><b>Files differ from the installed package.</b> Someone edited the add-on on the box; a rebuild will undo it. Put the change in the source and ship a new version.
    <pre>#encodeForHTML(arrayToList(drift, chr(10)))#</pre></div></cfif>
<div class="card">
    <h3 style="margin-top:0">Export to package</h3>
    <p class="small">Pitch cards, feature map, settings and operators changed in this console exist only on this box until they are exported and committed.
       Export writes them to <span class="mono">#exportRoot#/&lt;time&gt;/</span>; then the fleet's <span class="mono">trlv_addon.py seed-pull demo #lCase(application.env.OBTX_COMPANY_CODE ?: "")#</span> commits them to the add-on source on c0001.</p>
    <cfif unexp.recordCount><table><tr><th>What</th><th>Name</th><th>Changed</th></tr><cfloop query="unexp"><tr><td>#unexp.what#</td><td class="mono">#encodeForHTML(unexp.name)#</td><td class="small">#dateTimeFormat(unexp.updated_at, "d mmm HH:nn")#</td></tr></cfloop></table></cfif>
    <form method="post"><input type="hidden" name="action" value="export"><button class="btn primary">Export to package</button></form>
</div>
<h2>Settings</h2>
<form method="post" class="card"><input type="hidden" name="action" value="settings">
<table><tr><th style="width:220px">Key</th><th>Value</th><th style="width:160px">Changed</th></tr>
<cfloop query="settings">
    <tr><td class="mono">#settings.k#</td>
        <td><cfif len(settings.v) GT 80 OR find(chr(10), settings.v)><textarea name="SET_#settings.k#" rows="4">#encodeForHTML(settings.v)#</textarea>
            <cfelse><input type="text" name="SET_#settings.k#" value="#encodeForHTMLAttribute(settings.v)#"></cfif></td>
        <td class="small muted">#dateFormat(settings.updated_at, "d mmm")# #encodeForHTML(settings.updated_by ?: "")#</td></tr>
</cfloop></table>
<button class="btn primary">Save settings</button>
</form>
</div>
</cfoutput>
