# Система обмена данными FPGA - FT601 - PC

Этот проект реализует высокоскоростной тракт обмена данными между `Xilinx Spartan-6` и ПК через мост `FTDI FT601` в режиме `245 synchronous FIFO`.

Основной поток простой: байты приходят по GPIO, упаковываются в 32-битные слова, проходят через FIFO и уходят в ПК через USB 3.0. `GPIO_STROB` задает валидность каждого байта и дальше превращается в `BE[3:0]` для 32-битного слова. В том же bitstream есть loopback-режим. Он нужен для проверки FT601 и host-side софта без внешнего GPIO-источника: ПК отправляет данные в FPGA, а FPGA возвращает их обратно через тот же FT601.

Проект использует один универсальный bitstream. После reset система стартует в `normal mode`, а режимы переключаются служебными командами с ПК.

## Схемы

Верхнеуровневая схема системы сопряжения:

![Верхнеуровневая схема системы сопряжения](images/1.png)

Структурная схема СФ-блока ПЛИС:

![Структурная схема СФ-блока ПЛИС](images/2.png)

## Как это работает

В `normal mode` полезные данные идут по цепочке:

![Normal тракт](images/2_1.png)

GPIO-домен и FT601-домен разделены асинхронным FIFO. GPIO-интерфейс остается односторонним: внешнего `ready` назад к GPIO-источнику нет. Граница stream-тракта начинается внутри СФ-блока после упаковки байтов. `packer8to32` собирает четыре позиции GPIO в `data[31:0]`, а `keep[3:0]` формирует из `GPIO_STROB`; этот `keep` затем идет как `BE[3:0]`. Write-side adapter пишет упакованные слова в FIFO, а read-side adapter выдает стабильный `valid/ready/data/keep` поток в TX arbiter. В `normal mode` FT601 RX path используется для служебных команд.

В `loopback mode` источник данных меняется:

![Loopback тракт](images/2_2.png)

Loopback FIFO хранит не только `DATA[31:0]`, но и `BE[3:0]`, поэтому payload возвращается с тем же byte-enable mask. Service frame при этом не попадает в payload.

Третий поток - status response. Он формируется внутри FPGA по команде `CMD_GET_STATUS` и имеет приоритет над normal/loopback payload. Это важно: `STATUS_MAGIC` и `status_word` должны выйти подряд, без вклинивания пользовательских данных.

![Service/control тракт](images/2_3.png)

Если status запрошен рядом с активным payload-потоком, RTL останавливает дальнейшее чтение payload FIFO на время service-read фазы. Дальше возможны два легальных варианта: если host держит `TXE_N=0` и продолжает длинное чтение, payload может пойти сразу за `STATUS_MAGIC/status_word`; если host завершает короткое status-read и поднимает `TXE_N`, payload остается в FIFO до следующего чтения. Уже лежащие в USB endpoint старые payload-слова не исчезают, поэтому D3XX-утилита из `software/` при чтении статуса ищет `STATUS_MAGIC` с ограниченным пропуском stale-слов.

## Service protocol

Служебный протокол идет поверх обычных 32-битных слов FT601. Отдельный control endpoint не используется.

Команда состоит из двух слов по `EP02`:

```text
CMD_MAGIC = 0xA55A5AA5
opcode
```

Ответ на `CMD_GET_STATUS` тоже состоит из двух слов, но читается из `EP82`:

```text
STATUS_MAGIC = 0x5AA55AA5
status_word
```

Для service/status слов ожидается полное 32-битное слово, то есть `BE = 4'hF`. Для normal payload `BE` повторяет маску валидных GPIO-байтов.

Поддерживаемые команды:

| Opcode | Значение | Назначение |
| --- | --- | --- |
| `CMD_CLR_SERVICE_ERROR` | `0x00000001` | очистить `service_frame_error` |
| `CMD_SET_LOOPBACK` | `0xA5A50004` | перейти в loopback mode |
| `CMD_SET_NORMAL` | `0xA5A50005` | вернуться в normal mode |
| `CMD_GET_STATUS` | `0xA5A50006` | прочитать status frame |
| `CMD_FT601_RESET` | `0xA5A50007` | сформировать `RESET_N=0` для FT601 на два такта `CLK` |

`status_word` содержит текущий режим, `service_frame_error` и empty/full флаги двух FIFO:

| Бит | Поле |
| --- | --- |
| `0` | `loopback_mode` |
| `1` | `service_frame_error` |
| `2` | `tx_fifo_empty` |
| `3` | `tx_fifo_full` |
| `4` | `loopback_fifo_empty` |
| `5` | `loopback_fifo_full` |
| `31:6` | `0` |

## Reset model

`FPGA_RESET` - главный внешний hard reset проекта. Он сбрасывает оба домена FPGA через локальные reset-синхронизаторы и возвращает RTL в исходное состояние. Это единственный reset, который используется внутри модулей ПЛИС.

`RESET_N` - отдельный выход ПЛИС в FT601. В нормальном состоянии он равен `1`. Команда `CMD_FT601_RESET` формирует на нем импульс `0` длительностью два такта `CLK` FT601. Этот импульс сбрасывает только микросхему FT601 и не является сбросом логики ПЛИС: режим, FIFO, FSM, adapters и диагностические флаги не очищаются этой командой.

## Структура репозитория

```text
logic_analyzer/
├── rtl/                            # RTL и ограничения
│   ├── top.v                       # Верхнеуровневая интеграция
│   ├── ft601_wrapper.v             # Физическая граница FT601
│   ├── ft601_fsm.v                 # Управление шиной FT601
│   ├── ft601_rx_adapter.v          # Преобразование чтения FT601 в stream
│   ├── ft601_tx_adapter.v          # Преобразование stream в запись FT601
│   ├── axis_tx_arbiter.v           # Арбитраж TX-источников
│   ├── rx_stream_router.v          # Разделение служебного и payload RX-потока
│   ├── cmd_decoder.v               # Декодер служебных команд
│   ├── status_source.v             # Формирование служебного status frame
│   ├── service_status_policy.v     # Окно чтения status и блокировка payload
│   ├── axis_fifo_write_adapter.v   # Адаптер записи stream-слов в FIFO
│   ├── axis_fifo_read_adapter.v    # Адаптер чтения FIFO в stream-формате
│   ├── async_fifo.v                # Асинхронная FIFO для normal path
│   ├── loopback_fifo.v             # FIFO для loopback path
│   └── callistoS6.ucf              # Ограничения Spartan-6
├── tb/                             # SystemVerilog testbench для Vivado XSim
│   ├── testbench.sv                # Официальный полный regression
│   ├── run_tb.py                   # Консольный запуск Vivado XSim regression
│   ├── tb_pkg.sv                   # Общие константы, типы и helper-функции
│   ├── tb_assertions.svh           # Immediate assertions, concurrent SVA и инварианты протоколов
│   ├── tb_monitors.svh             # Пассивные мониторы шин и stream-линий
│   ├── tb_scoreboard.svh           # Сравнение ожидаемых и фактических данных
│   ├── tb_coverage.svh             # Счетчики покрытия и SystemVerilog covergroups
│   └── scenarios/                  # Сценарные группы
├── software/                       # Консольная D3XX-утилита для ПК
│   ├── main.cpp                    # Меню и запуск операций
│   ├── ft601_device.*              # Работа с устройством и каналами FTDI
│   ├── service_protocol.*          # Служебный протокол и чтение status
│   ├── payload_test.*              # Запись и чтение raw payload
│   ├── throughput.*                # Расчет прикладной скорости
│   ├── app_log.*                   # Логирование с временными метками
│   ├── FTD3XX.h                    # Локальный заголовок D3XX
│   ├── WU_FTD3XXLib/               # DLL и библиотеки D3XX
│   ├── WU_FTD3XX_Driver/           # Пакет драйвера FTDI D3XX
│   └── README.md                   # Сборка и использование утилиты
├── images/                         # Схемы и иллюстрации для README
├── README.md                       # Обзор проекта
└── SPECIFICATION.md                # Актуальная техническая спецификация
```

## Утилизация ресурсов

Целевая ПЛИС: `xc6slx150-3-fgg676`.

| Ресурс | Использовано | Доступно | Утилизация |
| --- | ---: | ---: | ---: |
| Slice Registers | `756` | `184304` | `1%` |
| Slice LUTs | `713` | `92152` | `1%` |
| Occupied Slices | `266` | `23038` | `1%` |
| Bonded IOBs | `54` | `498` | `10%` |
| RAMB16BWER | `36` | `268` | `13%` |
| BUFG/BUFGMUX | `2` | `16` | `12%` |

## Проверка RTL

Основной тестовый стенд находится в `tb/` и написан на SystemVerilog. Официальная локальная симуляция выполняется в Vivado XSim. Единственная официальная точка входа - `tb/testbench.sv`; она запускает основные публичные сценарии и дополнительные проверки требований FT601 boundary, payload, router, arbiter и mode/status policy.

Проверки включают scoreboard, постоянные мониторы, immediate assertions, concurrent SVA, обязательные счетчики покрытия и функциональное покрытие SystemVerilog через `covergroup`. Пассивные интерфейсы `tb_axis_if.sv` и `tb_ft601_if.sv` используют `clocking`/`modport` для синхронного monitor sampling. `GPIO_CLK` и `CLK` FT601 моделируются как асинхронные домены; при каждом запуске XSim testbench выбирает случайную начальную фазу GPIO-часов относительно FT601-часов. Отчет покрытия формируется через Vivado `xcrg`; текущий full regression закрывает native functional coverage на 100% по 11 covergroup.

Структурная схема тестбенча:

![Структурная схема тестбенча](images/4.png)

## Проверка с ПК

Сборка D3XX-утилиты описана в `software/README.md`. Команда сборки использует `MSYS2 MinGW x64` и библиотеку D3XX из `WU_FTD3XXLib`.

Минимальный ручной сценарий на железе такой. Сначала прошить FPGA и убедиться, что FT601 настроен в `245 synchronous FIFO mode`. Затем запустить утилиту из `software/`, прочитать `Get FPGA status`, включить `Set loopback mode`, выполнить `Write test payload` и отдельно включить `Read payload to file`. После этого можно вернуться через `Set normal mode` и при необходимости очистить `service_frame_error` командой `Clear service frame error`.

Raw-операции `Write test payload` и `Read payload to file` являются debug-инструментами. `Write test payload` пишет `64` значения счетчика в `EP02`, каждое значение идет четырьмя байтами: `00 00 00 01`, `00 00 00 02` и далее. В `normal mode` это не echo-тест: normal TX path формируется внешним GPIO-источником. `Read payload to file` включает потоковое чтение raw payload чанками по `256 KiB`, использует D3XX stream pipe, печатает статистику примерно раз в секунду и работает до нажатия `q`. Status frame читается только через `Get FPGA status`.
