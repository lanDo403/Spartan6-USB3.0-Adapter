# AGENTS.md

## Communication Style

- Be concise.
- Give facts, decisions, and actionable options.
- Avoid long context restatement unless it affects the decision.
- For non-trivial work, follow: context -> constraints -> options -> plan -> execution -> validation -> review -> documentation.

## Mode Detection

Classify tasks as one of:

- `RESEARCH`: analysis, comparison, investigation, no file changes unless requested.
- `GENERAL_CODING`: software changes outside RTL.
- `FPGA_VERILOG`: RTL, testbench, timing, constraints, hardware-facing behavior.

If unclear, ask once. Otherwise proceed with the most likely mode.

## Project Summary

This repository contains an RTL design for `Xilinx Spartan-6` and `FTDI FT601` in `245 synchronous FIFO` mode.

The current bitstream is intended to support:

- `normal mode`: GPIO/payload path toward FT601 and PC;
- `loopback mode`: PC -> FT601 -> FPGA -> FT601 -> PC;
- `status/service`: framed host commands and FPGA status response.

Service traffic uses framed 32-bit words on the same FT601 endpoints as payload:

- command frame: `CMD_MAGIC + opcode`;
- status frame: `STATUS_MAGIC + status_word`.

The public technical specification is now at repository root:

- `SPECIFICATION.md`

The old `docs/` tree is not part of the published GitHub documentation anymore. If a local `docs/` folder exists, treat it as local notes, reference material, diagrams, diploma sources, and engineering history unless the user explicitly says otherwise.

When project information conflicts, use this priority:

1. Current RTL, testbench, `ft601_test` source.
2. `SPECIFICATION.md`.
3. `HANDOFF.md` for fresh-chat orientation.
4. `README.md` and `ft601_test/README.md`.
5. Active planning files: `NEED_TO_FIX.md`, `AXIS_PLAN.md`, `PRES_PLAN.md`, `docs/UPDATE_TB.md`.
6. Historical notes: `docs/FIXED.md`, `docs/UPDATE.md`.
7. Reference projects under `docs/FTDI/`.
8. Old chat context.

## Local Documentation Map

- `HANDOFF.md`: short re-entry document for a fresh Codex chat after context cleanup. Read it together with `AGENTS.md`, `SPECIFICATION.md`, and `NEED_TO_FIX.md`.
- `NEED_TO_FIX.md`: active hardware/software issues grouped into stages. Treat it as the current bug-fix queue.
- `AXIS_PLAN.md`: future/internal architecture plan for AXI-Stream-like cleanup. It is not the implemented specification until reflected in RTL and `SPECIFICATION.md`.
- `AXI_REF.md`: universal AXI-Stream RTL guide based on `docs/FTDI` reference projects and external AXI documentation. It is not tied to the current RTL implementation.
- `DDR3_REF.md`: universal DDR3 subsystem guide based on `docs/FTDI` reference projects and external DDR3/MIG documentation. It is not tied to the current RTL implementation.
- `PRES_PLAN.md`: diploma presentation plan.
- `docs/ARCHITECTURE.md`: local engineering architecture notes. Keep it aligned with current implementation if edited.
- `docs/INTERFACES.md`: local interface notes. Keep signal names and protocol fields aligned with current implementation if edited.
- `docs/FIXED.md`: chronological fix log. It may mention old module names, old opcodes, and removed behavior.
- `docs/UPDATE.md`: historical/current planning file. Check against source and `SPECIFICATION.md` before using it as implementation guidance.
- `docs/UPDATE_TB.md`: testbench restructuring plan. It is a plan, not proof that the split/SystemVerilog migration is already implemented.
- `docs/*SCHEME*.md`: ASCII/GOST diagrams for diploma and explanation. Update them only when the user asks or when a documented architecture diagram becomes misleading.

## Reference Projects and Vendor Documents

Reference material lives under `docs/FTDI/` and must be treated as read-only research input, not as code to copy blindly.

- `docs/FTDI/core_ft60x_axi-master/`: FT60x/AXI-oriented reference. Useful for AXI-style architecture comparison and FT60x integration ideas.
- `docs/FTDI/FPGA-ftdi245fifo-main/`: FIFO-style FTDI reference with RTL, simulation, Python, and loopback flow. Useful for simpler FIFO/loopback patterns.
- `docs/FTDI/I2C_Master_Controller-main/`: clean valid/ready-style Verilog reference. Useful for naming and handshake discipline.
- `docs/FTDI/wb2axip-master/`: large AXI/AXI-Lite/AXI-Stream module collection. Useful for skid buffers, AXIS safety, stream switching, DMA/data movers, and memory bridge patterns.
- `docs/FTDI/core_ddr3_controller-master/`: lightweight AXI4 DDR3 controller reference. Use it for DDR3 architecture ideas, controller/PHY separation, retiming, and burst behavior; do not treat it as a Spartan-6 drop-in replacement for MIG/MCB.
- `docs/FTDI/spartan6_mst_fifo32_1.1/`: FTDI master FIFO reference. Use it as a reference example, not as a fixed-latency requirement for this project.
- `docs/FTDI/WU_APIUsageDemoApp/`, `WU_DataLoopbackApp/`, `WU_DataStreamerApp/`, `WU_ConfigurationProgrammerTool/`: D3XX host-side examples. Use them when changing `ft601_test`.
- FTDI PDFs in `docs/FTDI/`: `AN_379` for D3XX API, `AN_387` for DataStreamer behavior, `AN_386` for performance, `AN_421` for FT60x FIFO bus, and the FT600/FT601 datasheet for pin/timing semantics.
- FPGA/board PDFs in `docs/FPGA/`: Callisto S6 board docs, Spartan-6 datasheets/user guides, SelectIO/clocking/configuration docs, and Xilinx timing-closure references. Use them for pinout, clocking, I/O, reset, and timing decisions.
- Other PDFs directly under `docs/`: local methodology and ISE/timing references. Use them only as supporting material.

If a reference project suggests a different architecture, first explain the tradeoff and get approval before large RTL restructuring.

Before changing AXI-Stream-like internals, consult `AXI_REF.md`. Before proposing DDR3 integration or memory buffering, consult `DDR3_REF.md`.

## Diploma and Presentation Material

Diploma-related files are local documentation artifacts:

- `docs/диплом_какаха.docx`: current diploma draft.
- `docs/план.docx`: diploma structure/plan.
- `docs/Диплом_презентация_Лыков_ИВТ-42.pdf` and presentation-related files: presentation inputs.
- `docs/ГОСТ_19.701-90.pdf`: diagram notation reference.

Do not edit binary `.docx`/`.pdf` files unless the user explicitly asks. For diploma text, usually propose the text in chat first.

## Main Files

- `README.md`: human-facing project overview.
- `SPECIFICATION.md`: implemented protocol, reset model, datapath, FT601 behavior, and verification expectations.
- `source/top.v`: top-level RTL integration.
- `source/ft601_wrapper.v`: physical FT601 I/O boundary.
- `source/ft601_fsm.v`: FT601 bus control.
- `source/ft601_rx_adapter.v`: FT601 RX stream adapter.
- `source/ft601_tx_adapter.v`: FT601 TX stream adapter.
- `source/axis_fifo_write_adapter.v`: stream-to-FIFO write-side adapter.
- `source/axis_fifo_read_adapter.v`: registered FIFO-to-stream read-side adapter.
- `source/axis_tx_arbiter.v`: TX source arbitration.
- `source/rx_stream_router.v`: RX service/payload routing.
- `source/cmd_decoder.v`: framed command decoder.
- `source/status_source.v`: framed status source.
- `source/async_fifo.v`: normal TX async FIFO.
- `source/loopback_fifo.v`: loopback FIFO.
- `source/testbench.v`: top-level simulation testbench.
- `source/callistoS6.ucf`: Spartan-6 constraints.
- `ft601_test/`: Windows D3XX host utility.

## RTL Rules

Before changing FPGA/Verilog code, identify:

- clock domains;
- reset behavior;
- FT601 active-low signal semantics;
- stream/FIFO interfaces;
- timing-sensitive paths;
- UCF impact.

Rules:

- Do not change pinout or constraints unless explicitly required.
- Prefer synchronous design.
- Avoid combinational loops and direct combinational paths from `TXE_N/RXF_N` pads to `WR_N/RD_N/OE_N` outputs.
- Do not restore old fixed-latency master-fifo requirements as project requirements.
- Preserve framed service protocol unless the user explicitly requests a protocol change.
- Keep changes minimal and scoped.

FT601 active-low meanings:

- `TXE_N=0`: FT601 can accept data from FPGA.
- `RXF_N=0`: FT601 has data for FPGA.
- `WR_N=0`: FPGA writes to FT601.
- `RD_N=0`: FPGA reads from FT601.
- `OE_N=0`: FT601 drives the data bus.

## Reset Model

- `FPGA_RESET` is the physical project reset request.
- `FPGA_RESET` resets both GPIO and FT domains through domain-local reset synchronizers.
- `RESET_N` is an FPGA output to FT601. It is pulsed low only by `CMD_FT601_RESET` and is not an internal RTL reset.
- Host-side clear commands must only clear diagnostic sticky flags unless the specification is intentionally changed.

## Validation Commands

Run RTL simulation from:

```powershell
cd .\source
iverilog -g2005-sv -o testbench.out testbench.v
vvp .\testbench.out
verilator_bin.exe --lint-only --timing testbench.v
```

Build `ft601_test` from:

```powershell
cd .\ft601_test
C:\msys64\mingw64\bin\g++.exe -std=c++11 -Wall -Wextra -pedantic main.cpp app_log.cpp ft601_device.cpp service_protocol.cpp payload_test.cpp throughput.cpp -I. -L.\WU_FTD3XXLib\Lib\Dynamic\x64 -lFTD3XXWU -o main_gpp.exe
```

Run ISE only when timing, constraints, top-level ports, or synthesis-relevant RTL changed.

## Testbench Direction

The testbench should be scenario-based and should check externally visible behavior.

Preferred top-level scenarios:

- `reset_boot_normal`;
- `normal_path`;
- `loopback_path`;
- `diagnostics`.

Keep old directed bug checks out of the main scenario list unless they protect an active hardware issue. Fold their important assertions into one of the four scenarios or into always-on monitors.
Also keep AXI-Stream stability checks for internal stream lines: when `valid && !ready`, `valid/data/keep` must remain stable until handshake.

Avoid making internal `*_ff` state the primary pass/fail criterion. Use white-box access only when reproducing a diagnostic/fault case would otherwise become unnecessarily complex.

## Documentation Rules

When behavior changes, update the relevant public files:

- `SPECIFICATION.md` for protocol, reset, datapath, timing, and verification behavior;
- `README.md` for user-facing project overview;
- `ft601_test/README.md` for host utility usage and build flow.

Do not add links from `README.md` to the old `docs/` tree.

## Git Hygiene

- Do not use `git add -A` in this repository unless the user explicitly asks for the whole worktree.
- Stage files explicitly.
- Do not stage generated artifacts, local ISE outputs, binaries, dumps, waveforms, or local reference folders unless explicitly requested.
- Never revert user changes without explicit permission.
