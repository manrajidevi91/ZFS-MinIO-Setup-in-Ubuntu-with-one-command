@echo off
title MinIO Setup in Project Directory
echo ===================================
echo  Setting Up MinIO in E:\Work\Server\MinIO
echo ===================================
echo.

:: Define the MinIO project directory
set MINIO_DIR=E:\Work\Server\MinIO
set STORAGE_DIR=%MINIO_DIR%\storage

:: Create necessary directories
echo Creating MinIO Storage Directory...
mkdir "%STORAGE_DIR%"

:: Set environment variables (temporary for this session)
echo Setting Up Environment Variables...
set MINIO_ROOT_USER=admin
set MINIO_ROOT_PASSWORD=adminpassword

:: Download MinIO Server if not exists
if not exist "%MINIO_DIR%\minio.exe" (
    echo Downloading MinIO Server...
    powershell -Command "(New-Object System.Net.WebClient).DownloadFile('https://dl.min.io/server/minio/release/windows-amd64/minio.exe', '%MINIO_DIR%\minio.exe')"
)

:: Start MinIO Server
echo Starting MinIO Server...
start cmd /k "%MINIO_DIR%\minio.exe server %STORAGE_DIR% --console-address :9001"

:: Download and configure MinIO Client (mc)
if not exist "%MINIO_DIR%\mc.exe" (
    echo Downloading MinIO Client...
    powershell -Command "(New-Object System.Net.WebClient).DownloadFile('https://dl.min.io/client/mc/release/windows-amd64/mc.exe', '%MINIO_DIR%\mc.exe')"
)

:: Configure MinIO Client
echo Configuring MinIO Client...
"%MINIO_DIR%\mc.exe" alias set local http://127.0.0.1:9000 admin adminpassword

:: Create MinIO Bucket for Videos
echo Creating MinIO Bucket 'video-bucket'...
"%MINIO_DIR%\mc.exe" mb local/video-bucket

:: Set Public Access to MinIO Bucket
echo Setting Public Access for 'video-bucket'...
"%MINIO_DIR%\mc.exe" anonymous set public local/video-bucket

:: Display Success Message
echo.
echo MinIO Setup Completed Successfully in: %MINIO_DIR%
echo Access MinIO at: http://127.0.0.1:9001
echo Use MinIO Client with: mc alias set local http://127.0.0.1:9000 admin adminpassword
echo.

pause
exit
