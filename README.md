# Chromium-GOST PowerShell Installer

Минимальный установщик Chromium-GOST для локального запуска на Windows x64.

## Запуск

Запускайте PowerShell от имени администратора:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-ChromiumGost.ps1
```

Закреплённая версия должна использовать SHA-256 из GitHub release:

```powershell
.\Install-ChromiumGost.ps1 `
  -Version 152.0.7977.82 `
  -Sha256 3a968092cf6bf03a649345f36db742f48d2e600b072638db03360e470eee1c48
```

Дополнительные параметры:

- `-Force` — переустановить уже установленную версию;
- `-LogPath C:\Logs\chromium-gost.log` — писать журнал в файл;
- `-WhatIf` — получить сведения о релизе без скачивания и установки.

При первом запуске скрипт регистрирует задачу Windows Планировщика `Chromium-GOST daily update`: ежедневный запуск около 03:00 со случайной задержкой до 30 минут. Задача работает от имени `SYSTEM`, хранит копию скрипта в `C:\ProgramData\Chromium-Gost\` и пишет журнал в `C:\ProgramData\Chromium-Gost\update.log`.

Скрипт использует GitHub API и asset `windows-amd64-installer.exe`, проверяет SHA-256, принудительно закрывает процессы Chromium перед обновлением и подтверждает установленную версию. Поддерживаются только Windows x64 и запуск с правами администратора.
