# UART Design & Verification Project

---

## Overview

This project covers the design and functional verification of a **Universal Asynchronous Receiver/Transmitter (UART)** implemented in synthesizable Verilog HDL. The UART supports a configurable baud rate via `XTAL_CLK` and `BAUD` parameters (default: 2400 baud at 100 MHz system clock), making it portable across embedded and digital communication systems.

Verification uses a self-checking testbench with a golden reference model (`uart_ref_model`) and automated output comparison. Code coverage analysis is performed with **Questa SIM**; waveform debugging with **Vivado**.

---

## Repository Structure

```
UART_Project/
├── src/
│   ├── uart.v              # Top-level wrapper
│   ├── u_xmit.v            # Transmitter FSM
│   ├── u_rec.v             # Receiver FSM
│   └── u_baud.v            # Baud-rate generator
├── tb/
│   ├── uart_tb.v           # Self-checking testbench
│   
├── docs/
│   └── UART_Report.docx    # Full design & verification report
└── README.md
```

---

## Design Architecture

The design is split across three sub-modules instantiated under a top-level wrapper:

| Module      | Role                                                                 |
|-------------|----------------------------------------------------------------------|
| `u_baud`    | Divides `sys_clk` to generate `uart_clk` at 16× the baud rate      |
| `u_xmit`    | Moore FSM transmitter — serialises parallel data onto TX line        |
| `u_rec`     | Moore FSM receiver — deserialises incoming serial data into a byte   |

### Top-Level I/O

**Inputs**

| Signal           | Width | Description                                      |
|------------------|-------|--------------------------------------------------|
| `sys_clk`        | 1-bit | System clock (rising-edge triggered)             |
| `sys_rst`        | 1-bit | Active-low asynchronous reset                    |
| `xmitH`          | 1-bit | Pulse high to begin transmission                 |
| `xmit_dataH`     | 8-bit | Parallel byte to transmit (sampled on `xmitH`)   |
| `uart_rec_datah` | 1-bit | Serial RX input line (idle high)                 |

**Outputs**

| Signal             | Width | Description                                               |
|--------------------|-------|-----------------------------------------------------------|
| `uart_xmit_datah`  | 1-bit | Serial TX output (idle high, start low, stop high)        |
| `xmit_doneH`       | 1-bit | High when transmitter is idle / frame complete            |
| `xmit_active`      | 1-bit | High while transmission is in progress                    |
| `rec_readyh`       | 1-bit | High when a received byte is ready on `rec_datah`         |
| `rec_busyh`        | 1-bit | High while receiver is actively receiving a frame         |
| `rec_datah`        | 8-bit | Received parallel byte (valid when `rec_readyh` is high)  |
| `uart_clk`         | 1-bit | Internal baud clock output (16× baud rate)                |

---

## UART Frame Format

```
 IDLE   START   D0   D1   D2   D3   D4   D5   D6   D7   STOP   IDLE
  ─┐     ┌──────────────────────────────────────────────────┐    ┌─
   └─────┘  LSB                                        MSB  └────┘

Each bit period = 16 uart_clk ticks  |  Total frame = 160 ticks (10 bit-periods)
```

---

## FSM States

### Transmitter (`u_xmit`)
`IDLE → START → WAIT → TX → STOP → IDLE`

### Receiver (`u_rec`)
`IDLE → WAIT → REC → STOP → IDLE`

All state transitions are registered on the **positive edge of `uart_clk`** with **active-low asynchronous reset**.

---

## Testbench

The testbench (`uart_tb`) instantiates the DUT and the reference model in parallel, applying identical stimuli to both and comparing outputs automatically.

### Key Tasks & Functions

| Component                | Purpose                                                                 |
|--------------------------|-------------------------------------------------------------------------|
| `apply_test_tx`          | Pulses `xmitH`, waits for both DUT and REF `xmit_doneH`, then compares |
| `send_frame`             | Bit-bangs a correctly timed UART frame onto the RX input line           |
| `compare_tx`             | Compares `xmit_doneH`, `xmit_active`, `uart_xmit_datah` vs reference   |
| `compare_rx`             | Compares `rec_readyh`, `rec_busyh`, `rec_datah` vs reference            |
| `display_mismatch_tx/rx` | Prints full DUT and REF values on every FAIL for easy diagnosis         |
| `test_transmitter`       | All TX test cases (normal bytes, idle, no-transmit, mid-frame change)   |
| `test_receiver`          | All RX test cases (normal, idle, missing start, framing error, flags)   |

### Test Cases Covered

- Normal byte transmission: `0xA5`, `0x00`, `0xFF`, `0x55`, `0xAA`, `0x3C`
- Normal byte reception: `0x45`, `0x00`, `0xFF`, `0xA5`
- Serial line idle check
- `xmitH = 0` no-transmit check
- Mid-frame data change test
- Missing start-bit test (line held high)
- Framing error injection (stop bit forced low)
- `xmit_active` / `xmit_doneH` mutual-exclusion check
- `rec_readyh` / `rec_busyh` mutual-exclusion check

---

## Simulation Results

> **Simulator:** Questa SIM &nbsp;|&nbsp; **Waveform:** Vivado &nbsp;|&nbsp; **SIM\_BAUD:** 500,000 bps

| Metric      | Value  |
|-------------|--------|
| Total Tests | 18     |
| PASS        | 6      |
| FAIL        | 12     |
| Pass Rate   | 33.33% |

---

## Code Coverage Summary

| Coverage Type   | Bins | Hits | Misses | Coverage   |
|-----------------|------|------|--------|------------|
| Statements      | 78   | 78   | 0      | 100.00%    |
| Branches        | 51   | 51   | 0      | 100.00%    |
| FEC Conditions  | 2    | 2    | 0      | 100.00%    |
| Toggles         | 236  | 153  | 83     | 64.83% ⚠️  |
| FSM States      | 9    | 9    | 0      | 100.00%    |
| FSM Transitions | 17   | 12   | 5      | 70.58% ⚠️  |
| **Total**       |      |      |        | **90.02%** |

### Per-Unit Coverage

| Design Unit    | Total   | Statement | Branch  | Toggle   | FSM State | FSM Trans |
|----------------|---------|-----------|---------|----------|-----------|-----------|
| work.ref_model | 80.81%  | 96.72%    | 91.66%  | 34.88% ⚠️ | --        | --        |
| work.tb        | 72.35%  | 96.90%    | 75.00%  | 45.14% ⚠️ | --        | --        |
| work.u_baud    | 100.00% | 100.00%   | 100.00% | 100.00%  | --        | --        |
| work.u_rec     | 98.55%  | 93.33%    | 98.00%  | 100.00%  | 100.00%   | 100.00%   |
| work.u_xmit    | 99.26%  | 100.00%   | 97.05%  | 100.00%  | 100.00%   | 100.00%   |
| work.uart      | 100.00% | --        | --      | 100.00%  | --        | --        |

---

## Tools & Parameters

| Item         | Value / Tool            |
|--------------|-------------------------|
| Language     | Verilog HDL             |
| Simulator    | Questa SIM              |
| Waveform     | Vivado                  |
| Default BAUD | 2400 bps                |
| XTAL\_CLK    | 100 MHz                 |
| SIM\_BAUD    | 500,000 bps             |
| Word Length  | 8-bit                   |
| Frame Format | 1 start, 8 data, 1 stop |

---

## Future Work

- [ ] Random test input generation to cover all 256 byte values automatically
- [ ] Functional coverage groups for MODE, CMD, and INP\_VALID combinations
- [ ] Formal verification assertions (SVA) to prove FSMs never deadlock
- [ ] Multi-baud-rate regression (9600, 115200, 1,000,000 bps)
- [ ] Configurable word length (7-bit and 9-bit modes)
- [ ] Parity support (even/odd) with error detection
- [ ] System-level loopback testing inside a simple SoC

---

*For the full design and verification report, see `docs/UART_Report.docx`.*
