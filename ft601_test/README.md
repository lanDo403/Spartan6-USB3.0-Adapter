# FT601 Console App

## Назначение
Программа `main_gpp.exe` работает с FT601 через D3XX API (`FTD3XX.dll`) и предоставляет 2 операции:
- `1) Write counter 1..10000`: отправляет в OUT pipe (`0x02`) 10000 32-битных чисел от 1 до 10000, которые можно принять на ПЛИС.
- `2) Read to file`: читает из IN pipe (`0x82`) до таймаута и сохраняет данные в `rx_dump.bin`. Для успешного чтения с FT601 в файл необходимо на FT601 отправить данные с ПЛИС.

## Как работает программа
1. При старте открывает устройство FTDI по индексу `DEVICE_INDEX=0`.
2. Настраивает таймауты чтения/записи (`TIMEOUT_MS=2000` мс).
3. Показывает консольное меню.
4. При ошибках чтения/записи выводит имя `FT_STATUS` и код.
5. Если статус похож на отключение устройства (`FT_DEVICE_NOT_CONNECTED`, `FT_DEVICE_NOT_FOUND`, `FT_INVALID_HANDLE`), делает попытку переподключения и повтор операции.

## Константы в коде
- `OUT_PIPE = 0x02`
- `IN_PIPE = 0x82`
- `DEVICE_INDEX = 0`
- `TIMEOUT_MS = 2000`
- `CHUNK_BYTES = 1 MiB`

Файл исходника: `main.cpp`.

## Требования
- Windows.
- Установленный драйвер FTDI D3XX для FT601 (`WU_FTD3XX_Driver\\FTD3XXWU.inf`).
- `g++` в `PATH`. (x64)
- Библиотека `WU_FTD3XXLib\\Lib\\Dynamic\\x64\\FTD3XXWU.lib` и DLL `WU_FTD3XXLib\\Lib\\Dynamic\\x64\\FTD3XXWU.dll`.

## Сборка
- g++(4.9.2), стандарт c++11, линковщик ищет библиотеку в \\WU_FTD3XXLib\\Lib\\Dynamic\\x64.
- -Wall -Wextra -pedanctic параметры использовал, чтобы полностью отладить код.
g++ -std=c++11 -Wall -Wextra -pedantic main.cpp -I. -L.\\WU_FTD3XXLib\\Lib\\Dynamic\\x64 -lFTD3XXWU -o main_gpp.exe
