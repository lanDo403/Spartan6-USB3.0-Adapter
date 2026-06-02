# AXIS_PLAN.md

> Этот файл является проектным планом применения универсальных правил из `AXI_REF.md` к текущей RTL-архитектуре. Он не заменяет `SPECIFICATION.md`: реализованное состояние нужно сверять по RTL, testbench и `SPECIFICATION.md`.

## Назначение

Цель плана - постепенно привести внутренние data-bearing связи проекта к более чистому AXI-Stream-like subset без глобального переписывания RTL, без изменения внешнего FT601/GPIO поведения и без ухудшения timing.

Универсальные правила не дублируются здесь. Перед каждым этапом нужно смотреть `AXI_REF.md`, особенно разделы:

- handshake `TVALID/TREADY`;
- `TKEEP`;
- source/sink;
- FIFO write/read adapters;
- router/demux;
- arbiter/join;
- register slice / skid buffer;
- CDC;
- timing и testbench checklist.

## Что считается AXI-Stream-like внутри проекта

Для внутренних потоков данных используется subset:

- `tvalid` - источник держит валидное слово;
- `tready` - приемник готов принять слово;
- `tdata[31:0]` - 32-разрядное слово;
- `tkeep[3:0]` - byte-enable mask, соответствующая `BE[3:0]`;
- transfer происходит только при `tvalid && tready`;
- source удерживает `tdata/tkeep`, пока слово не принято.

`TLAST` не добавляется без отдельного технического решения. В текущем протоколе service/status frame имеет фиксированную длину, а payload идет как поток слов.

## Границы, которые не надо насильно превращать в AXI-Stream

Не являются AXI-Stream и остаются специализированными интерфейсами:

- физические pins FT601;
- `ft601_wrapper.v`, потому что это I/O boundary, IOB-регистры, tri-state и active-low FT601 pins;
- внешний GPIO-вход, потому что у источника нет обратного `ready`;
- reset/control/diagnostic side effects;
- внутренние указатели FIFO/SRAM.

AXI-Stream-like контракт должен начинаться после специализированных wrapper/adapters.

## Текущее состояние

Близкие к AXI-Stream участки:

- `ft601_fsm.v`: единый TX stream input и RX stream output на уровне интеграции;
- `ft601_rx_adapter.v`: преобразует FT601 read bus в RX stream;
- `ft601_tx_adapter.v`: принимает выбранный TX stream и пишет в FT601;
- `rx_stream_router.v`: разделяет RX stream на service/control и loopback payload;
- `axis_fifo_write_adapter.v`: stream-to-FIFO write adapter;
- `axis_fifo_read_adapter.v`: FIFO-to-stream read adapter;
- `axis_tx_arbiter.v`: fixed-priority TX arbiter;
- `status_source.v`: двухсловный status stream source.

Текущие архитектурные шероховатости:

- `tx_prefetch_en` связывает RX-router с TX-read path;
- `axis_fifo_read_adapter.v` зависит от внешнего `enable_i`, в который смешаны mode select, status priority и готовность FT601;
- `ft601_tx_adapter.v` знает о `prefetch_en_i` и `status_sel_i`, хотя должен видеть только выбранный `s_axis_*` поток и локальные FT601 bus-фазы;
- `top.v` содержит отдельную `status_payload_hold` логику, которая защищает service/status read от смешивания с payload;
- `axis_tx_arbiter.v` содержит frame-lock и preemption-поведение, которое нужно явно сохранить или вытеснить в отдельный policy-блок;
- нет явного решения, нужен ли skid/register boundary между `axis_tx_arbiter.v` и `ft601_tx_adapter.v` для разрыва ready-chain.

## Главное проектное решение перед рефакторингом

Нужно сохранить текущую внешнюю семантику: `CMD_GET_STATUS` должен выдавать `STATUS_MAGIC + status_word` без вклинивания payload.

С точки зрения строгого AXI-Stream нельзя молча отбросить слово после handshake. Поэтому возможны два пути:

1. Оставить service-priority preemption как локальное документированное исключение, но не размазывать его по нескольким модулям.
2. Перейти к строгому AXI-Stream: если payload уже принят downstream-границей, status response выходит после него.

Выбранный путь для этого плана: оставить service-priority поведение, но локализовать его в отдельном маленьком policy-блоке между control/status логикой и TX payload path. Это практичнее для текущего FT601 endpoint, где status и payload читаются через один IN pipe.

Выбранный архитектурный вариант:

- не оставлять policy в `top.v` как набор разрозненных регистров и assign-ов;
- не встраивать policy внутрь `axis_tx_arbiter.v`, чтобы arbiter оставался arbiter-ом;
- ввести отдельный небольшой service/status policy-блок, который владеет service read window и payload blocking.

Ожидаемая роль этого блока:

- принимать control-события уровня `status_req`, `status_frame_active`, локальное наблюдение за `TXE_N`/окном host-side read и при необходимости `mode_switch_busy`;
- формировать policy-сигналы вроде `payload_block`, `status_window_active`, `status_start_ready` или их упрощенный эквивалент;
- блокировать payload до AXI-handshake на downstream boundary, а не после него;
- не владеть маршрутизацией normal/loopback/status data-word-ов и не дублировать stream muxing.

## Skid buffer policy для этого плана

Skid buffer использовать не как обязательный AXI-Stream элемент, а как точечный timing/decoupling-инструмент по правилам из `AXI_REF.md`.

Главный кандидат:

- граница `axis_tx_arbiter.v -> ft601_tx_adapter.v`.

Причина:

- именно здесь сходятся normal, loopback и status sources;
- downstream готовность зависит от локального состояния FT601 TX path и `TXE_N`;
- без буфера может возникать длинная цепочка `TXE_N / TX adapter ready -> arbiter -> FIFO read adapter ready`;
- skid/register boundary может сделать `ft601_tx_adapter.v` обычным AXI-Stream sink с локальным буфером.

Где skid buffer пока не ставить:

- между каждым модулем подряд;
- на GPIO boundary;
- внутри `ft601_wrapper.v`;
- в `status_source.v`, если он уже держит двухсловный frame корректно;
- поверх `axis_fifo_read_adapter.v`, если его front/lookahead buffer уже выполняет ту же функцию.

Критическое ограничение:

- если payload слово принято в skid buffer после AXI-handshake, его нельзя молча отбросить ради `STATUS_MAGIC`;
- service/status priority должен блокировать payload до входа в skid buffer либо гарантировать, что уже принятое payload-слово будет отправлено раньше status response;
- поэтому skid buffer нельзя добавлять до локализации service/status policy.

Практический порядок:

1. Сначала локализовать service/status policy в отдельном блоке.
2. Затем убрать лишние sideband-связи и привести FIFO adapters/arbiter к явному `valid/ready`.
3. После этого проверить timing и ready-chain.
4. Если путь `axis_tx_arbiter -> ft601_tx_adapter -> source ready` остается длинным, добавить один skid/register boundary на этой границе.
5. После добавления проверить, что status frame не смешивается с payload и payload не теряется после handshake.

## Stage 0. Аудит по `AXI_REF.md`

Цель: перед кодовыми изменениями классифицировать текущие data-bearing связи по ролям из `AXI_REF.md`.

Что сделать:

- составить короткую таблицу `source/sink/router/arbiter/FIFO adapter/wrapper` для текущих модулей;
- отметить, где есть настоящий `valid/ready/data/keep`, а где только похожие сигналы;
- отметить все sideband-сигналы, влияющие на data flow: `tx_prefetch_en`, `enable_i`, `status_sel_i`, `status_payload_hold`, `status_txe_low_seen`, `tx_payload_accept`, `status_start_ready`, `mode_switch_busy`;
- определить, какие sideband-сигналы являются control-policy и должны остаться вне stream-контракта;
- определить, какие sideband-сигналы дублируют `valid/ready` и могут быть убраны.
- отметить ready-chain, где потенциально нужен skid/register boundary, особенно `axis_tx_arbiter -> ft601_tx_adapter`.
- отдельно отметить AXIS commit-boundary: после какого handshake слово уже считается принятым и не может быть отброшено ради status priority.

Критерий:

- есть понятный список интерфейсов, которые рефакторятся;
- нет попытки менять все модули одновременно;
- исключения от AXI-Stream описаны явно.

## Stage 0.5. Локализовать service/status policy в отдельный блок

Цель: до упрощения arbiter/TX adapter убрать размазанную service/status policy из `top.v` и зафиксировать единое место владения этой логикой.

Что сделать:

- определить интерфейс отдельного policy-блока: какие входы являются control/event (`status_req`, `status_frame_active`, `txe_n`, возможно `mode_switch_busy`), а какие выходы управляют только policy-gating;
- перенести в этот блок текущую логику, эквивалентную `status_payload_hold`, `status_txe_low_seen` и `tx_payload_accept`, либо ее упрощенный вариант;
- сделать так, чтобы normal/loopback payload блокировался до downstream AXI-handshake, если требуется приоритетный status response;
- оставить `axis_tx_arbiter.v` data mux-ом, `status_source.v` - source-ом, а `ft601_tx_adapter.v` - sink/bus-writer-ом;
- явно определить, что этот блок не имеет права принимать и потом отбрасывать уже handshaken payload-слово.

Что не делать:

- не переносить в policy-блок сам выбор normal/loopback/status data-word;
- не превращать policy-блок в еще один arbiter или FIFO;
- не смешивать в нем FT601 pin-level управление с stream policy.

Критерий:

- service/status policy живет в одном отдельном месте;
- `top.v` перестает быть владельцем сложной service window логики;
- дальше можно упрощать `axis_tx_arbiter.v` и `ft601_tx_adapter.v` без неявной зависимости от текущих регистров в `top.v`.

## Stage 1. Убрать RX-to-TX sideband `tx_prefetch_en`

Цель: `rx_stream_router.v` должен быть router/demux, а не управляющим блоком TX-prefetch.

Текущее проблемное место:

- `rx_stream_router.v` формирует `tx_prefetch_en_o`;
- `top.v` использует его для normal/loopback FIFO read adapters;
- `ft601_fsm.v` / `ft601_tx_adapter.v` получают `tx_prefetch_en_i` / `prefetch_en_i`.

Что сделать:

- убрать `tx_prefetch_en_o` из `rx_stream_router.v`;
- убрать `tx_prefetch_en_i` из `ft601_fsm.v`, если после анализа он не нужен;
- убрать `prefetch_en_i` из `ft601_tx_adapter.v`, если source-read можно выразить через `s_axis_tready_o` и локальную готовность adapter-а;
- разрешение чтения normal/loopback FIFO держать через выбор источника, `ready` и отдельный service-policy блок, а не через RX-router;
- не менять framed service protocol.

Критерий:

- RX-router не управляет TX path;
- payload и service/status не смешиваются;
- не появляется длинный combinational path от RX-router к FIFO read/TX ready.

## Stage 2. Привести FIFO adapters к ролям из `AXI_REF.md`

Цель: `axis_fifo_write_adapter.v` и `axis_fifo_read_adapter.v` должны быть простыми adapter-модулями, а не носителями mode/service политики.

### Write adapter

Ожидаемая роль:

- принять `s_axis_tvalid/tdata/tkeep`;
- выставить `s_axis_tready` по `enable_i`, `fifo_full_i` и валидности `tkeep`;
- сформировать `fifo_wen_o` только при handshake;
- записать `{tdata, tkeep}` без потери byte-enable.

Что проверить:

- `tkeep` не заменяется константой там, где он уже значим;
- `fifo_wen_o` не зависит от сторонних условий, которые лучше держать в `top.v` или router-е;
- `enable_i` остается только как внешний gate для режима, а не превращается во внутреннюю политику.

### Read adapter

Ожидаемая роль:

- запросить FIFO read, когда есть место во внутреннем buffer-е;
- выдать `m_axis_tvalid/tdata/tkeep`;
- удерживать слово при `valid && !ready`;
- не знать про `loopback_mode`, status, FT601 `TXE_N` и command state.

Что сделать:

- оставить внутри read adapter только FIFO-facing `ren` и output/skid/front buffer;
- mode select и status priority держать выше: в отдельном service-policy блоке и/или на уровне выбора stream-источника, но не внутри adapter-а;
- не тянуть `TXE_N` напрямую в `enable_i`, если это можно выразить через downstream `ready`.
- сохранить read adapter как latency-hiding source с front/lookahead buffer, а не упрощать до наивного одиночного регистра.

Критерий:

- FIFO adapters соответствуют разделам `FIFO write adapter` и `FIFO read adapter` из `AXI_REF.md`;
- `data/keep` стабильны при `valid && !ready`;
- no-read-when-empty и no-write-when-full сохраняются.

## Stage 3. Упростить `axis_tx_arbiter.v`

Цель: сделать специализированный fixed-priority arbiter/join по правилам `AXI_REF.md`.

Приоритет остается:

1. status response;
2. loopback payload при `loopback_mode=1`;
3. normal payload при `loopback_mode=0`.

Что проверить:

- можно ли использовать стандартный output-register pattern `can_load = !m_axis_tvalid || m_axis_tready`;
- не забирает ли arbiter слово у source раньше, чем downstream готов принять output;
- убрать из arbiter-а ownership service window policy; если frame-lock нужен для двухсловного status source, он должен относиться только к stream selection, а не к host-side payload blocking;
- достаточно ли блокировать payload sources через отдельный policy-блок до status completion;
- не дублируется ли status-lock между `axis_tx_arbiter.v`, `status_source.v` и отдельным policy-блоком;
- нужен ли output-register/skid-ready boundary на выходе arbiter-а, или текущий output-регистр уже закрывает эту задачу.

Что не делать:

- не делать универсальный параметризованный N-to-1 arbiter;
- не добавлять `TLAST` ради двухсловного status frame;
- не добавлять новые FIFO/очереди без timing или функциональной причины.

Критерий:

- source получает `ready` только если выбран и downstream готов;
- status frame выходит атомарно;
- normal и loopback не выбираются одновременно;
- payload не теряется из FIFO.
- arbiter не владеет service read window policy;
- если добавлен skid/register boundary, уже принятое слово не теряется при status priority.

## Stage 4. Разгрузить `ft601_tx_adapter.v`

Цель: TX adapter должен быть sink + bus writer, а не участником политики выбора источника.

Оставить роли:

- принять один выбранный `s_axis_*` поток;
- буферизовать минимум, нужный для непрерывной FT601 write-фазы;
- управлять `DATA/BE`, `WR_N`, `drive_tx` через локальную FT601 bus-логику;
- учитывать `TXE_N` только как готовность физического приемника.

Убрать или локализовать после анализа:

- `prefetch_en_i`;
- `status_sel_i`, если его смысл после выделения policy-блока можно выразить через обычный stream sequencing;
- дублирование source selection;
- условия, которые должны жить в arbiter-е или в отдельном service-policy блоке.

Skid/register boundary:

- если timing или чистота ready-chain требуют буфер, размещать его на входе TX adapter-а или сразу перед ним;
- этот буфер должен принимать только уже выбранный общий `s_axis_*` поток;
- буфер не должен знать про normal/loopback/status;
- service/status policy должна работать до этого буфера.

Критерий:

- `ft601_tx_adapter.v` не знает про normal/loopback/status как отдельные источники;
- он видит только один `s_axis_*` вход;
- `s_axis_tready_o` отражает возможность принять слово в локальный buffer;
- `WR_N` активируется только при валидном output word и готовом FT601;
- `DATA/BE` стабильны во время write.
- если используется skid buffer, он не создает дублей, потерь и нарушения status frame ordering.

## Stage 5. Оставить `ft601_fsm.v` координатором FT601 bus

Цель: FSM управляет фазами общей FT601 шины, но не выбирает payload/status источники.

Что сохранить:

- состояния доступа к FT601;
- выбор направления RX/TX;
- turnaround между направлениями;
- запрет одновременной активности `WR_N` и `OE_N/RD_N`;
- отсутствие прямого combinational path от `TXE_N/RXF_N` pad к `WR_N/RD_N/OE_N`.

Что упростить:

- убрать входы, относящиеся к TX-prefetch policy;
- оставить связь с одним TX stream sink и одним RX stream source;
- не переносить в FSM логику service/status arbitration или service window policy.

Критерий:

- `ft601_fsm.v` координирует только FT601 bus;
- выбор normal/loopback/status находится вне FSM;
- FSM interface остается небольшим и понятным.

## Stage 6. Проверить `rx_stream_router.v` как router, не fork

Цель: RX path должен быть router/demux по правилам `AXI_REF.md`.

Ожидаемая модель:

- service frame потребляется control path;
- payload в loopback mode идет в loopback FIFO;
- payload вне loopback mode не должен случайно попадать в loopback FIFO;
- одно слово не должно одновременно идти в service path и payload path.

Что проверить:

- parser `CMD_MAGIC + opcode` не создает ложный payload;
- malformed service frame выставляет только нужный diagnostic flag;
- router не управляет TX path;
- `s_axis_tready_o` отражает готовность выбранного downstream-пути;
- нет лишних counters/flags, которые не используются в статусе или проверках.

Критерий:

- router соответствует разделу `Router / demux` из `AXI_REF.md`;
- service/control и payload изолированы;
- fork-логика не появляется без необходимости.

## Stage 7. Локализовать service/status policy

Цель: после раннего выделения policy-блока проверить, что выбранная локализация действительно закрывает весь service/status exception и не оставляет дублирующей логики в других модулях.

Что решить:

- где именно находится policy-блок, который блокирует payload на время service/status read;
- не осталось ли скрытых policy-условий в `axis_tx_arbiter.v`, `ft601_tx_adapter.v`, `ft601_fsm.v` или `rx_stream_router.v`;
- какие сигналы являются policy/control, а какие stream handshake;
- как гарантируется, что payload FIFO не теряет данные;
- как host-side stale payload перед status обрабатывается без усложнения RTL.

Критерий:

- status response начинается с `STATUS_MAGIC`;
- status frame не перемешивается с payload;
- локально принятое payload-слово не теряется молча после AXI handshake;
- код не размазывает одну policy по `top.v`, arbiter, TX adapter и RX router одновременно;
- отдельный policy-блок имеет минимальный и понятный интерфейс.

## Stage 8. Testbench по чеклисту `AXI_REF.md`

Цель: после каждого RTL-этапа проверять не только сценарии, но и stream-контракт.

Обязательные проверки:

- reset boot в normal mode;
- normal path;
- loopback path;
- diagnostics/status;
- payload boundary без дублей;
- service/payload isolation;
- stream stability: при `valid && !ready` данные и `keep` стабильны;
- source не снимает `valid` до handshake;
- sink не принимает слово без `ready`;
- FIFO adapters сохраняют `tkeep` вместе с `tdata`.
- always-on checks как минимум для `ft_rx_axis_*`, `loopback_payload_*`, `normal_axis_*`, `loopback_axis_*`, `status_axis_*`, `tx_axis_*`.

Команды:

```powershell
cd .\source
iverilog -g2005-sv -o testbench.out testbench.v
vvp .\testbench.out
verilator_bin.exe --lint-only --timing testbench.v
```

Для timing-sensitive изменений дополнительно смотреть ISE synthesis/implementation reports.

## Stage 9. Документация после реализации этапов

Обновлять только после фактического изменения поведения или интерфейса:

- `SPECIFICATION.md` - если изменился datapath, stream-contract, reset/status/service behavior;
- `README.md` - если изменился пользовательский workflow или высокоуровневое описание;
- `ft601_test/README.md` - если изменилось host-side поведение;
- `docs/FIXED.md` - фиксировать выполненные изменения и закрытые проблемы.

`AXI_REF.md` не менять под конкретный RTL. Он остается универсальным гайдом.

## Целевая структура после применения плана

```text
GPIO pins
  -> gpio_wrapper
  -> packer8to32
  -> axis_fifo_write_adapter
  -> async_fifo
  -> axis_fifo_read_adapter
  -> service_policy_block (gating/control only)
  -> axis_tx_arbiter
  -> ft601_tx_adapter
  -> ft601_fsm / ft601_wrapper
  -> FT601

FT601
  -> ft601_wrapper / ft601_fsm
  -> ft601_rx_adapter
  -> rx_stream_router
     -> cmd_decoder / status_source
     -> axis_fifo_write_adapter
     -> loopback_fifo
     -> axis_fifo_read_adapter
     -> service_policy_block (gating/control only)
     -> axis_tx_arbiter
     -> ft601_tx_adapter
     -> FT601
```

Главный принцип: универсальные правила берутся из `AXI_REF.md`, а этот файл фиксирует только порядок применения этих правил к текущей архитектуре проекта.
