<cfinclude template="_brand.cfm">
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset d = demo.sessionDemo()>
<cfif structIsEmpty(d) OR (d.missing ?: true)>
    <cfoutput><div style="max-width:640px;margin:40px auto;font-family:Arial,sans-serif">
        <h2>Demo home</h2><p>This page is the prospect's start page. You are signed in as an operator:
        open the <a href="/ain5py/addon.cfm?a=demo&p=console">Demo Console</a>.</p></div></cfoutput>
    <cfexit>
</cfif>
<cfset ws = urlEncodedFormat(d.db)>
<cfset pitches = demo.navPitchItems(d.mode)>
<!--- the stories (Quick Start), in their order --->
<cfset stories = demo.stories()>
<cfset prog = demo.storyProgress(d.pid)>
<cfset storyKeys = []>
<cfloop collection="#stories#" item="sk"><cfset arrayAppend(storyKeys, {k: sk, s: stories[sk].sort})></cfloop>
<cfset arraySort(storyKeys, function(a, b) { return a.s - b.s; })>
<cfoutput>
<style>
.dw{font:15px/1.55 var(--fs);color:##1b2333;max-width:1080px;margin:18px auto 60px;padding:0 16px}
.dw .hero{background:linear-gradient(135deg,##0d47a1,##2457d6);color:##fff;border-radius:16px;padding:28px 28px 24px;margin-bottom:18px}
.dw .hero h1{margin:0 0 6px;font-size:28px;line-height:1.2}.dw .hero p{margin:0;opacity:.92}
.dw .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px}
.dw .card{border:1px solid ##e3e7ef;border-radius:14px;padding:18px;background:##fff;display:flex;flex-direction:column}
.dw .card h3{margin:0 0 6px;font-size:17px}.dw .card p{margin:0 0 12px;color:##5d6779;font-size:14px;flex:1}
.dw .go{display:inline-block;align-self:flex-start;background:##2457d6;color:##fff;padding:8px 16px;border-radius:999px;text-decoration:none;font-weight:600}
.dw h2{font-size:19px;margin:26px 0 10px}
.dw .lock{border:1px dashed ##c9d2e3;border-radius:12px;padding:14px;cursor:pointer;background:##fafbfe}
.dw .lock:hover{border-color:##2457d6;background:##f3f6fe}
.dw .lock b{display:block;margin-bottom:2px}.dw .lock span{font-size:13px;color:##5d6779}
.dw .try{background:##f6f7fb;border-radius:12px;padding:12px 16px;margin-top:14px;font-size:14px}
.dw .try code{background:##fff;padding:1px 6px;border-radius:6px}
.dw .qs{display:flex;align-items:center;gap:18px;flex-wrap:wrap;background:##fff;color:##1b2333;border-radius:14px;padding:16px 20px;margin-top:18px}
.dw .qs .qt{flex:1;min-width:220px}.dw .qs .qt b{display:block;font-size:18px}.dw .qs .qt span{color:##5d6779;font-size:14px}
.dw .qs .qgo{background:##ffb300;color:##1b2333;font-weight:800;font-size:16px;padding:12px 24px;border-radius:999px;text-decoration:none;white-space:nowrap}
.dw .qs .qgo:hover{background:##ffc233}
.dw .qs .qre{color:##2457d6;font-size:13px;font-weight:600}
.dw .qdone{background:##e3f5ee;border-radius:12px;padding:12px 16px;margin-bottom:14px}
</style>
<div class="dw">
    <div class="hero">
        <h1>Welcome#len(d.fname) ? ", " & encodeForHTML(d.fname) : ""#</h1>
        <p>This is your private Trilivy demo#len(d.company) ? " for " & encodeForHTML(d.company) : ""#. Everything you do here stays in your own sandbox. #d.daysLeft# days left.</p>
        <div style="margin-top:14px;display:flex;align-items:center;gap:10px;flex-wrap:wrap">
            <span style="font-weight:600">Experience:</span> #demo.switchHtml(d.mode, "demo-sw demo-sw-big")#
            <span style="opacity:.85;font-size:13.5px">#d.mode EQ "explorer" ? "The real Trilivy menus on your own copy." : "Switch to Full platform to use the real Trilivy menus on your own copy."#</span>
        </div>
        <cfloop array="#storyKeys#" item="sx">
            <cfset s = stories[sx.k]><cfset pr = prog[sx.k] ?: {}>
            <cfset started = NOT structIsEmpty(pr) AND NOT pr.done AND pr.n GT 1>
            <div class="qs">
                <div class="qt"><b>#encodeForHTML(s.title)#</b><span>#encodeForHTML(s.subtitle ?: "")# · about #s.minutes# minutes · #arrayLen(s.steps)# steps</span></div>
                <a class="qgo" href="/ain5py/addon.cfm?a=demo&p=story&arg=#encodeForURL(sx.k)#" data-demo-nav="story_#encodeForHTMLAttribute(sx.k)#">
                    #started ? "▶ Continue at step " & pr.n : ((pr.done ?: false) ? "▶ Take it again" : "▶ Start")#</a>
                <cfif started><a class="qre" href="/ain5py/addon.cfm?a=demo&p=story&arg=#encodeForURL(sx.k)#&restart=1">start over</a></cfif>
            </div>
        </cfloop>
    </div>
    <cfif len(url.story_done ?: "") AND structKeyExists(stories, url.story_done)>
        <div class="qdone"><b>You finished “#encodeForHTML(stories[url.story_done].title)#”.</b> Everything you built is still in your sandbox: keep asking the assistant,
            <cfif d.mode NEQ "explorer">switch to <b>Full platform</b> above to explore every menu,<cfelse>explore the menus at the top,</cfif>
            or use <a href="##" data-demo-action="talk">Contact us</a>.</div>
    </cfif>
    <div class="grid">
        <div class="card"><h3>💬 Ask the assistant</h3><p>An HR and IT service-desk assistant for a sample company, Orvane Group, built on its policies. Answers show their sources.</p>
            <a class="go" href="/ain5py/boty/boty_full.cfm?wsDsn=#ws#" target="_blank" data-demo-nav="assistant">Open the assistant</a></div>
        <div class="card"><h3>📄 Try your own documents</h3><p>Upload a few files and ask about them. They stay in your private sandbox and are deleted with it.</p>
            <a class="go" href="/ain5py/addon.cfm?a=demo&p=my_docs" data-demo-nav="my_docs">My documents</a></div>
        <div class="card"><h3>📚 Courses</h3><p>See the learner side: short lessons, quizzes and certificates built from company content.</p>
            <a class="go" href="/ain5py/lms_workshop/player/player_launch.cfm?wsDsn=#ws#" data-demo-nav="courses">Open courses</a></div>
    </div>
    <cfif d.mode EQ "explorer">
    <div class="try" style="background:##e3f5ee"><b>You have the full platform.</b> Use the menus at the top (JumpStart, Main AI, RAG, Manage):
        they work on your own private copy. A few server-wide screens stay locked and explain themselves when you open them.</div>
    </cfif>
    <div class="try"><b>Good first questions:</b> <code>How many days of annual leave do I get?</code> · <code>My VPN keeps disconnecting, what should I do?</code> · <code>What do I do if my laptop is stolen?</code> · <code>Can I claim a taxi to the airport?</code></div>

    <h2>In the full platform</h2>
    <p class="muted" style="margin-top:-4px;color:##5d6779">Not open in the demo, but each one explains what it does for you. Click any of them.</p>
    <div class="grid">
    <cfloop array="#pitches#" item="f">
        <div class="lock" data-demo-feature="#encodeForHTMLAttribute(f.feature_key)#"><b>🔒 #encodeForHTML(f.nav_label)#</b><span>#encodeForHTML(f.title)#</span></div>
    </cfloop>
    </div>
</div>
</cfoutput>
