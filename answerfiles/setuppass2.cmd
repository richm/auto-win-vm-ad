echo these are commands to be run upon second login post installation
echo Install Standalone Root CA
cscript a:\Setupca.vbs /IS
echo add setuppass3 RunOnce script
reg add HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\RunOnce /v SetupPass3 /t REG_SZ /d "cmd /c a:\setuppass3.cmd > c:\setuppass3.log 2>&1"
echo Reboot in 2 minutes because CA install requires a reboot to complete
shutdown -r -f -t 120 -c "Shutting down in 2 minutes - Reboot required for CA installation to complete"
