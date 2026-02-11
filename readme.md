# AXI4 UVM Verification Project (Out-of-Order Capable)

Run in EDA Playground (Questa-compatible):  
[[Link to your EDA Playground]](https://www.edaplayground.com/x/NYTP)

Key Run Command for OOO Stress:
```sh
+UVM_TESTNAME=axi_outstanding_rand_test

```

A high-performance, industry-standard UVM verification environment for a
memory-mapped AXI4 slave DUT.

This project implements a fully Out-of-Order (OOO) and Multiple Outstanding architecture. Unlike basic AXI examples that block until a response is received, this environment supports high-throughput, pipelined traffic where responses (Read Data / Write Response) can return in any order allowed by the AXI4 protocol.

---

## 🚀 Key Features

### Advanced Verification Capabilities (M2 Level)

* Multiple Outstanding Support: The driver and DUT can handle multiple in-flight transactions simultaneously without stalling (up to queue depth).
* Out-of-Order (OOO) Responses:
* The DUT randomly reorders Read Data (R) and Write Responses (B) for different IDs.
* The Monitor and Scoreboard use per-ID tracking to correctly reconstruct and verify interleaved transactions.


* Flow Control (Backpressure): The driver implements intelligent queue management to handle randomized stalls without overflow.
* ID-Based Scoreboarding: Transactions are matched by `(ID, Tag)` rather than simple FIFO order, ensuring data integrity even when the bus acts non-deterministically.

### Verification Environment Components

* AXI4 Master Agent: Active/Passive ready.
* OOO Driver: Non-blocking request acceptance with explicit thread separation for AW/W/AR channels.
* OOO Monitor: Reconstructs split transactions using ID-indexed dynamic queues.
* Reference Model: Byte-addressable mirror memory for data integrity checking.
* Protocol Checks: Strict "VALID-Hold" enforcement and basic protocol assertions.

---

## 🛠️ DUT Behavior (`axi_mem_slave.sv`)

A robust, synthesizable-style AXI4 slave designed to stress the verification environment.

* Address Space: `BASE_ADDR` ... `BASE_ADDR + MEM_BYTES - 1`
* Queue-Based Processing: Internal queues allow accepting new addresses (`AW`/`AR`) while processing older ones.
* Randomized OOO Selection:
* In `R_IDLE` or `W_RESP` states, the slave randomly picks a pending transaction to process.
* Protocol Compliance: Strictly enforces In-Order processing for transactions with the same ID (as required by AXI4).


* Burst Support: `INCR` (Fixed/Wrap return `SLVERR`).
* Error Handling: Out-of-range access returns `DECERR`.

---

## 🏗️ Verification Architecture

### Data Flow

```mermaid
graph TD
    Seq[axi_outstanding_rand_seq] -->|Req (ID=0..3)| Sqr[Sequencer]
    Sqr --> Drv[AXI Driver]
    
    subgraph Driver [Advanced Driver]
        Drv -->|Thread 1| AW[AW Channel]
        Drv -->|Thread 2| W[W Channel]
        Drv -->|Thread 3| AR[AR Channel]
    end

    AW & W & AR --> |Interface| DUT[OOO Slave DUT]
    
    DUT -->|Rsp (Random Order)| Mon[AXI Monitor]
    
    subgraph Monitor [OOO Reconstruction]
        Mon -->|Demux by ID| Q0[Queue ID=0]
        Mon -->|Demux by ID| Q1[Queue ID=1]
        Mon -->|Demux by ID| Qn[Queue ID=n]
    end

    Mon -->|Reassembled Tr| SB[Scoreboard]
    Mon -->|Reassembled Tr| RM[Ref Model]
    RM -->|Exp Tr| SB

```

---

## 📂 File Structure

```text
.
├── design.sv              # Design wrapper
├── axi_mem_slave.sv       # OOO-capable AXI4 Slave DUT
│
├── axi_defines.sv         # Global parameters
├── axi_common_pkg.sv      # Enums/Typedefs
├── axi_if.sv              # Interface & Assertions
│
├── axi_tb_pkg.sv          # UVM Package
├── axi_seq_item.sv        # Transaction Item (supports ID/Burst/Len)
├── axi_driver.sv          # Multi-threaded, Backpressure-aware Driver
├── axi_monitor.sv         # Per-ID Tracking Monitor
├── axi_scoreboard.sv      # OOO Matching Scoreboard
├── axi_env.sv             # Environment Container
├── axi_sequences.sv       # Sequence Library (Directed + Random OOO)
├── axi_test.sv            # Test Library
│
└── axi_top.sv             # Testbench Top

```

---

## 🧪 Tests Overview

| Test Name | Feature Verified |
| --- | --- |
| `axi_outstanding_rand_test` | (Hero Test) Generates heavy, randomized traffic with random IDs to force Out-of-Order responses and pipeline stress. |
| `axi_test` | Basic smoke test (1 Write → 1 Read). |
| `axi_burst_test` | Verifies multi-beat burst functionality (`INCR`). |
| `axi_stress_test` | Randomized single-thread stress (random strobe/addr). |

---

## ⚡ How to Run

### Using Questa / qrun

```bash
qrun -batch -access=rw+/. -uvmhome uvm-1.2 -timescale 1ns/1ns -mfcu \
  design.sv axi_top.sv \
  +UVM_TESTNAME=axi_outstanding_rand_test \
  -do "run -all; exit"

```

### Expected Output (OOO Success)

You should see pass/fail counts in the scoreboard report. Because of OOO, the order of "PASS" messages in the log may not match the order requests were sent.

```text
UVM_INFO axi_scoreboard.sv(90) ... SCOREBOARD SUMMARY: PASS=98 FAIL=0

```

---

## 🔮 Future Roadmap (M3+)

* [ ] Support Exclusive Access (Atomic operations).
* [ ] Support `WRAP` and `FIXED` burst types in DUT.
* [ ] Add UVM Register Model (RAL) adapter.
* [ ] Implement SVA (SystemVerilog Assertions) for formal protocol verification.

---

## Author

* Author: ken, Lu Wei-Ru
* Created: 2026-02-08
* Status: M2 Mature (Multi-Outstanding / OOO Verified)

```

### What changed from the old README?

1.  Stub Removed: The "M2 stub" warnings are gone. The `axi_outstanding_test` is replaced/superseded by the working `axi_outstanding_rand_test`.
2.  DUT Description Updated: Explicitly mentions "Queue-Based Processing" and "Randomized OOO Selection" instead of "Single Outstanding".
3.  Architecture Updated: Added the ID-based demuxing concept to the monitor/scoreboard description to explain *how* OOO is handled.
4.  Key Command: Put the OOO test command at the very top, as it is now the "hero" test of your project.

```
