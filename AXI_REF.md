# AXI_REF.md

## Назначение

Универсальный гайд по проектированию RTL на AXI-Stream-подобной модели.

Файл опирается на:
- reference-проекты из `docs/FTDI`;
- спецификации и руководства ARM/AMD/Xilinx;
- практические паттерны `valid/ready` для FPGA-дизайна.

Этот документ не описывает реализацию конкретного проекта. Его задача - дать правила и набор типовых блоков, которые можно применять при проектировании stream-архитектуры.

## Что такое AXI-Stream

AXI-Stream - однонаправленный потоковый интерфейс без адресации. Он подходит для передачи данных между блоками, если порядок слов важен, а доступ к памяти по адресу не нужен.

Минимальный набор сигналов:

| Сигнал | Направление | Назначение |
| --- | --- | --- |
| `TVALID` | source -> sink | источник держит валидное слово |
| `TREADY` | sink -> source | приемник готов принять слово |
| `TDATA` | source -> sink | данные |

Дополнительные часто используемые сигналы:

| Сигнал | Назначение |
| --- | --- |
| `TKEEP` | маска валидных байтов внутри `TDATA` |
| `TLAST` | конец пакета/frame |
| `TUSER` | пользовательские sideband-данные |
| `TID` | идентификатор потока |
| `TDEST` | адрес/назначение потока |

Для простой FPGA-архитектуры чаще достаточно `TVALID`, `TREADY`, `TDATA` и, если есть byte-enable, `TKEEP`.

## Основное правило handshake

Передача происходит только в такт, где одновременно активны `TVALID` и `TREADY`:

```verilog
wire axis_fire = tvalid && tready;
```

Правила:

- источник может выставить `TVALID` независимо от `TREADY`;
- приемник может выставить `TREADY` независимо от `TVALID`;
- если `TVALID=1` и `TREADY=0`, источник обязан удерживать `TDATA`, `TKEEP`, `TLAST` и sideband-сигналы стабильными;
- если `TVALID && TREADY`, слово считается принятым;
- после handshake источник может выдать следующее слово или снять `TVALID`;
- нельзя делать combinational loop между `TVALID` и `TREADY`.

Типовой source-регистр:

```verilog
always @(posedge clk) begin
    if (!rst_n) begin
        m_axis_tvalid <= 1'b0;
    end else if (!m_axis_tvalid || m_axis_tready) begin
        m_axis_tvalid <= next_valid;
        m_axis_tdata  <= next_data;
        m_axis_tkeep  <= next_keep;
    end
end
```

Условие `!m_axis_tvalid || m_axis_tready` означает: выходной регистр можно обновлять, если он пустой или текущее слово принято downstream-блоком.

## Нейминг

Рекомендуемый стиль портов:

```verilog
// Slave/input stream
input  wire        s_axis_tvalid_i,
output wire        s_axis_tready_o,
input  wire [31:0] s_axis_tdata_i,
input  wire [3:0]  s_axis_tkeep_i,

// Master/output stream
output wire        m_axis_tvalid_o,
input  wire        m_axis_tready_i,
output wire [31:0] m_axis_tdata_o,
output wire [3:0]  m_axis_tkeep_o
```

Локальные handshake-события:

```verilog
wire s_fire = s_axis_tvalid_i && s_axis_tready_o;
wire m_fire = m_axis_tvalid_o && m_axis_tready_i;
```

Для внутренних регистров удобно использовать суффикс `_ff`, для проводов - без суффикса или `_w`, если есть конфликт с портом.

## Типовые модули AXI-Stream архитектуры

### Source

Формирует `m_axis_*`.

Примеры:
- генератор тестовых данных;
- FIFO read adapter;
- packet/status frame source;
- memory-to-stream reader;
- receive-adapter физического интерфейса.

Главное требование: удерживать данные при `m_axis_tvalid_o && !m_axis_tready_i`.

### Sink

Принимает `s_axis_*`.

Примеры:
- FIFO write adapter;
- stream-to-memory writer;
- физический transmit-adapter;
- CRC/checker;
- packet parser.

Главное требование: принимать слово только при `s_axis_tvalid_i && s_axis_tready_o`.

### Register slice

Одностадийная регистрация stream-интерфейса.

Нужна, если:
- длинный путь по `TREADY` портит timing;
- нужно разорвать combinational path;
- между крупными блоками нужна понятная timing boundary.

Register slice обычно добавляет 1 такт latency, но упрощает timing closure.

### Skid buffer

Skid buffer нужен, когда downstream может снять `ready`, а upstream уже выдал слово. Он сохраняет одно дополнительное слово и не теряет данные при registered-ready архитектуре.

Типовая проблема:

```text
source -> long ready path -> sink
```

Если `TREADY` вычисляется через длинную цепочку условий, timing ухудшается. Если просто зарегистрировать `TREADY`, появляется риск: source еще один такт считает, что sink готов, и выдает слово. Skid buffer принимает это "лишнее" слово в запасной регистр.

Минимальная модель:

```text
input stream -> output register -> output stream
                   |
                   v
              skid register
```

Роли регистров:

- output register держит текущее слово на выходе;
- skid register хранит одно слово, принятое в момент, когда downstream уже остановился;
- input `TREADY` можно зарегистрировать или упростить, потому что есть место для аварийного слова;
- порядок слов сохраняется: сначала выходит output register, затем skid register.

Когда skid buffer полезен:

- нужно разорвать длинную `TREADY`-цепочку;
- downstream-ready приходит поздно относительно clock edge;
- source не должен останавливаться combinational-сигналом через несколько уровней логики;
- между arbiter/mux и физическим передатчиком нужен устойчивый registered boundary;
- требуется сохранить throughput `1 word/clock` при кратковременных stalls.

Когда skid buffer не нужен:

- уже есть корректный FIFO или output-register с тем же запасом;
- граница не timing-sensitive;
- поток идет только через один маленький модуль без длинного `ready`;
- добавление одного слова latency ломает protocol-level ordering;
- upstream уже нельзя корректно остановить, и нужен не skid, а полноценный FIFO/ingress buffer.

Важное ограничение: skid buffer принимает слово по AXI-handshake. После этого слово нельзя молча отбросить ради более приоритетного потока. Если в системе есть frame-priority или preemption, skid buffer должен стоять там, где уже принятое слово гарантированно будет отправлено, либо priority-policy должна блокировать вход skid buffer заранее.

Skid buffer - не замена FIFO. Он решает локальную проблему registered-ready и короткого stall, но не предназначен для накопления длинных bursts.

Проверки для skid buffer:

- нет потери слова при снятии downstream `TREADY`;
- порядок слов сохраняется;
- `TDATA/TKEEP/TLAST` стабильны при `TVALID && !TREADY`;
- при постоянном `TREADY=1` throughput остается `1 word/clock`;
- при чередовании `TREADY` нет дублей;
- reset очищает оба valid-регистра;
- sideband-сигналы проходят вместе с `TDATA`.

Reference:
- `docs/FTDI/wb2axip-master/wb2axip-master/rtl/skidbuffer.v`

Skid buffer не надо ставить везде. Его ставят только на границах с backpressure и timing-sensitive ready-chain.

### FIFO write adapter

Преобразует AXI-Stream input в raw FIFO write port.

Типовая логика:

```verilog
assign s_axis_tready_o = !fifo_full_i;
assign fifo_wen_o      = s_axis_tvalid_i && s_axis_tready_o;
assign fifo_data_o     = {s_axis_tdata_i, s_axis_tkeep_i};
```

Если `TKEEP=0` не должен записываться, это условие добавляют явно:

```verilog
assign fifo_wen_o = s_axis_tvalid_i && s_axis_tready_o && (s_axis_tkeep_i != 0);
```

### FIFO read adapter

Преобразует raw FIFO read port в AXI-Stream source.

Он нужен, если FIFO/RAM имеет зарегистрированный read-output или read-latency.

Обязанности:
- не читать FIFO, если output-регистр занят и downstream не готов;
- выставлять `TVALID`, когда есть слово;
- удерживать `TDATA/TKEEP` до handshake;
- не терять слово при `TREADY=0`.

### Router / demux

Один входной stream, несколько выходов. Слово направляется только в один output.

Примеры:
- command/data разделение;
- route по `TDEST`;
- route по header/opcode;
- route по режиму работы.

Правило: если слово принято на входе, выбранный выход тоже должен быть готов принять это слово. Иначе input `TREADY` должен быть снят.

### Broadcast / fork

Один входной stream, несколько выходов, одно и то же слово должно попасть во все selected outputs.

Fork сложнее router-а: input handshake допустим только тогда, когда все нужные outputs готовы или имеют внутренние буферы.

Если слово не должно идти одновременно в несколько мест, fork не нужен.

Reference:
- `docs/FTDI/wb2axip-master/wb2axip-master/rtl/axisbroadcast.v`

### Arbiter / mux / join

Несколько входных stream-source, один выходной stream.

Варианты:
- fixed priority;
- round-robin;
- weighted arbitration;
- frame-aware arbitration.

Правила:
- входной source получает `ready` только если он выбран и output готов;
- если используется `TLAST`, arbiter должен удерживать выбранный source до конца frame;
- если `TLAST` нет, атомарность frame должна обеспечиваться отдельной локальной логикой;
- нельзя забирать слово у source заранее, если оно потом может быть потеряно.

Reference:
- `docs/FTDI/wb2axip-master/wb2axip-master/rtl/axisswitch.v`

### Width converter / packer / unpacker

Изменяет ширину `TDATA` и пересчитывает `TKEEP`.

Примеры:
- 8 бит -> 32 бита;
- 32 бита -> 8 бит;
- 32 бита -> 64 бита;
- удаление пустых байтов по `TKEEP`.

References:
- `docs/FTDI/FPGA-ftdi245fifo-main/RTL/ftdi_245fifo/axi_stream_packing.v`
- `docs/FTDI/FPGA-ftdi245fifo-main/RTL/ftdi_245fifo/axi_stream_upsizing.v`
- `docs/FTDI/FPGA-ftdi245fifo-main/RTL/ftdi_245fifo/axi_stream_downsizing.v`
- `docs/FTDI/wb2axip-master/wb2axip-master/rtl/axispacker.v`

### Safety / protocol checker

Проверяет нарушения AXI-Stream контракта.

Типовые ошибки:
- `TDATA` меняется при `TVALID && !TREADY`;
- source снимает `TVALID` до handshake;
- `TLAST` меняется до handshake;
- frame не завершается;
- sink принимает данные без `TREADY`.

Reference:
- `docs/FTDI/wb2axip-master/wb2axip-master/rtl/axissafety.v`

## `TKEEP`

`TKEEP` показывает, какие байты внутри `TDATA` являются валидными.

Для 32-битного слова:

| Бит | Байты `TDATA` |
| --- | --- |
| `TKEEP[0]` | `TDATA[7:0]` |
| `TKEEP[1]` | `TDATA[15:8]` |
| `TKEEP[2]` | `TDATA[23:16]` |
| `TKEEP[3]` | `TDATA[31:24]` |

Правила:
- `TKEEP` должен идти вместе с `TDATA` через FIFO, router, arbiter и adapters;
- нельзя восстанавливать `TKEEP` константой, если выше по тракту он уже был значимым;
- если downstream не поддерживает partial words, это должно быть явно указано и проверено.

## `TLAST`

`TLAST` нужен только если есть реальная граница frame/packet:
- конец Ethernet-пакета;
- конец DMA-блока;
- конец строки/кадра видео;
- конец command frame переменной длины;
- принудительная отправка неполного слова после packer-а.

Если поток состоит из независимых слов или frame имеет фиксированную длину и отслеживается FSM, `TLAST` можно не вводить.

Плохая практика: добавлять `TLAST` только потому, что он есть в полном AXI-Stream. Неиспользуемый `TLAST` усложняет тесты и провоцирует ложную семантику packet boundary.

## Backpressure

Backpressure - нормальная часть AXI-Stream. `valid && !ready` не является ошибкой.

Ошибкой становится:
- потеря слова во время backpressure;
- изменение данных до handshake;
- бесконечный stall без документированной причины;
- combinational loop по `ready`;
- слишком длинный ready-path, который ломает timing.

Если блок не может остановить внешний источник, AXI-Stream должен начинаться после специализированного ingress-адаптера или FIFO.

## CDC

AXI-Stream сам по себе не решает crossing clock domains.

Для CDC нужны:
- async FIFO;
- handshake synchronizer для одиночных событий;
- pulse synchronizer;
- gray-code pointers внутри FIFO.

Нельзя напрямую соединять `TVALID/TREADY/TDATA` между разными clock-доменами.

## Timing

Типовые меры:
- registered outputs на границе крупных блоков;
- register slice/skid buffer на длинных ready-chain;
- короткие условия выбора source в arbiter;
- без широких combinational mux после сложной логики ready;
- без path от внешнего pad сразу в управляющий output;
- one-hot FSM там, где это улучшает timing и читаемость.

AXI-Stream архитектура не обязана быть fully combinational. Напротив, часто лучше добавить одну стадию регистрации, чем получить длинный критический путь.

## Testbench checklist

Для каждого stream-интерфейса проверить:

- transfer только при `TVALID && TREADY`;
- `TDATA/TKEEP/TLAST` стабильны при `TVALID && !TREADY`;
- source не теряет слово при stall;
- sink не принимает слово при `TREADY=0`;
- FIFO adapters сохраняют `TKEEP`;
- router не отправляет слово в неверный выход;
- arbiter не смешивает frame-слова разных источников;
- CDC не проверяется только поведенчески, а имеет отдельные assertions/структурные проверки.

## Reference-проекты в `docs/FTDI`

| Reference | Что смотреть |
| --- | --- |
| `docs/FTDI/wb2axip-master` | `skidbuffer`, `axissafety`, `axisbroadcast`, `axisswitch`, `axispacker`, AXI/AXIS bridges, DMA/data movers. |
| `docs/FTDI/core_ft60x_axi-master` | FT60x как AXI bus master, retiming, FIFO buffering, software transaction model. |
| `docs/FTDI/FPGA-ftdi245fifo-main` | FTDI 245 FIFO controller с AXI-Stream send/receive, byte enable, async FIFO, width conversion, loopback examples. |
| `docs/FTDI/I2C_Master_Controller-main` | Чистая valid/ready дисциплина, компактная модульность и понятный control/data split. |

## Внешние источники

- ARM AMBA AXI-Stream specification: https://www.arm.com/architecture/system-architectures/amba/amba-specifications
- AMD/Xilinx AXI Reference Guide UG1037: https://docs.amd.com/v/u/en-US/ug1037-vivado-axi-reference-guide
- AMD/Xilinx AXI4-Stream Infrastructure IP documentation: https://docs.amd.com/r/en-US/pg085-axi4stream-infrastructure
- ZipCPU `wb2axip`: https://github.com/ZipCPU/wb2axip
