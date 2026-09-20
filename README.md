# Chromium-GOST PowerShell Installer

PowerShell-скрипт для Windows x64. Он скачивает последний опубликованный стабильный релиз Chromium-GOST с GitHub, проверяет SHA-256 и устанавливает его на компьютер.

Источник релизов: [deemru/Chromium-Gost](https://github.com/deemru/Chromium-Gost/releases).

## Запуск

Запускайте PowerShell от имени администратора:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-ChromiumGost.ps1
```

Без `-Version` скрипт использует GitHub API `releases/latest`. Если такая же версия уже установлена, повторная установка не выполняется.

Для повторяемой установки укажите версию и SHA-256 соответствующего GitHub-релиза:

```powershell
.\Install-ChromiumGost.ps1 `
  -Version 152.0.7977.82 `
  -Sha256 3a968092cf6bf03a649345f36db742f48d2e600b072638db03360e470eee1c48
```

Дополнительные параметры:

- `-Force` — переустановить уже установленную версию;
- `-LogPath C:\Logs\chromium-gost.log` — писать журнал в файл;
- `-WhatIf` — получить сведения о релизе без скачивания и установки.

При первом обычном запуске скрипт регистрирует задачу Планировщика Windows `Chromium-GOST daily update`. Она запускается ежедневно около 03:00 со случайной задержкой до 30 минут, работает от имени `SYSTEM` и каждый раз проверяет последний опубликованный стабильный релиз. Копия скрипта хранится в `C:\ProgramData\Chromium-Gost\`, журнал — в `C:\ProgramData\Chromium-Gost\update.log`.

Закрепление через `-Version` действует для текущего запуска. Зарегистрированная задача запускает скрипт без `-Version` и поэтому при следующем запуске снова использует последний релиз.

Скрипт выбирает asset `windows-amd64-installer.exe`, проверяет SHA-256 до запуска установщика, закрывает процессы Chromium перед обновлением и подтверждает установленную версию после установки. Поддерживаются только Windows x64 и запуск с правами администратора.
