'Copyright (c) Microsoft Corporation.  All rights reserved.

'Disclaimer
'
'This sample script is not supported under any Microsoft standard support 
'program or service. This sample script is provided AS IS without warranty of 
'any kind. Microsoft further disclaims all implied warranties including,
'without limitation, any implied warranties of merchantability or of fitness
'for a particular purpose. The entire risk arising out of the use or 
'performance of the sample scripts and documentation remains with you. In no 
'event shall Microsoft, its authors, or anyone else involved in the creation,
'production, or delivery of the scripts be liable for any damages whatsoever 
'(including, without limitation, damages for loss of business profits, business
'interruption, loss of business information, or other pecuniary loss) arising 
'out of the use of or inability to use this sample script or documentation, 
'even if Microsoft has been advised of the possibility of such damages.



' Catch errors at compile time, sort of.
Option Explicit

'*****************************************************************
'Displays script-understood command line parameters
'
Sub Usage()
    Call OutputLine(ECHOMINIMAL, "SetupCA.vbs - Certificate Services Setup Automation for Windows Server 2008/2008 R2")
    Call OutputLine(ECHOMINIMAL, "")
    Call OutputLine(ECHOMINIMAL, "Parameters:")
    Call OutputLine(ECHOMINIMAL, "/SP <Prov>   - Specify Provider")
    Call OutputLine(ECHOMINIMAL, "/SK <Len>    - Specify Key length")
    Call OutputLine(ECHOMINIMAL, "/SA <Alg>    - Specify Hash algorithm")
    Call OutputLine(ECHOMINIMAL, "/SN <Name>   - Specify CA Name")
    Call OutputLine(ECHOMINIMAL, "/DN <Name>   - Specify DN Suffix for CA cert subject")
    Call OutputLine(ECHOMINIMAL, "/SR <CA>     - Specify Root CA (Required for subordinate CA" & Chr(39) & "s and Web service)")
    Call OutputLine(ECHOMINIMAL, "")
    Call OutputLine(ECHOMINIMAL, "/OR <File>   - Save CA cert request to a file (Required for offline root CA" & Chr(39) & "s)")
    Call OutputLine(ECHOMINIMAL, "")
    Call OutputLine(ECHOMINIMAL, "/RK <Name>   - Reuse Key")
    Call OutputLine(ECHOMINIMAL, "/RC <Name>   - Reuse Cert and Key")
    Call OutputLine(ECHOMINIMAL, "")
    Call OutputLine(ECHOMINIMAL, "/interactive - Specifiy whether CA will be set to interact with desktop")
    Call OutputLine(ECHOMINIMAL, "")
    Call OutputLine(ECHOMINIMAL, "/IE          - Install Enterprise Root CA Service")
    Call OutputLine(ECHOMINIMAL, "/IS          - Install Standalone Root CA Service")
    Call OutputLine(ECHOMINIMAL, "/IF          - Install Enterprise Subordinate CA Service")
    Call OutputLine(ECHOMINIMAL, "/IT          - Install Standalone Subordinate CA Service")
    Call OutputLine(ECHOMINIMAL, "/IW          - Install web CA Service - works with any of the above or by itself")
    Call OutputLine(ECHOMINIMAL, "               This option is not relevant for server core machines")
    Call OutputLine(ECHOMINIMAL, "")
    Call OutputLine(ECHOMINIMAL, "/UC          - Uninstall CA Service")
    Call OutputLine(ECHOMINIMAL, "")
    Call OutputLine(ECHOMINIMAL, "/?           - Display this usage")
    Call OutputLine(ECHOMINIMAL, "")
End Sub ' Usage

'*****************************************************************
'Define external constant values
'
' CA Role
Const ENTERPRISE_ROOTCA = 0
Const ENTERPRISE_SUBCA = 1
Const STANDALONE_ROOTCA = 3
Const STANDALONE_SUBCA = 4
Const NO_INSTALL_CA =  -1
Const UNINSTALL_CA = 8
Const UNINSTALL_WEB_PAGES = 9

'FileSystemObject defines
Const FILE_FLAG_READ = 1
Const FILE_FLAG_WRITE = 2
Const FILE_FLAG_APPEND = 8

'Logging level
Const ECHOMINIMAL = 1

'Error codes to handle:
Const RPC_UNAVAILABLE =  - 2147023174 '0x800706BA
Const DOMAIN_UNAVAILABLE =  - 2147023541 '0x8007054B
Const REG_VALUE_NOT_FOUND =  - 2147024894 '0x80070002
Const IMAGE_TAMPERED =  - 2147024319 '0x80070241
Const VALUE_OUT_OF_RANGE =  - 2147016574 '0x80072082
Const ROOT_CA_NOT_FOUND = 462

'Properties that can be set:
Const SETUPPROP_INVALID =  - 1
Const SETUPPROP_CATYPE = 0
Const SETUPPROP_CAKEYINFORMATION = 1
Const SETUPPROP_INTERACTIVE = 2
Const SETUPPROP_CANAME = 3
Const SETUPPROP_CADSSUFFIX = 4
Const SETUPPROP_VALIDITYPERIOD = 5
Const SETUPPROP_VALIDITYPERIODUNIT = 6
Const SETUPPROP_EXPIRATIONDATE = 7
Const SETUPPROP_PRESERVEDATABASE = 8
Const SETUPPROP_DATABASEDIRECTORY = 9
Const SETUPPROP_LOGDIRECTORY = 10
Const SETUPPROP_SHAREDFOLDER = 11
Const SETUPPROP_PARENTCAMACHINE = 12
Const SETUPPROP_PARENTCANAME = 13
Const SETUPPROP_REQUESTFILE = 14
Const SETUPPROP_WEBCAMACHINE = 15
Const SETUPPROP_WEBCANAME = 16

'*****************************************************************
'Define constants and defaults
'
Const CONST_ERROR = 0
Const CONST_WSCRIPT = 1
Const CONST_CSCRIPT = 2
Const CONST_SHOW_USAGE = 3
Const CONST_PROCEED = 4

Const DEFCANAME = ""
Const DEFDNSUFFIX = ""
Const DEFROOTCANAME = ""
Const DEF_SEL_KEY_SIZE = "2048"
Const DEF_SEL_HASH_ALG = "SHA1"
Const DEF_INSTALL_WEB_OPTION = False
Const DEF_INSTALL_SVC_OPTION = False
Const DEF_LOG_FILENAME = "c:\_SetupCA.log"
Const DEF_INTERACTIVE = False

'example Capi1 Provider:   "Microsoft Strong Cryptographic Provider"
'example RSA CNG provider: "RSA#MicrosoftKSP"
'example ECC 256 provider: "ECDSA_P256#Microsoft Software Key Storage Provider"
'example ECC 384 provider: "ECDSA_P384#Microsoft Software Key Storage Provider"
'example ECC 521 provider: "ECDSA_P521#Microsoft Software Key Storage Provider"
Const DEF_SEL_PROVIDER = "RSA#Microsoft Software Key Storage Provider"

'Cert Server Role
Dim eCARole
eCARole = NO_INSTALL_CA

'Root CA's name (if this is a subordinate)
Dim strRootCAName
strRootCAName = DEFROOTCANAME

'This CA's name
Dim strCAName
Dim strDNSuffix
strCAName = DEFCANAME
strDNSuffix = DEFDNSUFFIX

'Crypto provider to be used to sign certs this CA Issues
Dim strSelectedCSP
strSelectedCSP = "" ' DEF_SEL_PROVIDER

'Hash algorithm to be used to sign certs this CA Issues
Dim strSelectedHashAlg
strSelectedHashAlg = "" ' DEF_SEL_HASH_ALG

'Signing key length
Dim iSelectedKeySize
iSelectedKeySize = "" ' DEF_SEL_KEY_SIZE

'Save request to file, for submitting to offline root
Dim strRequestFile
strRequestFile = ""

'Key/Cert Re-use flags
Dim bReuseKey
Dim bReuseCert
Dim bReuseDB
bReuseKey  = False
bReuseCert = False
bReuseDB   = False

'Interactive Flag
Dim bInteractive
bInteractive = DEF_INTERACTIVE

'Default to install or uninstall
Dim bInstall
bInstall = True

'Install the Web interface
Dim bWebPages
bWebPages = DEF_INSTALL_WEB_OPTION

' Install the Cert Server service. 
Dim bInstallService
bInstallService = DEF_INSTALL_SVC_OPTION

'Log file 
Dim OutputFile
Dim OutputFile2

'Needs to differentiate which package needs to be installed
Dim PKGCA
Dim PKGIIS
Dim PKGWEB
PKGCA  = True
PKGIIS = False
PKGWEB = False

'Set if installing on core build
Dim bIsCore
bIsCore = False

'For the 'retry once' implementation
Dim bRecursed
bRecursed = False


'Begin script logic

'Ensure the output won't become hundreds of popup windows
Call VerifyStandardStreams()

'Set up Local logging
Set OutputFile = CreateLogFile(DEF_LOG_FILENAME)

Dim g_oCASetup

'Start the script
Call Main()

'********************************************************************
'*
'* Sub InstallPackages()
'*
'* Purpose: Install all required packagemanager packages
'*
'********************************************************************' 
Sub InstallPackages(Install)

    'Get shell object to determine system drive value
    Dim WshShell
    Set WshShell = WScript.CreateObject("WScript.Shell")

    If (Install = True) Then

        If (PKGCA = True) Then
            Call OutputLine(ECHOMINIMAL, "Installing CA Packages, this will take several minutes...")
            Call WshShell.Run ("cmd /c servermanagercmd -install ADCS-Cert-Authority -resultPath installResult.xml", 0 , True)
        End If

        If (PKGWEB = True) Then
            Call OutputLine(ECHOMINIMAL, "Installing Web Page Packages, this will take several minutes...")
            Call WshShell.Run ("cmd /c servermanagercmd -install ADCS-Web-Enrollment -resultPath installResult.xml", 0 , True)
        End If

    Else

        If (PKGWEB = True) Then
            Call OutputLine(ECHOMINIMAL, "Removing Web Page Packages, this will take several minutes...")
            Call WshShell.Run ("cmd /c servermanagercmd -remove ADCS-Web-Enrollment -resultPath installResult.xml", 0 , True)
        End If

        If (PKGCA = True) Then
            Call OutputLine(ECHOMINIMAL, "Removing CA Packages, this will take several minutes...")
            Call WshShell.Run ("cmd /c servermanagercmd -remove ADCS-Cert-Authority -resultPath installResult.xml", 0 , True)
        End If

    End If

    Call OutputLine(ECHOMINIMAL, "Installing Packages, this will take several minutes...")

    Set WShShell = Nothing
End Sub 'InstallPackage

'********************************************************************
'*
'* Sub Main()
'*
'* Purpose: Executes the main script logic
'* Input:   
'*
'* Output:  
'*
'********************************************************************
Sub Main ()
    Dim intOpMode

    'Parse the command line
    intOpMode = intParseCmdLine()

    Select Case intOpMode

        Case CONST_SHOW_USAGE
            Call Usage()
            Exit Sub

        Case CONST_PROCEED
            'Do Nothing

        Case CONST_ERROR
            Call OutputLine(ECHOMINIMAL,"Error occurred in passing parameters.")
            Exit Sub

        Case Else                    'Default -- should never happen
            Call OutputLine(ECHOMINIMAL,"Error occurred in passing parameters.")
            Exit Sub

    End Select

    'Check if certocm.dll is present, if not we are most likely running on core and need
    'to use ocsetup to install CA package to get certocm.dll
    Dim FSO
    Set FSO = CreateObject("Scripting.FileSystemObject")

    Dim WshShell
    Dim envVars
    Dim strWinDir
    Set WshShell = WScript.CreateObject("WScript.Shell")
    Set envVars  = WshShell.Environment("process")

    strWinDir    = envVars("windir")

    wscript.echo "Checking if certocm.dll is present..."

    If Not FSO.FileExists(strWinDir + "\system32\certocm.dll") Then
        bisCore = True
        wscript.echo "Certocm.dll is not present installing CA package..."
        Call WshShell.Run ("cmd /c start /w ocsetup CertificateServices /norestart /quiet", 0 , True)
        wscript.echo "CA package installed..."
    Else
        wscript.echo "Certocm.dll is present not installing CA package"
    End If

    Set WshShell = Nothing
    Set envVars  = Nothing

    Set g_oCASetup = CreateObject("certocm.CertSrvSetup")
    
    'Install Packages
    Call OutputLine(ECHOMINIMAL,"Proceeding to update packages ...")
    Call InstallPackages(bInstall)
wscript.echo "bInstallService: " & bInstallService
wscript.echo "eCARole: " & eCARole
wscript.echo "bWebPages: " & bWebPages
    If ((eCARole <> NO_INSTALL_CA) And (eCARole <> UNINSTALL_CA) And (eCARole <> UNINSTALL_WEB_PAGES)) or (bWebPages <> False) Then
        Call OutputLine(ECHOMINIMAL, "Main: Info collection complete. Starting install phase..." )
        ' got the info we needed, now install..
        Call OutputFile.WriteLine("Main: Installing...")

        If (True = InstallAndVerifyCA(eCARole, bInstallService, bWebPages)) Then
            Call OutputFile.WriteLine("Main: Install complete! Passed")
        Else
            Call OutputFile.WriteLine("Main: Install complete! Failed")
            Call WScript.Quit (1)
        End If 'Installed without errors
    Else
        If (eCARole = UNINSTALL_CA or eCARole = UNINSTALL_WEB_PAGES) Then
            If (eCARole = UNINSTALL_WEB_PAGES) Then
                Call OutputLine(ECHOMINIMAL, "Main: Uninstalling Web pages only...")
                'Uninstall web pages only
                Call UninstallCA(True)
                Call OutputLine(ECHOMINIMAL, "Main: web pages Uninstalled!")
            Else
                Call OutputLine(ECHOMINIMAL, "Main: Uninstalling CA...")
                'Uninstall web pages only
                Call UninstallCA(False)
                Call OutputLine(ECHOMINIMAL, "Main: Uninstalled!")
            End If
        End If
    End If

    ' Clean Up
    Call OutputFile.Close()

End Sub 'Main



'********************************************************************
'*
'* Sub VerifyStandardStreams()
'*
'* Purpose: verify CScript.exe was used to launch this script.
'* 
'********************************************************************
Sub VerifyStandardStreams()
    On Error Resume Next

    'Attempt to write to the error stream
    Call WScript.StdOut.WriteLine()

    'If couldn't display the error because cscript wasn't used, 

    If (Err.Number <> 0) Then

        'Report problem
        Call WScript.Echo("Please run this script from cscript.")

        'Exit the script
        Call WScript.Quit (1)
    End If

    On Error Goto 0
End Sub 'VerifyStandardStreams

'********************************************************************
'*
'* Sub OutputLine()
'*
'* Purpose: Control the debug output at one location
'* 
'* Input:   Level   compare to verbosity - if lower, do not display
'*          string  String to output.
'*
'********************************************************************
Sub OutputLine(ByVal level, ByVal String)

    Call OutputFile.WriteLine(String)
    WScript.StdOut.WriteLine String

End Sub ' OutputLine

'********************************************************************
'*
'* Sub PrintErrorInfo()
'*
'* Purpose: Control the debug output at one location
'* 
'* Input:   Message    Message to log
'*          Err        Error obejct to get info from
'*
'********************************************************************
Sub PrintErrorInfo(ByVal Message, ByVal oErr)
    Call OutputLine(ECHOMINIMAL, Message)
    Call OutputLine(ECHOMINIMAL, "Error Info: " & oErr.Number & ": " & oErr.Description)
    Call OutputLine(ECHOMINIMAL, "Error Source: " & oErr.Source)
End Sub ' OutputLine

'********************************************************************
'*
'* Function intParseCmdLine()
'*
'* Purpose: Parses the command line.
'*  
'* Input:   none
'*
'* Output:  none
'*
'********************************************************************
Function intParseCmdLine()
    On Error Resume Next

    Dim strFlag
    Dim intState
    Dim ArgTemp
    Dim intArgIter
    Dim objFileSystem

    If Wscript.Arguments.Count > 0 Then
        Call OutputFile.WriteLine("parsing arguments: ")

        For Each ArgTemp in WScript.Arguments

            If (InStr(ArgTemp," ") > 0) Then
                Call OutputFile.Write(Chr(34) & ArgTemp & Chr(34) & " ")
            Else
                Call OutputFile.Write(ArgTemp & " ")
            End If

        Next ' ArgTemp

        Call OutputFile.WriteLine
        strFlag = Wscript.arguments.Item(0)
    End If

    'No arguments have been received

    If IsEmpty(strFlag) Then
        intParseCmdLine = CONST_SHOW_USAGE
        Exit Function ' intParseCmdLine
    End If

    'Check if the user is asking for help or is just confused

    If (strFlag = "help") Or (strFlag = "/h") Or (strFlag = "\h") Or (strFlag = "-h") _
        Or (strFlag = "\?") Or (strFlag = "/?") Or (strFlag = "?") _
        Or (strFlag = "h") Then
        intParseCmdLine = CONST_SHOW_USAGE
        Exit Function ' intParseCmdLine
    End If

    'Retrieve the command line and set appropriate variables
    intArgIter = 0

    Do While intArgIter <= Wscript.arguments.Count - 1

        Select Case Left(LCase(Wscript.arguments.Item(intArgIter)),4)
            Case "/int"
                bInteractive = True
                intArgIter   = intArgIter + 1

            Case "/sp"

                If Not blnGetArg("Crypto Provider", strSelectedCSP, intArgIter) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intArgIter = intArgIter + 1

            Case "/sk"

                If Not blnGetArg("Key length", iSelectedKeySize, intArgIter) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intArgIter = intArgIter + 1

            Case "/sa"

                If Not blnGetArg("Hash algorithm",strSelectedHashAlg, intArgIter) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intArgIter = intArgIter + 1

            Case "/sn"

                If Not blnGetArg("CA Name", strCAName, intArgIter) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intArgIter = intArgIter + 1

            Case "/dn"

                If Not blnGetArg("DN Suffix", strDNSuffix, intArgIter) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intArgIter = intArgIter + 1
                
                
            Case "/sr"

                If Not blnGetArg("Root CA", strRootCAName, intArgIter) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intArgIter = intArgIter + 1

            Case "/or"

                If Not blnGetArg("Request File", strRequestFile, intArgIter) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intArgIter = intArgIter + 1

            Case "/iw"

                If bIsCore = False Then
                    bWebPages = True
                End If

                intArgIter = intArgIter + 1

            Case "/ie"

                If (eCARole <> NO_INSTALL_CA) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intParseCmdLine = CONST_PROCEED
                bInstallService = True
                eCARole         = ENTERPRISE_ROOTCA
                intArgIter      = intArgIter + 1

            Case "/is"

                If (eCARole <> NO_INSTALL_CA) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intParseCmdLine = CONST_PROCEED
                bInstallService = True
                eCARole         = STANDALONE_ROOTCA
                intArgIter      = intArgIter + 1

            Case "/if"

                If (eCARole <> NO_INSTALL_CA) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intParseCmdLine = CONST_PROCEED
                bInstallService = True
                eCARole         = ENTERPRISE_SUBCA
                intArgIter      = intArgIter + 1

            Case "/it"

                If (eCARole <> NO_INSTALL_CA) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                intParseCmdLine = CONST_PROCEED
                bInstallService = True
                eCARole         = STANDALONE_SUBCA
                intArgIter      = intArgIter + 1

            Case "/uc"

                If (eCARole <> NO_INSTALL_CA) And (eCARole <> UNINSTALL_CA)  Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                bInstallService = False
                bWebPages      = False
                bInstall        = False
                eCARole         = UNINSTALL_CA
                intParseCmdLine = CONST_PROCEED
                intArgIter      = intArgIter + 1

            Case "/uw"

                If (eCARole <> NO_INSTALL_CA) And (eCARole <> UNINSTALL_CA) Then
                    intParseCmdLine = CONST_ERROR
                    Exit Function ' intParseCmdLine
                End If

                bWebPages      = False
                bInstall        = False
                eCARole         = UNINSTALL_WEB_PAGES
                intParseCmdLine = CONST_PROCEED
                intArgIter      = intArgIter + 1

            Case "/rk"
                bReuseKey  = True
                intArgIter = intArgIter + 1

            Case "/rc"
                bReuseCert = True
                intArgIter = intArgIter + 1

            Case "/rcd"
                bReuseCert = True
                bReuseDB   = True
                intArgIter = intArgIter + 1

                'Depricated switches kept to prevent automation from failing
            Case "/sl"
                intArgIter = intArgIter + 2
            Case "/sc"
                intArgIter = intArgIter + 2
            Case "/si"
                intArgIter = intArgIter + 2

            Case Else 'We shouldn't get here
                Call OutputLine(ECHOMINIMAL, "Invalid or misplaced parameter: " & Wscript.arguments.Item(intArgIter))
                Call OutputLine(ECHOMINIMAL, "Please check the input and try again")
                Call OutputLine(ECHOMINIMAL, "or invoke with " & Chr(39) & "/?" & Chr(39) & " for help with the syntax.")
                Wscript.Quit

        End Select

    Loop '** intArgIter <= Wscript.arguments.Count - 1

    intParseCmdLine = CONST_PROCEED

End Function

'********************************************************************
'* 
'*  Function blnGetArg()
'*
'*  Purpose: Helper to intParseCmdLine()
'* 
'*  Usage:
'*
'*     Case "/s" 
'*       blnGetArg ("server name", strServer, intArgIter)
'*
'********************************************************************

Private Function blnGetArg (ByVal StrVarName, _
    ByRef strVar, _
    ByRef intArgIter)

    blnGetArg = False 'failure, changed to True upon successful completion
    Err.Clear

    If Len(Wscript.Arguments(intArgIter)) > 3 Then

        If Mid(Wscript.Arguments(intArgIter),4,1) = ":" Then

            If Len(Wscript.Arguments(intArgIter)) > 4 Then
                strVar    = Right(Wscript.Arguments(intArgIter), _
                Len(Wscript.Arguments(intArgIter)) - 4)
                blnGetArg = True
                Exit Function
            Else
                intArgIter = intArgIter + 1

                If intArgIter > (Wscript.Arguments.Count - 1) Then
                    Call OutputLine(ECHOMINIMAL, "Parameter Missing: " & StrVarName & ".")
                    Call OutputLine(ECHOMINIMAL, "Invalid " & StrVarName & ".")
                    Call OutputLine(ECHOMINIMAL, "Please check the input and try again.")
                    Exit Function
                End If

                strVar = Wscript.Arguments.Item(intArgIter)

                If Err.Number Then
                    Call OutputLine(ECHOMINIMAL, "Error: " & Err.Number & ": " & Err.Description & ".")
                    Call OutputLine(ECHOMINIMAL, "Invalid " & StrVarName & ".")
                    Call OutputLine(ECHOMINIMAL, "Please check the input and try again.")
                    Exit Function
                End If

                If InStr(strVar, "/") Then
                    Call OutputLine(ECHOMINIMAL, "Invalid " & StrVarName)
                    Call OutputLine(ECHOMINIMAL, "Invalid Parameter was:" & StrVar)
                    Call OutputLine(ECHOMINIMAL, "Please check the input and try again.")
                    Exit Function
                End If

                blnGetArg = True 'success
            End If

        Else
            strVar    = Right(Wscript.Arguments(intArgIter), _
            Len(Wscript.Arguments(intArgIter)) - 4)
            blnGetArg = True 'success
            Exit Function
        End If

    Else
        intArgIter = intArgIter + 1

        If intArgIter > (Wscript.Arguments.Count - 1) Then
            Call OutputLine(ECHOMINIMAL, "Parameter Missing: " & StrVarName & ".")
            Call OutputLine(ECHOMINIMAL, "Invalid " & StrVarName & ".")
            Call OutputLine(ECHOMINIMAL, "Please check the input and try again.")
            Exit Function
        End If

        strVar = Wscript.Arguments.Item(intArgIter)

        If Err.Number Then
            Call OutputLine(ECHOMINIMAL, "Error: " & Err.Number & ": " & Err.Description & ".")
            Call OutputLine(ECHOMINIMAL, "Invalid " & StrVarName & ".")
            Call OutputLine(ECHOMINIMAL, "Please check the input and try again.")
            Exit Function
        End If

        If InStr(strVar, "/") Then
            Call OutputLine(ECHOMINIMAL, "Invalid " & StrVarName)
            Call OutputLine(ECHOMINIMAL, "Invalid Parameter was:" & StrVar)
            Call OutputLine(ECHOMINIMAL, "Please check the input and try again.")
            Exit Function
        End If

        blnGetArg = True 'success
    End If

End Function

'********************************************************************
'*
'* Function CreateLogFile()
'*
'* Purpose: Creates the local log file of all of the script output
'* 
'* Input:  strLogFileName
'*
'********************************************************************
Function CreateLogFile(ByVal strLogFileName)
    Dim FileSystem
    Set FileSystem = CreateObject("Scripting.FileSystemObject")

    'Get the actual path
    Dim strFileName
    strFileName = FileSystem.GetAbsolutePathName(strLogFileName)

    Call WScript.StdOut.WriteLine ("setupca.vbs: Log file = " & strFileName)

    On Error Resume Next

    ' just append to

    If FileSystem.FileExists(strFileName) Then
        'Open Existing log
        Set CreateLogFile = FileSystem.OpenTextFile(strFileName, FILE_FLAG_APPEND, True)
    Else
        'Open new log
        Set CreateLogFile = FileSystem.CreateTextFile(strFileName, True)
    End If

    Set FileSystem = Nothing

    If Err.Number <> 0 Then
        Call WScript.StdErr.WriteLine ("Error creating the log file " & strFileName)
        Call WScript.StdErr.WriteLine ("Error " & Err.Number & " - " & Err.Description)
        Call WScript.Quit (1)
    End If

    On Error Goto 0
End Function ' CreateLogFile

'********************************************************************
'*
'* Function SetProvider()
'*
'* Purpose:
'* 
'* Input:  ProviderString
'*         HashAlg
'*         KeyLen
'*
'********************************************************************
Function SetProvider(ByRef oCASetup, ByVal ProviderString, ByVal HashAlg, ByVal KeyLen)
    Call OutputLine(ECHOMINIMAL, _
    "SetProvider called with " & _
    Chr(34) & ProviderString & Chr(34) & ", " & _
    Chr(34) & HashAlg & Chr(34) & ", " & _
    Chr(34) & KeyLen & Chr(34))

    'Declare variable to store KeyInfo object
    Dim oCAKeyInfo
    Dim retVal

    retVal = False

    Call OutputLine(ECHOMINIMAL, "SetProvider: Creating oCAKeyInfo by calling oCASetup.GetCASetupProperty(SETUPPROP_CAKEYINFORMATION )")
    ' Create CA KeyInfo object
    Set oCAKeyInfo = oCASetup.GetCASetupProperty(SETUPPROP_CAKEYINFORMATION)

    If ("" <> ProviderString) Then
        Call OutputLine(ECHOMINIMAL, "SetProvider: Changing oCAKeyInfo.ProviderName to " & ProviderString)
        oCAKeyInfo.ProviderName = ProviderString
    End If

    ' only modify key length if it was specified

    If ("" <> KeyLen) Then
        Call OutputLine(ECHOMINIMAL, "SetProvider: Changing oCAKeyInfo.Length to " & KeyLen)
        oCAKeyInfo.Length = KeyLen
    End If

    ' Only modify hash algorithm if it was specified

    If ("" <> HashAlg) Then
        Call OutputLine(ECHOMINIMAL, "SetProvider: Changing oCAKeyInfo.HashAlgorithm to " & HashAlg)
        oCAKeyInfo.HashAlgorithm = HashAlg
    End If

    Call OutputLine(ECHOMINIMAL, "SetProvider: Calling oCASetup.SetCASetupProperty(SETUPPROP_CAKEYINFORMATION, oCAKeyInfo) ")

    On Error Resume Next
    Call Err.Clear()

    ' Set the keyInfo property
    Call oCASetup.SetCASetupProperty(SETUPPROP_CAKEYINFORMATION, oCAKeyInfo)

    If (Err.Number <> 0) Then
        Call OutputLine(ECHOMINIMAL, "SetProvider1: Error " & Err.Number & ": " & Err.Description)
        Call OutputLine(ECHOMINIMAL, "Error Source: " & Err.Source)
        'Exit the script
        Call WScript.Quit (1)
    End If ' error occurred

    SetProvider = True
End Function 'SetProvider

'********************************************************************
'*
'* Function InstallAndVerifyCA()
'*
'* Purpose: runs setup on CA object with specified parameters
'* 
'* Input:  CAType
'*         CAService
'*         WebPages
'*
'********************************************************************' 
Function InstallAndVerifyCA(ByVal CAType, ByVal CAService, ByVal WebPages)
    Dim LocalCAConfig
    Dim CADBPath

    ' Default to failed
    InstallAndVerifyCA = False

    On Error Resume Next

    Call Err.Clear()

    Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: InitializeDefaults")
    Call OutputLine(ECHOMINIMAL, "CAService: " & CAService)
    Call OutputLine(ECHOMINIMAL, "WebPages: " & WebPages)

    Err.Number = 0

    ' Call this function with an error handling wrapper, or vbscript equivalent..
    Call g_oCASetup.InitializeDefaults(CAService, WebPages)

    If (0 <> Err.Number) Then

        If (5 = Err.Number) Then
            ' uninstall

            If(bRecursed          = False) Then
                bRecursed          = True
                Call UninstallCA(False)
                InstallAndVerifyCA = InstallAndVerifyCA( CAType, CAService, WebPages)
                Exit Function
            End If

        End If 'error is already installed

        Call PrintErrorInfo("CA Already install and cannot uninstall", Err)
        Call OutputLine(ECHOMINIMAL, "")
        Exit Function 'InstallAndVerifyCA
    End If 'error occurred

'CA Service setup section
If (CAService = True) then 
'Specify CA role
Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: SetCASetupProperty - CAType = " & CAType)
Call g_oCASetup.SetCASetupProperty(SETUPPROP_CATYPE,  CAType)

If (0 <> Err.Number) And (VALUE_OUT_OF_RANGE <> Err.Number) Then
Call PrintErrorInfo("InstallAndVerifyCA3:unable to set SETUPPROP_CATYPE!", Err)
Exit Function 'InstallAndVerifyCA
End If 'not a domain admin and error occurred


If (VALUE_OUT_OF_RANGE = Err.Number) Then
Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: Error! Must be a domain administrator to create Enterprise CA")
Exit Function 'InstallAndVerifyCA 
End If ' not a domain admin

Call Err.Clear()

if (bInteractive <> FALSE) then
Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: SetCASetupProperty - Interactive = " & bInteractive)
Call g_oCASetup.SetCASetupProperty(SETUPPROP_INTERACTIVE,  bInteractive)

If (0 <> Err.Number) Then
Call PrintErrorInfo("InstallAndVerifyCA:unable to set Interactive!", Err)
Call OutputLine(ECHOMINIMAL, "")
Exit Function 'InstallAndVerifyCA
End If
end if

If (False <> bReuseKey) Or (False <> bReuseCert) Then

If (False = SetupKeyReuse(bReuseKey, bReuseCert, strCAName)) Then
Call PrintErrorInfo("InstallAndVerifyCA: SetupKeyReuse failed.", Err)
Exit Function
End If

Else
If "" <> strCAName then
Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: SetCADistinguishedName")
'CAName, ignore UTF8, overwrite existing key, overwrite CA in DS
Dim strCAFullDN
strCAFullDN = "CN=" & strCAName
If "" <> strDNSuffix then strCAFullDN = strCAFullDN & "," & strDNSuffix 

Call g_oCASetup.SetCADistinguishedName(strCAFullDN, True, True, True)
'Display errors

If (g_oCASetup.CAErrorId <> 0) Then
Call PrintErrorInfo("InstallAndVerifyCA:SetCADistinguishedName failed. ", Err)
End If

End If

End If

Call Err.Clear()

If (CAType <> ENTERPRISE_ROOTCA) And (CAType <> STANDALONE_ROOTCA) And (bReuseCert <> True) Then
If (strRequestFile = "") Then
Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: SetParentCAInformation")
'Set parent CA information if it is a subordinate
Call g_oCASetup.SetParentCAInformation(strRootCAName)

If (0 <> Err.Number) And (ROOT_CA_NOT_FOUND <> Err.Number) Then
Call PrintErrorInfo("InstallAndVerifyCA:unable to set ParentCAInformation!", Err)
Call OutputLine(ECHOMINIMAL, "")
Exit Function 'InstallAndVerifyCA
End If ' root ca not found

If (ROOT_CA_NOT_FOUND = Err.Number) Then
Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: Root CA (to Subordinate to) could not be found!")
Exit Function 'InstallAndVerifyCA
End If ' root ca not found
Else
Call g_oCASetup.SetCASetupProperty(SETUPPROP_REQUESTFILE, strRequestFile)
End If
End If ' not root

If (bReuseCert = False) Then
Dim bProviderSet
bProviderSet = SetProvider(g_oCASetup, strSelectedCSP, strSelectedHashAlg, iSelectedKeySize)

If (False = bProviderSet) Then
Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA:unable to set key properties!")
Exit Function 'InstallAndVerifyCA
End If 'error occurred
End If

Call Err.Clear()
End If
    
If (True = WebPages) And (CAType = NO_INSTALL_CA) Then
        Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: SetWebCAInformation")
        'Set web CA information if it is a web pages
        Call g_oCASetup.SetWebCAInformation(strRootCAName)

        If (0 <> Err.Number) Then

            If ( REG_VALUE_NOT_FOUND <> Err.Number) Then
                Call PrintErrorInfo("InstallAndVerifyCA:unable to set SetWebCAInformation!", Err)
                Call OutputLine(ECHOMINIMAL, "")
            Else
                Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: install failed, registry key not present!")
            End If

            Exit Function 'InstallAndVerifyCA
        End If ' error

    End If ' web pages should be installed

    Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: Setting Key Properties")

    Call Err.Clear()

    Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: calling SetProvider")

    'Dim KeyLenVar
    'KeyLenVar = ProviderKeyLength(strSelectedCSP)

    'If ("" <> KeyLenVar) Then
    '  iSelectedKeySize = KeyLenVar
    'End If

    Call Err.Clear()

    Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: BeforeInstall!")

    Call g_oCASetup.Install()

    If (0 <> Err.Number) Then

        If ( REG_VALUE_NOT_FOUND <> Err.Number) Then
            Call PrintErrorInfo("InstallAndVerifyCA:Install failed!", Err)
            Call OutputLine(ECHOMINIMAL, "")
        Else
            Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: install failed, registry key not present!")
            Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: " & Err.Number & ": " & Err.Description)
        End If

        Exit Function 'InstallAndVerifyCA
    End If 'error occurred

    Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: AfterInstall!")

    On Error GoTo 0

    Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: calling GetLocalCAConfig")

    LocalCAConfig = GetLocalCAConfig()

    If (LocalCAConfig = "") Then
        Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: CA Reg entry not present!")
        Exit Function 'InstallAndVerifyCA
    End If ' getlocalcaconfig failed

    WScript.Sleep 30000

    If (CAService = True) Then

        If (0 <> PingCA(LocalCAConfig)) Then
            Call OutputLine(ECHOMINIMAL, "InstallAndVerifyCA: Service not started!")
            Exit Function 'InstallAndVerifyCA
        End If ' can't ping service

    End If ' ca set to install as a service

    InstallAndVerifyCA = True
End Function 'InstallAndVerifyCA

'********************************************************************
'*
'* Function UninstallCA()
'*
'* Purpose: Uninstalls all of the CA server components or optionally just the pages
'* 
'* Input:  
'*
'********************************************************************' 
Function UninstallCA(ByVal WebPagesOnly)
    Dim LocalCAConfig

    Call OutputLine(ECHOMINIMAL, "UninstallCA: calling GetLocalCAConfig")

    ' See where the server is at currently
    LocalCAConfig = GetLocalCAConfig()

if (WebPagesOnly = False) Then
If ("" = LocalCAConfig) Then
Call OutputLine(ECHOMINIMAL, "UninstallCA: CA not installed!")
UninstallCA = True
Exit Function 'UninstallCA
End If ' getlocalcaconfig failed
End If

    Call OutputLine(ECHOMINIMAL, "UninstallCA: calling .PreUninstall")

    ' Clean up the web pages
    On Error Resume Next
    Call g_oCASetup.PreUninstall(WebPagesOnly)

    If Err.Number <> 0 Then
        Call PrintErrorInfo("UninstallCA: ", Err)
    End If

    Call OutputLine(ECHOMINIMAL, "UninstallCA: calling .PostUninstall")

    Call g_oCASetup.PostUninstall()

    Call OutputLine(ECHOMINIMAL, "UninstallCA: calling .GetLocalCAConfig")

    ' Check registry to see if CA is still installed 
    LocalCAConfig = GetLocalCAConfig()

    If ("" = LocalCAConfig) Then
        'Not installed!
        Call OutputLine(ECHOMINIMAL, "UninstallCA: Uninstall completed Successfully!")
        UninstallCA = True
        Exit Function 'UninstallCA
    End If 'getlocalcaconfig failed

    Call OutputLine(ECHOMINIMAL, "UninstallCA: calling PingCA")

    ' If the registry is still there, it might just be slow. 
    ' Try pinging the CA 

    If (0 <> PingCA("")) Then
        UninstallCA = True
        Exit Function 'UninstallCA
    End If ' can't ping service

    ' Default to error
    UninstallCA = False
End Function 'UninstallCA

'********************************************************************
'*
'* Function GetLocalCAConfig()
'*
'* Purpose: Determine role of CA if installed
'* 
'* Input:  
'*
'********************************************************************' 
Function GetLocalCAConfig()
    Dim WshShell
    Dim ActiveConfig
    Dim CAName
    Dim CAServer

    On Error Resume Next

    Set WshShell = WScript.CreateObject("WScript.Shell")
    ActiveConfig = WshShell.RegRead("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\Active")

    If (Err.Number <> 0) Then

        If (REG_VALUE_NOT_FOUND <> Err.Number) Then
            GetLocalCAConfig = ""
            Call PrintErrorInfo("GetLocalCAConfig: ", Err)
            Exit Function 'GetLocalCAConfig
        Else ' reg value not found
            GetLocalCAConfig = ""
            Call OutputLine(ECHOMINIMAL, "GetLocalCAConfig: CA Not Installed!")
            Call OutputLine(ECHOMINIMAL, "")
            Exit Function 'GetLocalCAConfig
        End If ' reg value found

    End If ' error occurred

    Call OutputLine(ECHOMINIMAL," Reading HKLM\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\" & ActiveConfig & "\CommonName")
    CAName = WshShell.RegRead("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\" & ActiveConfig & "\CommonName")
    Call OutputLine(ECHOMINIMAL, "CAName: " & CAName)

    Call OutputLine(ECHOMINIMAL," Reading HKLM\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\" & ActiveConfig & "\CAServerName")
    CAServer = WshShell.RegRead("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\" & ActiveConfig & "\CAServerName")
    Call OutputLine(ECHOMINIMAL, "CAServer: " & CAServer)

    ' Cleanup
    Set WShShell = Nothing

    'Set Return value
    GetLocalCAConfig = CAServer & "\" & CAName
End Function 'GetLocalCAConfig

'********************************************************************
'*
'* Function PingCA()
'*
'* Purpose: use CertUtil to ping the CA
'* 
'* Input:  
'*
'********************************************************************' 
Function PingCA(ByVal CAConfig)
    Dim WshShell
    Dim command
    Dim RunRet

    Set WshShell = WScript.CreateObject("WScript.Shell")

    If ("" <> CAConfig) Then
        command = "certutil -config " & CAConfig & " -ping"
    Else 'caconfig param null
        command = "certutil -ping"
    End If ' caconfig param passed

    RunRet       = WshShell.Run(command, 1, False)

    Set WShShell = Nothing
    PingCA       = RunRet
End Function ' PingCA

'********************************************************************
'*
'* Function SetUpKeyReuse()
'*
'* Purpose: use CertUtil to ping the CA
'* 
'* Input:  
'*
'********************************************************************' 
Function SetUpKeyReuse(ByVal bReuseKey, ByVal bReuseCert, ByVal KeyName)

    Dim oCAKeyInfo
    Dim oExistingCerts
    Dim CertInfo

    On Error Resume Next

    Set oCAKeyInfo     = g_oCASetup.GetCASetupProperty(SETUPPROP_CAKEYINFORMATION)
    Set oExistingCerts = g_oCASetup.GetExistingCACertificates()

    Call OutputLine(ECHOMINIMAL,"Searching Existing Machine Keys")

    For Each CertInfo in oExistingCerts
        wscript.echo "Existing Cert: " & certinfo.ContainerName

        If (KeyName = certinfo.ContainerName) Then
            wscript.echo "Found cert!"
            oCAKeyInfo.Existing      = True
            If (Err.Number <> 0) Then Call PrintErrorInfo("SetUpKeyReuse: oCAKeyInfo.Existing", Err)
            oCAKeyInfo.ContainerName = CertInfo.ContainerName
            If (Err.Number <> 0) Then Call PrintErrorInfo("SetUpKeyReuse: oCAKeyInfo.ContainerName", Err)
            oCAKeyInfo.HashAlgorithm = CertInfo.HashAlgorithm
            If (Err.Number <> 0) Then Call PrintErrorInfo("SetUpKeyReuse: oCAKeyInfo.HashAlgorithm", Err)
            oCAKeyInfo.Length        = CertInfo.Length
            If (Err.Number <> 0) Then Call PrintErrorInfo("SetUpKeyReuse: oCAKeyInfo.Length", Err)
            oCAKeyInfo.ProviderName  = CertInfo.ProviderName
            If (Err.Number <> 0) Then Call PrintErrorInfo("SetUpKeyReuse: oCAKeyInfo.ProviderName", Err)

            If (bReuseCert = True) Then
                oCAKeyInfo.ExistingCACertificate = CertInfo.ExistingCACertificate
                If (Err.Number <> 0) Then Call PrintErrorInfo("SetUpKeyReuse: oCAKeyInfo.ExistingCACertificate", Err)
            End If

            Call g_oCASetup.SetCASetupProperty(SETUPPROP_CAKEYINFORMATION, oCAKeyInfo)
            If (Err.Number <> 0) Then Call PrintErrorInfo("SetUpKeyReuse: g_oCASetup.SetCASetupProperty(1, oCAKeyInfo)", Err)
            wscript.echo g_oCASetup.GetCASetupProperty(SETUPPROP_CANAME)
            wscript.echo g_oCASetup.GetCASetupProperty(SETUPPROP_CADSSUFFIX)
        End If

    Next

    SetupKeyReuse = True

End Function ' SetKeyReuse
