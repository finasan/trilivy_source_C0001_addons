<!--- story - a guided flow (2026-10-19). Slides are drawn here as a full page;
      a live step sends the prospect to the real platform page, where demo.js
      shows the coach panel (the task, Back / Next). Every move goes through here:
        p=story&arg=<key>            start, or go back to where the prospect was
        p=story&arg=<key>&step=n     go to step n (past the last = finished)
        p=story&arg=<key>&go=exit    leave the story
      Operators see a preview of the steps (nothing is recorded). --->
<cfinclude template="_brand.cfm">
<cfset demo = new trlvaddons.demo.lib.Demo()>
<cfset d = demo.sessionDemo()>
<cfset key = reReplace(lCase(request.addon.arg), "[^a-z0-9_]", "", "all")>
<cfset all = demo.stories()>
<cfif NOT len(key) AND structCount(all)><cfset key = listFirst(structKeyList(all))></cfif>
<cfset s = all[key] ?: {}>
<cfset isProspect = NOT structIsEmpty(d) AND NOT (d.missing ?: true)>
<cfif structIsEmpty(s)>
    <cfoutput><div style="max-width:640px;margin:40px auto;font:15px/1.6 var(--fs)"><h2>This tour is not available</h2>
        <p><a href="/ain5py/addon.cfm?a=demo&p=welcome">Back to your demo</a></p></div></cfoutput><cfexit>
</cfif>
<cfset total = arrayLen(s.steps)>

<cfif isProspect>
    <cfif (url.go ?: "") EQ "exit">
        <cfset demo.storyStop(d.pid, "story_exit", key)>
        <cflocation url="/ain5py/addon.cfm?a=demo&p=welcome" addtoken="false">
    </cfif>
    <cfif isNumeric(url.step ?: "")>
        <cfset n = int(url.step)>
    <cfelse>
        <!--- start, or resume: a finished story starts again --->
        <cfset pr = demo.storyProgress(d.pid)[key] ?: {n: 1, done: false}>
        <cfset n = pr.done ? 1 : pr.n>
        <cfif structKeyExists(url, "restart")><cfset n = 1></cfif>
    </cfif>
    <cfset r = demo.storyGo(d.pid, key, n)>
    <cfif r.done>
        <cflocation url="/ain5py/addon.cfm?a=demo&p=welcome&story_done=#encodeForURL(key)#" addtoken="false">
    </cfif>
    <cfset step = r.step><cfset n = r.n>
    <cfif step.kind EQ "live" AND len(trim(step.target_path ?: ""))>
        <!--- a page that shows other prospects' data or changes the server never opens:
              the step is shown here instead, with its card (it opens once the page is made safe) --->
        <cfset tf = demo.classify(lCase(listFirst(trim(step.target_path), "?")), d.mode)>
        <cfset liveBlocked = (tf.unsafe ?: false) OR listFind("boxwide,server", tf.safety) GT 0>
        <cfif NOT liveBlocked><cflocation url="#demo.storyStepUrl(key, step, d, r.n)#" addtoken="false"></cfif>
        <cfset demo.logEvent(d.pid, "story_blocked", {feature: "story_" & key, page: left(step.target_path, 255)})>
    </cfif>
<cfelse>
    <!--- operator preview --->
    <cfset n = min(max(1, val(url.step ?: 1)), total)>
    <cfset step = s.steps[n]>
    <cfset d = {db: "INST_xxxx_vdem_p0000", instance: "vdem_p0000", fname: "Alex", company: "Example Ltd"}>
</cfif>

<cfparam name="liveBlocked" default="false">
<cfset base = "/ain5py/addon.cfm?a=demo&p=story&arg=" & encodeForURL(key)>
<cfoutput>
<style>
.ds{font:16px/1.6 var(--fs,'IBM Plex Sans','Segoe UI',sans-serif);color:##1b2333;min-height:calc(100vh - 140px);display:flex;flex-direction:column;
    background:linear-gradient(160deg,##0d47a1 0%,##2457d6 55%,##3b6fe0 100%);padding:28px 16px 40px}
.ds .deck{max-width:960px;width:100%;margin:0 auto;background:##fff;border-radius:20px;box-shadow:0 20px 60px rgba(5,20,60,.35);overflow:hidden;display:flex;flex-direction:column}
.ds .top{display:flex;align-items:center;gap:12px;flex-wrap:wrap;padding:14px 22px;border-bottom:1px solid ##e3e7ef;font-size:13px;color:##5d6779}
.ds .top b{color:##1b2333}
.ds .dots{display:flex;gap:6px;margin-left:auto;flex-wrap:wrap}
.ds .dots a{width:26px;height:26px;border-radius:50%;display:grid;place-items:center;font-size:12px;font-weight:700;text-decoration:none;
    background:##eef1f6;color:##5d6779}
.ds .dots a.done{background:##dfe8fb;color:##2457d6}.ds .dots a.on{background:##2457d6;color:##fff}
.ds .body{padding:34px 40px 26px;display:grid;grid-template-columns:minmax(0,1.5fr) minmax(0,1fr);gap:34px}
.ds .kick{color:##2457d6;font-weight:700;text-transform:uppercase;letter-spacing:.12em;font-size:12px}
.ds h1{font-size:32px;line-height:1.18;margin:6px 0 14px}
.ds .txt p{margin:0 0 12px}.ds .txt ul{margin:0 0 12px;padding-left:20px}
.ds .ben{background:##f4f7fd;border-radius:14px;padding:18px 20px;align-self:start}
.ds .ben h3{margin:0 0 10px;font-size:13px;text-transform:uppercase;letter-spacing:.1em;color:##2457d6}
.ds .ben ul{list-style:none;padding:0;margin:0}
.ds .ben li{padding:8px 0 8px 30px;position:relative;border-bottom:1px solid ##e3e9f6}.ds .ben li:last-child{border-bottom:0}
.ds .ben li::before{content:"✓";position:absolute;left:0;top:8px;width:20px;height:20px;border-radius:50%;background:##2bb07f;color:##fff;font-size:12px;display:grid;place-items:center}
.ds .extra{display:flex;flex-wrap:wrap;gap:8px;margin-top:6px}
.ds .nav{display:flex;align-items:center;gap:10px;padding:16px 22px;border-top:1px solid ##e3e7ef;background:##fafbfe;flex-wrap:wrap}
.ds .btn{display:inline-block;padding:10px 20px;border-radius:999px;text-decoration:none;font-weight:700;border:1px solid ##c9d2e3;color:##1b2333;background:##fff;font-size:15px}
.ds .btn.p{background:##2457d6;border-color:##2457d6;color:##fff}.ds .btn.ghost{border-color:transparent;color:##5d6779;font-weight:600}
.ds .btn.next{margin-left:auto}
.ds .live{display:inline-block;background:##e3f5ee;color:##11845b;border-radius:999px;padding:2px 10px;font-size:12px;font-weight:700;margin-left:6px}
.ds .prev-note{background:##fff3df;border-radius:10px;padding:10px 14px;margin:0 0 14px;font-size:14px}
@media (max-width:760px){.ds .body{grid-template-columns:1fr;padding:22px 18px}.ds h1{font-size:25px}.ds .dots{margin-left:0}}
</style>
<div class="ds" data-demo-story="#encodeForHTMLAttribute(key)#">
  <div class="deck" role="region" aria-label="#encodeForHTMLAttribute(s.title)#">
    <div class="top">
        <span><b>#encodeForHTML(s.title)#</b> · step #n# of #total#</span>
        <nav class="dots" aria-label="Steps">
        <cfloop from="1" to="#total#" index="i">
            <a href="#base#&step=#i#" class="#i EQ n ? 'on' : (i LT n ? 'done' : '')#" title="#encodeForHTMLAttribute(s.steps[i].title)#">#i#</a>
        </cfloop>
        </nav>
    </div>
    <div class="body">
        <div class="txt">
            <cfif NOT isProspect><div class="prev-note">Preview for operators: prospects see this page<cfif step.kind EQ "live"> as the real page <span class="mono">#encodeForHTML(demo.storyText(step.target_path ?: "", d))#</span> with the coach panel</cfif>.</div></cfif>
            <div class="kick">#encodeForHTML(step.kicker ?: "")#<cfif step.kind EQ "live" AND NOT liveBlocked><span class="live">LIVE</span></cfif></div>
            <h1>#encodeForHTML(step.title)#</h1>
            <!--- written by operators in the Demo Console (Stories) --->
            #demo.storyText(step.body_html ?: "", d)#
            <cfif liveBlocked>
                <div class="prev-note"><b>This page opens in your pilot.</b> In this shared demo it stays closed, because it would show more than your own sandbox.
                    <cfif len(step.card_key ?: "")>See what it does with <b>More about this</b>, then continue.</cfif></div>
            <cfelseif step.kind EQ "live" AND len(step.task_html ?: "")><div class="prev-note"><b>Your task:</b> #demo.storyText(step.task_html, d)#</div></cfif>
            <cfif arrayLen(step.buttons) OR len(step.card_key ?: "")>
                <div class="extra">
                <cfloop array="#step.buttons#" item="b">
                    <cfif isStruct(b) AND len(b.label ?: "") AND (b.href ?: "") EQ "talk">
                        <a class="btn" href="##" data-demo-action="talk">#encodeForHTML(b.label)#</a>
                    <cfelseif isStruct(b) AND len(b.label ?: "") AND len(b.href ?: "")>
                        <a class="btn" href="#encodeForHTMLAttribute(demo.storyText(b.href, d))#"<cfif (b.target ?: "") EQ "_blank"> target="_blank" rel="noopener"</cfif>>#encodeForHTML(b.label)#</a>
                    </cfif>
                </cfloop>
                <cfif len(step.card_key ?: "")><a class="btn" href="##" data-demo-feature="#encodeForHTMLAttribute(step.card_key)#">More about this</a></cfif>
                </div>
            </cfif>
        </div>
        <cfif arrayLen(step.benefits)>
        <aside class="ben"><h3>What you get</h3><ul>
            <cfloop array="#step.benefits#" item="bn"><cfif isSimpleValue(bn) AND len(trim(bn))><li>#encodeForHTML(bn)#</li></cfif></cfloop>
        </ul></aside>
        </cfif>
    </div>
    <div class="nav">
        <cfif n GT 1><a class="btn" href="#base#&step=#n - 1#" data-demo-key="ArrowLeft">← Back</a></cfif>
        <cfif isProspect><a class="btn ghost" href="#base#&go=exit">Leave the tour</a></cfif>
        <cfif n LT total>
            <a class="btn p next" href="#base#&step=#n + 1#" data-demo-key="ArrowRight">#s.steps[n + 1].kind EQ "live" ? "Let's do it →" : "Continue →"#</a>
        <cfelse>
            <a class="btn p next" href="#base#&step=#n + 1#" data-demo-key="ArrowRight">Finish ✓</a>
        </cfif>
    </div>
  </div>
</div>
<script>
// the DEMO bar was drawn before this page moved the story on: show the step we are on
(function () {
  var a = document.querySelector('##demoBar .demo-story[href*="arg=#encodeForJavaScript(key)#"]');
  if (a) a.textContent = "▶ #encodeForJavaScript(s.title)# · #n#/#total#";
})();
// ← / → move through the slides (not while typing)
document.addEventListener("keydown", function (e) {
  var t = e.target;
  if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable) || e.altKey || e.ctrlKey || e.metaKey) return;
  var a = document.querySelector('[data-demo-key="' + e.key + '"]');
  if (a && !document.getElementById("demoOv")) { e.preventDefault(); location.href = a.href; }
});
</script>
</cfoutput>
