# FT601 Console App

## Назначение
`main_gpp.exe` — простая консольная утилита для ручной работы с `FT601` через `D3XX API`.

Утилита поддерживает два типа операций:
- `raw payload` через `EP02` (`0x02`) и `EP82` (`0x82`);
- `service protocol` для управления прошивкой FPGA и чтения ее статуса.

При старте программа:
- открывает устройство по `DEVICE_INDEX = 0`;
- настраивает таймауты `FT_SetPipeTimeout` для `0x02` и `0x82`;
- проверяет через `FT_GetPipeInformation`, что bulk pipe pair `0x02/0x82` реально существует;
- показывает простое консольное меню.

## Service protocol

Команда в FPGA передается framed protocol из двух 32-битных слов по `EP02`:
1. `CMD_MAGIC = 0xA55A5AA5`
2. `opcode`

Ответ на `CMD_GET_STATUS` приходит по `EP82` тоже двумя 32-битными словами:
1. `STATUS_MAGIC = 0x5AA55AA5`
2. `status_word`

Поддерживаемые `opcode`:
- `CMD_CLR_TX_ERROR = 0x00000001`
- `CMD_CLR_RX_ERROR = 0x00000002`
- `CMD_CLR_ALL_ERROR = 0x00000003`
- `CMD_SET_LOOPBACK = 0xA5A50004`
- `CMD_SET_NORMAL = 0xA5A50005`
- `CMD_GET_STATUS = 0xA5A50006`

Формат `status_word`:
- `bit[0]` — `loopback_mode`
- `bit[1]` — `tx_error`
- `bit[2]` — `rx_error`
- `bit[3]` — `tx_fifo_empty`
- `bit[4]` — `tx_fifo_full`
- `bit[5]` — `loopback_fifo_empty`
- `bit[6]` — `loopback_fifo_full`
- `bit[31:7]` — `0`

Утилита работает в stop-and-wait режиме:
- одна service-команда;
- затем ожидание эффекта;
- для `SET_*` и `CLR_*` сразу выполняется `GET_STATUS` и печатается подтверждение.

## Меню
1. `Write test payload` — отправляет `64` 32-битных слов `1..64` в `EP02`.
2. `Read payload to file` — читает raw payload из `EP82` до таймаута и сохраняет в `rx_dump.bin`.
3. `Get FPGA status` — отправляет `CMD_GET_STATUS` и печатает `status_word`.
4. `Set loopback mode` — отправляет `CMD_SET_LOOPBACK`, затем автоматически читает статус.
5. `Set normal mode` — отправляет `CMD_SET_NORMAL`, затем автоматически читает статус.
6. `Clear TX error` — отправляет `CMD_CLR_TX_ERROR`, затем автоматически читает статус.
7. `Clear RX error` — отправляет `CMD_CLR_RX_ERROR`, затем автоматически читает статус.
8. `Clear all errors` — отправляет `CMD_CLR_ALL_ERROR`, затем автоматически читает статус.
9. `Exit`

Важно:
- `Read payload to file` — это только raw dump, а не чтение статуса;
- статус читается только через `Get FPGA status` или автоматический `GET_STATUS` после service-команды.

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
cd C:\Users\userIvan\Desktop\my_projects\logic_analyzer\ft601_test
& 'C:\msys64\mingw64\bin\g++.exe' -std=c++11 -Wall -Wextra -pedantic main.cpp -I. -L.\WU_FTD3XXLib\Lib\Dynamic\x64 -lFTD3XXWU -o main_gpp.exe
```

## Запуск

```powershell
cd C:\Users\userIvan\Desktop\my_projects\logic_analyzer\ft601_test
.\main_gpp.exe
```

## Обработка ошибок
- При ошибке записи выполняется `FT_AbortPipe(0x02)`.
- При ошибке чтения или ошибке status frame выполняется `FT_AbortPipe(0x82)`.
- При статусах отключения устройства (`FT_DEVICE_NOT_CONNECTED`, `FT_DEVICE_NOT_FOUND`, `FT_INVALID_HANDLE`) утилита делает попытку `reopen` и повторяет операцию один раз.
- Если в статусном ответе первым словом пришел не `STATUS_MAGIC`, это считается protocol error.
