@echo off

setlocal

set TEMP=d:\tmp

pushd "%TEMP%"

set PAR_PACKER_VER=1.029

:DOWNLOAD
wget -O "%TEMP%\PAR-Packer-%PAR_PACKER_VER%.tar.gz" https://cpan.metacpan.org/authors/id/R/RS/RSCHUPP/PAR-Packer-%PAR_PACKER_VER%.tar.gz
if errorlevel 1 goto ERROR

:UNPACK
rmdir /S /Q "PAR-Packer-%PAR_PACKER_VER%"
mkdir "PAR-Packer-%PAR_PACKER_VER%"
tar --strip-components=1 -C "PAR-Packer-%PAR_PACKER_VER%" -xzf "PAR-Packer-%PAR_PACKER_VER%.tar.gz"
if errorlevel 1 goto ERROR

:PATCH
cd "PAR-Packer-%PAR_PACKER_VER%"
copy "%~dp0\PAR-Packer.patch" "%TEMP%\PAR-Packer-%PAR_PACKER_VER%"
d:\devel\msys2\usr\bin\patch.exe -p1 -i PAR-Packer.patch
if errorlevel 1 goto ERROR

call cpanm32 -v .
if errorlevel 1 goto ERROR

dmake clean

call cpanm64 -v .
if errorlevel 1 goto ERROR

goto EXIT

:ERROR
echo.
echo Something gone wrong. Exit.
goto EXIT

:EXIT
popd
del /Q "%TEMP%\PAR-Packer-%PAR_PACKER_VER%.tar.gz"
rmdir /S /Q "%TEMP%\PAR-Packer-%PAR_PACKER_VER%"
exit /B
