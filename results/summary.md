# APB UVM Verification — Results Summary

## Objective
Verify a 4-register APB slave using a full UVM testbench with scoreboard,
protocol assertions, and functional coverage.

## DUT
APB slave with 4 word-aligned 32-bit registers (CTRL, STATUS, DATA, CONFIG).
Zero wait-state (PREADY=1). PSLVERR on invalid address access.

## Simulator
Aldec Riviera-PRO 2025.04 via EDA Playground

## Tests Executed & Coverage
| Test | Transactions | Functional Coverage | Sim Time | Result |
|------|-------------|---------------------|-----------|--------|
| Smoke | 2 | ~15% (estimated) | ~200 ns | PASS |
| Register Access | 8 | 87.5% | 535 ns | PASS |
| Invalid Address | 8 | 37.5% | 535 ns | PASS |
| Random (30 txns) | 30 | 87.5% | 1195 ns | PASS |
| Full Functional | 56 | 100.0% | 2075 ns | PASS |

## Assertions
7 SVA properties checked continuously — 0 failures across all tests.

## Coverage
100% functional coverage achieved in apb_full_test.

## Final Status: ALL TESTS PASSED
