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