<!--- docs_api - the prospect's own documents: upload (into the sandbox folder,
      loaded into the sandbox's knowledge base only), status, delete.
      The knowledge base name is ALWAYS taken from the session, never from the request. --->
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset d = demo.sessionDemo()>
<cfif structIsEmpty(d) OR (d.missing ?: true)><cfset demo.json({ok: false, error: "not a demo account"}, 403)></cfif>
<cfset n = demo.names(d.pid)>
<cfset p = demo.prospectBy("pid", d.pid)>
<cfset caps = demo.caps(p)>
<cfset opn = lCase(url.op ?: form.op ?: "list")>
<cfset upDir = n.dir & "/demo_uploads">
<cfset api = reReplace(application.env.OBTX_FASTAPI_BASE_URL ?: "http://127.0.0.1:5006", "/+$", "")>

<cffunction name="refreshStates" returntype="void">
    <cfset var q = queryExecute("SELECT id, orig_name, ingest_note FROM cx_demo_docs WHERE pid = :p AND deleted_at IS NULL
                                 AND ingest_state IN ('queued','running')", {p: d.pid}, {datasource: "addon_demo"})>
    <cfloop query="q">
        <cfset var logId = val(listLast(q.ingest_note, ":"))>
        <cfif logId LTE 0><cfcontinue></cfif>
        <cfset var s = queryExecute("SELECT status, message, chunks FROM ingest_log WHERE id = :i", {i: logId}, {datasource: "airrag2"})>
        <cfif NOT s.recordCount><cfcontinue></cfif>
        <cfset var st = uCase(s.status ?: "")>
        <cfset var ns = "running">
        <cfif listFind("COMPLETED,COMPLETE,DONE,SUCCESS,SUCCEEDED,OK", st)><cfset ns = "ready">
        <cfelseif listFind("FAILED,ERROR,CANCELLED,CANCELED", st)><cfset ns = "failed">
        <cfelseif st EQ "PAUSED"><cfset ns = "queued"></cfif>
        <cfif ns NEQ "running" AND ns NEQ "queued">
            <cfset queryExecute("UPDATE cx_demo_docs SET ingest_state = :s, ingest_note = :m WHERE id = :i",
                {s: ns, m: left("log:#logId# " & (ns EQ "failed" ? (s.message ?: "") : (s.chunks ?: "") & " passages"), 500), i: q.id}, {datasource: "addon_demo"})>
            <cfif ns EQ "ready">
                <cfset demo.addUsage(d.pid, "ingests", 0)>
                <cfset demo.logEvent(d.pid, "ingest_done", {feature: "my_docs", detail: {name: q.orig_name}})>
            <cfelse>
                <cfset demo.logEvent(d.pid, "ingest_failed", {feature: "my_docs", detail: {name: q.orig_name, message: left(s.message ?: "", 300)}})>
            </cfif>
        </cfif>
    </cfloop>
</cffunction>

<cfswitch expression="#opn#">
<cfcase value="list">
    <cfset refreshStates()>
    <cfset q = queryExecute("SELECT id, orig_name, size_bytes, uploaded_at, ingest_state, ingest_note FROM cx_demo_docs
                             WHERE pid = :p AND deleted_at IS NULL ORDER BY id DESC", {p: d.pid}, {datasource: "addon_demo"})>
    <cfset rows = []>
    <cfloop query="q"><cfset arrayAppend(rows, {id: q.id, name: q.orig_name, kb: int(q.size_bytes / 1024), at: dateTimeFormat(q.uploaded_at, "d mmm HH:nn"), state: q.ingest_state})></cfloop>
    <cfset tot = demo.usageTotal(d.pid)>
    <cfset today = demo.usageToday(d.pid)>
    <cfset demo.json({ok: true, docs: rows, limits: {files_total: caps.files_total ?: 20, file_mb: caps.file_mb ?: 25, total_mb: caps.total_mb ?: 150,
        ingests_day: caps.ingests_day ?: 3, used_files: q.recordCount, used_mb: tot.upload_mb, used_today: today.ingests},
        types: demo.setting("upload_types", "pdf,docx,txt,md,html,htm")})>
</cfcase>

<cfcase value="upload">
    <cfif cgi.request_method NEQ "POST"><cfset demo.json({ok: false, error: "POST"}, 405)></cfif>
    <cfset live = queryExecute("SELECT COUNT(*) AS n FROM cx_demo_docs WHERE pid = :p AND deleted_at IS NULL", {p: d.pid}, {datasource: "addon_demo"})>
    <cfset tot = demo.usageTotal(d.pid)>
    <cfset today = demo.usageToday(d.pid)>
    <cfif live.n GTE val(caps.files_total ?: 20)><cfset demo.logEvent(d.pid, "cap_reached", {detail: {cap: "files_total"}})><cfset demo.json({ok: false, error: "You have reached the number of documents for the demo. Delete one, or talk to us about a pilot."})></cfif>
    <cfif today.ingests GTE val(caps.ingests_day ?: 3)><cfset demo.logEvent(d.pid, "cap_reached", {detail: {cap: "ingests_day"}})><cfset demo.json({ok: false, error: "You can load #caps.ingests_day ?: 3# documents a day in the demo. Try again tomorrow, or talk to us."})></cfif>
    <cfif NOT directoryExists(upDir)><cfdirectory action="create" directory="#upDir#"></cfif>
    <cfset types = demo.setting("upload_types", "pdf,docx,txt,md,html,htm")>
    <cftry>
        <cffile action="upload" filefield="file" destination="#getTempDirectory()#" nameconflict="makeunique" result="up">
        <cfcatch><cfset demo.json({ok: false, error: "No file received."})></cfcatch>
    </cftry>
    <cfset tmp = up.serverDirectory & "/" & up.serverFile>
    <cfset ext = lCase(up.clientFileExt)>
    <cfset sizeMb = up.fileSize / 1048576>
    <cfif NOT listFind(types, ext)>
        <cffile action="delete" file="#tmp#"><cfset demo.json({ok: false, error: "Only #replace(types, ',', ', ', 'all')# files can be loaded in the demo."})>
    </cfif>
    <cfif sizeMb GT val(caps.file_mb ?: 25)>
        <cffile action="delete" file="#tmp#"><cfset demo.json({ok: false, error: "The file is larger than #caps.file_mb ?: 25# MB."})>
    </cfif>
    <cfif tot.upload_mb + sizeMb GT val(caps.total_mb ?: 150)>
        <cffile action="delete" file="#tmp#"><cfset demo.logEvent(d.pid, "cap_reached", {detail: {cap: "total_mb"}})><cfset demo.json({ok: false, error: "That would go over the demo's storage allowance."})>
    </cfif>
    <cfset stored = lCase(hash(createUUID(), "SHA-256")).left(24) & "." & ext>
    <cfset final = upDir & "/" & stored>
    <cffile action="move" source="#tmp#" destination="#final#">
    <cfset origName = left(reReplace(up.clientFile, "[^\w .()+\-]", "_", "all"), 255)>
    <cfset queryExecute("INSERT INTO cx_demo_docs (pid, orig_name, stored_name, size_bytes, ingest_state) VALUES (:p, :o, :s, :b, 'queued')",
        {p: d.pid, o: origName, s: stored, b: up.fileSize}, {datasource: "addon_demo", result: "ins"})>
    <cfset docId = ins.generatedKey>
    <cfset demo.addUsage(d.pid, "uploads", 1)>
    <cfset demo.addUsage(d.pid, "upload_mb", sizeMb)>
    <cfset demo.addUsage(d.pid, "ingests", 1)>
    <cfset demo.logEvent(d.pid, "upload", {feature: "my_docs", detail: {name: origName, kb: int(up.fileSize / 1024)}})>
    <!--- Into the sandbox's own knowledge base only (loopback call, no key needed). --->
    <cftry>
        <cfhttp url="#api#/ingestmt_api/ingest_files" method="POST" timeout="60" result="ir">
            <cfhttpparam type="header" name="Content-Type" value="application/json">
            <cfhttpparam type="body" value="#serializeJSON({'table_name': n.base, 'files': [final], 'async_mode': true,
                'doc_category': 'general', 'confidentiality': 'internal', 'doc_series': left(listFirst(origName, '.'), 200)})#">
        </cfhttp>
        <cfset resp = deserializeJSON(ir.fileContent)>
        <cfset logId = (isStruct(resp) AND structKeyExists(resp, "jobs") AND arrayLen(resp.jobs)) ? val(resp.jobs[1].log_id) : 0>
        <cfif left(ir.statusCode, 1) NEQ "2" OR logId LTE 0><cfthrow message="#left(ir.fileContent, 300)#"></cfif>
        <cfset queryExecute("UPDATE cx_demo_docs SET ingest_state = 'running', ingest_note = :n WHERE id = :i", {n: "log:#logId#", i: docId}, {datasource: "addon_demo"})>
        <cfcatch>
            <cfset queryExecute("UPDATE cx_demo_docs SET ingest_state = 'failed', ingest_note = :n WHERE id = :i", {n: left(cfcatch.message, 500), i: docId}, {datasource: "addon_demo"})>
            <cfset demo.logEvent(d.pid, "ingest_failed", {feature: "my_docs", detail: {name: origName, message: left(cfcatch.message, 300)}})>
            <cfset demo.json({ok: false, error: "The document was saved but could not be loaded. Our team has been told."})>
        </cfcatch>
    </cftry>
    <cfset demo.json({ok: true, id: docId, message: "Uploaded. Loading it into your knowledge base takes a minute or two."})>
</cfcase>

<cfcase value="delete">
    <cfif cgi.request_method NEQ "POST"><cfset demo.json({ok: false, error: "POST"}, 405)></cfif>
    <cfset q = queryExecute("SELECT * FROM cx_demo_docs WHERE id = :i AND pid = :p AND deleted_at IS NULL", {i: val(form.id ?: 0), p: d.pid}, {datasource: "addon_demo"})>
    <cfif NOT q.recordCount><cfset demo.json({ok: false, error: "not found"}, 404)></cfif>
    <cfset logId = val(listLast(listFirst(q.ingest_note, " "), ":"))>
    <cfset removed = 0>
    <cfif logId GT 0>
        <!--- Its passages, from the sandbox's own tables only. --->
        <cfset tabs = queryExecute("SELECT c.table_name FROM information_schema.columns c WHERE c.table_schema = 'public'
                                    AND c.column_name = 'ingest_log_id' AND c.table_name LIKE :l",
            {l: replace(n.base, "_", "\_", "all") & "\_%"}, {datasource: "airrag2"})>
        <cfloop query="tabs">
            <cfset queryExecute("DELETE FROM #tabs.table_name# WHERE ingest_log_id = :i", {i: logId}, {datasource: "airrag2", result: "dr"})>
            <cfset removed += dr.recordCount>
        </cfloop>
        <cftry>
            <cfset queryExecute("DELETE FROM rag_docvault WHERE target_rag_table = :b AND ingest_log_id = :i", {b: n.base, i: logId}, {datasource: "airrag2"})>
            <cfcatch></cfcatch>
        </cftry>
    </cfif>
    <cfif fileExists(upDir & "/" & q.stored_name)><cffile action="delete" file="#upDir#/#q.stored_name#"></cfif>
    <cfset queryExecute("UPDATE cx_demo_docs SET deleted_at = NOW() WHERE id = :i", {i: q.id}, {datasource: "addon_demo"})>
    <cfset demo.logEvent(d.pid, "doc_deleted", {feature: "my_docs", detail: {name: q.orig_name, passages: removed}})>
    <cfset demo.json({ok: true, message: "Deleted, with its #removed# passages."})>
</cfcase>

<cfdefaultcase><cfset demo.json({ok: false, error: "unknown op"}, 400)></cfdefaultcase>
</cfswitch>
