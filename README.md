# Система высокоскоростного обмена данными на базе ПЛИС с использованием интерфейса USB 3.0

Этот репозиторий содержит RTL, ограничения и документацию для тракта обмена данными на базе `Xilinx Spartan-6` и `FTDI FT601` в режиме `245 synchronous FIFO`.

Основной сценарий проекта:

- принять 8-битный поток по GPIO;
- упаковать его в 32-битные слова;
- передать данные на ПК через `USB 3.0`.

Дополнительно в том же bitstream реализован runtime loopback-режим для проверки FT601 без внешнего источника данных на GPIO.

## Что умеет проект

- передавать поток `GPIO -> FT601 -> PC`;
- принимать служебные команды от ПК через FT601 RX path;
- включать loopback по команде без перепрошивки;
- возвращать данные `PC -> FT601 -> FPGA -> FT601 -> PC` в одном и том же bitstream;
- удерживать корректную FT601 burst-фазировку на RX и TX путях.

## Режимы работы

### Normal mode

Режим по умолчанию после reset.

Путь данных:

`GPIO -> get_gpio -> packer8to32 -> fifo_tx -> fifo_fsm -> FT601 -> PC`

Особенности:

- полезные данные приходят с GPIO;
- FT601 RX используется только для служебных команд;
- GPIO запись в TX FIFO блокируется при активном loopback.

### FT loopback mode

Включается service-frame `CMD_MAGIC + CMD_SET_LOOPBACK` через FT601 RX path.

Путь данных:

`PC -> FT601 -> fifo_fsm -> loopback_fifo -> fifo_fsm -> FT601 -> PC`

Особенности:

- loopback работает в одном bitstream с normal mode;
- payload хранится как `{BE, DATA}` в `source/fifo_singleclock.v`;
- штатный выход из loopback выполняется через `CMD_MAGIC + CMD_SET_NORMAL`;
- `FPGA_RESET` остается полным reset и тоже возвращает дизайн в `normal mode`.

## Структура репозитория

### `source/`

Основные HDL-файлы проекта.

Ключевые модули:

- `top.v` — верхний уровень;
- `bit_sync.v` — двухтактный синхронизатор одиночного бита между доменами;
- `ft601_io.v` — физическая обвязка FT601 и входная регистрация `TXE_N/RXF_N`;
- `fifo_fsm.v` — handshake и burst-логика FT601;
- `fifo_dualport.v` + `sram_dualport.v` — асинхронный TX FIFO между GPIO и FT domain;
- `fifo_singleclock.v` — loopback FIFO в домене `ft_clk_i`;
- `loopback_ft_ctrl.v` — FT-domain логика захвата RX-слов и управления loopback/TX prefetch;
- `host_cmd_ctrl.v` — потоковый декодер команд FT601 RX path;
- `tx_write_guard.v` — управление записью в TX FIFO и sticky TX error;
- `rst_sync.v` — синхронизация reset по доменам;
- `testbench.v` — основной проверочный стенд;
- `callistoS6.ucf` — pinout и timing constraints для Callisto S6.

### `docs/`

Справочные материалы и проектная документация.

Что лежит в папке:

- `SPECIFICATION.md` — техническая спецификация текущей архитектуры и требований к поведению;
- datasheet FT601;
- application note FTDI по master FIFO;
- reference design FTDI для Spartan-6;
- vendor Windows utilities `WU_*` для настройки и ручной проверки FT601;
- дополнительные материалы по FIFO, timing и ISE.

### `ft601_test/`

Консольная C++ программа для ручной работы с FT601 через D3XX API на стороне ПК.

Что лежит в папке:

- `main.cpp` — исходник консольной утилиты;
- `README.md` — краткий runbook по сборке и запуску;
- `WU_FTD3XXLib/` — библиотека D3XX для сборки и запуска;
- `WU_FTD3XX_Driver/` — драйвер D3XX для FT601 под Windows.

Что умеет утилита:

- писать raw payload в `EP02`;
- читать raw payload из `EP82` в `rx_dump.bin`;
- отправлять framed service-команды `CMD_MAGIC + opcode`;
- читать framed status response `STATUS_MAGIC + status_word`;
- переключать режимы и читать статус прошивки без перепрошивки FPGA.

## Как пользоваться проектом

### Работа на FPGA

Базовый сценарий на железе:

1. Собрать и прошить FPGA.
2. Настроить FT601 в `245 synchronous FIFO mode`.
3. После reset дизайн находится в `normal mode`.
4. В `normal mode` подавать полезные данные на GPIO и читать их на стороне ПК через FT601.
5. Для чтения текущего состояния можно отправить service-frame `CMD_MAGIC + CMD_GET_STATUS` и получить ответ `STATUS_MAGIC + status_word`.
6. Для входа в loopback отправить service-frame `CMD_MAGIC + CMD_SET_LOOPBACK`.
7. После этого передавать payload в FT601 RX path и читать его обратно через FT601 TX path.
8. Для штатного возврата в `normal mode` отправить `CMD_MAGIC + CMD_SET_NORMAL`.
9. `FPGA_RESET` использовать как полный reset, а не как штатную команду смены режима.

### Проверка со стороны ПК через `ft601_test`

Если нужен прямой тест обмена без отдельного GUI-приложения FTDI:

1. Собрать `ft601_test/main_gpp.exe` по инструкции из `ft601_test/README.md`.
2. Выбрать `Get FPGA status`, чтобы проверить текущий режим и агрегированные флаги ошибок.
3. Для входа в loopback выбрать `Set loopback mode`.
4. Для выхода из loopback выбрать `Set normal mode`.
5. Для recovery использовать `Clear TX error`, `Clear RX error` или `Clear all errors`.
6. Для raw datapath-проверки использовать `Write test payload` и `Read payload to file`.

### Что важно учитывать

- один bitstream обслуживает оба режима;
- FT601 RX path в `normal mode` предназначен для служебных команд;
- service-команды и status response идут как framed protocol `CMD_MAGIC + opcode` / `STATUS_MAGIC + status_word`;
- host-side utility работает в stop-and-wait режиме и не должна смешивать service traffic с raw payload;
- loopback payload не должен смешиваться с командным потоком;
- `TXE_N` и `RXF_N` внутри дизайна используются только в зарегистрированном виде после `ft601_io`.

## Куда смотреть дальше

Если нужен быстрый вход в проект:

1. `README.md` — общая карта репозитория и сценарии использования.
2. `docs/SPECIFICATION.md` — точные требования к архитектуре, handshake и verification.
3. `source/top.v` — верхний уровень и реальный datapath.
4. `source/testbench.v` — проверка текущего поведения дизайна.
5. `ft601_test/README.md` — host-side проверка FT601 через D3XX.

