# Week 2 — Milestone 1: Tomasulo's Algorithm

---

## Part A — Cycle-by-Cycle Trace

### Setup

**Code:**

```
I1: L.D   F2,  0(R1)        # Load
I2: MUL.D F4,  F2,  F6      # F4 = F2 * F6  (depends on I1)
I3: ADD.D F8,  F2,  F10     # F8 = F2 + F10 (depends on I1)
I4: SUB.D F4,  F8,  F2      # F4 = F8 - F2  (WAW on F4 with I2; depends on I3, I1)
I5: L.D   F8,  8(R1)        # Load           (WAW on F8 with I3)
I6: ADD.D F12, F4,  F8      # F12 = F4 + F8 (depends on I4 and I5)
```

**Hardware:**

| Resource | Count | Latency |
|---|---|---|
| Load RSs | 2 (Load1, Load2) | 2 cycles |
| Add/Sub RSs | 2 (Add1, Add2) | 2 cycles |
| Multiply RSs | 2 (Mult1, Mult2) | 6 cycles |

Single-issue, single CDB. Initial RST: all null.

---

### Notation

- **Vj / Vk** — operand value (ready)
- **Qj / Qk** — tag of the RS we are waiting on (not yet ready)
- `—` in a Qj/Qk column means the operand value is already in Vj/Vk (ready)
- RST shows which RS is the current producer for each tracked register

---

### Cycle 1 — Issue I1 (L.D F2)

**What happened:** I1 issues to Load1. R1 has no in-flight producer, so its address value is read from the register file. RST[F2] ← Load1.

| RS | Busy | Op | Vj | Vk | Qj | Qk |
|---|---|---|---|---|---|---|
| Load1 | ✓ | LD | [R1] | — | — | — |
| Load2 | — | | | | | |
| Add1 | — | | | | | |
| Add2 | — | | | | | |
| Mult1 | — | | | | | |
| Mult2 | — | | | | | |

**RST:**

| F2 | F4 | F8 | F12 |
|---|---|---|---|
| Load1 | — | — | — |

**CDB:** nothing

---

### Cycle 2 — Issue I2 (MUL.D F4, F2, F6). Load1 begins executing.

**What happened:** I2 issues to Mult1. F2: RST=Load1 (not ready) → Qj=Load1. F6: no producer → Vk=F6. RST[F4] ← Mult1. Load1 begins executing (will finish end of cycle 3).

| RS | Busy | Op | Vj | Vk | Qj | Qk |
|---|---|---|---|---|---|---|
| Load1 | ✓ *(exec)* | LD | [R1] | — | — | — |
| Load2 | — | | | | | |
| Add1 | — | | | | | |
| Add2 | — | | | | | |
| Mult1 | ✓ | MUL | — | [F6] | Load1 | — |
| Mult2 | — | | | | | |

**RST:**

| F2 | F4 | F8 | F12 |
|---|---|---|---|
| Load1 | Mult1 | — | — |

**CDB:** nothing

---

### Cycle 3 — Issue I3 (ADD.D F8, F2, F10). Load1 finishes → broadcasts.

**What happened:** I3 issues to Add1. F2: RST=Load1 → Qj=Load1. F10: no producer → Vk=F10. RST[F8] ← Add1.

Load1 finishes (2-cycle latency from cycle 2). Broadcasts **(Load1, mem[R1])** on the CDB.
- Mult1's Qj=Load1 → **captures** mem[R1] into Vj. Mult1 now has both operands — it is ready.
- Add1's Qj=Load1 → **captures** mem[R1] into Vj. Add1 now has both operands — it is ready.
- RST[F2]=Load1 → register file writes F2 = mem[R1], RST[F2] ← null.
- Load1 is freed.

| RS | Busy | Op | Vj | Vk | Qj | Qk |
|---|---|---|---|---|---|---|
| Load1 | — | | | | | |
| Load2 | — | | | | | |
| Add1 | ✓ *(ready)* | ADD | [F2] | [F10] | — | — |
| Add2 | — | | | | | |
| Mult1 | ✓ *(ready)* | MUL | [F2] | [F6] | — | — |
| Mult2 | — | | | | | |

**RST:**

| F2 | F4 | F8 | F12 |
|---|---|---|---|
| — | Mult1 | Add1 | — |

**CDB:** (Load1, mem[R1])

---

### Cycle 4 — Issue I4 (SUB.D F4, F8, F2). Mult1 and Add1 begin executing.

**What happened:** I4 issues to Add2. F8: RST=Add1 → Qj=Add1. F2: RST=null → Vk=F2 (from reg file, now safe). RST[F4] ← Add2. **This silently resolves the WAW on F4** — Mult1's result is no longer the final producer; Add2 is.

Mult1 is ready → begins executing (6-cycle latency, finishes end of cycle **9**).
Add1 is ready → begins executing (2-cycle latency, finishes end of cycle **5**).

| RS | Busy | Op | Vj | Vk | Qj | Qk |
|---|---|---|---|---|---|---|
| Load1 | — | | | | | |
| Load2 | — | | | | | |
| Add1 | ✓ *(exec)* | ADD | [F2] | [F10] | — | — |
| Add2 | ✓ | SUB | — | [F2] | Add1 | — |
| Mult1 | ✓ *(exec)* | MUL | [F2] | [F6] | — | — |
| Mult2 | — | | | | | |

**RST:**

| F2 | F4 | F8 | F12 |
|---|---|---|---|
| — | Add2 | Add1 | — |

**CDB:** nothing

---

### Cycle 5 — Issue I5 (L.D F8, 8(R1)). Add1 finishes → broadcasts.

**What happened:** I5 issues to Load2. No in-flight producer for R1, so address is read directly. RST[F8] ← Load2. **This silently resolves the WAW on F8** — Add1's result will not commit to the register file.

Add1 finishes (started cycle 4, done end of cycle 5). Broadcasts **(Add1, F8_result)** on the CDB.
- Add2's Qj=Add1 → **captures** F8_result into Vj. Add2 now has both operands — it is ready.
- RST[F8]=Load2 ≠ Add1 → register file **does not** write F8. (Load2 is the true final producer.)
- Add1 is freed.

Load2 will begin executing in cycle 6 (2-cycle latency, finishes end of **cycle 7**).

| RS | Busy | Op | Vj | Vk | Qj | Qk |
|---|---|---|---|---|---|---|
| Load1 | — | | | | | |
| Load2 | ✓ | LD | [R1+8] | — | — | — |
| Add1 | — | | | | | |
| Add2 | ✓ *(ready)* | SUB | [F8] | [F2] | — | — |
| Mult1 | ✓ *(exec)* | MUL | [F2] | [F6] | — | — |
| Mult2 | — | | | | | |

**RST:**

| F2 | F4 | F8 | F12 |
|---|---|---|---|
| — | Add2 | Load2 | — |

**CDB:** (Add1, F8_result)

---

### Cycle 6 — Issue I6 (ADD.D F12, F4, F8). Add2 begins executing.

**What happened:** I6 issues to Add1 (now freed). F4: RST=Add2 → Qj=Add2. F8: RST=Load2 → Qk=Load2. RST[F12] ← Add1.

Add2 is ready → begins executing (2-cycle latency, finishes end of **cycle 7**).
Load2 begins executing this cycle (finishes end of **cycle 7**).

| RS | Busy | Op | Vj | Vk | Qj | Qk |
|---|---|---|---|---|---|---|
| Load1 | — | | | | | |
| Load2 | ✓ *(exec)* | LD | [R1+8] | — | — | — |
| Add1 | ✓ | ADD | — | — | Add2 | Load2 |
| Add2 | ✓ *(exec)* | SUB | [F8] | [F2] | — | — |
| Mult1 | ✓ *(exec)* | MUL | [F2] | [F6] | — | — |
| Mult2 | — | | | | | |

**RST:**

| F2 | F4 | F8 | F12 |
|---|---|---|---|
| — | Add2 | Load2 | Add1 |

**CDB:** nothing

---

### Cycle 7 — Add2 and Load2 both finish. CDB arbitration: Load2 wins.

**What happened:** Both Add2 (I4) and Load2 (I5) finish this cycle. Only one may use the CDB — Load2 wins arbitration. Add2 holds its result and will broadcast next cycle.

CDB broadcasts **(Load2, mem[R1+8])**.
- Add1's Qk=Load2 → **captures** mem[R1+8] into Vk. Still waiting on Qj=Add2.
- RST[F8]=Load2 → register file writes F8 = mem[R1+8], RST[F8] ← null.
- Load2 is freed.

| RS | Busy | Op | Vj | Vk | Qj | Qk |
|---|---|---|---|---|---|---|
| Load1 | — | | | | | |
| Load2 | — | | | | | |
| Add1 | ✓ | ADD | — | [F8] | Add2 | — |
| Add2 | ✓ *(done, waiting)* | SUB | [F8] | [F2] | — | — |
| Mult1 | ✓ *(exec)* | MUL | [F2] | [F6] | — | — |
| Mult2 | — | | | | | |

**RST:**

| F2 | F4 | F8 | F12 |
|---|---|---|---|
| — | Add2 | — | Add1 |

**CDB:** (Load2, mem[R1+8])

---

### Cycle 8 — Add2 broadcasts its held result.

**What happened:** Add2 now gets the CDB. Broadcasts **(Add2, F4_result)**.
- Add1's Qj=Add2 → **captures** F4_result into Vj. Add1 now has both operands — it is ready.
- RST[F4]=Add2 → register file writes F4 = F4_result, RST[F4] ← null.
- Add2 is freed.

| RS | Busy | Op | Vj | Vk | Qj | Qk |
|---|---|---|---|---|---|---|
| Load1 | — | | | | | |
| Load2 | — | | | | | |
| Add1 | ✓ *(ready)* | ADD | [F4] | [F8] | — | — |
| Add2 | — | | | | | |
| Mult1 | ✓ *(exec)* | MUL | [F2] | [F6] | — | — |
| Mult2 | — | | | | | |

**RST:**

| F2 | F4 | F8 | F12 |
|---|---|---|---|
| — | — | — | Add1 |

**CDB:** (Add2, F4_result)

---

### Cycle 9 — Add1 begins executing. Mult1 finishes → broadcasts (dead result).

**What happened:** Add1 is ready → begins executing (2-cycle latency, finishes end of **cycle 10**).

Mult1 also finishes (started cycle 4, 6-cycle latency). Broadcasts **(Mult1, mul_result)**.
- No RS is waiting on Mult1's tag.
- RST[F4]=null ≠ Mult1 → register file **ignores** the broadcast. I4 (Add2) has already claimed F4 as the true producer. Mult1's result is architecturally dead — the WAW on F4 is completely resolved without any stall.
- Mult1 is freed.

| RS | Busy | Op | Vj | Vk | Qj | Qk |
|---|---|---|---|---|---|---|
| Load1 | — | | | | | |
| Load2 | — | | | | | |
| Add1 | ✓ *(exec)* | ADD | [F4] | [F8] | — | — |
| Add2 | — | | | | | |
| Mult1 | — | | | | | |
| Mult2 | — | | | | | |

**RST:**

| F2 | F4 | F8 | F12 |
|---|---|---|---|
| — | — | — | Add1 |

**CDB:** (Mult1, mul_result) — *ignored by register file*

---

### Cycle 10 — Add1 finishes. All instructions complete.

**What happened:** Add1 finishes. Broadcasts **(Add1, F12_result)**.
- RST[F12]=Add1 → register file writes F12 = F12_result, RST[F12] ← null.
- Add1 is freed.

All six instructions have now committed their architectural results.

| RS | Busy | Op | Vj | Vk | Qj | Qk |
|---|---|---|---|---|---|---|
| Load1 | — | | | | | |
| Load2 | — | | | | | |
| Add1 | — | | | | | |
| Add2 | — | | | | | |
| Mult1 | — | | | | | |
| Mult2 | — | | | | | |

**RST:**

| F2 | F4 | F8 | F12 |
|---|---|---|---|
| — | — | — | — |

**CDB:** (Add1, F12_result)

---

### Summary Timeline

| Cycle | Event |
|---|---|
| 1 | Issue I1 → Load1 |
| 2 | Issue I2 → Mult1; Load1 begins executing |
| 3 | Issue I3 → Add1; Load1 finishes → broadcasts; Mult1 and Add1 capture F2 and become ready |
| 4 | Issue I4 → Add2 (WAW on F4 silently resolved); Mult1 and Add1 begin executing |
| 5 | Issue I5 → Load2 (WAW on F8 silently resolved); Add1 finishes → broadcasts; Add2 captures F8 and becomes ready |
| 6 | Issue I6 → Add1 (reused slot); Add2 begins executing; Load2 begins executing |
| 7 | Add2 and Load2 both finish; Load2 wins CDB arbitration → broadcasts; Add1 captures mem[R1+8]; Add2 holds result |
| 8 | Add2 broadcasts F4_result; Add1 captures F4_result — Add1 now fully ready |
| 9 | Add1 begins executing; Mult1 finishes → broadcasts dead result (ignored — WAW absorbed) |
| 10 | Add1 finishes → broadcasts F12_result; F12 committed to register file. **Done.** |

**Total: 10 cycles for 6 instructions.**

The 6-cycle multiply ran entirely in the background. By the time it finished (cycle 9), its result had already been superseded — the WAW was absorbed without a single stall.

---

## Part B — How Tomasulo Eliminates WAW Hazards

I will use the WAW pair **I2 and I4** from the trace above: both write register F4.

```
I2: MUL.D F4, F2, F6    → allocated to Mult1
I4: SUB.D F4, F8, F2    → allocated to Add2   (issued later, in cycle 4)
```

In a scoreboard, the hardware would see two in-flight writers of F4 and refuse to issue I4 until I2 completes — a forced stall of however long the multiply takes. Tomasulo sidesteps this entirely.

**At I2's issue (cycle 2):** The RST entry for F4 is written: `RST[F4] ← Mult1`. Mult1's tag is now the "official" producer of F4.

**At I4's issue (cycle 4):** The RST entry for F4 is overwritten: `RST[F4] ← Add2`. From this moment, Add2 is the architecturally-correct final producer of F4. Any instruction issued after cycle 4 that reads F4 will copy tag Add2 into its Qj/Qk — not Mult1.

No stall has occurred. Both Mult1 and Add2 proceed independently.

**When Add2 finishes (cycle 7–8):** It broadcasts `(Add2, F4_result)` on the CDB. The register file checks `RST[F4]`: it equals Add2 — match. F4 is committed. `RST[F4] ← null`.

**When Mult1 finishes (cycle 9):** It broadcasts `(Mult1, mul_result)`. The register file checks `RST[F4]`: it is now null — no match. The register file ignores Mult1's broadcast entirely. The old value is not written; F4 correctly holds I4's result.

The key insight is that the RST always points to the *latest* producer in program order. Since issue is in-order, the last instruction to write a register will always be the last one to update the RST. The CDB's register-file-write check — "does my tag still match the RST?" — is the single gate that makes WAW a non-event. No special hazard detection, no stall logic. The design invariants make WAW impossible to express.
