<cfset activeTab = "library">
<cfinclude template="_ui.cfm">
<cfset msg = ""><cfset msgKind = "ok">
<cfset editId = val(url.id ?: 0)>
<cfset canVerify = listFind("admin,se", op.role) GT 0>

<cfif cgi.request_method EQ "POST">
    <cftry>
        <cfset objs = []>
        <cfloop from="1" to="8" index="i">
            <cfset q = trim(form["oq#i#"] ?: "")><cfset a = trim(form["oa#i#"] ?: "")>
            <cfif len(q) AND len(a)><cfset arrayAppend(objs, {q: q, a: a})></cfif>
        </cfloop>
        <cfset cta = []>
        <cfset cta = ["talk"]><!--- the only button (2026-10-15) --->
        <cfloop list="#form.cta ?: ''#" item="c"></cfloop>
        <cfset st = form.status ?: "draft">
        <cfif NOT listFind("draft,verified,live,retired", st)><cfset st = "draft"></cfif>
        <cfif listFind("verified,live", st) AND NOT canVerify><cfthrow message="Only operators with role admin or se can verify or publish a card."></cfif>
        <cfif listFind("verified,live", st) AND (form.checked ?: "") NEQ "1"><cfthrow message="Tick 'every claim on this card has been checked' to verify or publish it."></cfif>
        <cfset fk = reReplace(lCase(form.feature_key ?: ""), "[^a-z0-9_]", "", "all")>
        <cfset aud = listFind("business,it", form.audience ?: "") ? form.audience : "business">
        <cfset lang = reReplace(lCase(form.lang ?: "en"), "[^a-z]", "", "all")>
        <cfset prm = {fk: fk, aud: aud, lang: left(lang, 2), st: st, kicker: left(form.kicker ?: "", 120), headline: left(form.headline ?: "", 200),
                      why: form.why_html ?: "", how: form.how_html ?: "", objs: demo.toJson(objs), proof: form.proof_html ?: "",
                      cta: demo.toJson(cta), by: op.name ?: op.oid, ver: listFind("verified,live", st) ? 1 : 0}>
        <cfif NOT len(fk) OR NOT len(prm.headline)><cfthrow message="Feature and headline are required."></cfif>
        <cfif val(form.id ?: 0)>
            <cfset prm.id = val(form.id)>
            <cfset queryExecute("UPDATE cx_demo_pitch SET feature_key = :fk, audience = :aud, lang = :lang, status = :st, kicker = :kicker,
                headline = :headline, why_html = :why, how_html = :how, objections = :objs, proof_html = :proof, cta = :cta,
                version = version + 1, updated_by = :by,
                verified_by = IF(:ver = 1, :by, NULL), verified_at = IF(:ver = 1, NOW(), NULL) WHERE id = :id", prm, {datasource: "addon_demo"})>
            <cfset editId = val(form.id)>
        <cfelse>
            <cfset queryExecute("INSERT INTO cx_demo_pitch (feature_key, audience, lang, status, kicker, headline, why_html, how_html, objections, proof_html, cta, updated_by, verified_by, verified_at)
                VALUES (:fk, :aud, :lang, :st, :kicker, :headline, :why, :how, :objs, :proof, :cta, :by, IF(:ver = 1, :by, NULL), IF(:ver = 1, NOW(), NULL))", prm, {datasource: "addon_demo", result: "ins"})>
            <cfset editId = ins.generatedKey>
        </cfif>
        <cfset msg = "Saved (#st#).">
        <cfcatch><cfset msg = cfcatch.message><cfset msgKind = "err"></cfcatch>
    </cftry>
</cfif>

<cfset cards = queryExecute("
    SELECT c.id, c.feature_key, c.audience, c.lang, c.status, c.headline, c.updated_at, c.updated_by, c.verified_by,
           (SELECT COALESCE(SUM(s.times),0) FROM cx_demo_pitch_seen s WHERE s.card_key = CONCAT(c.feature_key,'/',c.audience,'/',c.lang)) AS shown,
           (SELECT COUNT(*) FROM cx_demo_events e WHERE e.feature_key = c.feature_key AND e.type = 'objection_open') AS objections,
           (SELECT COUNT(*) FROM cx_demo_events e WHERE e.feature_key = c.feature_key AND e.type = 'cta_click') AS ctas,
           (SELECT ROUND(AVG(e.duration_ms)/1000) FROM cx_demo_events e WHERE e.feature_key = c.feature_key AND e.type = 'popup_closed') AS secs
    FROM cx_demo_pitch c ORDER BY c.feature_key, c.audience, c.lang", {}, {datasource: "addon_demo"})>
<cfset feats = demo.features()>
<cfoutput>
<h1>Pitch library</h1>
<cfif len(msg)><div class="note #msgKind#">#encodeForHTML(msg)#</div></cfif>
<cfif demo.setting("pitch_show_drafts", "0") EQ "1">
    <div class="note warn">Prospects currently also see <b>draft</b> cards (marked DRAFT). Switch this off under Package &amp; settings before real prospects.</div>
</cfif>

<cfif editId OR structKeyExists(url, "new")>
    <cfset c = {id: 0, feature_key: url.feature ?: "", audience: listFind("business,it", url.audience ?: "") ? url.audience : "business", lang: "en", status: "draft", kicker: "", headline: "", why_html: "", how_html: "", objections: "[]", proof_html: "", cta: '["talk"]'}>
    <cfif editId>
        <cfset q = queryExecute("SELECT * FROM cx_demo_pitch WHERE id = :i", {i: editId}, {datasource: "addon_demo"})>
        <cfif q.recordCount><cfset c = queryGetRow(q, 1)></cfif>
    </cfif>
    <cfset objs = []><cftry><cfset objs = deserializeJSON(c.objections)><cfcatch></cfcatch></cftry>
    <cfset ctas = []><cftry><cfset ctas = deserializeJSON(c.cta)><cfcatch></cfcatch></cftry>
    <div class="card">
    <form method="post">
        <input type="hidden" name="id" value="#c.id#">
        <div class="grid">
            <!--- any card key (2026-10-19): a feature, a page's own card (pg_<id>), a menu code's card (mg_...), a tip --->
            <div><label>Card key</label><input type="text" name="feature_key" list="cardKeys" value="#encodeForHTMLAttribute(reReplace(lCase(c.feature_key), '[^a-z0-9_]', '', 'all'))#" maxlength="60" required>
                <datalist id="cardKeys">
                <cfloop array="#feats#" item="f"><option value="#f.feature_key#">#encodeForHTML(f.title)#</option></cfloop>
                <cfloop list="moment_citations,moment_10q,moment_upload,moment_expiring" item="m"><option value="#m#">tip</option></cfloop>
                <cfset nk = queryExecute("SELECT DISTINCT card_key, label FROM cx_demo_nodes WHERE card_key IS NOT NULL ORDER BY card_key", {}, {datasource: "addon_demo"})>
                <cfloop query="nk"><option value="#nk.card_key#">menu: #encodeForHTML(nk.label)#</option></cfloop>
                </datalist></div>
            <div><label>Audience</label><select name="audience"><cfloop list="business,it" item="a"><option #c.audience EQ a ? "selected" : ""#>#a#</option></cfloop></select></div>
            <div><label>Language</label><input type="text" name="lang" value="#encodeForHTMLAttribute(c.lang)#" maxlength="2"></div>
            <div><label>Status</label><select name="status"><cfloop list="draft,verified,live,retired" item="s"><option #c.status EQ s ? "selected" : ""#>#s#</option></cfloop></select></div>
        </div>
        <label>Kicker (small line above the headline)</label><input type="text" name="kicker" value="#encodeForHTMLAttribute(c.kicker ?: "")#">
        <label>Headline: the outcome, not the feature name</label><input type="text" name="headline" value="#encodeForHTMLAttribute(c.headline)#">
        <label>Why it matters (HTML, sales voice)</label><textarea name="why_html" rows="4">#encodeForHTML(c.why_html ?: "")#</textarea>
        <label>How it works (HTML, sales-engineer voice)</label><textarea name="how_html" rows="4">#encodeForHTML(c.how_html ?: "")#</textarea>
        <label>You might be wondering… (objection → honest answer)</label>
        <cfloop from="1" to="6" index="i">
            <div class="grid" style="margin-bottom:6px"><input type="text" name="oq#i#" placeholder="Objection #i#" value="#encodeForHTMLAttribute(arrayLen(objs) GTE i ? objs[i].q : "")#">
            <input type="text" name="oa#i#" placeholder="Answer" value="#encodeForHTMLAttribute(arrayLen(objs) GTE i ? objs[i].a : "")#"></div>
        </cfloop>
        <label>See for yourself (HTML): facts a buyer can check - a number, a hard limit, something to try in the demo, a customer result. Empty = the tab is not shown</label><textarea name="proof_html" rows="2">#encodeForHTML(c.proof_html ?: "")#</textarea>
        <p class="small muted" style="margin-top:10px">Cards have no Contact us button: prospects use the one in the DEMO bar (it opens a ticket in the platform's Talk to a Person).</p>
        <label style="font-weight:400;margin-top:12px"><input type="checkbox" name="checked" value="1"> Every claim on this card has been checked (needed for verified / live)</label>
        <div style="margin-top:12px;display:flex;gap:8px"><button class="btn primary">Save</button><a class="btn" href="/ain5py/addon.cfm?a=demo&p=library">Back to the list</a></div>
    </form>
    </div>
    <cfif c.id>
        <h2>Preview</h2>
        <div class="card" style="max-width:680px">
            <div style="background:##2457d6;color:##fff;padding:12px 16px;border-radius:10px 10px 0 0;margin:-14px -16px 12px"><div class="small" style="opacity:.85;text-transform:uppercase;letter-spacing:.1em">#encodeForHTML(c.kicker ?: "")#</div><b style="font-size:18px">#encodeForHTML(c.headline)#</b></div>
            #c.why_html ?: ""#<cfif len(c.how_html ?: "")><h3>How it works</h3>#c.how_html#</cfif>
            <cfif arrayLen(objs)><h3>You might be wondering…</h3><cfloop array="#objs#" item="o"><details><summary><b>#encodeForHTML(o.q)#</b></summary>#encodeForHTML(o.a)#</details></cfloop></cfif>
            <cfif len(c.proof_html ?: "")><h3>See for yourself</h3><div class="note">#c.proof_html#</div></cfif>
        </div>
    </cfif>
<cfelse>
    <p><a class="btn primary" href="/ain5py/addon.cfm?a=demo&p=library&new=1">+ New card</a></p>
    <table><tr><th>Feature</th><th>Audience</th><th>Status</th><th>Headline</th><th>Shown</th><th>Objections read</th><th>Buttons</th><th>Avg. open</th><th>Updated</th></tr>
    <cfloop query="cards">
        <tr><td><a href="/ain5py/addon.cfm?a=demo&p=library&id=#cards.id#"><b>#cards.feature_key#</b></a></td><td>#cards.audience# / #cards.lang#</td><td>#badge(cards.status)#</td>
            <td class="small">#encodeForHTML(cards.headline)#</td><td>#cards.shown#</td><td>#cards.objections#</td><td>#cards.ctas#</td><td>#len(cards.secs) ? cards.secs & " s" : "-"#</td>
            <td class="small">#dateFormat(cards.updated_at, "d mmm")# #encodeForHTML(cards.updated_by ?: "")#</td></tr>
    </cfloop>
    </table>
</cfif>
</div>
</cfoutput>
