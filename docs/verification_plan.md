# APB Slave Verification Plan

## 1. DUT Features Under Verification
| Feature | Description |
|---------|-------------|
| Reset | All registers return to defined reset values |
| Write | PWDATA stored to addressed register |
| Read | PRDATA returns addressed register value |
| Invalid Address | PSLVERR asserted for non-valid addresses |
| Protocol Timing | Setup -> Enable phase sequencing |
| Back-to-back | Consecutive transfers without corruption |

## 2. Verification Architecture
- **Interface**: apb_if.sv — bundles all APB signals
- **Sequence Item**: apb_seq_item.sv — one APB transfer
- **Sequences**: 7 sequences (write, read, readback, all-reg, invalid, random, back-to-back)
- **Sequencer**: Standard UVM sequencer
- **Driver**: Converts transactions to APB pin activity (setup -> enable -> idle)
- **Monitor**: Observes completed transfers, publishes via analysis port, collects coverage
- **Agent**: Groups sequencer + driver + monitor
- **Scoreboard**: Maintains expected register model, checks reads, verifies PSLVERR
- **Environment**: Instantiates agent + scoreboard, connects analysis ports

## 3. Checking Strategy
### Scoreboard
- Maintains software register model initialized to reset values
- On write: updates model
- On read: compares DUT PRDATA vs expected
- On invalid access: checks PSLVERR = 1

### SVA Assertions
- PENABLE requires PSEL
- Setup before enable phase
- Address, PWRITE, PWDATA stable during transfer
- Invalid address raises PSLVERR
- Valid address does not raise PSLVERR

## 4. Coverage Plan
| Coverpoint | Bins |
|-----------|------|
| Read/Write | read, write |
| Address | 0x00, 0x04, 0x08, 0x0C, invalid |
| Error | PSLVERR=0, PSLVERR=1 |
| Cross | read/write x address |

## 5. Test Plan
| Test | Sequences Used | Goal |
|------|---------------|------|
| Smoke | write, read | Basic sanity |
| Register | all_reg | Full register map |
| Invalid | invalid_addr | Error handling |
| Random | random | Stress |
| Full | all combined | Complete verification |
