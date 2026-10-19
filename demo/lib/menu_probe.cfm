<!--- menu_probe - run by Demo.scanMenus() as a cfmodule, so each area's
      menu_config.cfm (which defines the same function names) gets its own scope.
      Hands back the raw menu (before menu_filter) in attributes.out.menu.
      "instance" = the Instance Control Panel sidebar (menuinst/icp_menu_config.cfm):
      it has no menu_filter hook, so it is read here with the variables
      icp_menu.cfm sets before its include (a placeholder instance). --->
<cfif thisTag.executionMode EQ "end"><cfexit></cfif>
<cfparam name="attributes.area" default="">
<cfif attributes.area EQ "instance">
    <cfset IC = {db_name: "demo_probe", instance_name: "demo_probe", txt_title: ""}>
    <cfset wsBaseUrl = "/ain5py/lms_workshop/constructors">
    <cfset playerUrl = "/ain5py/lms_workshop/player">
    <cfset actionRegistryUrl = "/ain5py/actionregistry">
    <cfset botxAdminUrl = "/ain5py/boty/admin">
    <!--- icp_menu_config.cfm starts with "var wsDsn = ...": it only runs inside a function --->
    <cffunction name="_icpMenu" returntype="any" output="false">
        <cfinclude template="/ain5py/menuinst/icp_menu_config.cfm">
        <cfreturn variables.icpMenu ?: []>
    </cffunction>
    <cfset _m = _icpMenu()>
    <cfif isArray(_m)><cfset attributes.out.menu = _m></cfif>
    <cfexit>
</cfif>
<cfif NOT listFind("manage,kb,quick", attributes.area)><cfexit></cfif>
<cfinclude template="/ain5py/#attributes.area#/menu_config.cfm">
<cfif structKeyExists(variables, "menuStructure") AND isArray(variables.menuStructure)>
    <cfset attributes.out.menu = variables.menuStructure>
</cfif>
