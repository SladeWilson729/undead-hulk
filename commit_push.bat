@echo off
setlocal
rem ================================================================
rem  commit_push.bat - stage everything, commit, and push to GitHub.
rem
rem  Usage:
rem    Double-click it            -> asks for a commit message
rem    commit_push "your message" -> uses that message
rem ================================================================

rem Always run from the folder this script lives in (the project root),
rem no matter where it was launched from.
cd /d "%~dp0"

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] git is not installed or not on PATH.
    echo         Install from git-scm.com, then open a NEW terminal.
    goto :end
)

set "MSG=%~1"
if not defined MSG set /p "MSG=Commit message: "
if not defined MSG (
    echo [ERROR] Commit message can't be empty. Nothing was committed.
    goto :end
)

echo.
echo === Changes being committed ===
git add -A
git status --short

rem Skip the commit if nothing changed, but still try to push older local commits.
git diff --cached --quiet
if not errorlevel 1 (
    echo Nothing new to commit.
    goto :push
)

git commit -m "%MSG%"
if errorlevel 1 (
    echo [ERROR] Commit failed. Read the message above.
    goto :end
)

:push
git remote get-url origin >nul 2>nul
if errorlevel 1 (
    echo.
    echo [INFO] Committed locally, but there's no GitHub remote yet, so nothing was pushed.
    echo        One-time setup:
    echo          1. Create an EMPTY repo on github.com - no README, no .gitignore
    echo          2. git remote add origin https://github.com/YOUR-USERNAME/undead-hulk.git
    echo          3. Run this script again
    goto :end
)

echo.
echo === Pushing ===
rem -u links the local branch to GitHub on the first push; harmless after that.
git push -u origin HEAD
if errorlevel 1 (
    echo [ERROR] Push failed. Common causes: not signed in to GitHub, or GitHub has
    echo         commits you don't have locally - run: git pull --rebase  then try again.
    goto :end
)
echo.
echo Done. Committed and pushed.

:end
echo.
rem Keep the window open when double-clicked; skip the pause when run with a message from a terminal.
if "%~1"=="" pause
endlocal
