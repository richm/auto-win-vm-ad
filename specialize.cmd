echo specialize is currently empty
echo these are commands run during the specialize phase of windows install
echo better to use RunSynchronous in most cases
echo create our SetupComplete.cmd
md c:\windows\setup\scripts
copy a:\SetupComplete.cmd c:\windows\setup\scripts
