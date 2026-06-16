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

Верхний уровень находится в `rtl/top.v`. Он соединяет GPIO-домен, FT-домен, FIFO, stream-router, arbiter, command decoder, status source и service/status policy. Последовательная логика распределена по небольшим модулям, поэтому `top.v` остается схемой соединений.

Физическая граница FT601 находится в `ft601_wrapper.v`. Там стоят буферы `IBUFG`, `IBUF`, `OBUF`, `IOBUF`, входная регистрация `TXE_N/RXF_N`, output-регистры управляющих сигналов и регистры для `DATA/BE`. Wrapper принимает уже готовые внутренние сигналы от FSM/adapters и выдает безопасный внешний интерфейс FT601.

`ft601_fsm.v` задает фазы доступа к FT601 и владеет сменой направления общей шины `DATA/BE`. Между RX- и TX-burst используется состояние `TURNAROUND`: в нем `WR_N`, `RD_N`, `OE_N` неактивны, а ПЛИС не формирует `DATA/BE`. RX-запрос имеет приоритет и может прервать TX burst через `TURNAROUND`, чтобы новые host-команды и loopback RX-пакеты не ждали окончания длинной TX-передачи. RX-захват вынесен в `ft601_rx_adapter.v`, TX stream sink и bus-writer вынесен в `ft601_tx_adapter.v`, поэтому FSM координирует только доступ к шине. Он видит один TX stream, один RX stream и зарегистрированные `TXE_N/RXF_N`; normal/loopback/status selection и mode-switch policy остаются вне FSM.

Внутренние потоки связаны AXI-Stream-подобным контрактом: `valid`, `ready`, `data`, `keep`. Передача слова происходит при `valid && ready`. Источник держит `data/keep` стабильными, пока приемник не подтвердил передачу через `ready`. `keep[3:0]` соответствует `BE[3:0]`, а `data[31:0]` соответствует `DATA[31:0]`. Stream-порты модулей используют `s_axis_*` для входного потока и `m_axis_*` для выходного. Границы service/status frame задаются фиксированной длиной в два слова и локальной control-логикой. FIFO write/read ports обернуты в `axis_fifo_write_adapter.v` и `axis_fifo_read_adapter.v`, чтобы stream-логика работала со стабильным handshake, а не с raw FIFO-сигналами.

Основные stream-ветки:

| Поток | Назначение |
| --- | --- |
| `normal_axis_*` | payload из normal TX FIFO |
| `loopback_axis_*` | payload из loopback FIFO |
| `status_axis_*` | status response source |
| `tx_axis_*` | общий TX stream после arbitration |
| `ft_rx_axis_*` | поток слов, принятых от FT601 |

`axis_tx_arbiter.v` выбирает источник для TX path. Приоритет фиксированный: status response, затем loopback при `loopback_mode=1`, затем normal TX FIFO при `loopback_mode=0`. Status frame удерживается самим `status_source.v` через `frame_active_o` до отправки двух слов: `STATUS_MAGIC` и `status_word`. Общий выход `tx_axis_*` зарегистрирован и использует обычное правило `can_load = !valid || ready`: если downstream не готов и output-регистр занят, `tx_axis_tdata/tx_axis_tkeep` не меняются; если output-регистр пуст, выбранное слово может быть принято и затем удерживается до downstream handshake.

Если `CMD_GET_STATUS` принят во время подготовленного payload TX, status request переводит TX path в service-priority режим. `service_status_policy.v` владеет service read window и payload blocking: normal/loopback FIFO-read останавливается не только на время двухсловного status frame, но и до тех пор, пока хост хотя бы один раз не откроет TX-окно для этого status-ответа и shared FT601 TX path не вернется в idle. Уже принятые локальными TX-register/buffer boundary payload-слова не отбрасываются arbiter-ом; поэтому перед `STATUS_MAGIC/status_word` в общем EP82 stream могут появиться stale payload words. Host-side status-read должен искать `STATUS_MAGIC` с ограниченным пропуском таких слов. Если `TXE_N` остается низким непрерывно, payload может продолжиться сразу за `STATUS_MAGIC/status_word` в том же длинном host-read. Если хост поднимает `TXE_N` сразу после двух status-слов, payload остается в FIFO до следующего чтения.

`rx_stream_router.v` принимает слова от FT601 RX adapter и разделяет их на service traffic и loopback payload как router/demux, а не fork. Service frame потребляется внутри control path. Payload-слова в loopback mode записываются в `loopback_fifo` как `{DATA, BE}`. Одно входное слово выбирает только один путь: `CMD_MAGIC` и следующий opcode не создают payload, malformed opcode выставляет только service diagnostic, payload вне loopback mode не пишется в loopback FIFO. `s_axis_tready_o` отражает готовность выбранного пути: payload backpressure применяется только к payload-словам, а service header/opcode может быть принят control path даже при заполненном payload buffer-е.

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

`mode_switch_busy` нужен только как временный запрет новых service/TX действий во время безопасной смены режима. `service_status_policy.v` использует его для payload blocking, status-source block и RX-router acceptance, пока FT path idle. `ft601_fsm.v` и `ft601_tx_adapter.v` этот сигнал не получают. Он не является reset или flush сигналом.

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

TX path работает от общего `tx_axis_*` stream. `ft601_tx_adapter.v` видит только уже выбранный stream, не получает normal/loopback/status/mode-switch sideband и не сбрасывает локальные буферы по service policy. Adapter принимает слово при `s_axis_tvalid && s_axis_tready`, держит output/lookahead-регистры, выставляет `DATA/BE` и активирует `WR_N` только в write-фазе при готовом FT601 (`TXE_N=0`). `drive_tx` управляет tri-state отдельно от `WR_N`, поэтому шина данных включается и выключается явно. При смене направления `ft601_fsm.v` проходит через `TURNAROUND`, где write/read стороны FT601 bus одновременно не активны.

RX path работает через `ft601_rx_adapter.v`. FSM активирует read-фазы, adapter управляет `OE_N/RD_N`, сэмплирует `DATA/BE` и выдает слово в `ft_rx_axis_*`. Внутри adapter есть небольшая очередь для принятых слов и незавершенных read-операций, поэтому `ft_rx_axis_tvalid/tdata/tkeep` удерживаются до `valid && ready`. Commit принятого слова выполняется только пока зарегистрированный `RXF_N` остается активным; это не дает последнему stale-слову попасть в stream, если FT601 закрыл RX-поток на границе пакета. Backpressure приходит через `ft_rx_axis_tready`: в loopback mode payload-слова зависят от свободного места в `loopback_fifo`, но service frame обслуживается control path отдельно; в normal mode RX path готов принимать service traffic. Управление `RD_N/OE_N` опирается на локальный credit adapter, а не на прямую downstream-ready цепочку.

Основные требования к handshake: отсутствует прямой combinational path от `TXE_N/RXF_N` pad к `WR_N/RD_N/OE_N`; `WR_N` и `drive_tx` остаются независимыми; `WR_N` и `OE_N` не активируются одновременно; при backpressure слова сохраняют порядок; во время active write `DATA/BE` стабильны; во время RX и reset ПЛИС не формирует FT601 data bus.

## Проверка

Основной самопроверочный стенд находится в `tb/` и написан на SystemVerilog. Официальный локальный симулятор - Vivado XSim. `rtl/testbench.v` остается старым Verilog-стендом и не является основным regression flow.

Точки входа:

| Файл | Назначение |
| --- | --- |
| `tb/testbench_main.sv` | Основные публичные сценарии: reset, normal path, loopback path, service/control. |
| `tb/testbench_requirements.sv` | Основные сценарии и дополнительные проверки требований FT601 boundary, payload, router, arbiter и mode/status policy. |
| `tb/testbench.sv` | Полный regression. |

Основные файлы тестового стенда:

| Файл | Назначение |
| --- | --- |
| `tb/tb_pkg.sv` | Общие константы, типы, коды команд, magic-слова и helper-функции. |
| `tb/tb_ft601_if.sv` | SystemVerilog interface для внешней шины FT601. |
| `tb/tb_axis_if.sv` | SystemVerilog interface для внутренних stream-линий. |
| `tb/tb_common.svh` | Общие задачи подготовки стенда и базовые операции сценариев. |
| `tb/tb_ft601_driver.svh` | Драйвер модели FT601 для чтения и записи 32-битных слов. |
| `tb/tb_gpio_driver.svh` | Драйвер GPIO-входа для normal path. |
| `tb/tb_service_helpers.svh` | Помощники для служебных команд и чтения status frame. |
| `tb/tb_scoreboard.svh` | Сравнение ожидаемых и фактически принятых данных. |
| `tb/tb_monitors.svh` | Пассивные проверки шины FT601 и stream-протокола. |
| `tb/tb_assertions.svh` | Assertions для reset, handshake, arbitration, FSM и ключевых флагов. |
| `tb/tb_coverage.svh` | Обязательные счетчики покрытия и SystemVerilog `covergroup`. |
| `tb/tb_runtime.svh` | Итоговый pass/fail, summary покрытия и завершение симуляции. |
| `tb/scenarios/*.svh` | Группы сценариев для основных потоков и требований спецификации. |

Активные проверки являются проверками требований из этой спецификации; старые сценарии воспроизведения багов, host-log sequences и AXIS_PLAN stage diagnostics не входят в официальный regression.

Постоянные мониторы работают независимо от сценария. Они проверяют, что `WR_N` и `OE_N` не активны одновременно, запись не идет при закрытом `TXE_N`, чтение не идет при закрытом `RXF_N`, `DATA/BE` не конфликтуют на общей шине, а внутренние stream-линии удерживают `valid/data/keep` при `valid && !ready`. Для управляющих FSM также должны проверяться допустимые состояния, допустимые переходы и ключевые флаги, которые напрямую разрешают или блокируют смену состояния, включая арбитраж TX-источников. Фиксированная latency FTDI reference-дизайна не является pass/fail критерием.

Pass/fail задают scoreboard, assertions и обязательные счетчики покрытия. Функциональное покрытие SystemVerilog включается через `TB_HAS_SV_COVERGROUP`; модель `covergroup` описывает bins на уровне требований и формирует отчет Vivado `xcrg`. Низкое code/functional coverage не должно использоваться вместо scoreboard, но полный regression должен завершаться без assertion/scoreboard ошибок и с `COVERAGE SUMMARY END missing_bins=0`.

### Сценарии использования

Сначала проверяется базовый запуск. Пользователь включает плату или нажимает `FPGA_RESET`, после чего дизайн должен выйти в безопасное состояние, снять внутренние reset-сигналы ПЛИС и стартовать в `normal mode`. `RESET_N` FT601 при этом остается в неактивном состоянии `1`, если не была отправлена команда `CMD_FT601_RESET`.

В `normal mode` проверяется основной поток от GPIO к ПК. Дизайн принимает байты со стороны GPIO, собирает их в 32-битные слова, формирует `BE` из `GPIO_STROB`, кладет `{DATA, BE}` в normal TX FIFO и отдает в FT601 без перестановок и потери маски байтов.

В `loopback mode` пользователь включает режим командой `SET_LOOPBACK`, подтверждает его через status и отправляет payload с ПК. Принятые слова должны пройти через RX path, loopback FIFO и TX arbiter обратно в FT601. После `FPGA_RESET` режим возвращается в `normal`, а повторное включение loopback снова должно давать корректный возврат payload.

В `service_control` проверяются status frame, команда очистки service-ошибки и команда `CMD_FT601_RESET`. Status читается несколько раз подряд. Через `GET_STATUS` проверяются текущий режим, empty/full состояния FIFO и `service_frame_error`; очистка диагностического флага проверяется командой `CMD_CLR_SERVICE_ERROR`.

### Техническое покрытие сценариев

| Сценарий | Что делает testbench | Критерий прохождения |
| --- | --- | --- |
| `reset_boot_normal` | Активирует `FPGA_RESET`, проверяет inactive `WR_N/RD_N/OE_N`, tri-state `DATA/BE`, release доменных reset и неактивный `RESET_N=1`. | После release дизайн в `normal mode`, FT601 bus безопасен. |
| `normal_path` | Подает байтовый поток в GPIO/packer path, держит FT601 TX закрытым, затем разрешает передачу. | FT601 TX получает ожидаемые 32-битные слова и ожидаемую `BE`-маску из `GPIO_STROB`; порядок сохраняется, RX path не активируется. |
| `loopback_path` | Включает loopback, выполняет полный payload compare, затем проверяет loopback после `FPGA_RESET` и повторного `SET_LOOPBACK`. | Количество, порядок, `DATA` и `BE` на TX совпадают с отправленным RX payload; reset возвращает режим в `normal`. |
| `service_control` | Проверяет repeated `GET_STATUS`, `service_frame_error`, `CMD_CLR_SERVICE_ERROR`, `SET_LOOPBACK`, `SET_NORMAL`, `CMD_FT601_RESET` и сохранение RTL-состояния при reset FT601. | Status frame всегда начинается с `STATUS_MAGIC`, diagnostic bits соответствуют ожидаемому состоянию, `CMD_CLR_SERVICE_ERROR` очищает `service_frame_error`, `CMD_FT601_RESET` не сбрасывает RTL. |
| `ft601_turnaround_rx_priority` | Создает pending TX payload, затем активирует `RXF_N` при открытом TX window. | `WR_N` не пересекается с `OE_N/RD_N`, `DATA/BE` корректно переключаются между drive и tri-state, RX получает приоритет через безопасную смену направления. |
| `ft601_rxf_boundary` | Закрывает RX-поток на границе read-beat. | RX adapter не пропускает stale-слово после закрытия `RXF_N`. |
| `long_gapped_loopback_payload` | Передает loopback payload больше `1024` слов с RX/TX-паузами и частичными `BE`. | Количество, порядок, `DATA` и `BE` совпадают с ожидаемой моделью, длинный/gapped payload не теряется. |
| `status_window_with_payload` | Запрашивает status при подготовленном payload TX. | Status frame находится через `STATUS_MAGIC`, service window освобождается после открытия TX-окна, stale payload учитывается как разрешенное внешнее поведение. |
| `mode_switch_waits_idle` | Переключает режим при активном FT-трафике. | Mode-switch policy не меняет источник до безопасного idle/hold состояния. |
| `router_demux_backpressure` | Проверяет service/payload demux и payload backpressure. | Service frame потребляется control path, payload идет только в loopback path, backpressure не превращает payload в service. |
| `arbiter_priority` | Одновременно подготавливает несколько TX-источников. | TX arbiter выбирает status выше loopback и normal, порядок payload после service сохраняется. |

Host-side проверка выполняется через D3XX-утилиту из `software/`. Базовый сценарий: `GET_STATUS`, `SET_LOOPBACK`, `Write test payload`, `Read payload to file`, `SET_NORMAL`, `CLR_SERVICE_ERROR`, снова `GET_STATUS`. Raw-операция `Write test payload` создает `64` значения счетчика, сохраняет `*_raw_tx.bin` и отправляет каждое значение четырьмя байтами: `00 00 00 01`, `00 00 00 02` и далее. `Read payload to file` включает потоковое чтение `EP82` чанками по `256 KiB`, работает до нажатия `q`, сохраняет фактически принятый raw dump и не сравнивает его с TX-файлом. Для raw read утилита использует `FT_SetStreamPipe`, временно ставит короткий timeout на `EP82` для проверки клавиши остановки, печатает статистику из отдельного stats-потока примерно раз в секунду, затем выполняет `FT_ClearStreamPipe` и возвращает обычный timeout для status-read. Все menu-action, кроме отрисовки меню, получают timestamp-маркеры в `log.txt`.

## Исходники архитектуры

Ключевые RTL-файлы:

| Файл | Назначение |
| --- | --- |
| `rtl/top.v` | Верхний уровень проекта, соединяет GPIO, FT601, service/control path и FIFO. |
| `rtl/ft601_wrapper.v` | Физическая граница FT601: регистрация внешних сигналов, управление `DATA/BE` и active-low линиями. |
| `rtl/ft601_fsm.v` | Управление фазами чтения, записи и turnaround на шине FT601. |
| `rtl/ft601_rx_adapter.v` | Преобразует чтение FT601 в внутренний stream с `valid/ready/data/keep`. |
| `rtl/ft601_tx_adapter.v` | Преобразует выбранный TX stream в запись на шину FT601. |
| `rtl/axis_tx_arbiter.v` | Выбирает TX-источник с приоритетом status выше loopback и normal payload. |
| `rtl/rx_stream_router.v` | Разделяет принятые слова на служебный поток и payload loopback. |
| `rtl/cmd_decoder.v` | Декодирует служебные команды и формирует управляющие импульсы. |
| `rtl/status_source.v` | Формирует `STATUS_MAGIC` и `status_word` для ответа ПК. |
| `rtl/service_status_policy.v` | Управляет окном чтения status и блокировкой payload во время service-ответа. |
| `rtl/axis_fifo_write_adapter.v` | Записывает stream-слова в FIFO с сохранением `DATA` и `BE`. |
| `rtl/axis_fifo_read_adapter.v` | Читает FIFO и выдает данные в stream-формате. |
| `rtl/async_fifo.v` | Асинхронная FIFO normal path между GPIO-доменом и FT-доменом. |
| `rtl/loopback_fifo.v` | FIFO для возврата payload из RX path в TX path. |
| `rtl/gpio_wrapper.v` | Синхронизирует внешний GPIO-вход и передает байты в packer. |
| `rtl/packer8to32.v` | Собирает GPIO-байты и `GPIO_STROB` в 32-битные слова с маской `BE`. |
| `rtl/rst_sync.v` | Синхронизатор reset для локального clock-domain. |
| `rtl/bit_sync.v` | Синхронизатор одиночного бита между clock-domain. |
| `rtl/pulse_sync.v` | Синхронизатор импульса между clock-domain. |

Ограничения лежат в `rtl/callistoS6.ucf`. Основной SystemVerilog testbench находится в `tb/`; старый Verilog-стенд - `rtl/testbench.v`. Проверка со стороны ПК находится в `software/`.
