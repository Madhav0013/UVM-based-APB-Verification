# UVM-Based Verification of APB Slave using SystemVerilog

## Project Overview

This project implements a complete UVM-based verification environment for an APB
(Advanced Peripheral Bus) slave design. APB is a simple bus protocol from ARM's
AMBA family, used to connect low-bandwidth peripherals in SoC designs.

The project demonstrates: UVM methodology, protocol verification, transaction-level
modeling, scoreboard-based checking, SVA assertions, and functional coverage.

## DUT — APB Slave

A zero wait-state APB slave with 4 internal 32-bit registers:

| Address | Register | Reset Value |
|---------|----------|-------------|
| 0x00     | CTRL     | 0x00000000  |
| 0x04     | STATUS   | 0x00000001  |
| 0x08     | DATA     | 0x00000000  |
| 0x0C     | CONFIG   | 0x00000000  |

- Valid address access: register read/write, PSLVERR = 0
- Invalid address access: PSLVERR = 1, PRDATA = 0 (reads)

## Verification Architecture

```text
┌──────────────────────────────────────────────────────┐
│                    UVM Test                           │
│  (Decides which sequences to run)                    │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │              UVM Environment                   │  │
│  │                                                │  │
│  │  ┌──────────────────────────┐   ┌───────────┐ │  │
│  │  │       APB Agent          │   │Scoreboard │ │  │
│  │  │                          │   │           │ │  │
│  │  │  ┌──────────┐           │   │ Expected  │ │  │
│  │  │  │ Sequencer│           │   │ register  │ │  │
│  │  │  │  (FIFO)  │           │   │ model +   │ │  │
│  │  │  └────┬─────┘           │   │ checker   │ │  │
│  │  │       │                 │   │           │ │  │
│  │  │  ┌────▼─────┐          │   └─────▲─────┘ │  │
│  │  │  │  Driver  │          │         │        │  │
│  │  │  │ (drives  │          │         │        │  │
│  │  │  │  APB     │          │         │        │  │
│  │  │  │  pins)   │          │         │        │  │
│  │  │  └────┬─────┘          │         │        │  │
│  │  │       │                │         │        │  │
│  │  │  ┌────┴──────────────┐ │         │        │  │
│  │  │  │     Monitor       ├─┼─────────┘        │  │
│  │  │  │ (observes bus,    │ │  analysis port   │  │
│  │  │  │  samples txns,    │ │                  │  │
│  │  │  │  collects cov)    │ │                  │  │
│  │  │  └────┬──────────────┘ │                  │  │
│  │  └───────┼────────────────┘                  │  │
│  └──────────┼───────────────────────────────────┘  │
│             │                                      │
│        ┌────▼──────────┐                           │
│        │ APB Interface │                           │
│        └────┬──────────┘                           │
│        ┌────▼──────────┐     ┌──────────────────┐  │
│        │   DUT (APB    │     │   Assertions     │  │
│        │    Slave)     │     │ (protocol checks)│  │
│        └───────────────┘     └──────────────────┘  │
└──────────────────────────────────────────────────────┘
```

## UVM Components

| Component | File | Purpose |
|-----------|------|---------|
| Interface | `tb/apb_if.sv` | Signal bundle connecting DUT and TB |
| Seq Item | `tb/apb_seq_item.sv` | Transaction object (1 APB transfer) |
| Sequences | `tb/apb_sequences.sv` | 7 stimulus patterns |
| Sequencer | `tb/apb_sequencer.sv` | Transaction pipeline |
| Driver | `tb/apb_driver.sv` | Converts transactions to APB signals |
| Monitor | `tb/apb_monitor.sv` | Observes bus, publishes transactions |
| Agent | `tb/apb_agent.sv` | Groups seqr + drv + mon |
| Scoreboard | `tb/apb_scoreboard.sv` | Reference model + checker |
| Environment | `tb/apb_env.sv` | Top verification container |
| Tests | `tb/apb_test.sv` | 5 test classes |
| Assertions | `tb/apb_assertions.sv` | 7 SVA protocol checks |

## Tests Executed & Coverage

| Test | Transactions | Functional Coverage | Sim Time | Result |
|------|-------------|---------------------|-----------|--------|
| Smoke | 2 | ~15% (estimated) | ~200 ns | PASS |
| Register Access | 8 | 87.5% | 535 ns | PASS |
| Invalid Address | 8 | 37.5% | 535 ns | PASS |
| Random (30 txns) | 30 | 87.5% | 1195 ns | PASS |
| Full Functional | 56 | 100.0% | 2075 ns | PASS |

## Assertions

- PENABLE requires PSEL
- Setup phase must precede enable phase
- Address, PWRITE, PWDATA stable during transfer
- Bus idle after reset
- Invalid address raises PSLVERR
- Valid address does not raise PSLVERR

## How to Run

### Local Simulation (Modelsim/Questa)
```bash
cd sim
make run_all
```

### EDA Playground
This project has been verified using Aldec Riviera-PRO 2025.04 on EDA Playground.
Check the `eda_playground/` folder for consolidated files (`design.sv` and `testbench.sv`) that can be pasted directly into EDA Playground without needing file include gymnastics.

Run Options: `+UVM_TESTNAME=apb_full_test +UVM_VERBOSITY=UVM_MEDIUM`

## Results

All tests pass. Scoreboard reports 0 mismatches. All 7 concurrent SVA assertions report zero violations across all tested vectors.
Functional coverage (Read/Write, Address Map, and PSLVERR permutations) is completely covered at **100% final achieved coverage**.
