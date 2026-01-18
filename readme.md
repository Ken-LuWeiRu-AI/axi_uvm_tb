# AXI4 UVM Verification Project

Run in EDA Playground (Questa-compatible):  
https://www.edaplayground.com/x/pfw6

A **minimal-yet-scalable UVM verification environment** for a
**memory-mapped AXI4 slave DUT**.

This project demonstrates a **clean, industry-style AXI UVM architecture**:

**sequence → sequencer → driver → interface → DUT**,  
with a **monitor → reference model → scoreboard** checking path.

The environment is designed for **M0/M1 bring-up correctness**, while clearly
documenting what is required to evolve toward **M2 (multi-outstanding / out-of-order)** AXI verification.

---

## Features

### Verification Environment
- AXI4 master UVM agent (ACTIVE / PASSIVE ready)
- Driver using AXI clocking block (`MASTER_MP`)
- Passive monitor using clocking block (`MON_MP`)
- Byte-addressable **reference model with mirror memory**
- Scoreboard comparing **ACT vs EXP** transactions
- Optional functional coverage subscriber
- Clear separation of **design / interface / TB package / top**

### Supported AXI Features (Current)
- Channels: **AW / W / B / AR / R**
- **INCR bursts**
- **WSTRB byte enables**
- Single-beat and burst transactions
- VALID-hold protocol correctness
- Backpressure via READY
- Single outstanding write
- Single outstanding read

---

## DUT Behavior (`axi_mem_slave.sv`)

- Memory-mapped AXI4 slave
- Address space:
```

BASE_ADDR ... BASE_ADDR + MEM_BYTES - 1

```
- Memory is **byte-addressable**
- Burst support:
- ✅ `INCR`
- ❌ `FIXED`, `WRAP` → `SLVERR`
- Address checking:
- Out-of-range access → `DECERR`
- Latency knobs:
- `RD_LATENCY`  : delay before first `RVALID`
- `WR_RESP_LATENCY` : delay before `BVALID`
- Assumptions (intentional):
- One outstanding write
- One outstanding read
- In-order completion

This DUT is intentionally **simple but protocol-correct**, making it ideal for learning and bring-up.

---

## Verification Architecture (UVM)

### Overall Testbench Hierarchy (Word Diagram)

```

axi_top
│
├── Clock / Reset
│
├── axi_if (interface)
│   ├── MASTER_MP  (driver)
│   └── MON_MP     (monitor)
│
├── DUT : axi_mem_slave
│
└── uvm_test_top
└── axi_test
└── axi_env
├── axi_agent
│   ├── axi_sequencer
│   ├── axi_driver
│   └── axi_monitor
│
├── axi_ref_model
│
├── axi_scoreboard
│
└── axi_cov_subscriber (optional)

```

---

### Data Flow Diagram (Transaction View)

```

axi_*_seq
|
v
axi_sequencer
|
v
axi_driver
|
v
axi_if (MASTER_MP)
|
v
DUT
|
v
axi_if (MON_MP)
|
v
axi_monitor
|
+-----------------------+
|                       |
v                       v
axi_ref_model        axi_scoreboard (ACT)
|
v
axi_scoreboard (EXP)

```

- **ACT path**: monitor → scoreboard  
- **EXP path**: monitor → ref_model → scoreboard  
- Scoreboard performs **transaction-level comparison**

---

## File Structure

```

.
├── design.sv              # Design-side compile wrapper
├── axi_mem_slave.sv       # AXI4 slave DUT
│
├── axi_defines.sv         # Global AXI parameters (widths, defaults)
├── axi_common_pkg.sv      # AXI enums (burst, resp, rw)
├── axi_if.sv              # AXI interface + clocking blocks + assertions
│
├── axi_tb_pkg.sv          # Central UVM package (classes only)
├── axi_seq_item.sv
├── axi_sequencer.sv
├── axi_driver.sv
├── axi_monitor.sv
├── axi_agent.sv
├── axi_ref_model.sv
├── axi_scoreboard.sv
├── axi_cov_subscriber.sv
├── axi_env.sv
├── axi_sequences.sv
├── axi_test.sv
│
└── axi_top.sv             # Testbench top (clk/rst, interface, DUT, run_test)

````

---

## Running the Simulation

### Questa / qrun

```sh
qrun -batch -access=rw+/. -uvmhome uvm-1.2 -timescale 1ns/1ns -mfcu \
  design.sv axi_top.sv \
  -do "run -all; exit"
````

### Selecting a Test

```sh
+UVM_TESTNAME=axi_test
+UVM_TESTNAME=axi_smoke_test
+UVM_TESTNAME=axi_burst_test
+UVM_TESTNAME=axi_stress_test
+UVM_TESTNAME=axi_outstanding_test
```

---

## Tests Overview

| Test Name              | Purpose                                   |
| ---------------------- | ----------------------------------------- |
| `axi_test`             | Minimal smoke test (1 write → 1 read)     |
| `axi_smoke_test`       | Multiple single-beat accesses             |
| `axi_burst_test`       | Directed burst read/write                 |
| `axi_stress_test`      | Random read/write/size/len/strobe         |
| `axi_outstanding_test` | **M2 stub** (documents required upgrades) |

---

## Common Pitfalls (Already Solved Here)

| Issue                   | Cause                    | Solution                     |
| ----------------------- | ------------------------ | ---------------------------- |
| interface compile error | interface inside package | `axi_if.sv` kept outside     |
| scoreboard mismatch     | missing ref model        | mirror-memory RM             |
| burst data mismatch     | wrong beat math          | `len + 1` handled everywhere |
| VALID instability       | payload changed early    | clocking block + assertions  |
| default arg warnings    | extern mismatch          | defaults only in definition  |

---

## How to Extend This Project (Roadmap)

Recommended next steps:

* Enable **true multi-outstanding (M2)**:

  * Queue AW / AR in DUT
  * Parallel channel threads in driver
  * Per-ID reconstruction in monitor
  * OOO matching in scoreboard
* Add **AXI protocol assertions**
* Add **UVM RAL (register model)**
* Support `WRAP` bursts
* Add USER sideband signals

---

## Author

* **Author:** ken, Lu Wei-Ru
* **Created:** 2026-01-18
* **Purpose:** Learning-quality AXI4 + UVM reference project

---

## License

Suggested: **MIT License**
(Adjust based on your usage)

```

---

### Why this is strong (important)

- ✅ Same **structure & readability** as your APB README  
- ✅ AXI complexity explained **without overwhelming**
- ✅ Shows **engineering judgment** (what is implemented vs intentionally omitted)
- ✅ Interviewers immediately see:
  - You understand **M0 → M1 → M2 progression**
  - You know **why AXI is hard**, not just how to code it

If you want next:
- I can **align APB & AXI READMEs stylistically** so they look like a *series*
- Or write a **top-level repo README** that links APB → AXI progression
- Or help you write a **“Design Decisions” section** (very attractive in interviews)

Just tell me.
```
