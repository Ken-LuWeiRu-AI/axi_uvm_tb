# APB UVM Verification Project
run in EDA playground : https://www.edaplayground.com/x/pfw6
A minimal-yet-complete UVM verification environment for a simple APB slave DUT.
This project demonstrates a typical UVM structure:
**sequence → sequencer → driver → interface → DUT**, with a **monitor → ref_model → scoreboard** checking path.

## Features
- APB master UVM agent (active/passive configurable)
- Driver using clocking block (MASTER_MP)
- Passive monitor using clocking block (MON_MP)
- Reference model with mirror memory
- Scoreboard comparing ACT vs EXP transactions
- DUT supports programmable wait states (`N`) and error response on illegal address

## DUT Behavior (design.sv)
- Address space: `0x00 ~ 0x07` (8 locations), each stores 8-bit data
- Transfer phases:
  - SETUP: `PSEL=1, PENABLE=0` latch request
  - ACCESS: `PSEL=1, PENABLE=1` complete transfer
- Wait states:
  - `N=1`: `PREADY` asserts immediately in ACCESS
  - `N>=2`: `PREADY` stays low for `N-1` ACCESS cycles, asserts on the Nth
- Error:
  - Illegal write (`addr > 0x07`) sets `PSLVERR=1`
  - Reads return the mirror memory value at `addr[2:0]`

## Verification Architecture (UVM)

### Overall Testbench Hierarchy (Word Diagram)

```
apb_top
│
├── Clock / Reset
│
├── apb_if (interface)
│   ├── MASTER_MP  (driver)
│   └── MON_MP     (monitor)
│
├── DUT : apb_slave
│
└── uvm_test_top
    └── apb_test
        └── apb_env
            ├── apb_agent
            │   ├── apb_sequencer
            │   ├── apb_driver
            │   └── apb_monitor
            │
            ├── apb_ref_model
            │
            └── apb_scoreboard
```

---

### Data Flow Diagram (Transaction View)

```
apb_write_seq / apb_read_seq
        |
        v
  apb_sequencer
        |
        v
   apb_driver
        |
        v
   apb_if (MASTER_MP)
        |
        v
      DUT
        |
        v
   apb_if (MON_MP)
        |
        v
   apb_monitor
        |
        +--------------------+
        |                    |
        v                    v
 apb_ref_model        apb_scoreboard (ACT)
        |
        v
 apb_scoreboard (EXP)
```

ACT path: monitor → scoreboard

EXP path: monitor → ref_model → scoreboard

Scoreboard performs cycle-accurate transaction comparison

---

## File Structure
```
┌─────────────────────────────────────────────────┐
│    Top                                          │
│ ┌───────────────────────────────────────────┐   │
│ │  Test                                     │   │
│ │┌─────────────────────────────────────────┐│   │
│ ││ Env                                     ││   │
│ ││┌────────────────┐                       ││   │
│ │││ Agent          │                       ││   │
│ │││                │                       ││   │
│ │││┌─────────────┐ │                       ││   │
│ ││││  Sequencer  │ │   ┌───────────┐       ││   │
│ ││││ ┌────────┐  │ │ ┌─►ScoreBoard │       ││   │
│ ││││ │Sequence│  │ │ │ └────▲──────┘       ││   │
│ ││││ └───┬────┘  │ │ │ ┌────┼────────┐     ││   │
│ │││└─────┼───────┘ │ │ │Refence Model│     ││   │
│ │││      │         │ │ └────▲────────┘     ││   │
│ │││┌─────▼───────┐ │ │ ┌────┼────┐         ││   │
│ ││││  Driver     │ │ └─┼ Monitor │         ││   │
│ │││└──────┬──────┘ │   └────▲────┘         ││   │
│ ││└───────┼────────┘        │              ││   │
│ │└────────┼─────────────────┼──────────────┘│   │
│ └─────────┼─────────────────┼───────────────┘   │
│  ┌────────▼─────────────────┼──────────────┐    │
│  │     apb_if                              │    │
│  └──────┬─▲─────────────────▲──────────────┘    │
│    ┌────▼─┼───┐         ┌───┼───────────┐       │
│    │  DUV     │         │Clock Generator│       │
│    └──────────┘         └───────────────┘       │
└─────────────────────────────────────────────────┘

```


```
.
├── design.sv              # APB slave DUT
├── apb_top.sv             # Testbench top (clk/rst, interface, DUT, run_test)
├── apb_defines.sv         # ADDR_WIDTH / DATA_WIDTH macros
├── apb_if.sv              # APB interface + clocking blocks + assertions
│
├── apb_tb_pkg.sv          # UVM package (classes only)
├── apb_seq_item.sv
├── apb_sequencer.sv
├── apb_driver.sv
├── apb_monitor.sv
├── apb_agent.sv
├── apb_ref_model.sv
├── apb_scoreboard.sv
├── apb_env.sv
├── apb_write_seq.sv
├── apb_read_seq.sv
└── apb_test.sv
```



## Running the Simulation

### Questa / qrun

```sh
qrun -batch -uvmhome uvm-1.2 -timescale 1ns/1ns -mfcu \
  design.sv apb_top.sv \
  -voptargs=+acc=npr \
  -do "run -all; exit"
```

### Notes on Warnings

**Warning: `vopt-10587 (+acc)`**

* This is **not an error**
* Indicates reduced optimization due to debug visibility
* Acceptable during development
* Can be removed later for performance

---

## Common Pitfalls (Already Solved Here)

| Issue                    | Cause                    | Solution                         |
| ------------------------ | ------------------------ | -------------------------------- |
| interface compile error  | interface inside package | move `apb_if.sv` outside         |
| multiply driven signals  | TB & DUT both drive      | only DUT drives PRDATA/PREADY    |
| extern constructor error | default mismatch         | keep defaults only in definition |
| scoreboard mismatch      | ordering issues          | queue-based ACT/EXP matching     |

---

## How to Extend This Project

Recommended next steps:

* Add **coverage** in `apb_monitor`
* Add **assertions** for APB stability during wait states
* Add **UVM RAL (register model)**
* Extend to **APB4** (`PSTRB`, `PPROT`)
* Randomize DUT wait-state parameter `N`

---

## Author

* **Author:** ken, Lu Wei-Ru
* **Created:** 2026-01-18
* **Purpose:** Learning-quality APB + UVM reference project

---

## License

Suggested: **MIT License**
(You may change based on your use case)