<cfset activeTab = "stories">
<cfinclude template="_ui.cfm">
<!--- Stories (2026-10-19) - the guided flows prospects start from the demo home
      and the DEMO bar (the Quick Start first). A step is a SLIDE (a full page:
      the benefits) or LIVE (the real platform page, with a coach panel: the task,
      Back / Next). A live step's page opens for the prospect while the step is
      running, also in Guided (never a box-wide or server page). --->
<cfset msg = ""><cfset msgKind = "ok">
<cfset canEdit = listFind("admin,se", op.role) GT 0>
<cfset DONE_EVENTS = "chat_question,chat_answer,ingest_done,page_view,gate_shown">
<cfparam name="url.k" default="">
<cfparam name="url.step" default="0">
<cfset k = reReplace(lCase(url.k), "[^a-z0-9_]", "", "all")>

<cfscript>
    function lines(string s) {
        var out = [];
        for (var l in listToArray(replace(arguments.s, chr(13), "", "all"), chr(10))) if (len(trim(l))) arrayAppend(out, trim(l));
        return out;
    }
    function jsonOrNull(any v) { return (isArray(v) && !arrayLen(v)) || (isStruct(v) && structIsEmpty(v)) ? "" : demo.toJson(v); }
    function renumber(string key) {
        var q = queryExecute("SELECT id FROM cx_demo_story_step WHERE story_key = :k ORDER BY step_no, id", {k: arguments.key}, {datasource: "addon_demo"});
        var i = 0;
        // two passes: the (story_key, step_no) key is unique
        for (var r in q) { i++; queryExecute("UPDATE cx_demo_story_step SET step_no = :n WHERE id = :id", {n: 10000 + i, id: r.id}, {datasource: "addon_demo"}); }
        queryExecute("UPDATE cx_demo_story_step SET step_no = step_no - 10000 WHERE story_key = :k AND step_no > 10000", {k: arguments.key}, {datasource: "addon_demo"});
    }
</cfscript>

<cfif cgi.request_method EQ "POST">
    <cftry>
        <cfif NOT canEdit><cfthrow message="Only operators with role admin or se can change stories."></cfif>
        <cfset by = op.email ?: op.oid>
        <cfswitch expression="#form.action ?: ''#">
            <cfcase value="story">
                <cfset sk = reReplace(lCase(form.story_key ?: ""), "[^a-z0-9_]", "", "all")>
                <cfif NOT len(sk) OR NOT len(trim(form.title ?: ""))><cfthrow message="Key and title are required."></cfif>
                <cfset st = listFind("draft,live,retired", form.status ?: "") ? form.status : "draft">
                <cfset queryExecute("INSERT INTO cx_demo_story (story_key, title, subtitle, minutes, status, sort, updated_by) VALUES (:k, :t, :s, :m, :st, :so, :by)
                    ON DUPLICATE KEY UPDATE title = VALUES(title), subtitle = VALUES(subtitle), minutes = VALUES(minutes), status = VALUES(status), sort = VALUES(sort), updated_by = VALUES(updated_by)", {
                    k: left(sk, 40), t: left(trim(form.title), 160), s: {value: left(trim(form.subtitle ?: ""), 255), null: NOT len(trim(form.subtitle ?: ""))},
                    m: {value: val(form.minutes ?: 8), cfsqltype: "cf_sql_integer"}, st: st, so: {value: val(form.sort ?: 100), cfsqltype: "cf_sql_integer"}, by: by
                }, {datasource: "addon_demo"})>
                <cfset k = sk><cfset msg = "Story saved.">
            </cfcase>
            <cfcase value="step">
                <cfset id = val(form.id ?: 0)>
                <cfset dw = {}>
                <cfif listFind(DONE_EVENTS, form.done_event ?: "")><cfset dw = {event: form.done_event, count: max(1, val(form.done_count ?: 1))}></cfif>
                <cfset btns = []>
                <cfloop array="#lines(form.buttons ?: '')#" item="bl">
                    <cfset parts = listToArray(bl, "|")>
                    <cfif arrayLen(parts) GTE 2><cfset b = {label: trim(parts[1]), href: trim(parts[2])}><cfif arrayLen(parts) GTE 3 AND trim(parts[3]) EQ "_blank"><cfset b.target = "_blank"></cfif><cfset arrayAppend(btns, b)></cfif>
                </cfloop>
                <cfset prm = {
                    kind: (form.kind ?: "") EQ "live" ? "live" : "slide",
                    kicker: {value: left(trim(form.kicker ?: ""), 120), null: NOT len(trim(form.kicker ?: ""))},
                    title: left(trim(form.title ?: ""), 200),
                    body: {value: form.body_html ?: "", cfsqltype: "cf_sql_longvarchar"},
                    ben: {value: jsonOrNull(lines(form.benefits ?: "")), null: NOT arrayLen(lines(form.benefits ?: ""))},
                    task: {value: form.task_html ?: "", null: NOT len(trim(form.task_html ?: ""))},
                    tp: {value: left(trim(form.target_path ?: ""), 500), null: NOT len(trim(form.target_path ?: ""))},
                    ap: {value: jsonOrNull(lines(form.allow_paths ?: "")), null: NOT arrayLen(lines(form.allow_paths ?: ""))},
                    ck: {value: left(reReplace(lCase(form.card_key ?: ""), "[^a-z0-9_]", "", "all"), 60), null: NOT len(trim(form.card_key ?: ""))},
                    dw: {value: jsonOrNull(dw), null: structIsEmpty(dw)},
                    bt: {value: jsonOrNull(btns), null: NOT arrayLen(btns)},
                    st: listFind("draft,live,retired", form.status ?: "") ? form.status : "live",
                    by: by
                }>
                <cfif NOT len(prm.title)><cfthrow message="A step needs a title."></cfif>
                <cfif prm.kind EQ "live" AND prm.tp.null><cfthrow message="A live step needs the page it opens (target)."></cfif>
                <cfif id>
                    <cfset prm.id = id>
                    <cfset queryExecute("UPDATE cx_demo_story_step SET kind = :kind, kicker = :kicker, title = :title, body_html = :body, benefits = :ben, task_html = :task,
                        target_path = :tp, allow_paths = :ap, card_key = :ck, done_when = :dw, buttons = :bt, status = :st, updated_by = :by WHERE id = :id", prm, {datasource: "addon_demo"})>
                <cfelse>
                    <cfset prm.k = k>
                    <cfset mx =queryExecute("SELECT COALESCE(MAX(step_no), 0) + 1 AS n FROM cx_demo_story_step WHERE story_key = :k", {k: k}, {datasource: "addon_demo"}).n>
                    <cfset prm.n = {value: 20000 + mx, cfsqltype: "cf_sql_integer"}>
                    <cfset queryExecute("INSERT INTO cx_demo_story_step (story_key, step_no, kind, kicker, title, body_html, benefits, task_html, target_path, allow_paths, card_key, done_when, buttons, status, updated_by)
                        VALUES (:k, :n, :kind, :kicker, :title, :body, :ben, :task, :tp, :ap, :ck, :dw, :bt, :st, :by)", prm, {datasource: "addon_demo", result: "ins"})>
                    <!--- in place: after the step it was added after --->
                    <cfset aft = val(form.after ?: 0)>
                    <cfif aft>
                        <cfset queryExecute("UPDATE cx_demo_story_step SET step_no = step_no + 1 WHERE story_key = :k AND step_no > :a AND step_no < 20000 ORDER BY step_no DESC", {k: k, a: aft}, {datasource: "addon_demo"})>
                        <cfset queryExecute("UPDATE cx_demo_story_step SET step_no = :n WHERE id = :id", {n: aft + 1, id: ins.generatedKey}, {datasource: "addon_demo"})>
                    </cfif>
                    <cfset renumber(k)>
                    <cfset id = ins.generatedKey>
                </cfif>
                <cfset url.step = queryExecute("SELECT step_no FROM cx_demo_story_step WHERE id = :id", {id: id}, {datasource: "addon_demo"}).step_no>
                <cfset msg = "Step saved.">
            </cfcase>
            <cfcase value="move">
                <cfset q = queryExecute("SELECT id, step_no FROM cx_demo_story_step WHERE story_key = :k ORDER BY step_no", {k: k}, {datasource: "addon_demo"})>
                <cfset order = []><cfloop query="q"><cfset arrayAppend(order, q.id)></cfloop>
                <cfset pos = arrayFind(order, val(form.id ?: 0))>
                <cfset to = pos + ((form.dir ?: "") EQ "up" ? -1 : 1)>
                <cfif pos AND to GTE 1 AND to LTE arrayLen(order)>
                    <cfset arraySwap(order, pos, to)>
                    <cfloop from="1" to="#arrayLen(order)#" index="i"><cfset queryExecute("UPDATE cx_demo_story_step SET step_no = :n WHERE id = :id", {n: 10000 + i, id: order[i]}, {datasource: "addon_demo"})></cfloop>
                    <cfset queryExecute("UPDATE cx_demo_story_step SET step_no = step_no - 10000 WHERE story_key = :k AND step_no > 10000", {k: k}, {datasource: "addon_demo"})>
                    <cfset msg = "Step moved.">
                </cfif>
            </cfcase>
            <cfcase value="delete">
                <cfset queryExecute("DELETE FROM cx_demo_story_step WHERE id = :id AND story_key = :k", {id: val(form.id ?: 0), k: k}, {datasource: "addon_demo"})>
                <cfset renumber(k)><cfset url.step = 0>
                <cfset msg = "Step deleted.">
            </cfcase>
        </cfswitch>
        <cfset demo.pagesChanged()>
        <cfcatch><cfset msg = cfcatch.message><cfset msgKind = "err"></cfcatch>
    </cftry>
</cfif>

<cfset storiesQ = queryExecute("SELECT s.*, (SELECT COUNT(*) FROM cx_demo_story_step t WHERE t.story_key = s.story_key AND t.status <> 'retired') AS steps,
        (SELECT COUNT(*) FROM cx_demo_story_progress p WHERE p.story_key = s.story_key) AS started,
        (SELECT COUNT(*) FROM cx_demo_story_progress p WHERE p.story_key = s.story_key AND p.done_at IS NOT NULL) AS finished
    FROM cx_demo_story s ORDER BY s.sort, s.story_key", {}, {datasource: "addon_demo"})>
<cfoutput>
<h1>Stories</h1>
<p class="muted" style="margin-top:-6px">Guided flows like a slide deck: <b>slides</b> explain a step and its benefits; <b>live</b> steps open the real page with a coach panel
    (the task, Back / Next). While a live step runs, its page opens for the prospect, in Guided too; a box-wide or server page never does (it shows its card).
    Prospects start a story from their demo home or the DEMO bar. Text may use <span class="mono">{wsDsn}</span> (the prospect's sandbox), <span class="mono">{fname}</span>, <span class="mono">{company}</span>.</p>
<cfif len(msg)><div class="note #msgKind#">#encodeForHTML(msg)#</div></cfif>
<cfif demo.setting("pitch_show_drafts", "0") NEQ "1"><div class="note small">Prospects see <b>live</b> stories and steps only (drafts too while pitch_show_drafts = 1).</div></cfif>

<table><tr><th>Story</th><th>Status</th><th>Steps</th><th>Started</th><th>Finished</th><th></th></tr>
<cfloop query="storiesQ">
    <tr><td><a href="/ain5py/addon.cfm?a=demo&p=stories&k=#storiesQ.story_key#"><b>#encodeForHTML(storiesQ.title)#</b></a> <span class="mono small muted">#storiesQ.story_key#</span></td>
        <td>#badge(storiesQ.status)#</td><td>#storiesQ.steps#</td><td>#storiesQ.started#</td><td>#storiesQ.finished#</td>
        <td><a class="btn" href="/ain5py/addon.cfm?a=demo&p=story&arg=#storiesQ.story_key#" target="_blank">Preview</a></td></tr>
</cfloop>
</table>

<cfset sq = queryExecute("SELECT * FROM cx_demo_story WHERE story_key = :k", {k: k}, {datasource: "addon_demo"})>
<cfset s = sq.recordCount ? queryGetRow(sq, 1) : {story_key: "", title: "", subtitle: "", minutes: 8, status: "draft", sort: 100}>
<details class="card" #len(k) AND NOT sq.recordCount ? "open" : ""#>
    <summary style="cursor:pointer;font-weight:700">#sq.recordCount ? "Story settings: " & encodeForHTML(s.title) : "+ New story"#</summary>
    <form method="post" style="margin-top:8px"><input type="hidden" name="action" value="story">
        <div class="grid">
            <div><label>Key</label><input type="text" name="story_key" value="#encodeForHTMLAttribute(s.story_key)#" #sq.recordCount ? "readonly" : ""# maxlength="40"></div>
            <div><label>Title</label><input type="text" name="title" value="#encodeForHTMLAttribute(s.title)#" maxlength="160"></div>
            <div><label>Minutes</label><input type="number" name="minutes" value="#s.minutes#"></div>
            <div><label>Status</label><select name="status"><cfloop list="draft,live,retired" item="x"><option #s.status EQ x ? "selected" : ""#>#x#</option></cfloop></select></div>
            <div><label>Order</label><input type="number" name="sort" value="#s.sort#"></div>
        </div>
        <label>Subtitle (on the demo home)</label><input type="text" name="subtitle" value="#encodeForHTMLAttribute(s.subtitle ?: '')#" maxlength="255">
        <div style="margin-top:10px"><button class="btn primary" #canEdit ? "" : "disabled"#>Save the story</button></div>
    </form>
</details>

<cfif sq.recordCount>
    <cfset steps = queryExecute("SELECT * FROM cx_demo_story_step WHERE story_key = :k ORDER BY step_no", {k: k}, {datasource: "addon_demo"})>
    <!--- how far prospects got: who reached each step --->
    <cfset reach = {}>
    <cfset rq = queryExecute("SELECT CAST(JSON_EXTRACT(detail, '$.step') AS SIGNED) AS n, COUNT(DISTINCT pid) AS c FROM cx_demo_events
                              WHERE type = 'story_step' AND JSON_UNQUOTE(JSON_EXTRACT(detail, '$.story')) = :k GROUP BY n", {k: k}, {datasource: "addon_demo"})>
    <cfloop query="rq"><cfset reach[rq.n] = rq.c></cfloop>
    <h2>Steps of “#encodeForHTML(s.title)#”</h2>
    <table><tr><th>##</th><th>Kind</th><th>Title</th><th>Page / card</th><th>Status</th><th>Reached</th><th></th></tr>
    <cfloop query="steps">
        <tr #val(url.step) EQ steps.step_no ? 'style="background:##f3f6fe"' : ''#>
            <td>#steps.step_no#</td><td>#badge(steps.kind EQ "live" ? "active" : "verified")# #steps.kind#</td>
            <td><a href="/ain5py/addon.cfm?a=demo&p=stories&k=#k#&step=#steps.step_no#"><b>#encodeForHTML(steps.title)#</b></a></td>
            <td class="small mono">#encodeForHTML(steps.target_path ?: "")##len(steps.card_key ?: "") ? " 🃏 " & steps.card_key : ""#</td>
            <td>#badge(steps.status)#</td><td>#reach[steps.step_no] ?: 0#</td>
            <td style="white-space:nowrap"><cfif canEdit>
                <form method="post" style="display:inline"><input type="hidden" name="action" value="move"><input type="hidden" name="id" value="#steps.id#"><input type="hidden" name="dir" value="up"><button class="btn" title="Move up">↑</button></form>
                <form method="post" style="display:inline"><input type="hidden" name="action" value="move"><input type="hidden" name="id" value="#steps.id#"><input type="hidden" name="dir" value="down"><button class="btn" title="Move down">↓</button></form>
                <a class="btn" href="/ain5py/addon.cfm?a=demo&p=story&arg=#k#&step=#steps.currentRow#" target="_blank">Preview</a>
            </cfif></td>
        </tr>
    </cfloop>
    </table>
    <p><a class="btn" href="/ain5py/addon.cfm?a=demo&p=stories&k=#k#&step=new&after=#steps.recordCount#">+ Add a step at the end</a></p>

    <cfif url.step EQ "new" OR val(url.step)>
        <cfset e = {id: 0, kind: "slide", kicker: "", title: "", body_html: "", benefits: "", task_html: "", target_path: "", allow_paths: "", card_key: "", done_when: "", buttons: "", status: "live", step_no: 0}>
        <cfif val(url.step)>
            <cfset eq = queryExecute("SELECT * FROM cx_demo_story_step WHERE story_key = :k AND step_no = :n", {k: k, n: val(url.step)}, {datasource: "addon_demo"})>
            <cfif eq.recordCount><cfset e = queryGetRow(eq, 1)></cfif>
        </cfif>
        <cfset ben = []><cftry><cfset ben = len(e.benefits ?: "") ? deserializeJSON(e.benefits) : []><cfcatch></cfcatch></cftry>
        <cfset ap = []><cftry><cfset ap = len(e.allow_paths ?: "") ? deserializeJSON(e.allow_paths) : []><cfcatch></cfcatch></cftry>
        <cfset dw = {}><cftry><cfset dw = len(e.done_when ?: "") ? deserializeJSON(e.done_when) : {}><cfcatch></cfcatch></cftry>
        <cfset bt = []><cftry><cfset bt = len(e.buttons ?: "") ? deserializeJSON(e.buttons) : []><cfcatch></cfcatch></cftry>
        <cfset btTxt = []><cfloop array="#bt#" item="b"><cfset arrayAppend(btTxt, (b.label ?: "") & " | " & (b.href ?: "") & ((b.target ?: "") EQ "_blank" ? " | _blank" : ""))></cfloop>
        <div class="card">
        <h3 style="margin-top:0">#e.id ? "Step " & e.step_no & ": " & encodeForHTML(e.title) : "New step"#</h3>
        <form method="post"><input type="hidden" name="action" value="step"><input type="hidden" name="id" value="#e.id#"><input type="hidden" name="after" value="#val(url.after ?: 0)#">
            <div class="grid">
                <div><label>Kind</label><select name="kind"><option value="slide" #e.kind EQ "slide" ? "selected" : ""#>slide (a full page)</option><option value="live" #e.kind EQ "live" ? "selected" : ""#>live (the real page + coach)</option></select></div>
                <div><label>Status</label><select name="status"><cfloop list="live,draft,retired" item="x"><option #e.status EQ x ? "selected" : ""#>#x#</option></cfloop></select></div>
                <div><label>Card ("More about this" / "Why it matters")</label><input type="text" name="card_key" value="#encodeForHTMLAttribute(e.card_key ?: '')#" placeholder="e.g. mg_rag_maker"></div>
            </div>
            <label>Kicker (small line above the title)</label><input type="text" name="kicker" value="#encodeForHTMLAttribute(e.kicker ?: '')#" maxlength="120">
            <label>Title</label><input type="text" name="title" value="#encodeForHTMLAttribute(e.title)#" maxlength="200">
            <label>Text (HTML): what this step is and why it matters</label><textarea name="body_html" rows="7">#encodeForHTML(e.body_html ?: "")#</textarea>
            <label>Benefits (one per line, shown as ✓ "What you get")</label><textarea name="benefits" rows="4">#encodeForHTML(arrayToList(ben, chr(10)))#</textarea>
            <label>Buttons on the slide (Label | address | _blank), one per line</label><textarea name="buttons" rows="2">#encodeForHTML(arrayToList(btTxt, chr(10)))#</textarea>
            <h3>Live step</h3>
            <label>Page it opens (target)</label><input type="text" name="target_path" value="#encodeForHTMLAttribute(e.target_path ?: '')#" placeholder="/ain5py/boty/boty_full.cfm?wsDsn={wsDsn}">
            <label>Extra pages the prospect can open during this step (one per line)</label>
            <div class="small muted" style="margin:-2px 0 4px">They are not opened by themselves: each one is shown as a link under the task in the coach panel
                ("Also on this step: …"), and the prospect may open it from there or from a link inside the step's page. A line with * (e.g. <span class="mono">/ain5py/frontend/ragw_*</span>)
                only gives permission, without a link. A page labelled box-wide or server in the Access map never opens.</div>
            <textarea name="allow_paths" rows="2">#encodeForHTML(arrayToList(ap, chr(10)))#</textarea>
            <cfif arrayLen(ap)>
                <div class="small" style="margin-top:4px">
                <cfloop array="#ap#" item="x">
                    <cfif isSimpleValue(x) AND len(trim(x))>
                        <cfif find("*", x)><div class="muted">· <span class="mono">#encodeForHTML(x)#</span>: permission only (no link)</div>
                        <cfelse><cfset xi = demo.storyExtraInfo(trim(x))>
                            <cfif xi.opens><div style="color:##11845b">✓ <b>#encodeForHTML(xi.label)#</b> <span class="mono muted">#encodeForHTML(x)#</span>: shown as a link</div>
                            <cfelse><div style="color:##b26a00">⚠ <b>#encodeForHTML(xi.label)#</b> <span class="mono">#encodeForHTML(x)#</span>: #encodeForHTML(xi.why)#</div></cfif>
                        </cfif>
                    </cfif>
                </cfloop>
                </div>
            </cfif>
            <label>The task, in the coach panel (HTML)</label><textarea name="task_html" rows="3">#encodeForHTML(e.task_html ?: "")#</textarea>
            <div class="grid">
                <div><label>Done when (lights up Next)</label><select name="done_event"><option value="">— never (the prospect presses Next)</option>
                    <cfloop list="#DONE_EVENTS#" item="x"><option value="#x#" #(dw.event ?: "") EQ x ? "selected" : ""#>#x#</option></cfloop></select></div>
                <div><label>…this many times</label><input type="number" name="done_count" value="#dw.count ?: 1#" min="1"></div>
            </div>
            <div style="margin-top:12px;display:flex;gap:8px;flex-wrap:wrap">
                <button class="btn primary" #canEdit ? "" : "disabled"#>Save the step</button>
                <cfif e.id><a class="btn" href="/ain5py/addon.cfm?a=demo&p=stories&k=#k#&step=new&after=#e.step_no#">+ Add a step after this one</a></cfif>
            </div>
        </form>
        <cfif e.id AND canEdit>
            <form method="post" style="margin-top:10px" onsubmit="return confirm('Delete this step?')"><input type="hidden" name="action" value="delete"><input type="hidden" name="id" value="#e.id#">
                <button class="btn danger">Delete the step</button></form>
        </cfif>
        </div>
    </cfif>
</cfif>
</div>
</cfoutput>
