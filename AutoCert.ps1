Param (
	[switch]$Console = $false,
	[switch]$Debug = $false,
	[switch]$Status = $False,
	[Switch]$UseIPC = $False
)

<#======================================================================================
         File Name : AutoCert.ps1
   Original Author : Kenneth C. Mazie (kcmjr AT kcmjr.com)
                   : 
       Description : Automatically processes VPN certificates on a weekly schedule.
                   : 
             Notes : Normal operation is with no command line options. Requires certutil.exe. exists on system execting script.
                   : Create files in cert store named "username.update" to trigger the update section manually.
                   : Run via a scheduled task to run as needed.
                   :
         Arguments : Note - Any combination of arguments may be used at once.
                   : "-console $true" option to display runtime info on the console. 
                   : "-debug $true"   includes a status email to debug user(s) only.  Use for troubleshooting
                   :     NOTE - As currently set a "debugging" email goes out BCC to the debug user(s) each 
                   :     time a user email is sent.  See "sendemail" function...
                   : "-status $true"  sends status results to the status user(s) only.  Use for managers, etc who insist on reports.
                   :
          Warnings : See end of file for configuration file settings and example !!!
                   :   
             Legal : Public Domain. Modify and redistribute freely. No rights reserved.
                   : SCRIPT PROVIDED "AS IS" WITHOUT WARRANTIES OR GUARANTEES OF 
                   : ANY KIND. USE AT YOUR OWN RISK. NO TECHNICAL SUPPORT PROVIDED.
                   :
           Credits : Code snippets and/or ideas came from many sources including but 
                   :   not limited to the following:
                   : 
   Original Author : Unknown via the Internet.  Modded by Tyler Applebaum for use in production environemnt.
    Last Update by : Kenneth C. Mazie 
   Version History : v1.00 - 06-01-14 - Original
    Change History : v2.00 - 07-13-15 - Major rewrite.   
                   : v2.10 - 08-13-15 - Added option to send update notices.    
                   : v2.10 - 04-18-16 - Added bypass for admin accounts
                   : v3.00 - 05-26-16 - Added option to create stand alone certs
                   : v3.10 - 08-10-16 - fixed bug that caused script to abort on every run
                   : v3.20 - 08-15-16 - Added option to include requestor in email if force is used.
                   : v3.30 - 08-19-16 - Added eventlog tracking and improved debug messaging
                   : v4.00 - 08-29-16 - Branched to AutoCert variant.  Added try/catch to snag errors.
                   : v4.10 - 09-20-16 - Numerous coding changes and bug fixes.  Mostly in output.
                   : v5.00 - 01-13-17 - Fixed for use with DFS share.  Numerous changes. Fixed status email.
                   : v5.10 - 02-08-17 - fixed notice email attachments throwing error and stopping email from sending.
                   :                    adjusted message text.  changed so reply to is no longer the user.  Added BCC.
                   :                    disabled force option.  Added user first name to email.
                   : v5.10 - 02-16-17 - fixed issue with detecting console color.
                   : v5.20 - 03-29-17 - added error checking to generation function.
                   : v5.30 - 04-14-17 - Added better handling of stsus users.
                   : v5.40 - 04-20-17 - Added error checks to make sure temp folder works for service account running script.
                   :                    Expanded list of bypass patterns.
                   : v5.50 - 04-21-17 - Retooled email system.  Adjusted logging.  Removed un-needed code.
                   : v5.60 - 06-20-17 - Commented out line 635 for cleaning up variables.
                   : v5.61 - 03-02-18 - Minor notation tweak for PS Gallery upload.  Moved more variables out to config file.
                   : v6.00 - 05-01-18 - Major rewrite to include W2012 certifcate commandlets and fix folder permission issues.
                   :
=======================================================================================#>
<#PSScriptInfo
.VERSION 6.00
.GUID 39d43bd3-0d21-4060-b4ce-eafc88302f57
.AUTHOR Kenneth C. Mazie (kcmjr AT kcmjr.com)
.DESCRIPTION 
 Automatically creates VPN certificates based on expiration date of exisiting cert.
#> 

Clear-Host 
$ErrorActionPreference = "silentlyContinue"

If ($Console){$Script:Console = $true}
If ($Debug){$Script:Debug = $true}
If ($Status){$Script:Status = $true}
If ($UseIPC){$Script:UseIPC = $true}

$Computer = $Env:ComputerName
$Script:ScriptName = ($MyInvocation.MyCommand.Name).split(".")[0] 
$Script:LogFile = $PSScriptRoot + "\"+$ScriptName + "_{0:MM-dd-yyyy_HHmmss}.log" -f (Get-Date)
$Script:ConfigFile = "$PSScriptRoot\$ScriptName.xml" 

$Script:ConsoleEmail = $true #--[ Use this to enable sending of a debug email any time an operation is performed. ]--
$Script:ConsoleEmailOK = $false #--[ Used as a flag by the script to determine whether to send a debug email.  Don't change this ]--

$Script:Datetime = Get-Date -Format "MM-dd-yyyy_HH:mm"
$Script:EmailMsg = ""
$ErrorMessage = ""
$FailedItem = ""
$Script:Installed = $False
$Script:Counter = 0
$Script:DebugLogMsg = @()
$Script:EventLogMsg = ""
$Script:TempDir = "$env:temp" #--[ *** Temporary local folder *** ]--
$IllegalUser = $False
$Script:Attach = $false
$Script:NotifyUser = $False
$DarkConsole = ((Get-Host).UI.RawUI.BackgroundColor -like "*Dark*") #--[ Detect console color and adjust accordingly ]------------------------------
$ScriptColor = @{
	1 = "Green"
	2 = "Red"
	3 = "Yellow"
	4 = "Blue"
	5 = "Cyan"
	6 = "Magenta"
	7 = "Gray"
	8 = "White"
	9 = "Black"
	11 = "DarkGreen"
	12 = "DarkRed"
	13 = "DarkCyan"
	14 = "DarkBlue"
	15 = "DarkCyan"
	16 = "DarkMagenta"
	17 = "DarkGray"
	18 = "Gray"
	19 = "Black"
}

#--[ Read and load configuration file ]-----------------------------------------
If (!(Test-Path "$PSScriptRoot\$ScriptName.xml")){ #--[ Error out if configuration file doesn't exist ]--
	Write-host "MISSING CONFIG FILE.  Script aborted." -ForegroundColor red
	break
}Else{
	[xml]$Script:Configuration = Get-Content "$PSScriptRoot\$ScriptName.xml" #--[ Load configuration ]--
	$Script:CompanyName = $Script:Configuration.Settings.General.CompanyName
	$Script:CompanyInitials = $Script:Configuration.Settings.General.CompanyInitials #--[ Used to prefix files and notations ]--
	$Script:SupportPhone = $Script:Configuration.Settings.General.SupportPhone
	$Script:Title = $Script:Configuration.Settings.General.ReportTitle 
	$Script:DebugUser = $Script:Configuration.Settings.Email.DebugUser
	$Script:StatusUser = $Script:Configuration.Settings.Email.StatusUser
	$Script:DebugSubject = $Script:Configuration.Settings.Email.DebugSubject 
	#$Script:EmailTo = $Script:Configuration.Settings.Email.To                  #--[ Determined by script ]--
	$Script:EmailHTML = $Script:Configuration.Settings.Email.HTML
	$Script:EmailSubject = $Script:Configuration.Settings.Email.Subject
	$Script:EmailFrom = $Script:Configuration.Settings.Email.From
	$Script:EmailDomain = $Script:Configuration.Settings.Email.Domain
	$Script:SmtpServer = $Script:Configuration.Settings.Email.SmtpServer
	$Script:UserName = $Script:Configuration.Settings.Credentials.Username
	$Script:Password = $Script:Configuration.Settings.Credentials.Password
	$Script:Key = $Script:Configuration.Settings.Credentials.Key
	$Script:VPNPassword = $Script:Configuration.Settings.Credentials.VPNPassword
	$Script:VPNUsers = $Script:Configuration.Settings.General.VPNGroup
	$Script:EventlogName = $Script:Configuration.Settings.General.EventlogName
	$Script:EventlogID = $Script:Configuration.Settings.General.EventlogID
	$Script:EventlogType = $Script:Configuration.Settings.General.EventlogType
	$Script:CertStore = $Script:Configuration.Settings.General.CertStore 
	$Script:Attach1 = $Script:Configuration.Settings.Email.Attachments.Attach1
	$Script:Attach2 = $Script:Configuration.Settings.Email.Attachments.Attach2
	$Script:Attach3 = $Script:Configuration.Settings.Email.Attachments.Attach3
	$Script:BadPattern = $Script:Configuration.Settings.General.BadPattern #--[ Anything matching this pattern is bypassed.  Use for admin accounts ]--
	$Script:TemplateName = $Script:Configuration.Settings.General.TemplateName
	$Script:CAName = $Script:Configuration.Settings.General.CaName 
	$Script:BA = [System.Convert]::FromBase64String($Script:Key)
	$Script:SC = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Script:Username, ($Script:Password | ConvertTo-SecureString -Key $Script:BA)
	$Script:SP = $SC.GetNetworkCredential().Password 
} 

#-------------------------------------------------------------------------------

[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") #--[ Assembly required for balloon tips ]--
Try{
    New-EventLog -LogName Application -Source $Script:EventlogName -ErrorAction SilentlyContinue #--[ Register new eventlog type ]--
}Catch{
}    

#==[ Functions ]================================================================
Function MessageLog ($Mode, $MsgText, [Int]$MsgColor){ #--[ Compiles and writes log out to the local eventlog and for email ]--
	$Script:EventLogMsg += "$MsgText`n"
	If ($Script:Console -and ($mode -ne "DebugLogOnly")){ #--[ Only used in certain places. Don't alter this or you will break the status email ]--    
		If ($DarkConsole){
			$Color = $ScriptColor[$MsgColor]
		}Else{
			$Color = $ScriptColor[($MsgColor + 10)]
		} 
		If ($MsgText -eq "HR"){
			Write-host "`n===============================================================`n" -ForegroundColor $Color
		}Else{
			write-host $MsgText -ForegroundColor $Color
		}
	}

	If ($Mode -ne "ConsoleOnly"){ #--[ Only used in certain places. Don't alter this or you will break the status email ]--
		$Color = $ScriptColor[($MsgColor + 10)]
		If ($MsgText -eq "HR"){$MsgText = "<br>===============================================================<br>"}
		$Script:DebugLogMsg += "<font color="+$Color + ">"+"$MsgText</font><br>"
	}
}

Function SendEmail {
	$Smtp = new-object Net.Mail.SmtpClient($Script:SmtpServer)
	$Email = New-Object System.Net.Mail.MailMessage
	$Email.From = "$Script:EmailFrom@$Script:EmailDomain"
	$Email.Subject = $Script:EmailSubject
	$Email.Body = $Script:EmailMsg 
	If ($Script:EmailHTML){$Email.IsBodyHtml = $true}
	If ($Script:Attach){                            #--[ Attachments should include "USER.pfx", "Root.p7b", "Intermediate.p7b, install doc" ]--
		Try{
			$Email.Attachments.Add($Script:EmailAttach1)
			$Email.Attachments.Add($Script:EmailAttach2)
			$Email.Attachments.Add($Script:EmailAttach3)
			$Email.Attachments.Add($Script:EmailAttach4)
		}Catch{
			$ErrorMessage = $_.Exception.Message
			$FailedItem = $_.Exception.ItemName
			$Email.Subject = $Script:EmailSubject + "- EMAIL FAILURE REPORT -"
			$Email.Body = "- ATTACHMENT FAILURE REPORT -<br>"+$_.Exception.Message+' <br> '+$_.Exception.ItemName
			$Email.To.Add("$Script:DebugUser@$Script:EmailDomain")
			$Script:NotifyUser = $False
		} 
	}

	If ($Script:NotifyUser){                                                               #--[ Email target user ]--
		$Email.To.Add("$Script:TargetUser@$Script:EmailDomain")
		MessageLog "Both" "-- Target user added to email --" "3"
	}

	If (!($Script:Debug)){                                                                 #--[ Email debug user(s) ]--
		$Email.Bcc.Add("$Script:DebugUser@$Script:EmailDomain")                            #--[ Always BCC debug user(s) as a safety check ]--
		MessageLog "Both" "-- Debug user(s) added as BCC to email --" "3"
	}

	If ($Script:NotifyUser){ 
		$Smtp.Send($Email)
		MessageLog "Both" "===== Target user notification email Sent =====`n" "1"
	}Else{
		MessageLog "Both" "===== NO TARGET USER EMAIL SENT =====`n" "3"
	}

	$Smtp.Dispose()
	$Email.Dispose() 

	$Script:NotifyUser = $False
	StatusEmail 
}

Function StatusEmail {
	If (((Get-Date -Format dddd) -eq "Monday") -or ($Script:Debug) -or ($Script:Status)){ #--[Only send status mail on mondays or when debugging ]--
		$StatusEmail = New-Object System.Net.Mail.MailMessage 
		$StatusSmtp = new-object Net.Mail.SmtpClient($Script:SmtpServer)
		$StatusEmail.From = "$Script:EmailFrom@$Script:EmailDomain"
		If ($Script:EmailHTML){$StatusEmail.IsBodyHtml = $true}

		If ($Script:Debug){
			$StatusEmail.Subject = $Script:DebugSubject
			$StatusEmail.To.Add("$Script:DebugUser@$Script:EmailDomain") #--[ Always copy debug user(s) as a safety check ]--
			MessageLog "Both" "-- Debug user(s) added to email --" "3"
		}

		If (((Get-Date -Format dddd) -eq "Monday") -or ($Script:Status)){
			$StatusEmail.Subject = "VPN Certificate Status Check" 
			ForEach ($User in $Script:StatusUser.User){
				$StatusEmail.To.Add("$User@$Script:EmailDomain") #--[ Send to status user only if option was specified ]--
			}
			MessageLog "Both" "-- Status user(s) added to email --" "3"
		}

		MessageLog "Both" "===== Status and Debugging Email Sent =====`n" "1"
		$StatusEmail.Body = $Script:DebugLogMsg 
		$StatusSmtp.Send($StatusEmail)
	}Else{
		MessageLog "Both" "====== NO STATUS EMAILS SENT =====`n" "2"
	} 
}

Function PurgeLocalStore { #--[ Purge local store ]-------------------------------------------------------------
	MessageLog "Both" "-- Purging any old certificates from the local store --" "3"
	Try{
		Get-ChildItem cert:\currentuser\my | ?{ $_.Subject -eq "CN=$Script:TargetUser"} | %{ 
			$xcert = $_
			$xstore = New-Object System.Security.Cryptography.X509Certificates.X509Store "my", "currentuser"
			$xstore.Open("ReadWrite")
			$xstore.Remove($xcert)
			$xstore.Close()
			Sleep -Seconds 1
		} 
	}catch{
		MessageLog "Both" $_.Exception.Message "2" 
		MessageLog "Both" $_.Exception.ItemName "2" 
	} 
}

Function PurgeTemp { #--[ Clean out temp folder ]-----------------------------------------------------------
    MessageLog "Both" "-- Purging work files from local temp folder as needed --" "3"
	If (Test-Path "$Script:TempDir\*.inf"){Remove-Item "$Script:TempDir\*.inf" -ErrorAction silentlycontinue -Force:$true}
	If (Test-Path "$Script:TempDir\*.req"){Remove-Item "$Script:TempDir\*.req" -ErrorAction silentlycontinue -Force:$true}
	If (Test-Path "$Script:TempDir\*.cer"){Remove-Item "$Script:TempDir\*.cer" -ErrorAction silentlycontinue -Force:$true}
	If (Test-Path "$Script:TempDir\*.p7b"){Remove-Item "$Script:TempDir\*.p7b" -ErrorAction silentlycontinue -Force:$true}
	If (Test-Path "$Script:TempDir\*.pfx"){Remove-Item "$Script:TempDir\*.pfx" -ErrorAction silentlycontinue -Force:$true}
	If (Test-Path "$Script:TempDir\*.rsp"){Remove-Item "$Script:TempDir\*.rsp" -ErrorAction silentlycontinue -Force:$true}
	If (Test-Path "$Script:TempDir\*.docx"){Remove-Item "$Script:TempDir\*.docx" -ErrorAction silentlycontinue -Force:$true}
}

Function GenerateNewRequest { #--[ Generate new request file ]------------------------------------------------
	MessageLog "Both" "-- Generating new certificate request file --" "3" 
	add-content $Script:TempDir\usercert.inf "[NewRequest]`r
	Subject = `"CN=$Script:TargetUser`"`r
    Exportable = TRUE`r 
	RequestType = CMC`r
	[RequestAttributes]`r
	CertificateTemplate = `"$Script:TemplateName`"`r
    SAN = `"Email=$Email`""

	#--[ Compile the request file ]--------------------------------------------
	MessageLog "Both" "-- Compiling certificate request --" "3"
	Try{
		$Result = C:\Windows\system32\certreq.exe -new $Script:TempDir\usercert.inf $Script:TempDir\usercert.req
	}Catch{
		$Script:DebugSubject = $ErrorMessage
		MessageLog "Both" "Build Cert               : $_.Exception.Message" "7"
		StatusEmail
		break;break;break 
	}
}

Function SubmitNewRequest { #--[ Send request to authority ]--------------------------------------------
	MessageLog "Both" "-- Submitting certificate request to CA --" "3" 
	Try{ 
		#Get-Certificate -Template $Script:TemplateName -DnsName bankofstockton.com -Url http://pki/certsrv/ -Credential $SC -CertStoreLocation cert:\CurrentUser\My
		$Result = C:\Windows\system32\certreq.exe -submit -config "$Script:CertAuthName" $Script:TempDir\usercert.req $Script:TempDir\usercert.cer
	}Catch{
		$Script:DebugSubject = $ErrorMessage
		MessageLog "Both" "Request Cert               : $_.Exception.Message" "7"
		StatusEmail
		break;break;break 
	} 
	$ID = $Result.Split(" ")[1]
	MessageLog "Both" "-- Request ID --$ID" "3" 
}

Function InstallCertificate { #--[ Install certificate on local machine ]--------------------------------- 
	MessageLog "Both" "-- Importing certificate to local store --" "3"
	Try{
		$result = Import-Certificate -FilePath $Script:TempDir\usercert.cer -CertStoreLocation Cert:\CurrentUser\My
		#C:\Windows\system32\certreq.exe -accept $Script:TempDir\usercert.cer
		$Script:Installed = $true 
	}Catch{
		$ErrorMessage = $_.Exception.Message
		$FailedItem = $_.Exception.ItemName
		$Script:DebugSubject = $ErrorMessage
		MessageLog "Both" "Install cert on local     : $ErrorMessage" "7"
		StatusEmail
	} 
}

Function ExportCertificate { #--[ Export certificate from local store ]----------------------------------------
	MessageLog "Both" "-- Exporting certificate to work folder  --" "3" 
	Try{
		#--[ If the next line fails using a variable hard code the ca search as "CN=CA1\CA1*".  ]--
		#     dir cert:\currentuser\my | ? { $_.hasPrivateKey -and $_.Subject -like "*$Script:TargetUser*" -and $_.PrivateKey.CspKeyContainerInfo.Exportable -and $_.Subject -notlike "*E=*" -and $_.Issuer -like "CN=$Script:CertAuthName*"} | Foreach-Object {[IO.file]::WriteAllBytes("$Script\TempDir\$Script:TargetUser.pfx", ($_.Export('PFX', $Script:VPNPassword)))} #Find VPN cert and exclude internal User cert
		$SecPwd = (ConvertTo-SecureString -String $Script:VPNPassword -Force -AsPlainText)
		$Certificate = Get-ChildItem -Path Cert:\currentuser\My | Where-Object {$_.Subject -like "*$Script:TargetUser*"}
		$CertificateExport = $Script:CertStore + '\' + $Script:TargetUser + '.pfx'
		$Result = Export-PfxCertificate -Cert $Certificate.PSPath -FilePath $CertificateExport -Password $SecPwd
	}Catch{
		$Script:DebugSubject = $ErrorMessage
		MessageLog "Both" "Export Cert               : $_.Exception.Message" "7"
		StatusEmail
		break;break;break
	}

	MessageLog "Both" "-- Detecting exported PFX certificate file --" "3"
	While (!(Test-Path "$Script:CertStore\$Script:TargetUser.pfx")){
		Sleep 2
		$Script:Counter ++
		If ($Script:Counter -ge 5){
			MessageLog "Both" "-- Failure to detect newly generated certificate in backup location." "2"
       		StatusEmail
    		break;break;break
		}
	} 
}

Function GenerateCert {
	$ErrorActionPreference = "stop" 
	$Script:CertAuthName = $Script:CaName + "\"+$Script:CaName
	PurgeLocalStore
	PurgeTemp 
	GenerateNewRequest
	SubmitNewRequest 
	InstallCertificate
	ExportCertificate

	MessageLog "Both" "-- Preparing certificate files for mailing --" "3"
	#--[ Copy cert files to local temp folder for email attach, otherwise path causes an error ]--    
	Copy-Item -Path ($Script:CertStore + "\"+$Script:Attach1) -Destination $Script:TempDir -Force:$true -Confirm:$false 
	$Script:EmailAttach1 = "$Script:TempDir\$Script:Attach1"
	Copy-Item -Path ($Script:CertStore + "\"+$Script:Attach2) -Destination $Script:TempDir -Force:$true -Confirm:$false 
	$Script:EmailAttach2 = "$Script:TempDir\$Script:Attach2"
	Copy-Item -Path ($Script:CertStore + "\"+$Script:Attach3) -Destination $Script:TempDir -Force:$true -Confirm:$false 
	$Script:EmailAttach3 = "$Script:TempDir\$Script:Attach3"
	Copy-Item -Path ($Script:CertStore + "\"+$Script:TargetUser + ".pfx") -Destination $Script:TempDir -Force:$true -Confirm:$false 
	$Script:EmailAttach4 = $Script:TempDir + "\"+$Script:TargetUser + ".pfx"
	$Script:Attach = $true

	MessageLog "Both" "-- Emailing user --" "3" 
	If (Test-Path $Script:EmailAttach4){
		$Script:EmailMsg = $Script:TargetFName.givenName+',<br><br>This is an automated email from the '+$Script:CompanyName + ' VPN server.<br>
		The system has generated an updated VPN certificate for you. The required files are attached.<br><br>
		Please download and install the attached certificates on your personal computer in order to<br>
		allow you to connect to, or continue to connect to the '+$Script:CompanyName+' VPN.<br><br>
		If four files are NOT attached to this email please contact IT Support.<br><br>
		Once the attachments are saved, right click on the <strong>'+$Script:CompanyInitials+'-Root.p7b</strong> file and select "Install Certificate"<br> 
		(			Click Next, Browse and select Trusted Root Certification Authorities, click OK,<br> 
			Next, Finish, click Yes on the warning). After that, right click on the <strong>'+$Script:CompanyInitials+'-Issuing.p7b</strong><br> 
		file and select "Install Certificate" (Click Next, Next, Finish).<br><br>Do the same on your personal 
		'+$Script:TargetUser+' certificate (Click Next, Next, enter the password, Next, Next, Finish).<br><br>
		The password to import your personal certificate is lowercase "'+$Script:VPNPassWord+'" (no quotes).<br><br>
		Please retain this email for reference. This will be the only notice sent.<br><br>
		Contact Support at '+$Script:SupportPhone+' or reply to this email if you have issues or questions.<br><br>
		'+$Script:CompanyName+' IT Network Department'
		$Script:NotifyUser = $true
		SendEmail #--[ Send the user email ]--
	}Else	{
		$Script:EmailMsg = 'This is an automated email from the '+$Script:CompanyName + ' VPN server.<br><br>
		There was an issue in the creation of your VPN certificate. IT Support has been<br>
		notified automatically. They will contact you shortly.'
		$Script:NotifyUser = $true
		SendEmail #--[ Send the user email ]--
	}
}

#==[ End Of Functions ]===========================================================================================================

MessageLog "Both" "=============== VPN Certificate Inpection Script Initializing ===============`n" "5" 
MessageLog "Both" "Script executed from server : $Env:ComputerName on $Script:DateTime" "7"
MessageLog "Both" "Certificate store           : $Script:CertStore" "7"
#--[ Determine OS version ]------------------------------------
$OSver = (Get-WmiObject Win32_OperatingSystem).Version
[int]$OS = $OSver -replace ".{6}$"
If ($OS -lt [int]6.2) {
	MessageLog "Both" "`n-- This script requires Windows 8.1 or Server 2012 due to certificate commandlets in use. --" "2"
	Exit
}Else{
	MessageLog "Both" "Windows OS version verified : $OSver" "7"
}

#--[ OPTIONAL: Make an IPC connection to the CertStore ]--
If ($Script:UseIPC){
	net use \\$Script:CertStore\ipc$ /user:$Script:UN $SP | Out-Null #--[ Use if connection issues occur ]--
} 

$Email = "$Script:TargetUser@$Script:EmailDomain" 

Try{                #--[ Test for the ability to write to the cert store ]--
	Add-Content -Value "X" -Path $Script:CertStore'\-ScriptFlag-.txt' -Force:$true -ErrorAction Stop -Confirm:$false 
	$X = Get-Content -Path $Script:CertStore'\-ScriptFlag-.txt' -ErrorAction:Stop
	Remove-Item -Path $Script:CertStore'\-ScriptFlag-.txt' -Force:$true -ErrorAction Stop -Confirm:$false
}Catch{
	$ErrorMessage = $_.Exception.Message
	$FailedItem = $_.Exception.ItemName
	$Script:DebugSubject = "Script failure during CERTSTORE check. "
	MessageLog "Both" "Script failure during CERTSTORE check. " "7"
	MessageLog "Both" "Error Message             : $ErrorMessage" "7"
	MessageLog "Both" "Failed Item               : $FailedItem" "7"
	$Script:Debug = $true
	$Script:NotifyUser = $False
	StatusEmail
	Break;break;break
} 

Try{                #--[ Test for the ability to write to the temp work folder ]--
	Add-Content -Value "X" -Path $Script:TempDir'\-ScriptFlag-.txt' -Force:$true -ErrorAction Stop -Confirm:$false 
	$X = Get-Content -Path $Script:TempDir'\-ScriptFlag-.txt' -ErrorAction Stop
	Remove-Item -Path $Script:TempDir'\-ScriptFlag-.txt' -Force:$true -ErrorAction Stop -Confirm:$false
}Catch{
	$ErrorMessage = $_.Exception.Message
	$FailedItem = $_.Exception.ItemName
	$Script:DebugSubject = "Script failure during TEMP check."
	MessageLog "Both" "Script failure during TEMP check. " "7"
	MessageLog "Both" "Error Message             : $ErrorMessage" "7"
	MessageLog "Both" "Failed Item               : $FailedItem" "7"
	$Script:Debug = $true
	$Script:NotifyUser = $False
	StatusEmail
	Break;break;break
}

Try{
	If ($Script:Debug){
		$GroupMembers = Get-ADUser -Identity $Script:DebugUser -Properties * -Credential $Script:SC
	}Else{ 
		$GroupMembers = Get-ADGroupMember -Identity $Script:VPNUsers -Credential $Script:SC | Sort Name
	} 
	MessageLog "Both" "HR" "2" #--[ Inserts a hard rule ]--
	Foreach ($Member in $GroupMembers){
		$Script:EventLogMsg = @() #New-Object System.Collections.ArrayList
		$Script:TargetUser = $Member.SamAccountName.ToUpper() 
		$Script:TargetFName = Get-AdUser -Identity $Script:TargetUser -Properties * -Credential $Script:SC

		MessageLog "Both" "-- VPN Certificate Inspection is executing for target user: $Script:TargetUser --" "5"

		#==[ This section is for MANUAL processing.  It has been disabled for this version of the script but left in for reference ]==
		#
		#$Script:TargetUser = $env:username        #--[ Sets the target user to the current session username variable ]--
		#$Script:EmailTo = $env:username            #--[ Set the destination email to the same as above ]--
		#
		#If($Script:Force){   #--[ Adjustments for targeted execution ]--
		#    $Script:TargetUser = Read-Host -Prompt "Enter Target User ID:  (- DO NOT include a domain and extension - To abort leave the User ID blank -)"
		#    If (($Script:TargetUser -eq "") -or($Script:TargetUser -eq $Null)){
		#        MessageLog "Both" "NOTICE: VPN Certificate Script execution terminated due to a blank user ID..." "2"
		#        Write-EventLog -LogName Application -Source VPN_PowerShell -EntryType Information -EventId 12345 -Message $Script:EventLogMsg
		#        break
		#    }
		#    $Script:EmailAlternate = Read-Host -Prompt "Enter YOUR user ID.  A copy of the email will be sent to you as a failsafe."
		#    $Script:EmailTo = $Script:TargetUser
		#}
		#
		#If (($env:username -eq "testuser") -or ($env:username -eq $Script:DebugUser)){    #--[ Additional adjustments for debugging ]--
		#    $Script:TargetUser = "testuser"
		#    $Script:EmailTo = "user1"
		#}
		#==============================================================================================================================

        #--[ This section may be omitted if exclusively using the new PS cert commandlets ]--
		If ((!(Test-Path "c:\Windows\System32\certutil.exe")) -or (!(Test-Path "c:\Windows\Syswow64\certutil.exe"))){
			MessageLog "Both" "-- Certutil was not found on system ! --" "2"
			Write-EventLog -LogName Application -Source $Script:EventlogName -EntryType $Script:EventlogType -EventId $Script:EventlogID -Message ($Script:EventLogMsg | out-string)
			$Script:Debug = $true
			$Script:NotifyUser = $False
			StatusEmail
			Break;break;break
		}

		#--[ Detect illegal users ]----------------------------------------------------------------
		ForEach ($Pattern in $Script:BadPattern.Pattern){
			if ($Script:TargetUser -like $Pattern){
				$IllegalUser = $True
			} 
		} 

		if (!($IllegalUser)){
			If (Test-Path "$Script:CertStore\$Script:TargetUser.update"){ 
                #==========================================================================================================
				#--[ NON-STANDARD OPERATION: Force an email to user due to some out-of-cycle update.                    ]--
				#--[ This section normally will never fire.  Manually add a "user.update" file to trigger for a user.   ]--
				#--[ This flag file will preempt ALL other detection.                                                   ]--
                #==========================================================================================================
				MessageLog "Both" "-- Detected an UPDATE flag file.  Removing update flag file and sending notification email --" "3" 
				Remove-item "$Script:CertStore\$Script:TargetUser.update" -ErrorAction stop -Force -Confirm:$False

				$Script:EmailMsg = $Script:TargetFName.givenName+',<br><br>This is an automated courtesy email from the '+$Script:CompanyName + ' VPN server.<br><br>
				Please do NOT reply to it, this is an unmonitored email address.<br><br>
				We have made changes to the encryption protocols used on the VPN that require you to update the security<br>
				certificates installed on your PC so that they match the ones used for the '+$Script:CompanyName+' computer systems.<br><br> 
				Attached to this email you will find copies of the '+$Script:CompanyName+' updated Public Key Infrastructure root certificates.<br><br>
				Please install the files as described in the included instruction document.<br><br>
				It is not necessary to re-install your personal certificate, it is being included for completeness.<br><br>
				Please contact Support at '+$Script:SupportPhone+' if you have issues or questions.<br><br>
				This will be the only notice sent.<br><br>
				'+$Script:CompanyName+' IT Network Department'
				$Script:NotifyUser = $True
				SendEmail
			}Else{    #--[ NORMAL OPERATION continues here... ]--
				If (Test-Path "$Script:CertStore\$Script:TargetUser.pfx"){
					MessageLog "Both" "-- Existing certificate found --" "1"
					$CertDump = certutil -p $Script:VPNPassword -dump ("$Script:CertStore\$Script:TargetUser.pfx").tostring() 
					$CertLogDump = @()
					$CertLogDump = certutil -p $Script:VPNPassword -dump ("$Script:CertStore\$Script:TargetUser.pfx").tostring() 
					$CertTmp1 = ""
					$CertTmp2 = ""

					foreach ($LineIn in $CertLogDump){
						$CertTmp1 += ($LineIn + "`n")
						$CertTmp2 += "<font color="+$ScriptColor[16]+">$LineIn</font><br>" 
					}
					MessageLog "ConsoleOnly" $CertTmp1 "6"
					MessageLog "DebugLogOnly" $CertTmp2 "6"
                    
                    #--------------------------------------------------------------------------------------------------------------------------------
					#--[ NOTE: Dumpfile parsing is unreliable and gives differing results on various machines.  This routine finds the first date ]--
                    #--------------------------------------------------------------------------------------------------------------------------------
					$Line3 = (((($CertDump -split "`r")[3]) -split " ")[2]) -as [datetime]
					$Line4 = (((($CertDump -split "`r")[4]) -split " ")[2]) -as [datetime]
					$Line5 = (((($CertDump -split "`r")[5]) -split " ")[2]) -as [datetime]
					$Line6 = (((($CertDump -split "`r")[6]) -split " ")[2]) -as [datetime]
					If ($Line3){ 
						$CreationDate = ((($CertDump -split "`r")[3]) -split " ")[2] #command formatted to work on PowerShell v2
						$ExpireDate = ((($CertDump -split "`r")[4]) -split " ")[2]   #command formatted to work on PowerShell v2    
					}elseIf ($Line4){
						$CreationDate = ((($CertDump -split "`r")[4]) -split " ")[2] #command formatted to work on PowerShell v3
						$ExpireDate = ((($CertDump -split "`r")[5]) -split " ")[2]   #command formatted to work on PowerShell v3
					}elseif ($Line5){
						$CreationDate = ((($CertDump -split "`r")[5]) -split " ")[2] #command formatted to work on PowerShell v4
						$ExpireDate = ((($CertDump -split "`r")[6]) -split " ")[2]   #command formatted to work on PowerShell v4
					}elseif ($Line6){
						$CreationDate = ((($CertDump -split "`r")[6]) -split " ")[2] #command formatted to work on PowerShell v5
						$ExpireDate = ((($CertDump -split "`r")[7]) -split " ")[2]   #command formatted to work on PowerShell v5
					} 
					$CreationDate = get-date $CreationDate -f "MM-dd-yyyy"

					MessageLog "Both" ($MsgText = '-- Cert Creation Date : '+$CreationDate) "3" 
					$ExpireDate = get-date $ExpireDate -f "MM-dd-yyyy"
					MessageLog "Both" ($MsgText = '-- Cert Expire Date   : '+$ExpireDate) "3" 
					$Today = Get-Date -f "MM-dd-yyyy"
					MessageLog "Both" ($MsgText = '-- Today is           : '+$Today) "3" 
					$Remaining = NEW-TIMESPAN –Start $Today –End $ExpireDate
					$Remaining = [math]::abs($Remaining.Days)
					MessageLog "Both" "-- $Remaining days left until expiration --" "1"

					#--[ UNCOMMENT AND CHANGE THESE TO TEST EXPIRATION TRIGGERS DURING DEBUGGING ]-------------
					#    If ($Script:TargetUser -eq $Script:DebugUser){
					#        $Remaining = 14
					#        MessageLog "Both" ("-- TESTING: Days until expire adjusted to  : "+$Remaining) "2"     
					#    }
					#--[ UNCOMMENT AND CHANGE THESE TO TEST EXPIRATION TRIGGERS DURING DEBUGGING ]-------------

					#--[ Determine what to do depending on number of remaining days ]----------------
					If ($Remaining -le 15){ #--[ 15 days until certificate expires.  Generate a new one and send. ]--
						MessageLog "Both" "-- Less than 15 days is remaining. Clearing flag file.  Generating new cert.  Archiving old cert." "3" 
						If (Test-Path "$Script:CertStore\$Script:TargetUser.flag"){remove-item "$Script:CertStore\$Script:TargetUser.flag" -Force -Confirm:$False }
						[string]$Script:BackupName = $Script:TargetUser + "_$ExpireDate.pfx.old"
						If (Test-Path "$Script:CertStore\$Script:TargetUser.pfx"){
							If ($Script:Console){
								Write-Host "Renaming and Relocating: " -ForegroundColor "3" -NoNewline 
								Write-Host $Script:CertStore"\"$Script:TargetUser.pfx -ForegroundColor "5" -NoNewline
								Write-Host " to: " -ForegroundColor "3" -NoNewline 
								Write-Host $Script:CertStore"\Backups\"$Script:BackupName -ForegroundColor "6" 
							}
							try{
								If (Test-Path "$Script:CertStore\$Script:TargetUser.pfx"){
									rename-item "$Script:CertStore\$Script:TargetUser.pfx" $Script:CertStore"\"$Script:BackupName -ErrorAction stop -Force -Confirm:$False
									move-Item $Script:CertStore"\"$Script:BackupName -Destination $Script:CertStore"\backups\"$Script:BackupName -ErrorAction stop -Force -Confirm:$False
								}
							}catch{
								MessageLog "Both" $_.Exception.Message "2" 
								MessageLog "Both" $_.Exception.ItemName "2" 
							}
						}
						GenerateCert
					}ElseIf ($Remaining -le 30){ #--[ NOTIFY USER.  Certificate due to expire. ]--
						If (!(Test-Path "$Script:CertStore\$Script:TargetUser.flag")){
							MessageLog "Both" "-- Less than 30 days is remaining.  Writing flag file.  Sending warning email --" "3" 
							Add-Content -Path "$Script:CertStore\$Script:TargetUser.flag" -Value "30 day notice"

							$Script:EmailMsg = $Script:TargetFName.givenName+',<br><br>This is an automated courtesy email from the '+$Script:CompanyName + ' VPN server.<br><br>
							We store a copy of your VPN certificate as a backup. This backup is automatically scanned<br>
							every two to three days and the expiration date is checked. <br><br>
							'+$Script:TargetUser+' Certificate Statistics:<br>
							Created on: '+$CreationDate+'<br>
							<strong>Expires on: '+$ExpireDate+'</strong><br><br>
							Your '+$Script:CompanyName+' VPN certificate is due to expire within 30 days. There is <br>
							nothing you need to do except be aware of this fact. Within approximately 15 days you will<br>
							be emailed a new certificate with instructions on how to install it. Please watch for it.<br><br>
							If after 3 weeks you have not received it, please contact support at '+$Script:SupportPhone+'.<br><br>
							If your certificate expires you will be unable to use the company VPN to connect to the network.<br><br>
							This will be the only notice sent. Please reply to this email should you have any questions.<br><br>
							'+$Script:CompanyName+' IT Network Department'
							$Script:NotifyUser = $true
							SendEmail #--[ This is just a notification. ]--
						}Else{
							MessageLog "Both" "-- Less than 30 days is remaining.  Flag file exists.  Exiting --" "3" 
						}
					}Else{ #--[ Greater than 30 days remaining. Cleanup any old lingering flag files. ]--    
						If (Test-Path "$Script:CertStore\$Script:TargetUser.flag"){
							Try{ 
								MessageLog "Both" "-- Removing stale flag file" "3" 
								Remove-Item "$Script:CertStore\$Script:TargetUser.flag" -Force -Confirm:$false 
							}Catch{
								$ErrorMessage = $_.Exception.Message
								$FailedItem = $_.Exception.ItemName
							}
							MessageLog "Both" $ErrorMessage "2" 
							MessageLog "Both" $FailedItem "2" 
						}
						MessageLog "Both" "-- Greater than 30 days until certificate expiration.  NOTHING TO DO --" "1" 
					}

				}Else{ #--[ No existing certificate found in archive.  Generate a new one. ]--
					MessageLog "Both" "-- No VPN cert was found.  Generating a new one --" "3"
					$Global:EmailBody = $Script:EmailMsg
					GenerateCert
				}
			}
		}Else{
			MessageLog "Both" "-- Detected an invalid user account.  Admin and Service accounts are not permitted to use VPN.  Bypassing... --" "2"
		}

		If($Script:Installed){
			MessageLog "Both" ('-- Removing any '+$Script:TargetUser + ' certificates from local store --') "3" 
			If ($Script:TargetUser -ne $Env:Username){
				dir Cert:\CurrentUser -Recurse | ? subject -match $Script:TargetUser | Remove-Item #-WhatIf
			} 
			$Script:Installed = $False
		}

		MessageLog "Both" "`n-- VPN Certificate Processing Completed --" "5" 
		MessageLog "Both" "HR" "2" #--[ Inserts a hard rule ]--
		$IllegalUser = $False
		$Script:Attach = $false 
		$Script:NotifyUser = $False
		Write-EventLog -LogName Application -Source $Script:EventlogName -EntryType $Script:EventlogType -EventId $Script:EventlogID -Message ($Script:EventLogMsg | out-string)
		PurgeTemp #--[ Clean up files left in temp folder ]--------------------------
	}
}Catch{
	$ErrorMessage = $_.Exception.Message
	$FailedItem = $_.Exception.ItemName
	MessageLog "Both" $ErrorMessage "2" 
	MessageLog "Both" $FailedItem "2"
}

If ($Script:Console){
	Write-host "-- Debug Setting  : $Script:Debug" -Foreground Yellow
	Write-host "-- Status Setting : $Script:Status" -Foreground Yellow
	Write-host "-- Attach Setting : $Script:Attach" -Foreground Yellow
}

#--[ Disconnect from CertStore ]-----------------------
If ($Script:UseIPC){
	net use \\$Script:TargetSystem\ipc$ /d | Out-Null 
} 

MessageLog "Both" "`n-- VPN Script Completed --`n" "5" 
StatusEmail

[System.GC]::Collect()

<#--[ Configuration file example.  The file must be named same as script (autocert.xml) and be located with the script ]--

<!-- Settings & Configuration File -->
<Settings>
    <General>
        <CompanyName>My Company</CompanyName>
		<CompanyInitials>IBM</CompanyInitials>
		<SupportPhone></SupportPhone>
        <ScriptName>AutoCert.ps1</ScriptName>
        <VPNGroup>vpnusers</VPNGroup>                         <!-- AD group for VPN access -->
        <EventlogName>VPN_PowerShell</EventlogName>           
        <EventlogID>12345</EventlogID>
        <EventlogType>Information</EventlogType>
        <CertStore>\\mydomain\VPN$\VPN</CertStore>            <!-- Network share where certs are stored -->
        <TemplateName>VPNUserTemplate</TemplateName>          <!-- cert template name on your CA -->
        <CaName>PKICA1</CaName>                               <!-- name of your CA -->
        <BadPattern>
            <Pattern>*admin*</Pattern>                        <!-- AD accounts to exclude -->
            <Pattern>*service*</Pattern>
        </BadPattern>
    </General>
    <Email>
        <From>itnetwork</From>
        <To>This_field_not_used</To>
        <Subject>My Company VPN</Subject>
        <DebugSubject>VPN Certificate Status and Debugging Information</DebugSubject>
        <Domain>MyCompany.com</Domain>
        <HTML>$true</HTML>
        <SmtpServer>10.10.50.51</SmtpServer>
        <DebugUser>
            <User>User1</User>
        </DebugUser>
        <StatusUser>
            <User>user1</User>
            <User>user2</User>
            <User>user3</User>
            <User>user4</User>    
        </StatusUser>
        <Attachments>
            <Attach1>Root.p7b</Attach1>
            <Attach2>Issuing.p7b</Attach2>
            <Attach3>SSLVPN-Install.docx</Attach3>
        </Attachments>
    </Email>
    <Credentials>
        <UserName></UserName>
        <Password></Password>
        <VPNPassword>vpnpwd</VPNPassword>
    </Credentials>
</Settings>    

#>