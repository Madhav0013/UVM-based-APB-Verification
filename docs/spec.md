# APB Slave Specification

## 1. DUT Overview

The DUT is a simple APB slave containing four 32-bit internal registers.
It supports standard APB read and write transactions.
The slave is always ready (PREADY = 1, zero wait states).
Invalid address accesses raise PSLVERR = 1.

## 2. Register Map

| Address  | Name     | Access | Reset Value    | Description              |
|----------|----------|--------|----------------|--------------------------|
| 0x00     | CTRL     | R/W    | 32'h0000_0000  | Control register         |
| 0x04     | STATUS   | R/W    | 32'h0000_0001  | Status register          |
| 0x08     | DATA     | R/W    | 32'h0000_0000  | Data register            |
| 0x0C     | CONFIG   | R/W    | 32'h0000_0000  | Configuration register   |

All registers are 32-bit, word-aligned. Only addresses 0x00, 0x04, 0x08, 0x0C are valid.

## 3. Interface Signals

### Inputs
| Signal      | Width | Description                    |
|-------------|-------|--------------------------------|
| PCLK        | 1     | APB clock                      |
| PRESETn     | 1     | Active-low asynchronous reset  |
| PSEL        | 1     | Slave select                   |
| PENABLE     | 1     | Enable phase indicator         |
| PWRITE      | 1     | 1 = write, 0 = read           |
| PADDR       | 32    | Address bus                    |
| PWDATA      | 32    | Write data bus                 |

### Outputs
| Signal      | Width | Description                    |
|-------------|-------|--------------------------------|
| PRDATA      | 32    | Read data bus                  |
| PREADY      | 1     | Always 1 (zero wait states)    |
| PSLVERR     | 1     | Slave error (invalid address)  |

## 4. Transfer Behavior

### Write Transfer
Condition: PSEL == 1 && PENABLE == 1 && PWRITE == 1
- Valid address: Store PWDATA into addressed register. PSLVERR = 0.
- Invalid address: No register modified. PSLVERR = 1.

### Read Transfer
Condition: PSEL == 1 && PENABLE == 1 && PWRITE == 0
- Valid address: Drive addressed register value onto PRDATA. PSLVERR = 0.
- Invalid address: Drive PRDATA = 0. PSLVERR = 1.

## 5. Reset Behavior
When PRESETn == 0:
- All registers return to their reset values (see register map)
- PRDATA = 0
- PSLVERR = 0

## 6. Protocol Rules
- Setup phase: PSEL=1, PENABLE=0. Address, PWRITE, and PWDATA are placed.
- Enable phase: PSEL=1, PENABLE=1. Transfer completes.
- PADDR and PWRITE must remain stable from setup through enable phase.
- PENABLE must not be high unless PSEL is high.
