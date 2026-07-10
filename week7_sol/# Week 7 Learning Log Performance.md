# Week 7 Learning Log: Performance and Synthesis

## Measurement & Amdahl's Law
This week completely shifted the perspective from functional correctness to hardware performance. Building the cycle-counting harness and calculating IPC revealed how theoretical width (2-wide) is bounded by physical reality. I learned firsthand how a single architectural bottleneck (in this case, our single commit port) will throttle the entire pipeline to 1.0 IPC, perfectly illustrating Amdahl's Law regarding structural constraints.

## Quartus Synthesis
Moving the code from ModelSim to Quartus was an eye-opener. I learned that just because Verilog simulates correctly doesn't mean it synthesizes perfectly. I had to pay close attention to inferred latches and multiple drivers. Synthesizing the design also confirmed what the theory taught us: the **Wakeup-Select Loop** is the absolute critical path of an Out-of-Order processor because it consists of a massive, unbroken chain of combinational logic that dictates the `Fmax` clock speed limit.