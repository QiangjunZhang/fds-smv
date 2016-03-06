@echo off
Rem setup environment variables (defining where repository resides etc) 

set envfile="%userprofile%"\fds_smv_env.bat
IF EXIST %envfile% GOTO endif_envexist
echo ***Fatal error.  The environment setup file %envfile% does not exist. 
echo Create a file named %envfile% and use SMV/scripts/fds_smv_env_template.bat
echo as an example.
echo.
echo Aborting now...

pause>NUL
goto:eof

:endif_envexist

call %envfile%

%svn_drive%
echo copying %ProgramFiles%\FDS\FDS5\bin\objects.svo to %svn_root%\SMV\for_bundle\objects.svo
pause
copy "%ProgramFiles%\FDS\FDS5\bin\objects.svo" %svn_root%\SMV\for_bundle\objects.svo
pause