@echo off
REM One-time Feishu binding for the release token.
REM Device-code flow: a URL and a user code are printed below.
REM Open the URL, confirm within 10 minutes. Otherwise it expires (API error 410).
REM Re-run this file as many times as needed.

set "SKILL=C:\Users\zhuangmenghong\.workbuddy\skills\sofunny-resource-sharing"
set "PY=C:\Users\zhuangmenghong\.workbuddy\binaries\python\versions\3.13.12\python.exe"

echo.
echo Feishu binding for the release token
echo -----------------------------------
echo A link and a user code will appear below.
echo Open the link in a browser and confirm within 10 minutes.
echo.
"%PY%" "%SKILL%\scripts\publish.py" login --feishu

echo.
echo Exit code: %ERRORLEVEL%
pause
