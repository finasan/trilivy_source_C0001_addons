<!--- menu_probe - run by Demo.scanMenus() as a cfmodule, so each area's
      menu_config.cfm (which defines the same function names) gets its own scope.
      Hands back the raw menu (before menu_filter) in attributes.out.menu. --->
<cfif thisTag.executionMode EQ "end"><cfexit></cfif>
<cfparam name="attributes.area" default="">
<cfif NOT listFind("manage,kb,quick", attributes.area)><cfexit></cfif>
<cfinclude template="/ain5py/#attributes.area#/menu_config.cfm">
<cfif structKeyExists(variables, "menuStructure") AND isArray(variables.menuStructure)>
    <cfset attributes.out.menu = variables.menuStructure>
</cfif>
