# HANDOFF

## Purpose

This file is the short handoff for a fresh Codex chat. Use it to re-enter the project after clearing the conversation context.

## Source Of Truth

Use this order when information conflicts:

1. Current source code in `source/` and `ft601_test/`.
2. `SPECIFICATION.md`.
3. `README.md` and `ft601_test/README.md`.
4. `NEED_TO_FIX.md` for active hardware/software issues.
5. `AXIS_PLAN.md` for future AXI-Stream cleanup plans.
6. `AGENTS.md` for workflow rules, validation commands, reference map, and constraints.
7. `docs/FIXED.md` and `docs/UPDATE.md` only as history.
8. Old chat context should not be used as a source of truth.

## Current Implementation

The project is an RTL design for `Xilinx Spartan-6` + `FTDI FT601` in `245 synchronous FIFO` mode.

Current modes:

- `normal mode`: GPIO bytes -> packer -> normal async FIFO -> FT601 -> PC.
- `loopback mode`: PC -> FT601 -> loopback FIFO -> FT601 -> PC.
- `service/control`: PC sends framed commands and receives framed status response.

Internal datapath uses an AXI-Stream-like contract: `valid`, `ready`, `data[31:0]`, `keep[3:0]`. GPIO itself remains one-way and has no external backpressure.

## Protocol

Service commands go through `EP02` as two 32-bit words:

```text
CMD_MAGIC = 0xA55A5AA5
opcode
```

Status response is read from `EP82` as two 32-bit words:

```text
STATUS_MAGIC = 0x5AA55AA5
status_word
```

Supported opcodes:

- `CMD_CLR_SERVICE_ERROR = 0x00000001`
- `CMD_SET_LOOPBACK = 0xA5A50004`
- `CMD_SET_NORMAL = 0xA5A50005`
- `CMD_GET_STATUS = 0xA5A50006`
- `CMD_FT601_RESET = 0xA5A50007`

`status_word` bit layout:

| Bit | Meaning |
| --- | --- |
| `0` | `loopback_mode` |
| `1` | `service_frame_error` |
| `2` | `tx_fifo_empty` |
| `3` | `tx_fifo_full` |
| `4` | `loopback_fifo_empty` |
| `5` | `loopback_fifo_full` |
| `31:6` | `0` |

## Reset Model

- `FPGA_RESET` is the only internal RTL reset source.
- `FPGA_RESET` resets GPIO and FT domains through local reset synchronizers.
- `RESET_N` is an output from Spartan-6 to FT601.
- `CMD_FT601_RESET` only pulses external `RESET_N=0` for two FT601 `CLK` cycles.
- `CMD_FT601_RESET` does not clear RTL state, FIFOs, mode, adapters, router, FSM, or diagnostics.
- `CMD_CLR_SERVICE_ERROR` only clears `service_frame_error`.

## Host Utility

`ft601_test` is a synchronous console utility using D3XX API.

Menu:

1. `Write test payload`
2. `Read payload to file`
3. `Get FPGA status`
4. `Set loopback mode`
5. `Set normal mode`
6. `Clear service frame error`
7. `Reset FT601`
8. `Exit`

Important behavior:

- There is no separate loopback integrity menu item.
- Manual loopback check: `Set loopback mode` -> `Get FPGA status` -> `Write test payload` -> `Read payload to file` -> compare `*_raw_tx.bin` and `*_raw_rx.bin` externally if needed.
- `Write test payload` sends 64 32-bit counter words and saves `*_raw_tx.bin`.
- Raw counter byte order is `00 00 00 01`, `00 00 00 02`, ... .
- `Read payload to file` reads `EP82` as a stream in 256 KiB chunks until `q`, then saves `*_raw_rx.bin` if data was received.
- Service commands do not automatically read status; use `Get FPGA status` separately.

## Validation Commands

RTL simulation from `source/`:

```powershell
iverilog -g2005-sv -o testbench.out testbench.v
vvp .\testbench.out
verilator_bin.exe --lint-only --timing testbench.v
```

Build `ft601_test` from `ft601_test/`:

```powershell
C:\msys64\mingw64\bin\g++.exe -std=c++11 -Wall -Wextra -pedantic main.cpp app_log.cpp ft601_device.cpp service_protocol.cpp payload_test.cpp throughput.cpp -I. -L.\WU_FTD3XXLib\Lib\Dynamic\x64 -lFTD3XXWU -o main_gpp.exe
```

Run ISE only when timing, constraints, top-level ports, or synthesis-relevant RTL changed.

## Active Issues

See `NEED_TO_FIX.md` first. Current practical next step is hardware retest and localization after local fixes/diagnostics:

- loopback RX has previously been shorter than TX on hardware;
- `GET_STATUS` after payload traffic has previously been unstable on hardware;
- status/FIFO flags must be checked on hardware after the latest local changes;
- docs should only be updated after confirmed behavior changes.

## New Chat Bootstrap

After clearing context, start with:

```text
Read AGENTS.md, HANDOFF.md, SPECIFICATION.md, NEED_TO_FIX.md. Treat old chat context as unreliable and use current files as source of truth.
```
