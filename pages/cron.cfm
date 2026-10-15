<!--- cron - housekeeping, called by the add-on's timers (py/cron_call.py signs in
      as the add-on's system operator over loopback). Also safe to call by hand.
        job=hourly  expiring / expired status + their e-mails, purge after retention
        job=daily   idle score decay, owners' daily digest --->
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset mailer = new trlvaddons.demo.lib.Mailer()>
<cfset job = lCase(url.job ?: "hourly")>
<cfset report = {job: job, at: dateTimeFormat(now(), "yyyy-mm-dd HH:nn:ss"), expiring: [], expired: [], purged: [], errors: [], digests: 0, decayed: 0}>
<cflock name="demo_cron" type="exclusive" timeout="5" throwontimeout="false">
<cfset report.locked = true>
<cftry>
<cfif job EQ "hourly">
    <cfset warnDays = val(demo.setting("expiring_warn_days", "3"))>
    <cfset keepDays = val(demo.setting("retention_days", "30"))>
    <!--- 1. ending soon --->
    <cfset q = queryExecute("SELECT pid FROM cx_demo_prospects WHERE status IN ('invited','active')
                             AND expires_at > NOW() AND expires_at <= NOW() + INTERVAL :w DAY", {w: {value: warnDays, cfsqltype: "cf_sql_integer"}}, {datasource: "addon_demo"})>
    <cfloop query="q">
        <cfset queryExecute("UPDATE cx_demo_prospects SET status = 'expiring' WHERE pid = :p", {p: q.pid}, {datasource: "addon_demo"})>
        <cfset sent = queryExecute("SELECT 1 FROM cx_demo_mail_log WHERE pid = :p AND template = 'expiring' AND status = 'sent'", {p: q.pid}, {datasource: "addon_demo"})>
        <cfif NOT sent.recordCount>
            <cfset p = demo.prospectBy("pid", q.pid)>
            <cfif isDate(p.first_login_at) AND demo.setting("mail_expiring", "0") EQ "1">
                <cfset mailer.sendTemplate("expiring", p.email, demo.mailVars(p), p.pid)>
            </cfif>
            <cfset demo.alert(p, "Demo ends soon", "The demo ends on #dateFormat(p.expires_at, 'd mmm yyyy')#. Extend it or follow up.")>
        </cfif>
        <cfset arrayAppend(report.expiring, q.pid)>
    </cfloop>
    <!--- 2. ended (sign-in already stops at account_expires_at) --->
    <cfset q = queryExecute("SELECT pid FROM cx_demo_prospects WHERE status IN ('invited','active','expiring','converted','suspended') AND expires_at <= NOW()", {}, {datasource: "addon_demo"})>
    <cfloop query="q">
        <cfset queryExecute("UPDATE cx_demo_prospects SET status = 'expired', purge_after = NOW() + INTERVAL :k DAY WHERE pid = :p",
            {k: {value: keepDays, cfsqltype: "cf_sql_integer"}, p: q.pid}, {datasource: "addon_demo"})>
        <cfset p = demo.prospectBy("pid", q.pid)>
        <cfif isDate(p.first_login_at) AND demo.setting("mail_ended", "0") EQ "1">
            <cfset mailer.sendTemplate("ended", p.email, demo.mailVars(p), p.pid)>
        </cfif>
        <cfset demo.logEvent(q.pid, "expired")>
        <cfset arrayAppend(report.expired, q.pid)>
    </cfloop>
    <!--- 3. purge after retention --->
    <cfset q = queryExecute("SELECT pid FROM cx_demo_prospects WHERE status = 'expired' AND purge_after IS NOT NULL AND purge_after <= NOW() LIMIT 10", {}, {datasource: "addon_demo"})>
    <cfset sb = new trlvaddons.demo.lib.Sandbox()>
    <cfloop query="q">
        <cfset r = sb.purge(q.pid)>
        <cfif r.ok><cfset arrayAppend(report.purged, q.pid)><cfelse><cfset arrayAppend(report.errors, q.pid & ": " & r.error)></cfif>
    </cfloop>
<cfelseif job EQ "daily">
    <!--- idle decay, once a day --->
    <cfif demo.setting("state_last_decay", "") NEQ dateFormat(now(), "yyyy-mm-dd")>
        <cfset w = demo.jsonSetting("score_weights")>
        <cfset pct = val(w.idle_decay_pct ?: 10)>
        <cfset r = queryExecute("UPDATE cx_demo_prospects SET score = FLOOR(score * (100 - :pct) / 100),
                                   score_band = CASE WHEN FLOOR(score * (100 - :pct) / 100) >= :hot THEN 'hot'
                                                     WHEN FLOOR(score * (100 - :pct) / 100) >= :warm THEN 'warm' ELSE 'cold' END
                                 WHERE status IN ('active','expiring') AND (last_seen_at IS NULL OR last_seen_at < NOW() - INTERVAL 1 DAY)",
            {pct: pct, hot: val(w.hot ?: 60), warm: val(w.warm ?: 25)}, {datasource: "addon_demo", result: "dr"})>
        <cfset report.decayed = dr.recordCount>
        <cfset demo.setSetting("state_last_decay", dateFormat(now(), "yyyy-mm-dd"), "cron")>
    </cfif>
    <!--- digest per owner: yesterday's activity of their prospects --->
    <cfif demo.setting("mail_digest", "0") EQ "1" AND demo.setting("state_last_digest", "") NEQ dateFormat(now(), "yyyy-mm-dd")>
        <cfset owners = queryExecute("SELECT DISTINCT o.oid, o.email, o.display_name FROM cx_demo_operators o
                                      JOIN cx_demo_prospects p ON p.owner_oid = o.oid
                                      WHERE o.active = 1 AND o.email <> '' AND p.status IN ('invited','active','expiring','converted')", {}, {datasource: "addon_demo"})>
        <cfloop query="owners">
            <cfset rows = queryExecute("
                SELECT p.pid, p.fname, p.lname, p.company, p.status, p.score, p.score_band, p.expires_at,
                  SUM(e.type = 'chat_question') AS q, SUM(e.type = 'gate_shown') AS g, SUM(e.type IN ('talk_request','handoff_requested')) AS t,
                  SUM(e.type = 'wishlist_add') AS w, SUM(e.type = 'ingest_done') AS u, COUNT(e.id) AS n
                FROM cx_demo_prospects p LEFT JOIN cx_demo_events e ON e.pid = p.pid AND e.ts >= CURDATE() - INTERVAL 1 DAY AND e.ts < CURDATE()
                WHERE p.owner_oid = :o AND p.status IN ('invited','active','expiring','converted')
                GROUP BY p.pid ORDER BY n DESC", {o: owners.oid}, {datasource: "addon_demo"})>
            <cfset lines = []>
            <cfloop query="rows">
                <cfset arrayAppend(lines, "- #rows.fname# #rows.lname# (#rows.company#, #rows.pid#): " &
                    (rows.n ? "#rows.q# questions, #rows.g# locked features opened, #rows.u# documents loaded, #rows.w# wish-list items" & (rows.t ? ", ASKED FOR A PERSON" : "") : "no activity") &
                    ". Score #rows.score# (#rows.score_band#), ends #dateFormat(rows.expires_at, 'd mmm')#.")>
            </cfloop>
            <cfset body = "Your demo prospects yesterday:" & chr(10) & chr(10) & arrayToList(lines, chr(10)) & chr(10) & chr(10)
                        & "Demo Console: " & demo.publicHost() & "/ain5py/addon.cfm?a=demo&p=console">
            <cfset mailer.send(owners.email, "[Demo] Daily digest · " & dateFormat(now(), "d mmm"), body, "digest")>
            <cfset report.digests++>
        </cfloop>
        <cfset demo.setSetting("state_last_digest", dateFormat(now(), "yyyy-mm-dd"), "cron")>
    </cfif>
</cfif>
<cfcatch><cfset arrayAppend(report.errors, cfcatch.message)></cfcatch>
</cftry>
</cflock>
<cfset demo.json(report)>
