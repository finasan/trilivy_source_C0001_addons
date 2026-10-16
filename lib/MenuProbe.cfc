<!--- The raw menu of a menu_config area (manage, kb, quick), read through
      menu_probe.cfm as a cfmodule so each config file gets its own scope. --->
<cfcomponent output="false">
    <cffunction name="menu" access="public" returntype="array" output="false">
        <cfargument name="area" type="string" required="true">
        <cfset var box = {menu: []}>
        <cfmodule template="/trlvaddons/demo/lib/menu_probe.cfm" area="#arguments.area#" out="#box#">
        <cfreturn box.menu>
    </cffunction>
</cfcomponent>
