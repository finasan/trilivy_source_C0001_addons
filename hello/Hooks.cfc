<cfcomponent output="false" hint="hello: proves the hook framework. Acts only for sessions with session.hello_test = true; everyone else sees no change.">

<cffunction name="init" access="public" returntype="any" output="false">
    <cfargument name="meta" type="struct" required="true">
    <cfset variables.meta = arguments.meta>
    <cfreturn this>
</cffunction>

<cffunction name="on" access="private" returntype="boolean" output="false">
    <cfreturn structKeyExists(session, "hello_test") AND session.hello_test EQ true>
</cffunction>

<cffunction name="mode" access="private" returntype="string" output="false">
    <cfreturn on() ? (session.hello_mode ?: "") : "">
</cffunction>

<cffunction name="note" access="private" returntype="void" output="false">
    <cfargument name="what" type="string" required="true">
    <cflog file="addons" type="information" text="hello: #arguments.what#">
</cffunction>

<cffunction name="isOperator" access="public" returntype="boolean" output="false">
    <cfreturn on() AND (session.hello_operator ?: false) EQ true>
</cffunction>

<cffunction name="login_check" access="public" returntype="struct" output="false">
    <cfargument name="ctx" type="struct" required="true">
    <cfreturn { allow: true }>
</cffunction>

<cffunction name="session_init" access="public" returntype="void" output="false">
    <cfargument name="ctx" type="struct" required="true">
</cffunction>

<cffunction name="request_gate" access="public" returntype="struct" output="false">
    <cfargument name="ctx" type="struct" required="true">
    <cfif mode() EQ "throw_gate"><cfthrow message="hello: deliberate request_gate failure"></cfif>
    <cfif on() AND arguments.ctx.path EQ "/ain5py/manage/changepass.cfm">
        <cfreturn { action: "deny", message: "hello denied this page" }>
    </cfif>
    <cfif on() AND arguments.ctx.path EQ "/ain5py/manage/view_myprofile.cfm">
        <cfreturn { action: "redirect", url: "/ain5py/addon.cfm?a=hello&p=hello&arg=redirected" }>
    </cfif>
    <cfreturn { action: "continue" }>
</cffunction>

<cffunction name="page_access" access="public" returntype="string" output="false">
    <cfargument name="ctx" type="struct" required="true">
    <cfif on() AND arguments.ctx.path CONTAINS "/ain5py/tips/">
        <cfreturn "page:hello:tips">
    </cfif>
    <cfreturn "default">
</cffunction>

<cffunction name="nav_items" access="public" returntype="void" output="false">
    <cfargument name="ctx" type="struct" required="true">
    <cfif NOT on()><cfreturn></cfif>
    <cfset arrayAppend(arguments.ctx.nav, { on: 1, label: "HELLO-NAV", emoji: "", href: "##", target: "", attrs: 'data-hello="1"' })>
    <cfset arguments.ctx.flags.supportChat = 0>
</cffunction>

<cffunction name="page_top" access="public" returntype="string" output="false">
    <cfargument name="ctx" type="struct" required="true">
    <cfif mode() EQ "throw_top"><cfthrow message="hello: deliberate page_top failure"></cfif>
    <cfreturn on() ? '<div id="hello-top" data-where="#encodeForHTMLAttribute(arguments.ctx.where ?: "")#">HELLO-TOP</div>' : "">
</cffunction>

<cffunction name="menu_filter" access="public" returntype="void" output="false">
    <cfargument name="ctx" type="struct" required="true">
    <cfif on()><cfset arguments.ctx.menu = [ { id: "hello", label: "HELLO-MENU", url: "##" } ]></cfif>
</cffunction>

<cffunction name="chat_pre" access="public" returntype="struct" output="false">
    <cfargument name="ctx" type="struct" required="true">
    <cfreturn { allow: true }>
</cffunction>

<cffunction name="event" access="public" returntype="void" output="false">
    <cfargument name="ctx" type="struct" required="true">
    <cfif on() OR listFind("login_failed", arguments.ctx.type)>
        <cfset note("event #arguments.ctx.type#")>
    </cfif>
</cffunction>

</cfcomponent>
