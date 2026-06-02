# SPECIFICATION

## Назначение

Проект описывает RTL-архитектуру для `Xilinx Spartan-6` и `FTDI FT601` в режиме `245 synchronous FIFO`. Один bitstream поддерживает три рабочих сценария: передача GPIO-потока в ПК, возврат данных в loopback-режиме и служебный control/status обмен с хоста.

После полного сброса система стартует в `normal mode`. Хост может переключать режимы и читать статус через framed service protocol без перепрошивки FPGA.

## Внешние интерфейсы

Со стороны GPIO используются `GPIO_CLK`, `GPIO_DATA[7:0]`, `GPIO_STROB` и `FPGA_RESET`. `GPIO_CLK` задает write-домен. `GPIO_STROB` является признаком валидности текущего байта. `packer8to32` начинает упаковку по первому активному `GPIO_STROB`, затем в течение четырех GPIO-тактов формирует `data[31:0]` и `keep[3:0]`. Если внутри этого окна `GPIO_STROB=0`, соответствующая байтовая позиция заполняется нулем, а ее `keep`-бит равен `0`. Первый принятый байт попадает в младший байт 32-битного слова.

`FPGA_RESET` - внешний active-high reset request. Он является единственным сбросом внутренней логики ПЛИС и формирует доменные reset-сигналы для GPIO- и FT-домена.

Со стороны FT601 используются сигналы synchronous FIFO bus: `CLK`, `TXE_N`, `RXF_N`, `OE_N`, `WR_N`, `RD_N`, `RESET_N`, `DATA[31:0]` и `BE[3:0]`. `CLK` формирует FT-домен. `TXE_N=0` означает, что FT601 готов принять слово от FPGA. `RXF_N=0` означает, что FT601 имеет слово для FPGA. `WR_N=0` записывает данные в FT601. `OE_N=0` вместе с `RD_N=0` разрешает чтение слова из FT601.

`DATA[31:0]` и `BE[3:0]` являются двунаправленными шинами. Во время TX ПЛИС формирует обе шины через `ft601_wrapper.v`; во время RX и reset они переводятся в tri-state.

## Система сброса

В проекте есть два reset-сигнала с разным назначением.

`FPGA_RESET` - внешний active-high reset request от платы. Это единственный reset, который сбрасывает внутреннюю RTL-логику ПЛИС. В `top.v` он проходит через `IBUF` и формирует два доменных reset request:

```verilog
gpio_rst_req = fpga_reset_i;
ft_rst_req   = fpga_reset_i;
```

Для GPIO- и FT-домена используется `rst_sync.v`: reset активируется асинхронно, а отпускается синхронно относительно своего clock. В GPIO-домене результатом является `gpio_rst_n_i`, в FT-домене - `ft_rst_n_i`.

`FPGA_RESET` очищает `gpio_wrapper`, `packer8to32`, write-side normal FIFO path, `ft601_wrapper`, `ft601_fsm`, RX/TX adapters, `rx_stream_router`, `cmd_decoder`, `status_source`, `loopback_fifo` и read-side normal FIFO path. После release `cmd_decoder` устанавливает `loopback_mode=0`, поэтому система стартует в `normal mode`.

`RESET_N` - отдельный active-low output ПЛИС в микросхему FT601. Он не используется как reset внутри RTL-модулей. В обычном состоянии `RESET_N=1`. Команда `CMD_FT601_RESET` формирует `RESET_N=0` на два такта `CLK` FT601, после чего сигнал снова возвращается в `1`.

`CMD_FT601_RESET` сбрасывает только внешнюю микросхему FT601. Эта команда не очищает FIFO, FSM, adapters, router, status source, диагностические sticky-флаги и не меняет `loopback_mode`.

Команда `CMD_CLR_SERVICE_ERROR` не является reset-командой. Она очищает только `service_frame_error` внутри `cmd_decoder.v`.

## Основная архитектура

Верхний уровень находится в `source/top.v`. Он соединяет GPIO-домен, FT-домен, FIFO, stream-router, arbiter, command decoder и status source. Последовательная логика распределена по небольшим модулям, поэтому `top.v` остается схемой соединений.

Физическая граница FT601 находится в `ft601_wrapper.v`. Там стоят буферы `IBUFG`, `IBUF`, `OBUF`, `IOBUF`, входная регистрация `TXE_N/RXF_N`, output-регистры управляющих сигналов и регистры для `DATA/BE`. Wrapper принимает уже готовые внутренние сигналы от FSM/adapters и выдает безопасный внешний интерфейс FT601.

`ft601_fsm.v` задает фазы доступа к FT601 и владеет сменой направления общей шины `DATA/BE`. Между RX- и TX-burst используется состояние `TURNAROUND`: в нем `WR_N`, `RD_N`, `OE_N` неактивны, а ПЛИС не формирует `DATA/BE`. RX-запрос имеет приоритет и может прервать TX burst через `TURNAROUND`, чтобы новые host-команды и loopback RX-пакеты не ждали окончания длинной TX-передачи. RX-захват вынесен в `ft601_rx_adapter.v`, TX output/prefetch path вынесен в `ft601_tx_adapter.v`, поэтому FSM координирует доступ к шине, а datapath хранится в отдельных блоках.

Внутренние потоки связаны AXI-Stream-подобным контрактом: `valid`, `ready`, `data`, `keep`. Передача слова происходит при `valid && ready`. Источник держит `data/keep` стабильными, пока приемник не подтвердил передачу через `ready`. `keep[3:0]` соответствует `BE[3:0]`, а `data[31:0]` соответствует `DATA[31:0]`. Stream-порты модулей используют `s_axis_*` для входного потока и `m_axis_*` для выходного. Границы service/status frame задаются фиксированной длиной в два слова и локальной control-логикой. FIFO write/read ports обернуты в `axis_fifo_write_adapter.v` и `axis_fifo_read_adapter.v`, чтобы stream-логика работала со стабильным handshake, а не с raw FIFO-сигналами.

Основные stream-ветки:

| Поток | Назначение |
| --- | --- |
| `normal_axis_*` | payload из normal TX FIFO |
| `loopback_axis_*` | payload из loopback FIFO |
| `status_axis_*` | status response source |
| `tx_axis_*` | общий TX stream после arbitration |
| `ft_rx_axis_*` | поток слов, принятых от FT601 |

`axis_tx_arbiter.v` выбирает источник для TX path. Приоритет фиксированный: status response, затем loopback при `loopback_mode=1`, затем normal TX FIFO при `loopback_mode=0`. Status frame удерживает источник до отправки двух слов: `STATUS_MAGIC` и `status_word`. Общий выход `tx_axis_*` зарегистрирован: если downstream не готов, `tx_axis_tdata/tx_axis_tkeep` не меняются, а normal/loopback payload не забирается внутрь arbiter-а раньше фактического handshake.

Если `CMD_GET_STATUS` принят во время подготовленного payload TX, status request переводит TX path в service-priority режим. Normal/loopback FIFO-read останавливается не только на время двухсловного status frame, но и до завершения host-side service-read фазы: payload снова разрешается после того, как FT601 деактивирует `TXE_N`. Локально подготовленное payload-слово на границе TX arbiter/adapter может быть отброшено, но содержимое самих FIFO не очищается. Это сделано для того, чтобы ответ на service-запрос начинался с `STATUS_MAGIC` и за ним в том же коротком чтении не добавлялись payload-слова.

`rx_stream_router.v` принимает слова от FT601 RX adapter и разделяет их на service traffic и loopback payload. Service frame потребляется внутри control path. Payload-слова в loopback mode записываются в `loopback_fifo` как `{DATA, BE}`.

## Datapath режимов

В `normal mode` данные идут от GPIO к ПК:

```text
GPIO -> gpio_wrapper -> packer8to32 -> axis_fifo_write_adapter -> async_fifo -> axis_fifo_read_adapter -> axis_tx_arbiter -> ft601_tx_adapter -> ft601_wrapper -> FT601 -> PC
```

GPIO-домен пишет в normal TX FIFO слова `{DATA[31:0], BE[3:0]}` через `axis_fifo_write_adapter`. `BE` здесь формируется из `GPIO_STROB`, поэтому normal payload может содержать не только `4'hF`, но и частичные маски байтов. GPIO-интерфейс односторонний и не имеет внешнего `ready` к источнику. FT-домен читает FIFO через `axis_fifo_read_adapter`, который держит front/lookahead слова и выдает `normal_axis_*`. FT601 RX path остается активным для service-команд. Обычный raw write с ПК в `EP02` в normal mode не является источником normal FIFO и не должен восприниматься как echo-тест: источник normal payload - внешний GPIO-тракт.

В `FT loopback mode` данные приходят с ПК и возвращаются обратно:

```text
PC -> FT601 -> ft601_rx_adapter -> rx_stream_router -> axis_fifo_write_adapter -> loopback_fifo -> axis_fifo_read_adapter -> axis_tx_arbiter -> ft601_tx_adapter -> FT601 -> PC
```

Loopback FIFO хранит 36 бит на слово: `{DATA[31:0], BE[3:0]}`. Это сохраняет byte-enable информацию. Командные слова service frame в эту FIFO не записываются. Write-side и read-side loopback FIFO подключены через `axis_fifo_write_adapter` и `axis_fifo_read_adapter`, поэтому loopback path соблюдает `valid/ready/data/keep` contract.

Status path работает как отдельный TX-source. По `CMD_GET_STATUS` блок `status_source.v` формирует двухсловный response. Если TX burst уже активен, status ждет безопасное окно; если payload только ожидает отправки, status получает приоритет.

## Framed service protocol

Service traffic идет по тем же endpoints, что и payload: команды пишутся в `EP02`, ответы читаются из `EP82`. Для service/status слов используется полное 32-битное слово с `BE=4'hF`.

Команда состоит из двух 32-битных слов:

```text
CMD_MAGIC = 32'hA55A5AA5
opcode
```

Parser распознает команду после полного слова `CMD_MAGIC`. Следующее полное слово потребляется как opcode. Известный opcode запускает действие. Неизвестный opcode завершает frame без изменения состояния. Оба слова service frame остаются внутри control path.

Поддерживаемые opcode:

| Opcode | Значение | Действие |
| --- | --- | --- |
| `CMD_CLR_SERVICE_ERROR` | `32'h00000001` | очистить `service_frame_error` |
| `CMD_SET_LOOPBACK` | `32'hA5A50004` | перейти в loopback mode |
| `CMD_SET_NORMAL` | `32'hA5A50005` | вернуться в normal mode |
| `CMD_GET_STATUS` | `32'hA5A50006` | запросить status response |
| `CMD_FT601_RESET` | `32'hA5A50007` | сформировать `RESET_N=0` для FT601 на два такта `CLK` |

Ответ на `CMD_GET_STATUS`:

```text
STATUS_MAGIC = 32'h5AA55AA5
status_word
```

`status_word`:

| Биты | Значение |
| --- | --- |
| `0` | `loopback_mode` |
| `1` | `service_frame_error` |
| `2` | `tx_fifo_empty` |
| `3` | `tx_fifo_full` |
| `4` | `loopback_fifo_empty` |
| `5` | `loopback_fifo_full` |
| `31:6` | `0` |

## Mode switch и diagnostic clear

Переходы между `normal` и `loopback` выполняет `cmd_decoder.v`. При смене режима decoder выставляет `mode_switch_busy`, дожидается idle-состояния FT path и только после этого фиксирует новый `loopback_mode`. Переключение режима не выполняет reset FT-домена и не очищает FIFO.

`mode_switch_busy` нужен только как временный запрет новых service/TX действий во время безопасной смены режима. Он не является reset или flush сигналом.

Diagnostic clear отделен от reset. В текущей RTL-модели удерживаемым диагностическим флагом является только `service_frame_error`. Его очищает команда `CMD_CLR_SERVICE_ERROR`.

## Диагностика

Внешний статус содержит один удерживаемый диагностический флаг: `service_frame_error`. Он выставляется, если после `CMD_MAGIC` принято неполное opcode-слово. Флаг удерживается до service-команды очистки.

`full` и `empty` у `async_fifo` и `loopback_fifo` являются обычными состояниями FIFO. Они запрещают запись или чтение на тот такт, где операция невозможна, но не превращаются в sticky error. Когда место в FIFO появляется или данные становятся доступны, поток продолжает работу без обязательной диагностической очистки.

| Флаг | Событие |
| --- | --- |
| `service_frame_error` | после `CMD_MAGIC` принято не полное 32-битное opcode-слово |

Обычный `valid && !ready` на внутреннем stream-интерфейсе сам по себе не считается ошибкой. `CMD_CLR_SERVICE_ERROR` очищает `service_frame_error`.

## FT601 handshake и timing

На внешней границе FT601 используются зарегистрированные управляющие сигналы. `TXE_N` и `RXF_N` принимаются через `ft601_wrapper.v`, регистрируются в FT-домене и затем используются FSM/adapters. `WR_N`, `RD_N`, `OE_N`, `DATA`, `BE` также проходят через зарегистрированную boundary-логику wrapper.

TX path работает от общего `tx_axis_*` stream. Когда выбранный источник имеет данные, `ft601_tx_adapter.v` подготавливает слово, управляет prefetch/output-регистрами, выставляет `DATA/BE` и активирует `WR_N` только в write-фазе. `drive_tx` управляет tri-state отдельно от `WR_N`, поэтому шина данных включается и выключается явно. При смене направления `ft601_fsm.v` проходит через `TURNAROUND`, где write/read стороны FT601 bus одновременно не активны.

RX path работает через `ft601_rx_adapter.v`. FSM активирует read-фазы, adapter управляет `OE_N/RD_N`, сэмплирует `DATA/BE` и выдает слово в `ft_rx_axis_*`. Внутри adapter есть небольшая очередь для принятых слов и незавершенных read-операций, поэтому `ft_rx_axis_tvalid/tdata/tkeep` удерживаются до `valid && ready`. Commit принятого слова выполняется только пока зарегистрированный `RXF_N` остается активным; это не дает последнему stale-слову попасть в stream, если FT601 закрыл RX-поток на границе пакета. Backpressure приходит через `ft_rx_axis_tready`: в loopback mode он зависит от свободного места в `loopback_fifo`, в normal mode RX path готов принимать service traffic. Управление `RD_N/OE_N` опирается на локальный credit adapter, а не на прямую downstream-ready цепочку.

Основные требования к handshake: отсутствует прямой combinational path от `TXE_N/RXF_N` pad к `WR_N/RD_N/OE_N`; `WR_N` и `drive_tx` остаются независимыми; `WR_N` и `OE_N` не активируются одновременно; при backpressure слова сохраняют порядок; во время active write `DATA/BE` стабильны; во время RX и reset ПЛИС не формирует FT601 data bus.

## Проверка

Основной самопроверочный стенд - `source/testbench.v`. Верхний flow проверяет reset, normal path, loopback path, diagnostics, две активные диагностические регрессии, FT601 boundary и payload boundary. Это соответствует текущему набору проверок RTL: базовые сценарии подтверждают рабочие режимы, а диагностические регрессии защищают участки, которые проверялись на плате.

Постоянные мониторы работают независимо от сценария. Они проверяют, что `WR_N` и `OE_N` не активны одновременно, запись не идет при закрытом `TXE_N`, чтение не идет при закрытом `RXF_N`, `DATA/BE` не конфликтуют на общей шине, а внутренние stream-линии удерживают `valid/data/keep` при `valid && !ready`. Фиксированная latency FTDI reference-дизайна не является pass/fail критерием.

### Сценарии использования

Сначала проверяется базовый запуск. Пользователь включает плату или нажимает `FPGA_RESET`, после чего дизайн должен выйти в безопасное состояние, снять внутренние reset-сигналы ПЛИС и стартовать в `normal mode`. `RESET_N` FT601 при этом остается в неактивном состоянии `1`, если не была отправлена команда `CMD_FT601_RESET`.

В `normal mode` проверяется основной поток от GPIO к ПК. Дизайн принимает байты со стороны GPIO, собирает их в 32-битные слова, формирует `BE` из `GPIO_STROB`, кладет `{DATA, BE}` в normal TX FIFO и отдает в FT601 без перестановок и потери маски байтов.

В `loopback mode` пользователь включает режим командой `SET_LOOPBACK`, подтверждает его через status и отправляет payload с ПК. Принятые слова должны пройти через RX path, loopback FIFO и TX arbiter обратно в FT601. После `FPGA_RESET` режим возвращается в `normal`, а повторное включение loopback снова должно давать корректный возврат payload.

В diagnostics-сценарии проверяются status frame, команда очистки service-ошибки и команда `CMD_FT601_RESET`. Status читается несколько раз подряд. Через `GET_STATUS` проверяются текущий режим, empty/full состояния FIFO и `service_frame_error`; очистка диагностического флага проверяется командой `CMD_CLR_SERVICE_ERROR`.

### Техническое покрытие сценариев

| Сценарий | Что делает testbench | Критерий прохождения |
| --- | --- | --- |
| `reset_boot_normal` | Активирует `FPGA_RESET`, проверяет inactive `WR_N/RD_N/OE_N`, tri-state `DATA/BE`, release доменных reset и неактивный `RESET_N=1`. | После release дизайн в `normal mode`, FT601 bus безопасен. |
| `normal_path` | Подает байтовый поток в GPIO/packer path, держит FT601 TX закрытым, затем разрешает передачу. | FT601 TX получает ожидаемые 32-битные слова и ожидаемую `BE`-маску из `GPIO_STROB`; порядок сохраняется, RX path не активируется. |
| `loopback_path` | Включает loopback, выполняет полный payload compare, затем проверяет loopback после `FPGA_RESET` и повторного `SET_LOOPBACK`. | Количество, порядок, `DATA` и `BE` на TX совпадают с отправленным RX payload; reset возвращает режим в `normal`. |
| `loopback_counter64_diagnostic` | Передает в loopback `64` 32-битных слова счетчика, повторяя payload из `ft601_test`. | Количество принятых RX-слов, записей loopback FIFO, чтений loopback FIFO и TX-слов равно `64`; первое и последнее слова сохраняются. |
| `service_status_diagnostic` | Запрашивает status при заполненном loopback FIFO и активном service/status path. | Status frame выходит как `STATUS_MAGIC + status_word`, а payload не вклинивается в короткое service-read окно. |
| `diagnostics` | Проверяет repeated `GET_STATUS`, `service_frame_error`, `CMD_CLR_SERVICE_ERROR`, `SET_LOOPBACK`, `SET_NORMAL` и двухтактный `RESET_N` от `CMD_FT601_RESET`. | Status frame всегда начинается с `STATUS_MAGIC`, diagnostic bits соответствуют ожидаемому состоянию, `CMD_CLR_SERVICE_ERROR` очищает `service_frame_error`, `CMD_FT601_RESET` не сбрасывает RTL. |
| `ft601_boundary` | Создает pending TX payload, затем активирует RXF_N как при ChipScope-захвате с одновременной готовностью TX/RX. | `WR_N` не пересекается с `OE_N/RD_N`, `DATA/BE` корректно переключаются между drive и tri-state, RX получает приоритет через безопасную смену направления. |
| `payload_boundary` | Передает loopback payload больше `1024` слов, делает RX/TX-паузы на границах `128` слов и проверяет внутренние счетчики RX/FIFO/TX. | На границах пакетов не появляются adjacent-дубли и stale-слова; количество принятых, записанных, прочитанных и отправленных слов совпадает. |

Обязательные локальные команды:

```powershell
cd .\source
iverilog -g2005-sv -o testbench.out testbench.v
vvp .\testbench.out
verilator_bin.exe --lint-only --timing testbench.v
```

После timing-sensitive RTL-изменений используется ISE flow. Минимум - `xst -ifn top.xst -ofn top.syr`. Для оценки частоты нужны post-PAR отчеты `top.twr` и `top.twx`.

Host-side проверка выполняется через `ft601_test`. Базовый сценарий: `GET_STATUS`, `SET_LOOPBACK`, `Write test payload`, `Read payload to file`, `SET_NORMAL`, `CLR_SERVICE_ERROR`, снова `GET_STATUS`. Raw-операция `Write test payload` создает `64` значения счетчика, сохраняет `*_raw_tx.bin` и отправляет каждое значение четырьмя байтами: `00 00 00 01`, `00 00 00 02` и далее. `Read payload to file` включает потоковое чтение `EP82` чанками по `256 KiB`, работает до нажатия `q`, сохраняет фактически принятый raw dump и не сравнивает его с TX-файлом. Для raw read утилита использует `FT_SetStreamPipe`, временно ставит короткий timeout на `EP82` для проверки клавиши остановки, печатает статистику из отдельного stats-потока примерно раз в секунду, затем выполняет `FT_ClearStreamPipe` и возвращает обычный timeout для status-read. Все menu-action, кроме отрисовки меню, получают timestamp-маркеры в `log.txt`.

## Исходники архитектуры

Ключевые RTL-файлы: `top.v`, `ft601_wrapper.v`, `ft601_fsm.v`, `ft601_rx_adapter.v`, `ft601_tx_adapter.v`, `axis_fifo_write_adapter.v`, `axis_fifo_read_adapter.v`, `axis_tx_arbiter.v`, `rx_stream_router.v`, `cmd_decoder.v`, `status_source.v`, `async_fifo.v`, `loopback_fifo.v`, `sram_dualport.v`, `gpio_wrapper.v`, `packer8to32.v`, `rst_sync.v`, `bit_sync.v`, `pulse_sync.v`.

Ограничения лежат в `source/callistoS6.ucf`. Testbench - `source/testbench.v`. Host-side проверка - в `ft601_test/`.
