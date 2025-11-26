# Windows USB Deployment Toolkit

**Интерактивный инструмент для создания загрузочной USB с Windows, Office (ODT) и MAS активацией**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)
[![Version](https://img.shields.io/badge/Version-1.1.0-brightgreen.svg)](https://github.com/pv-udpv/windows-usb-deployment-toolkit/releases)

## 🚀 Возможности

### v1.1.0 - Новое!
- ✨ **Расширенное сканирование USB** с анализом загрузчиков и разметки
- 🔍 **Определение типа разметки** (GPT/MBR/RAW)
- 🛡️ **Детектирование загрузчиков** (Ventoy, Rufus, Windows, GRUB)
- ⚡ **Анализ загрузочных возможностей** (UEFI/BIOS)
- ⚠️ **Система предупреждений** для защиты от потери данных
- 🔄 **Функция пересканирования** USB дисков

### Базовые возможности
- ✅ **Автоматическое сканирование USB-дисков** с отображением размера и модели
- ✅ **Поддержка Rufus и Ventoy** для создания загрузочных USB
- ✅ **Интеграция Office Deployment Tool** для silent-установки Office
- ✅ **MAS (Microsoft Activation Scripts)** для активации Windows и Office
- ✅ **Автоматические скрипты** для post-install конфигурации
- ✅ **Интерактивный TUI** с цветным выводом и пошаговыми инструкциями

## 📋 Требования

- Windows 10/11 или Windows Server 2016+
- PowerShell 5.1 или выше (PowerShell 7+ рекомендуется)
- Права администратора
- USB-накопитель (минимум 16 GB, рекомендуется 32 GB+)
- Интернет-соединение для скачивания компонентов

## 🎯 Быстрый старт

### Способ 1: Прямой запуск

```powershell
# Клонировать репозиторий
git clone https://github.com/pv-udpv/windows-usb-deployment-toolkit.git
cd windows-usb-deployment-toolkit

# Запустить от имени администратора
.\USB-Deployment-Tool.ps1
```

### Способ 2: Скачать и запустить

```powershell
# Скачать скрипт напрямую
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/pv-udpv/windows-usb-deployment-toolkit/main/USB-Deployment-Tool.ps1" -OutFile "USB-Deployment-Tool.ps1"

# Запустить
.\USB-Deployment-Tool.ps1
```

### Способ 3: С параметрами

```powershell
# С существующим ISO и выбором метода
.\USB-Deployment-Tool.ps1 -Method Ventoy -WindowsIsoPath "C:\ISO\Win11_23H2.iso"

# С custom рабочей директорией
.\USB-Deployment-Tool.ps1 -WorkDir "D:\USBDeployment" -Verbose
```

## 🛠️ Рабочий процесс

### 1. Сканирование USB (Новое в v1.1.0)

Скрипт автоматически обнаруживает USB-накопители с детальным анализом:

```
═══════════════════════════════════════════════════════════════
          AVAILABLE USB DRIVES (DETAILED SCAN)
═══════════════════════════════════════════════════════════════

  [0] D: - SanDisk Ultra USB 3.0 (32.0 GB)
      Partition: GPT | Bootloader: Ventoy 1.0.99 | Type: UEFI/BIOS
      Content: 3 ISO file(s)
      ⚠️  Ventoy detected - will be overwritten!
      Status: ⚠️  Backup data before proceeding

  [1] E: - Kingston DataTraveler (64.0 GB)
      Partition: MBR | Bootloader: Windows Bootloader | Type: BIOS
      Content: Windows Installation Media
      ⚠️  Contains Windows installation media
      Status: ⚠️  Backup data before proceeding
      
  [2] F: - Generic USB Drive (16.0 GB)
      Partition: RAW | Bootloader: None | Type: Not formatted
      Status: ✓ Can be formatted and used

  [Q] Quit
  [R] Rescan USB drives
```

**Определяется:**
- ✅ Тип разметки (GPT/MBR/RAW)
- ✅ Существующие загрузчики (Ventoy, Rufus, Windows, GRUB)
- ✅ Загрузочные возможности (UEFI/BIOS/Multi-boot)
- ✅ EFI partition
- ✅ Содержимое (ISO файлы, Windows media)
- ✅ Предупреждения о потере данных

### 2. Выбор Windows ISO

Три варианта:
- **Указать путь** к существующему ISO файлу
- **Скачать Windows 11** (откроется браузер с официальной страницей загрузки)
- **Пропустить ISO** (только payload без создания загрузочного диска)

### 3. Подготовка Payload

Автоматически загружает и настраивает:

#### Microsoft Activation Scripts (MAS)
- Источник: [massgravel/Microsoft-Activation-Scripts](https://github.com/massgravel/Microsoft-Activation-Scripts)
- Методы: HWID, KMS38, Online KMS
- Поддержка Windows и Office активации

#### Office Deployment Tool (ODT)
- Office 365 ProPlus (64-bit)
- Языки: Русский + Английский
- Silent installation с auto-activation
- Исключения: OneDrive, Skype for Business

#### Скрипты автоматизации
- `FirstRun.cmd` - главный скрипт post-install
- `README.md` - инструкции по использованию

### 4. Выбор метода создания USB

#### Метод 1: Rufus
**Преимущества:**
- Простота использования
- Кастомизация Windows Setup (bypass TPM, disable telemetry)
- Быстрое создание

**Процесс:**
1. Скачивается последняя версия Rufus
2. Запускается с GUI
3. Пользователь выбирает настройки
4. После завершения payload копируется на USB

#### Метод 2: Ventoy
**Преимущества:**
- Multi-boot поддержка (несколько ISO на одном USB)
- Просто копировать ISO файлы
- Поддержка auto-install плагинов

**Процесс:**
1. Скачивается и устанавливается Ventoy
2. ISO копируется в корень USB
3. Payload размещается в `/PostInstall`
4. Создаётся базовый `autounattend.xml`

## 🔐 Система безопасности (v1.1.0)

### Предупреждения о потере данных

При выборе USB с существующими данными:

```
⚠️  WARNING: Selected USB drive has existing data!

  Drive: SanDisk Ultra USB 3.0 (32.0 GB)
  Current State:
    ⚠️  Ventoy detected - will be overwritten!
    ⚠️  Contains 3 ISO files

All data on this drive will be PERMANENTLY ERASED!

Are you ABSOLUTELY sure you want to continue? (type 'YES' to confirm):
```

**Требуется:**
- Ввод 'YES' (регистрозависимо)
- Просмотр всех предупреждений
- Возможность отмены

## 📂 Структура USB после создания

### Rufus метод:
```
E:\
├── [Windows Installation Files]
├── bootmgr
├── boot/
├── efi/
├── sources/
└── PostInstall/
    ├── MAS/
    │   └── MAS_AIO.cmd
    ├── Office/
    │   ├── setup.exe
    │   └── configuration.xml
    ├── FirstRun.cmd
    └── README.md
```

### Ventoy метод:
```
E:\
├── Win11_23H2.iso
├── ventoy/
│   ├── scripts/
│   │   └── autounattend.xml
│   └── ventoy.json
└── PostInstall/
    ├── MAS/
    ├── Office/
    ├── FirstRun.cmd
    └── README.md
```

## 🎬 Post-Install процесс

### Автоматический (FirstRun.cmd)

1. **После установки Windows:**
   - Откройте File Explorer
   - Перейдите на USB-диск
   - **ПКМ на `PostInstall\FirstRun.cmd` → "Запустить от имени администратора"**

2. **Скрипт выполнит:**
   ```
   [1/3] Installing Microsoft Office...     ✓ Silent installation
   [2/3] Waiting for completion...          ⏳ 30 секунд
   [3/3] Launching MAS Activation...        🚀 Interactive wizard
   ```

3. **В MAS выберите метод активации:**
   - `[1] HWID` - для Windows (permanent)
   - `[2] Ohook` - для Office (permanent)
   - `[3] Online KMS` - для временной активации

### Ручной процесс

```powershell
# 1. Установка Office
cd D:\PostInstall\Office
.\setup.exe /configure configuration.xml

# 2. Активация (через 5-10 минут после установки Office)
cd D:\PostInstall\MAS
.\MAS_AIO.cmd
```

## ⚙️ Параметры скрипта

```powershell
.PARAMETER Method
    Метод создания USB: 'Rufus', 'Ventoy', 'Auto' (по умолчанию)
    
.PARAMETER WindowsIsoPath
    Полный путь к Windows ISO файлу
    
.PARAMETER WorkDir
    Рабочая директория для временных файлов
    По умолчанию: $env:TEMP\USBDeployment
```

### Примеры использования

```powershell
# Интерактивный режим (рекомендуется)
.\USB-Deployment-Tool.ps1

# Ventoy с указанным ISO
.\USB-Deployment-Tool.ps1 -Method Ventoy -WindowsIsoPath "C:\ISO\Win11.iso"

# Rufus с verbose логированием
.\USB-Deployment-Tool.ps1 -Method Rufus -Verbose

# Custom рабочая директория
.\USB-Deployment-Tool.ps1 -WorkDir "D:\Temp" -WindowsIsoPath "E:\Win11.iso"
```

## 📊 Office Configuration (ODT)

Дефолтная конфигурация `configuration.xml`:

```xml
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="ru-ru" />
      <Language ID="en-us" />
      <ExcludeApp ID="Groove" />        <!-- OneDrive -->
      <ExcludeApp ID="Lync" />          <!-- Skype -->
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="AUTOACTIVATE" Value="1" />
</Configuration>
```

### Кастомизация Office

Для изменения компонентов Office:

1. **Использовать Office Configuration Tool:**
   - https://config.office.com/
   - Настроить через wizard
   - Экспортировать `configuration.xml`
   - Заменить файл в `PayloadDir\Office\configuration.xml`

2. **Ручное редактирование:**
   ```xml
   <!-- Добавить Visio -->
   <Product ID="VisioProRetail">
     <Language ID="ru-ru" />
   </Product>
   
   <!-- Изменить channel на Semi-Annual -->
   <Add OfficeClientEdition="64" Channel="SemiAnnual">
   
   <!-- Исключить Access -->
   <ExcludeApp ID="Access" />
   ```

## 🔐 MAS Activation Methods

### HWID (Hardware ID)
- **Для:** Windows 10/11
- **Тип:** Permanent digital license
- **Метод:** Генерация HWID ключа
- **Онлайн:** Требуется для активации
- **Реактивация:** Автоматическая после переустановки

### Ohook
- **Для:** Office 2016/2019/2021/365
- **Тип:** Permanent activation
- **Метод:** DLL hook activation
- **Онлайн:** Не требуется
- **Преимущество:** Работает оффлайн

### KMS38
- **Для:** Windows 10/11 Enterprise/Education
- **Тип:** До 2038 года
- **Метод:** Локальный KMS сервер
- **Онлайн:** Требуется для активации

### Online KMS
- **Для:** Windows и Office (любые версии)
- **Тип:** 180 дней (auto-renewal)
- **Метод:** Внешний KMS сервер
- **Онлайн:** Требуется для renewal

## 🛡️ Безопасность

### Проверенные источники

- **Rufus:** https://github.com/pbatard/rufus
- **Ventoy:** https://github.com/ventoy/Ventoy
- **MAS:** https://github.com/massgravel/Microsoft-Activation-Scripts
- **ODT:** https://microsoft.com (официальный download link)

### Хеши компонентов

Проверка целостности загруженных файлов:

```powershell
# Проверить SHA256 хеш MAS
Get-FileHash -Path "$env:TEMP\USBDeployment\Tools\MAS.zip" -Algorithm SHA256

# Сравнить с GitHub releases
# https://github.com/massgravel/Microsoft-Activation-Scripts/releases
```

### Антивирусы

⚠️ **Некоторые антивирусы могут блокировать MAS:**
- Причина: Модификация системных файлов для активации
- Решение: Добавить исключение для `MAS` директории
- Безопасность: MAS - open-source, код доступен для проверки

## 🐛 Troubleshooting

### USB не обнаружен

```powershell
# Проверить USB диски вручную
Get-WmiObject -Class Win32_DiskDrive | Where-Object {$_.InterfaceType -eq 'USB'}

# Переподключить USB и повторить запуск
```

### Rufus не запускается

```powershell
# Проверить наличие файла
Test-Path "$env:TEMP\USBDeployment\Tools\rufus.exe"

# Скачать вручную
Invoke-WebRequest -Uri "https://github.com/pbatard/rufus/releases/download/v4.6/rufus-4.6p.exe" -OutFile "rufus.exe"
```

### Office не устанавливается

```powershell
# Проверить логи ODT
Get-Content "$env:TEMP\OfficeSetup*.log" | Select-String -Pattern "Error"

# Ручная установка
cd D:\PostInstall\Office
.\setup.exe /configure configuration.xml

# Проверить статус установки
Get-Process -Name "OfficeClickToRun" -ErrorAction SilentlyContinue
```

### MAS активация не работает

```powershell
# Проверить текущий статус активации
slmgr /xpr    # Windows
cscript "C:\Program Files\Microsoft Office\Office16\ospp.vbs" /dstatus  # Office

# Очистить старые ключи
slmgr /upk
slmgr /cpky

# Запустить MAS с логированием
cd D:\PostInstall\MAS
MAS_AIO.cmd > mas_log.txt 2>&1
```

### Ventoy не загружается

- **Проблема:** Secure Boot блокирует загрузку
- **Решение:** 
  1. Войти в BIOS/UEFI (обычно F2, Del, F12)
  2. Найти Secure Boot
  3. Отключить Secure Boot
  4. Сохранить и перезагрузиться

## 📚 Дополнительные ресурсы

### Документация

- [Rufus FAQ](https://github.com/pbatard/rufus/wiki/FAQ)
- [Ventoy Documentation](https://www.ventoy.net/en/doc_start.html)
- [MAS Documentation](https://massgrave.dev/)
- [Office Deployment Tool](https://learn.microsoft.com/deployoffice/overview-office-deployment-tool)

### Полезные ссылки

- [UnattendedWinstall](https://github.com/memstechtips/UnattendedWinstall) - готовые autounattend.xml
- [Windows Answer Files](https://schneegans.de/windows/unattend-generator/) - генератор autounattend.xml
- [Office Config Tool](https://config.office.com/) - настройка ODT конфигурации

## 🤝 Contributing

Приветствуются pull requests! Для больших изменений сначала откройте issue для обсуждения.

### Области для улучшения

См. [Issue #1](https://github.com/pv-udpv/windows-usb-deployment-toolkit/issues/1) для полного roadmap.

**Приоритетные:**
- [ ] Автоматический download Windows ISO через API
- [ ] Интеграция драйверов (DISM)
- [ ] Unattended installation (autounattend.xml generator)
- [ ] WinGet integration
- [ ] Pester testing framework

**Будущие:**
- [ ] GUI версия (WPF)
- [ ] Configuration profiles (JSON)
- [ ] Windows Server support
- [ ] Multi-language support

## 📝 Changelog

### v1.1.0 (2025-11-27)

**Новые возможности:**
- ✨ **Enhanced USB Detection** - расширенное сканирование с анализом загрузчиков (#2)
- 🔍 Определение типа разметки (GPT/MBR/RAW)
- 🛡️ Детектирование загрузчиков (Ventoy, Rufus, Windows, GRUB)
- ⚡ Анализ загрузочных возможностей (UEFI/BIOS/Multi-boot)
- 🔐 EFI partition detection
- ⚠️ Система предупреждений для защиты от потери данных
- 🔄 Функция пересканирования USB дисков `[R]`
- ✅ Safety confirmation при выборе USB с данными

**Технические улучшения:**
- Использование `Get-Disk` и `Get-Partition` cmdlets
- Color-coded UI для различных типов разметки и загрузчиков
- Расширенный объект результата с дополнительными свойствами
- Backward compatible - все оригинальные свойства сохранены

### v1.0.0 (2025-11-26)

**Первый релиз:**
- ✨ Интерактивное сканирование USB дисков
- ✨ Поддержка Rufus и Ventoy методов
- ✨ Автоматическая загрузка MAS и ODT
- ✨ Генерация FirstRun.cmd для post-install
- ✨ Office configuration с silent install
- ✨ Цветной TUI с пошаговыми инструкциями
- 📚 Полная документация и примеры

## ⚖️ License

MIT License - см. [LICENSE](LICENSE)

## 👤 Author

**pv-udpv**
- GitHub: [@pv-udpv](https://github.com/pv-udpv)
- Repository: [windows-usb-deployment-toolkit](https://github.com/pv-udpv/windows-usb-deployment-toolkit)

## 🙏 Acknowledgments

- [Rufus](https://github.com/pbatard/rufus) - Pete Batard
- [Ventoy](https://github.com/ventoy/Ventoy) - Ventoy Team
- [Microsoft Activation Scripts](https://github.com/massgravel/Microsoft-Activation-Scripts) - massgravel
- [UnattendedWinstall](https://github.com/memstechtips/UnattendedWinstall) - memstechtips

## ⭐ Star History

Если проект оказался полезным, поставьте ⭐ на GitHub!

---

**Made with ❤️ for Windows SysAdmins and DevOps Engineers**
