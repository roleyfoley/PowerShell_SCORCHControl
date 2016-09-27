# Load balancing Control - MF2201 - 01/03/2016
# This script is used to control the load balancing state of a machine using System Centre Orchestrator 
# Using this script a job is submitted to SCORCH to change the state of the machine. 
# The called job will validate the hostname of the Computer to make sure it exists and check that it is in the load balancer. 

# 3 Switches are available to control the script
# -Enable - Enable the server in Load balancing
# -Disable - Disable the server in Load balancing
# -Status - Get the current status of the Server in load balancing 
# -- Default will be the status 

# Once completed the script will return the NodeName and the state that it is in after the job ran 
# Possible return states:
# - Errors
# -- HOST_NOT_FOUND - Server name not in DNS
# -- NODE_NOT_FOUND - Server in DNS but not in load balancer
# -- STATUS_NOT_FOUND - The desired state requested is not valid 
# - Sucessful
# -- monitor-enabled_up - Online and responding to health checks
# -- monitor-enabled_down - Online but not responding to health checks
# -- user-disabled_up - Offline and responding to health checks
# -- user-disabled_down - Ofline and not responding to health checks
# -- user-disabled_user-down - Forced Offline

# Authentication
# - The script will use default credentials to connect to the Orchestrator server 

[CmdletBinding(DefaultParameterSetName='Status')]

param (
    [Parameter(ParameterSetName='-Enable',Mandatory=$false)][switch]$Enable,
    [Parameter(ParameterSetName='-Disable',Mandatory=$false)][switch]$Disable,
    [Parameter(ParameterSetName='-Status',Mandatory=$false)][switch]$Status
)

# -- Convert Paramater into Variable 
# Set the State parameter based on the switch
if ( $Enable -eq $true) {
    $DesiredState = "enable"
 }
 elseif ( $Disable -eq $true) {
    $DesiredState = "disable" 
} 
else {
    $DesiredState = "status"
} 

# **** VARIABLE SETUP ****
# -- Set Computer Name using the local server details unless one has been specified. 
$NodeName = [string]$($env:COMPUTERNAME)

$ScorchServer = ''
$ScorchPort = "81" 

# - Global F5 Variables
$RunBookNodeNameProp = "Node Name"
$RunBookOutputProperty = "NodeState" 

# -- Change Status Specifc Variables
$ChangeRunBookName = ""
$ChangeRunBookDesiredStateProp = "DesiredState" 

# -- Get Status Specific Variables
$GetRunBookName = "F5 - Node Status"

# **** FUNCTION DEFINITIONS ******* 
#The Function is called to retreive the "Id" Property
# This occurs by:
# + Passing in an XML object
# + Specifying the name of the propery being searched for (Input1)
# + Specifying that the runbook property is an "In" direction property
# + Specifying that the element neded for that property is the GUID based Id

function GetScorchProperty([System.Object]$XMLString, [string]$Name, [string]$Direction, [string]$DesiredData){
   $nsmgr = New-Object System.XML.XmlNamespaceManager($XMLString.NameTable)    
   $nsmgr.AddNamespace('d','http://schemas.microsoft.com/ado/2007/08/dataservices')
   $nsmgr.AddNamespace('m','http://schemas.microsoft.com/ado/2007/08/dataservices/metadata')
 
   # Create an Array of Properties based on the 'Name' value
   $inputs = $XMLString.SelectNodes('//d:Name',$nsmgr)
 
   foreach ($parameter in $inputs){
      # Each 'Name' has related elements at the same level in XML
      # So the parent node is found and a new array of siblings 
      # is created.
 
      #Reset Property values 
      $obName          =""
      $obId            =""
      $obType          =""
      $obDirection     =""
      $obDescription   =""
 
      $siblings = $($parameter.ParentNode.ChildNodes)
 
      # Each of the sibling properties is identified
      foreach ($elements in $siblings){
      # write-host "Element = " $elements.ToString()
          If ($elements.ToString() -eq "Name"){
            $obName = $elements.InnerText
          }   
          If ($elements.ToString() -eq "Id"){
             $obId = $elements.InnerText
          }
          If ($elements.ToString() -eq "type"){
             $obType = $elements.InnerText
          }
          If ($elements.ToString() -eq "Direction"){
             $obDirection = $elements.InnerText
          }
         If ($elements.ToString() -eq "Description"){
            $obDescription = $elements.InnerText
         }
         If ($elements.ToString() -eq "Value"){
           # write-host "Value = "$elements.InnerText
            $obValue = $elements.InnerText
         }
       }

        if (($Name -eq $obName) -and ($Direction -eq $obDirection)){
          # "Correct input found"
          #Return the Requested Property
 
         If ($DesiredData -eq "Id"){
            return $obId 
         }
         If ($DesiredData -eq "Value"){
            return $obValue
         }
          }
   }
   return $Null
}

# **** SCRIPT STARTS HERE ****
$RunBookName = ""
switch ( $DesiredState ) {
    "enable" { $RunBookName = $ChangeRunBookName }
    "disable" { $RunBookName = $ChangeRunBookName }
    default { $RunBookName = $GetRunBookName }
}

# ** Get the Run Book GUID
$RunBookURI = "http://$($ScorchServer):$($ScorchPort)/Orchestrator2012/Orchestrator.svc/Runbooks?`$filter=Name eq '$RunBookName'"
$RunBookResponse = Invoke-WebRequest -Uri $RunBookURI -Method Get -UseDefaultCredentials 
$RunBookXML = [xml] $RunBookResponse.Content
$RunBookGUIDURL = $RunBookXML.feed.entry.id 
$RunBookGUID = $RunBookGUIDURL.Substring($RunBookGUIDURL.Length - 38,36)

# ** Get the Input Parameters and their GUID
$ParameterResponse = Invoke-WebRequest -Uri "$($RunBookGUIDURL)/Parameters" -Method Get -UseDefaultCredentials
[System.Xml.XmlDocument] $ParameterXML = $ParameterResponse.Content
$PropNodeNameGUID = GetScorchProperty $ParameterXML $RunBookNodeNameProp "In" "Id"

# Change the HTTP request body based on the action that is being performed.
switch ($DesiredState ) {
    { ($_ -eq "enable") -or ($_ -eq "disable") } { 
        $PropDesiredStateGUID = GetScorchProperty $ParameterXML $ChangeRunBookDesiredStateProp  "In" "Id"
        # ** Build the Job Request
$POSTBody = @"
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<entry xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" xmlns="http://www.w3.org/2005/Atom">
<content type="application/xml">
<m:properties>
<d:RunbookId type="Edm.Guid">{$($RunbookGUID)}</d:RunbookId>
<d:Parameters>&lt;Data&gt;&lt;Parameter&gt;&lt;ID&gt;{$($PropNodeNameGUID)}&lt;/ID&gt;&lt;Value&gt;$($NodeName)&lt;/Value&gt;&lt;/Parameter&gt;&lt;Parameter&gt;&lt;ID&gt;{$($PropDesiredStateGUID)}&lt;/ID&gt;&lt;Value&gt;$($DesiredState)&lt;/Value&gt;&lt;/Parameter&gt;&lt;/Data&gt;</d:Parameters>
</m:properties>
</content>
</entry>
"@

    }
    default {
$POSTBody = @"
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<entry xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" xmlns="http://www.w3.org/2005/Atom">
<content type="application/xml">
<m:properties>
<d:RunbookId type="Edm.Guid">{$($RunbookGUID)}</d:RunbookId>
<d:Parameters>&lt;Data&gt;&lt;Parameter&gt;&lt;ID&gt;{$($PropNodeNameGUID)}&lt;/ID&gt;&lt;Value&gt;$($NodeName)&lt;/Value&gt;&lt;/Parameter&gt;&lt;/Data&gt;</d:Parameters>
</m:properties>
</content>
</entry>
"@
} 
}

# ** Submit the Job
$JobURI = "http://$($ScorchServer):$($ScorchPort)/Orchestrator2012/Orchestrator.svc/Jobs/"
$JobResposnse = Invoke-WebRequest -Uri $JobURI -Method POST -UseDefaultCredentials -Body $POSTBody -ContentType "application/atom+xml"
$JobResponseXML = [xml] $JobResposnse.Content
$JobResposnseURL = $JobResponseXML.entry.id

$JobStatus = ""
$JobStatus = $JobResponseXML.entry.content.properties.Status

# ** Wait for the Job to finish 
$DoExit = ""
do
{
	if($JobStatus -ne "Completed")
	{
		start-sleep -second 5
		$SleepCounter = $SleepCounter + 1
			if($SleepCounter -eq 20)
			{
				$DoExit="Yes"
			}
	}
	Else
	{
		$DoExit="Yes"
	}
 
    # Query the web service for the current status
     $ResponseObject = invoke-webrequest -Uri "$($JobResposnseURL)" -method Get -UseDefaultCredentials
     $JobResponseXML = [xml] $ResponseObject.Content
     $RunbookJobURL = $JobResponseXML.entry.id
     $Jobstatus = $JobResponseXML.entry.content.properties.Status
}While($DoExit -ne "Yes")

# ** When the job has finsihed get the response of the job
$InstanceResponse = Invoke-WebRequest -Uri "$($JobResposnseURL)/Instances" -Method Get -UseDefaultCredentials
$InstanceXML = [xml] $InstanceResponse
$InstanceURL = $InstanceXML.feed.entry.id

# ** Grab the returned Properties
$InstancePropertiesResponse = Invoke-WebRequest -Uri "$($InstanceURL)/Parameters" -Method Get -UseDefaultCredentials
[System.Xml.XmlDocument] $InstancePropertiesXML = $InstancePropertiesResponse.Content
$InstancePropertiesResult = GetScorchProperty $InstancePropertiesXML $RunBookOutputProperty "Out" "Value"

$JobResults = @{}
$JobResults.Add("NodeName",$NodeName)
$JobResults.Add("State",$InstancePropertiesResult)

New-Object PSObject -Property $JobResults
