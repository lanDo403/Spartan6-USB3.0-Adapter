# FT601 Console App

## Назначение

`main_gpp.exe` — простая консольная утилита для ручной проверки `FT601` через `D3XX API`.

Утилита разделяет два типа операций:
- `raw payload` через `EP02` (`0x02`) и `EP82` (`0x82`);
- `service protocol` для управления RTL-прошивкой FPGA и чтения статуса.

Структурная схема программы:

![Структурная схема программы](../images/3.png)

При старте программа:
- открывает устройство по `DEVICE_INDEX = 0`;
- выводит краткую информацию о выбранном устройстве;
- проверяет bulk pipe pair `0x02/0x82` через `FT_GetPipeInformation`;
- настраивает `FT_SetPipeTimeout` для обоих pipe;
- показывает flat console menu.


## Структура директории

```text
software/
├── main.cpp                    # Console menu, dispatch операций и retry/reopen flow
├── ft601_device.h/.cpp         # D3XX device open, pipe discovery, raw read/write и cleanup
├── service_protocol.h/.cpp     # CMD/status protocol, opcodes и декодирование status_word
├── payload_test.h/.cpp         # Write test payload и Read payload to file
├── throughput.h/.cpp           # Расчет скорости payload-операций
├── app_log.h/.cpp              # log.txt и timestamp-маркеры операций
├── FTD3XX.h                    # Локальный заголовок D3XX
├── FTD3XXWU.dll                # DLL для запуска рядом с .exe
├── WU_FTD3XXLib/               # Import libraries и DLL FTDI D3XX
├── WU_FTD3XX_Driver/           # Драйвер FTDI D3XX
├── README.md                   # Этот файл
└── *_raw_tx.bin, *_raw_rx.bin   # Timestamped payload dumps, создаются при ручных тестах
```

`.o`, `.exe`, `log.txt` и payload dumps являются локальными результатами сборки/запуска. Исходная логика приложения находится в `*.cpp` и `*.h`.

## Роли исходников

- `main.cpp` — меню, dispatch операций и retry/reopen flow.
- `app_log.h/.cpp` — запись системных сообщений в `log.txt` без логирования отрисовки меню. Каждая выбранная операция дополнительно получает timestamp-маркер начала и конца, чтобы сопоставлять лог с ChipScope-захватами.
- `ft601_device.h/.cpp` — открытие устройства, pipe discovery, raw D3XX read/write, reopen и pipe abort.
- `service_protocol.h/.cpp` — framed service protocol, opcodes, status frame и декодирование `status_word`.
- `payload_test.h/.cpp` — raw test write и потоковое чтение payload.
- `throughput.h/.cpp` — прикладной расчет скорости через `QueryPerformanceCounter`.

## Service protocol

Команда в FPGA передается двумя 32-битными словами по `EP02`:
1. `CMD_MAGIC = 0xA55A5AA5`
2. `opcode`

Ответ на `CMD_GET_STATUS` читается двумя 32-битными словами по `EP82`:
1. `STATUS_MAGIC = 0x5AA55AA5`
2. `status_word`

Поддерживаемые `opcode`:
- `CMD_CLR_SERVICE_ERROR = 0x00000001`
- `CMD_SET_LOOPBACK = 0xA5A50004`
- `CMD_SET_NORMAL = 0xA5A50005`
- `CMD_GET_STATUS = 0xA5A50006`
- `CMD_FT601_RESET = 0xA5A50007`

Формат `status_word`:
- `bit[0]` — `loopback_mode`
- `bit[1]` — `service_frame_error`
- `bit[2]` — `tx_fifo_empty`
- `bit[3]` — `tx_fifo_full`
- `bit[4]` — `loopback_fifo_empty`
- `bit[5]` — `loopback_fifo_full`
- `bit[31:6]` — `0`

Service-команды выполняются в stop-and-wait режиме. `SET_*`, `CLR_*` и `CMD_FT601_RESET` только отправляют команду; статус читается отдельно через пункт `Get FPGA status`.

`ReadStatusFrame` после `CMD_GET_STATUS` читает из `EP82` ровно `8` байт: `STATUS_MAGIC` и `status_word`. Это короткое blocking-чтение, отдельное от потокового raw payload-read. Если пришло меньше `8` байт, первое слово не равно `STATUS_MAGIC` или второе слово не похоже на `status_word`, операция считается protocol error.

`Read payload to file` использует `FT_SetStreamPipe` только на время raw payload capture. После остановки по `q` программа вызывает `FT_ClearStreamPipe` и возвращает обычный timeout для `EP82`, поэтому следующий `Get FPGA status` работает как короткий status-read, а не как продолжение потокового чтения.

## Меню

1. `Write test payload` — отправляет `64` значения счетчика в `EP02`, печатает скорость записи и сохраняет `*_raw_tx.bin`. Каждое значение записывается четырьмя байтами: `00 00 00 01`, `00 00 00 02` и далее.
2. `Read payload to file` — включает потоковое чтение `EP82`, читает данные чанками по `256 KiB`, сохраняет timestamped `*_raw_rx.bin` и примерно раз в секунду печатает скорость чтения из отдельного stats-потока. Чтение идет до нажатия `q`; если payload-байтов не было, RX-файл не создается.
3. `Get FPGA status` — отправляет `CMD_GET_STATUS` и печатает `status_word`.
4. `Set loopback mode` — отправляет `CMD_SET_LOOPBACK`.
5. `Set normal mode` — отправляет `CMD_SET_NORMAL`.
6. `Clear service frame error` — отправляет `CMD_CLR_SERVICE_ERROR`.
7. `Reset FT601` — отправляет `CMD_FT601_RESET`, который формирует `RESET_N=0` на два такта `CLK` FT601.
8. `Exit`

Важно:
- `Write test payload` только пишет raw-поток в `EP02`; в `normal mode` это не является echo-тестом, потому что normal TX path идет от внешнего GPIO-источника;
- `Read payload to file` — это потоковое payload-чтение до `q`, а не чтение статуса; внутри используется `FT_SetStreamPipe`, короткий timeout для проверки клавиши остановки, `FT_ClearStreamPipe` после остановки и возврат обычного timeout для коротких status-read операций;
- после остановки пункта `2` можно сразу выполнять `Get FPGA status`: программа уже вернула `EP82` из stream-режима в обычный режим чтения;
- status frame читается только через `Get FPGA status`.

## Ручная loopback-проверка

1. Включить loopback через `Set loopback mode`.
2. Проверить режим через `Get FPGA status`.
3. Запустить `Write test payload`.
4. Запустить `Read payload to file` и остановить чтение клавишей `q`, когда данные получены.

`Write test payload` сохраняет отправленный файл `*_raw_tx.bin`. `Read payload to file` сохраняет принятый файл `*_raw_rx.bin`. Автоматическое сравнение TX/RX в отдельном пункте меню больше не выполняется.

## Throughput

Скорость считается только для payload-операций. Service-команды и status frame слишком маленькие, поэтому программа не использует их как benchmark.

`Write test payload` показывает host-to-device скорость. `Read payload to file` показывает device-to-host скорость примерно раз в секунду по счетчику принятых байтов и итоговую скорость для фактически принятого dump.

Это прикладная оценка для blocking D3XX flow, а не точный USB benchmark. Расчет времени сделан через `QueryPerformanceCounter`; выводятся `MiB/s` и `Mib/s`. На маленьких payload результат будет шумным, потому что накладные расходы Windows, D3XX и консольного приложения сравнимы с самой передачей. Если потоковое чтение остановлено без payload-байтов, файл не создается и скорость не считается.

## Требования

- Windows.
- Установленный D3XX драйвер для FT601.
- `FTD3XXWU.dll` доступна рядом с `.exe` или через `PATH`.
- Компилятор и import library должны быть одной архитектуры.

В проекте библиотека лежит в `WU_FTD3XXLib\Lib\Dynamic\x64`, поэтому компилятор тоже должен быть `x64`.
Если использовать 32-битный `g++`, линковка с `x64` библиотекой не пройдет.

## Сборка

Проверенная команда сборки для `MSYS2 MinGW x64`:

```powershell
cd .\software
g++ -std=c++11 -Wall -Wextra -pedantic main.cpp app_log.cpp ft601_device.cpp service_protocol.cpp payload_test.cpp throughput.cpp -I. -L.\WU_FTD3XXLib\Lib\Dynamic\x64 -lFTD3XXWU -o main_gpp.exe
```

## Запуск

```powershell
cd .\software
.\main_gpp.exe
```

## Обработка ошибок

- При ошибке записи выполняется `FT_AbortPipe(0x02)`.
- При ошибке чтения или protocol error выполняется `FT_AbortPipe(0x82)`.
- При disconnect-статусах (`FT_DEVICE_NOT_CONNECTED`, `FT_DEVICE_NOT_FOUND`, `FT_INVALID_HANDLE`) и `FT_OTHER_ERROR` утилита делает попытку reopen и повторяет операцию один раз.
- Если status-read получил меньше `8` байт, первое слово не равно `STATUS_MAGIC` или второе слово не похоже на `status_word`, это protocol error.
- `CMD_FT601_RESET` управляет только внешним `RESET_N` FT601. Он не сбрасывает RTL-логику ПЛИС, FIFO, режим или диагностические флаги.
