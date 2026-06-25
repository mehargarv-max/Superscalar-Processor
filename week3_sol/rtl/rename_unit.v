// rename_unit.v
// Single-issue Rename Unit for PRAVAH superscalar processor
// Specification:
//   - 32 architectural registers -> 48 physical registers
//   - Rename map  : 32-entry table, arch -> phys (identity on reset)
//   - Free list   : FIFO queue of unallocated physical regs (P32-P47 on reset)
//   - Dispatch    : looks up 2 sources + old dest, pops 1 free phys reg
//   - Commit      : returns old physical reg back to free list
//   - Stall       : asserted when free list is empty and dispatch needs a reg
// Verilog-2001 only — no SystemVerilog constructs

module rename_unit #(
    parameter NUM_ARCH_REGS = 32,
    parameter NUM_PHYS_REGS = 48,
    parameter ARCH_ADDR_W   = 5,    // $clog2(32) = 5
    parameter PHYS_ADDR_W   = 6,    // $clog2(48) rounded up = 6
    parameter FREE_LIST_SZ  = 16    // NUM_PHYS_REGS - NUM_ARCH_REGS = 16
)(
    input  wire                   clk_i,
    input  wire                   reset_i,

    // ---- Dispatch port ----
    input  wire                   disp_valid_i,       // instruction at dispatch
    input  wire                   disp_writes_rd_i,   // 0 for store/branch (no dest)
    input  wire [ARCH_ADDR_W-1:0] disp_rs1_arch_i,   // architectural source 1
    input  wire [ARCH_ADDR_W-1:0] disp_rs2_arch_i,   // architectural source 2
    input  wire [ARCH_ADDR_W-1:0] disp_rd_arch_i,    // architectural destination

    output wire [PHYS_ADDR_W-1:0] disp_rs1_phys_o,      // physical source 1
    output wire [PHYS_ADDR_W-1:0] disp_rs2_phys_o,      // physical source 2
    output wire [PHYS_ADDR_W-1:0] disp_rd_phys_o,       // newly allocated physical dest
    output wire [PHYS_ADDR_W-1:0] disp_rd_old_phys_o,   // old mapping (for ROB rollback)

    output wire                   stall_o,   // 1 = stall front-end (no free phys regs)

    // ---- Commit port ----
    input  wire                   commit_valid_i,
    input  wire [PHYS_ADDR_W-1:0] commit_old_phys_i   // old phys reg to return to free list
);

    // =========================================================
    // Internal state
    // =========================================================
    reg [PHYS_ADDR_W-1:0] rename_map [0:NUM_ARCH_REGS-1];
    reg [PHYS_ADDR_W-1:0] free_list  [0:FREE_LIST_SZ-1];

    // Pointers are one bit wider than log2(FREE_LIST_SZ) by convention
    reg [$clog2(FREE_LIST_SZ):0] fl_head;
    reg [$clog2(FREE_LIST_SZ):0] fl_tail;
    reg [$clog2(FREE_LIST_SZ):0] fl_count;

    integer i;
    reg [PHYS_ADDR_W-1:0] fl_init_val;  // scratch for free-list reset loop

    // =========================================================
    // Helper wires — do we actually act this cycle?
    // =========================================================
    wire do_dispatch = disp_valid_i & disp_writes_rd_i & ~stall_o;
    wire do_commit   = commit_valid_i;

    // =========================================================
    // Combinational outputs (reads are always live)
    // =========================================================
    assign disp_rs1_phys_o    = rename_map[disp_rs1_arch_i];
    assign disp_rs2_phys_o    = rename_map[disp_rs2_arch_i];
    assign disp_rd_old_phys_o = rename_map[disp_rd_arch_i];

    // The next free physical register sits at the head of the free list
    assign disp_rd_phys_o = free_list[fl_head[$clog2(FREE_LIST_SZ)-1:0]];

    // Stall when dispatch needs a phys reg but the free list is empty
    assign stall_o = disp_valid_i & disp_writes_rd_i & (fl_count == 0);

    // =========================================================
    // Synchronous state update (rising edge)
    // =========================================================
    always @(posedge clk_i) begin
        if (reset_i) begin
            // Identity map: architectural register R -> physical register R
            for (i = 0; i < NUM_ARCH_REGS; i = i + 1)
                rename_map[i] <= i[PHYS_ADDR_W-1:0];

            // Free list holds the "spare" physical registers P32..P47
            for (i = 0; i < FREE_LIST_SZ; i = i + 1) begin
                fl_init_val  = NUM_ARCH_REGS[PHYS_ADDR_W-1:0] + i[PHYS_ADDR_W-1:0];
                free_list[i] <= fl_init_val;
            end

            fl_head  <= 0;
            fl_tail  <= 0;
            fl_count <= FREE_LIST_SZ;

        end else begin
            // ---- Dispatch: pop free list head, update rename map ----
            if (do_dispatch) begin
                rename_map[disp_rd_arch_i] <= free_list[fl_head[$clog2(FREE_LIST_SZ)-1:0]];
                fl_head <= (fl_head + 1) % FREE_LIST_SZ;
            end

            // ---- Commit: push old physical reg onto free list tail ----
            if (do_commit) begin
                free_list[fl_tail[$clog2(FREE_LIST_SZ)-1:0]] <= commit_old_phys_i;
                fl_tail <= (fl_tail + 1) % FREE_LIST_SZ;
            end

            // ---- Update free list count atomically ----
            // Both happen: net 0   |   dispatch only: -1   |   commit only: +1
            if (do_dispatch && do_commit)
                fl_count <= fl_count;           // net zero
            else if (do_dispatch)
                fl_count <= fl_count - 1;
            else if (do_commit)
                fl_count <= fl_count + 1;
        end
    end

endmodule
