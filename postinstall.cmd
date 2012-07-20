echo these are commands to be run upon first login post installation
rem echo activate windows with the product key
rem cscript c:\Windows\System32\slmgr.vbs /ipk "the product key"
rem cscript c:\Windows\System32\slmgr.vbs /ato
echo Setup AD as Domain Controller
%SystemRoot%\System32\dcpromo.exe /unattend:a:\dcinstall.ini > c:\dcinstall.log 2>&1
rem echo Disable LUA
rem reg add HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v EnableLUA /t REG_DWORD /d 0 /f
echo Install Standalone Root CA
cscript a:\Setupca.vbs /IS
rem echo Enable LUA
rem reg add HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v EnableLUA /t REG_DWORD /d 1 /f
echo add setuppass2 RunOnce script
reg add HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\RunOnce /v SetupPass2 /t REG_SZ /d "cmd /c a:\setuppass2.cmd > c:\setuppass2.log 2>&1"
echo Reboot in 2 minutes because AD install require a reboot to complete
shutdown -r -f -t 120 -c "Shutting down in 2 minutes - Reboot required for AD installation to complete"
