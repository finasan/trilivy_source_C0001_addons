<cfcomponent output="false" hint="Demo add-on e-mail (2026-10-15): templates from cx_demo_settings (mail_<name>_subject/_body), {placeholders}, sent through the platform's cf_XSendMail and logged in cx_demo_mail_log.">

<cffunction name="sendTemplate" access="public" returntype="struct" output="false">
    <cfargument name="name" type="string" required="true">
    <cfargument name="to"   type="string" required="true">
    <cfargument name="vars" type="struct" required="true">
    <cfargument name="pid"  type="string" required="false" default="">
    <cfset var demo = new trlvaddons.demo.lib.Demo()>
    <cfset var subject = fill(demo.setting("mail_#arguments.name#_subject", "Trilivy demo"), arguments.vars)>
    <cfset var body    = fill(demo.setting("mail_#arguments.name#_body", ""), arguments.vars)>
    <cfreturn send(arguments.to, subject, body, arguments.name, arguments.pid)>
</cffunction>

<cffunction name="send" access="public" returntype="struct" output="false">
    <cfargument name="to"       type="string" required="true">
    <cfargument name="subject"  type="string" required="true">
    <cfargument name="text"     type="string" required="true">
    <cfargument name="template" type="string" required="false" default="custom">
    <cfargument name="pid"      type="string" required="false" default="">
    <cfset var out = { ok: false, error: "" }>
    <cfset var html = "">
    <cfif NOT isValid("email", trim(arguments.to))>
        <cfset out.error = "invalid recipient">
        <cfreturn out>
    </cfif>
    <!--- Plain text in, simple HTML out: paragraphs, line breaks and links. --->
    <!--- Links are cut out of the RAW text first (they contain &), escaped
          separately, then put back as anchors. --->
    <cfset var links = reMatch("https?://[^\s<>""]+", arguments.text)>
    <cfset var raw = arguments.text>
    <cfloop from="1" to="#arrayLen(links)#" index="local.i">
        <cfset raw = replace(raw, links[local.i], "@@LINK" & local.i & "@@", "one")>
    </cfloop>
    <cfset html = htmlEditFormat(raw)>
    <cfloop from="1" to="#arrayLen(links)#" index="local.i">
        <cfset html = replace(html, "@@LINK" & local.i & "@@",
            '<a href="' & htmlEditFormat(links[local.i]) & '">' & htmlEditFormat(links[local.i]) & '</a>', "one")>
    </cfloop>
    <cfset html = "<p>" & replace(replace(html, chr(10) & chr(10), "</p><p>", "all"), chr(10), "<br>", "all") & "</p>">
    <cfset html = '<div style="font-family:Arial,sans-serif;font-size:15px;line-height:1.5;color:##1b2333;max-width:620px">' & html & '</div>'>
    <cftry>
        <cf_XSendMail to="#trim(arguments.to)#" subject="#arguments.subject#" type="html"><cfoutput>#html#</cfoutput></cf_XSendMail>
        <cfset out.ok = true>
        <cfcatch type="any">
            <cfset out.error = left(cfcatch.message, 500)>
        </cfcatch>
    </cftry>
    <cftry>
        <cfquery datasource="addon_demo">
            INSERT INTO cx_demo_mail_log (pid, template, to_email, subject, status, error)
            VALUES (<cfqueryparam value="#arguments.pid#" null="#NOT len(arguments.pid)#">,
                    <cfqueryparam value="#left(arguments.template, 40)#">,
                    <cfqueryparam value="#left(trim(arguments.to), 200)#">,
                    <cfqueryparam value="#left(arguments.subject, 250)#">,
                    <cfqueryparam value="#out.ok ? 'sent' : 'failed'#">,
                    <cfqueryparam value="#out.error#" null="#NOT len(out.error)#">)
        </cfquery>
        <cfcatch type="any"></cfcatch>
    </cftry>
    <cfreturn out>
</cffunction>

<cffunction name="fill" access="public" returntype="string" output="false">
    <cfargument name="tpl"  type="string" required="true">
    <cfargument name="vars" type="struct" required="true">
    <cfset var s = arguments.tpl>
    <cfloop collection="#arguments.vars#" item="local.k">
        <cfif isSimpleValue(arguments.vars[local.k])>
            <cfset s = replaceNoCase(s, "{" & local.k & "}", arguments.vars[local.k], "all")>
        </cfif>
    </cfloop>
    <cfreturn s>
</cffunction>

</cfcomponent>
