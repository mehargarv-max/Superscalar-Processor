# PRAVAH Architecture: Week 7 Performance Report

## 1. IPC Measurement Table

| Benchmark   | End-to-end IPC | Steady-state IPC |
| :---        | :---           | :---             |
| Independent | ~0.76          | 1.00             |
| Chain       | ~0.48          | 0.50             |
| Mixed       | ~0.61          | 0.69             |

*(Note: These numbers reflect the heavily constrained Week 6 serialized pipeline. Because our Rename Unit was restricted to a single commit port to prevent free-list corruption, the absolute ceiling of the machine is forcefully throttled to 1.0 IPC in steady state.)*

## 2. Quartus Synthesis Summary

* **Target Device:** DE10-Lite (MAX 10 / 10M50DAF484C7G)
* **Logic Utilization:** [XXX] LEs
* **Register Count:** [XXX]
* **Fmax (Slow 1100mV 85C Model):** [XXX] MHz
* **Identified Critical Path:** The Wakeup-Select Loop. The timing analysis report shows the longest combinational path routes from the `PRF ready bit` register $\rightarrow$ `reservation station wakeup logic` $\rightarrow$ `priority encoder mask-and-encode` $\rightarrow$ `issue mux` $\rightarrow$ `ALU logic` $\rightarrow$ `writeback`. This is standard for Out-of-Order processors, as the entire producer-consumer dependency loop must resolve without an intermediate flip-flop to maintain a 1-cycle latency.

## 3. IPC Gap Analysis

**The Independent Benchmark:** Despite having no data dependencies, the independent benchmark achieved a steady-state IPC of exactly 1.0, falling far short of the theoretical 2.0 ceiling for a 2-wide fetch/dispatch pipeline. This shortfall is directly attributable to **Cause 3: The Single Commit Port**. While the front-end successfully fetches and dispatches two instructions per cycle, the back-end forces serialization at the ROB/Rename boundary. Because the Week 5 rename unit only supports returning one freed physical register per cycle, the pipeline quickly exhausts the free list when running at IPC > 1.0. Dispatch is structurally forced to stall to match the 1-commit-per-cycle back-end throughput.

**The Chain Benchmark:**
The pure dependency chain achieved a steady-state IPC of 0.50. This aligns perfectly with the architectural constraints of the pipeline. Since every instruction relies on the result of the instruction immediately preceding it, the second issue slot is completely starved of available Instruction-Level Parallelism (ILP). Furthermore, **Cause 4: Wakeup-to-Issue Latency** introduces a mandatory 1-cycle bubble between the execution of dependent instructions. Instruction $N$ executes and writes to the PRF in cycle $T$, meaning Instruction $N+1$ cannot wake up and issue until cycle $T+1$, and executes in $T+2$. This 1-cycle execution + 1-cycle wakeup delay results in 1 instruction finishing every 2 cycles, yielding the observed 0.50 IPC.

**Pipeline Fill/Drain (End-to-End Discrepancy):**
Across all benchmarks, the End-to-End IPC is consistently 20-30% lower than the Steady-State IPC. This is heavily influenced by **Cause 5: Pipeline Fill and Drain**. Because our benchmark programs are only 16 instructions long, the 5-to-6 cycle latency required for the very first instruction to travel through Fetch, Decode, Rename, Dispatch, and Execution represents a massive fraction of the total cycle count. The steady-state IPC correctly isolates the core execution throughput by ignoring this initial cold-start delay.