// tb_rename_unit.v
// Self-checking testbench for rename_unit.v
// Covers all 7 required test cases from the spec.
// Run in ModelSim: vlog tb_rename_unit.v rename_unit.v && vsim -c tb_rename_unit -do "run -all"

`timescale 1ns/1ps

module tb_rename_unit;

    // =========================================================
    // DUT signals
    // =========================================================
    reg         clk;
    reg         reset;

    // Dispatch port
    reg         disp_valid;
    reg         disp_writes_rd;
    reg  [4:0]  disp_rs1_arch;
    reg  [4:0]  disp_rs2_arch;
    reg  [4:0]  disp_rd_arch;

    wire [5:0]  disp_rs1_phys;
    wire [5:0]  disp_rs2_phys;
    wire [5:0]  disp_rd_phys;
    wire [5:0]  disp_rd_old_phys;
    wire        stall;

    // Commit port
    reg         commit_valid;
    reg  [5:0]  commit_old_phys;

    // =========================================================
    // DUT instantiation
    // =========================================================
    rename_unit #(
        .NUM_ARCH_REGS(32),
        .NUM_PHYS_REGS(48),
        .ARCH_ADDR_W(5),
        .PHYS_ADDR_W(6),
        .FREE_LIST_SZ(16)
    ) dut (
        .clk_i              (clk),
        .reset_i            (reset),
        .disp_valid_i       (disp_valid),
        .disp_writes_rd_i   (disp_writes_rd),
        .disp_rs1_arch_i    (disp_rs1_arch),
        .disp_rs2_arch_i    (disp_rs2_arch),
        .disp_rd_arch_i     (disp_rd_arch),
        .disp_rs1_phys_o    (disp_rs1_phys),
        .disp_rs2_phys_o    (disp_rs2_phys),
        .disp_rd_phys_o     (disp_rd_phys),
        .disp_rd_old_phys_o (disp_rd_old_phys),
        .stall_o            (stall),
        .commit_valid_i     (commit_valid),
        .commit_old_phys_i  (commit_old_phys)
    );

    // =========================================================
    // Clock: 10 ns period (100 MHz)
    // =========================================================
    initial clk = 0;
    always  #5 clk = ~clk;

    // =========================================================
    // Error counter
    // =========================================================
    integer errors   = 0;
    integer test_num = 0;

    // =========================================================
    // Helper tasks
    // =========================================================
    task check_phys;
        input [5:0]   actual;
        input [5:0]   expected;
        input [255:0] label;
        begin
            test_num = test_num + 1;
            if (actual === expected)
                $display("  PASS [T%0d]: %s  (got P#%0d)", test_num, label, actual);
            else begin
                $display("  FAIL [T%0d]: %s  (expected P#%0d, got P#%0d)",
                         test_num, label, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task check_bit;
        input        actual;
        input        expected;
        input [255:0] label;
        begin
            test_num = test_num + 1;
            if (actual === expected)
                $display("  PASS [T%0d]: %s  (got %b)", test_num, label, actual);
            else begin
                $display("  FAIL [T%0d]: %s  (expected %b, got %b)",
                         test_num, label, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task idle;
        begin
            disp_valid    = 0;
            disp_writes_rd= 0;
            disp_rs1_arch = 0;
            disp_rs2_arch = 0;
            disp_rd_arch  = 0;
            commit_valid  = 0;
            commit_old_phys = 0;
        end
    endtask

    // Dispatch one instruction that writes a destination
    task dispatch_write;
        input [4:0] rs1, rs2, rd;
        begin
            disp_valid     <= 1;
            disp_writes_rd <= 1;
            disp_rs1_arch  <= rs1;
            disp_rs2_arch  <= rs2;
            disp_rd_arch   <= rd;
        end
    endtask

    // Dispatch one non-writing instruction (store / branch)
    task dispatch_nowrite;
        input [4:0] rs1, rs2;
        begin
            disp_valid     <= 1;
            disp_writes_rd <= 0;
            disp_rs1_arch  <= rs1;
            disp_rs2_arch  <= rs2;
            disp_rd_arch   <= 0;
        end
    endtask

    // Commit, returning old_phys to the free list
    task commit;
        input [5:0] old_phys;
        begin
            commit_valid    <= 1;
            commit_old_phys <= old_phys;
        end
    endtask

    // =========================================================
    // Test stimulus
    // =========================================================
    initial begin
        $display("==============================================");
        $display("  rename_unit Testbench");
        $display("==============================================");

        idle;
        reset = 1;
        @(posedge clk); @(posedge clk);
        @(negedge clk);
        reset = 0;

        // ----------------------------------------------------------
        // TEST 1: Reset state
        //   rename_map[i] = i for i in [0,31]
        //   free list has 16 entries (P32..P47)
        //   stall = 0 (not even trying to dispatch)
        // ----------------------------------------------------------
        $display("\n[TEST 1] Reset state: identity map and free list head = P32");
        @(posedge clk); #1;

        // Read source mappings via combinational outputs
        // Probe arch reg 0 -> should be P0
        disp_rs1_arch = 5'd0; disp_rs2_arch = 5'd3;
        disp_rd_arch  = 5'd3; // old phys of rd should be P3
        disp_valid = 1; disp_writes_rd = 1;  // just reading combinational outputs
        #1;
        check_phys(disp_rs1_phys,    6'd0, "Reset: arch 0 -> P0");
        check_phys(disp_rs2_phys,    6'd3, "Reset: arch 3 -> P3");
        check_phys(disp_rd_old_phys, 6'd3, "Reset: old phys of arch 3 = P3");
        check_phys(disp_rd_phys,     6'd32,"Reset: free list head = P32");
        check_bit (stall,            1'b0, "Reset: stall = 0 (16 free entries)");

        // De-assert so nothing actually commits on the next posedge
        disp_valid <= 0; disp_writes_rd <= 0;
        @(posedge clk);

        idle;

        // ----------------------------------------------------------
        // TEST 2: Single dispatch writing arch R3
        //   Expected: disp_rd_phys = P32, disp_rd_old_phys = P3
        // ----------------------------------------------------------
        $display("\n[TEST 2] Single dispatch writing arch R3");
        @(posedge clk);
        // Read combinational before the clock edge
        disp_rd_arch  = 5'd3;
        disp_rs1_arch = 5'd1;
        disp_rs2_arch = 5'd2;
        disp_valid    = 1; disp_writes_rd = 1;
        #1;
        check_phys(disp_rd_phys,     6'd32, "Dispatch R3: allocated P32");
        check_phys(disp_rd_old_phys, 6'd3,  "Dispatch R3: old phys = P3");
        check_phys(disp_rs1_phys,    6'd1,  "Dispatch R3: rs1 phys = P1");
        check_phys(disp_rs2_phys,    6'd2,  "Dispatch R3: rs2 phys = P2");

        @(posedge clk);  // latch the dispatch (rename_map[3] <- P32, fl_head++)
        disp_valid <= 0; disp_writes_rd <= 0;
        @(posedge clk); #1;

        // After dispatch: rename_map[3] should now be P32, fl head at P33
        disp_rd_arch = 5'd3; disp_rs1_arch = 5'd3;
        #1;
        check_phys(disp_rs1_phys, 6'd32, "Post-dispatch: arch 3 now -> P32");

        idle;

        // ----------------------------------------------------------
        // TEST 3: Back-to-back dispatches writing the SAME arch reg
        //   *** The most important test: WAW dissolution ***
        //   I1 writes R3 -> gets P33 (P32 taken in Test 2)
        //   I2 writes R3 -> must get P34 (different from P33)
        // ----------------------------------------------------------
        $display("\n[TEST 3] Back-to-back dispatches to same arch reg (WAW dissolution)");

        // Dispatch I1: write R3
        @(posedge clk);
        disp_rd_arch = 5'd3; disp_rs1_arch = 5'd0; disp_rs2_arch = 5'd0;
        disp_valid = 1; disp_writes_rd = 1;
        #1;
        begin : t3_i1
            reg [5:0] phys_i1;
            phys_i1 = disp_rd_phys;
            $display("    I1 writes R3 -> allocated P#%0d (old=P#%0d)",
                     disp_rd_phys, disp_rd_old_phys);
            @(posedge clk); // latch I1 dispatch
            disp_valid <= 0; disp_writes_rd <= 0;
            @(posedge clk); #1;  // one idle cycle so rename_map is updated

            // Dispatch I2: write R3 again
            disp_rd_arch  = 5'd3;
            disp_rs1_arch = 5'd0; disp_rs2_arch = 5'd0;
            disp_valid = 1; disp_writes_rd = 1;
            #1;
            $display("    I2 writes R3 -> allocated P#%0d (old=P#%0d)",
                     disp_rd_phys, disp_rd_old_phys);

            // Key assertion: I1 and I2 must have DIFFERENT physical destinations
            test_num = test_num + 1;
            if (disp_rd_phys !== phys_i1) begin
                $display("  PASS [T%0d]: WAW dissolved — I1=P#%0d, I2=P#%0d (different)",
                         test_num, phys_i1, disp_rd_phys);
            end else begin
                $display("  FAIL [T%0d]: WAW NOT dissolved — both got P#%0d!",
                         test_num, phys_i1);
                errors = errors + 1;
            end

            // old_phys for I2 must be what I1 allocated (P#phys_i1)
            check_phys(disp_rd_old_phys, phys_i1, "WAW: I2 old_phys = I1 new_phys");

            @(posedge clk); // latch I2 dispatch
            disp_valid <= 0; disp_writes_rd <= 0;
        end

        idle;
        @(posedge clk);

        // ----------------------------------------------------------
        // TEST 4: Dispatch followed by commit returning old phys
        //   After 3 dispatches in tests 2+3 the free list has 13 entries.
        //   Commit with old_phys = P3 (the very first old phys from Test 2).
        //   Count should go back to 14.
        //   Next allocation should eventually reach P3 again (FIFO).
        // ----------------------------------------------------------
        $display("\n[TEST 4] Commit returns old phys to free list");
        @(posedge clk);
        commit_valid    <= 1;
        commit_old_phys <= 6'd3;   // return P3
        @(posedge clk);
        commit_valid <= 0;
        // No assertion on the internal fl_count directly, but stall must stay 0.
        #1;
        // Drive a non-writing dispatch to observe stall without allocating
        disp_valid = 1; disp_writes_rd = 1;  // writes_rd=1 but free list not empty -> no stall
        disp_rd_arch = 5'd5;
        #1;
        check_bit(stall, 1'b0, "Commit: free list non-empty, stall = 0");
        disp_valid = 0; disp_writes_rd = 0;

        idle;
        @(posedge clk);

        // ----------------------------------------------------------
        // TEST 5: Non-writing instruction does NOT touch rename map or free list
        // ----------------------------------------------------------
        $display("\n[TEST 5] Non-writing instruction (disp_writes_rd = 0)");

        // Capture current mapping of R5 before non-writing dispatch
        @(posedge clk); #1;
        disp_rs1_arch = 5'd5; disp_rd_arch = 5'd5;
        disp_valid = 1; disp_writes_rd = 0;  // store/branch: no dest
        #1;
        begin : t5
            reg [5:0] phys_before;
            phys_before = disp_rs1_phys;   // mapping of R5 before

            @(posedge clk); // latch (should be a no-op for map/free list)
            disp_valid <= 0;
            @(posedge clk); #1;

            // Probe R5 mapping again
            disp_rs1_arch = 5'd5; disp_valid = 1; disp_writes_rd = 0;
            #1;
            check_phys(disp_rs1_phys, phys_before, "Non-write: R5 mapping unchanged");
            check_bit(stall, 1'b0, "Non-write: no stall even though writes_rd=0");
        end

        idle;
        @(posedge clk);

        // ----------------------------------------------------------
        // TEST 6: Free list exhaustion — 16th+1 dispatch -> stall = 1
        //   At this point the free list has 14 entries after Tests 2,3,4.
        //   Drain the remaining 14, then the 15th must stall.
        //   (We start counting from the current state, not from reset.)
        // ----------------------------------------------------------
        $display("\n[TEST 6] Free list exhaustion -> stall");

        // Drain all remaining entries (we know there are 14 left:
        //   16 initial - 3 dispatches in T2/T3 + 1 commit in T4 = 14)
        begin : t6
            integer k;
            // Drain 14
            for (k = 0; k < 14; k = k + 1) begin
                @(posedge clk);
                disp_valid     <= 1;
                disp_writes_rd <= 1;
                disp_rd_arch   <= k[4:0]; // arbitrary arch reg
                disp_rs1_arch  <= 0;
                disp_rs2_arch  <= 0;
            end
            @(posedge clk);
            disp_valid <= 0; disp_writes_rd <= 0;
            @(posedge clk); #1;

            // Now free list should be empty — next dispatch with writes_rd must stall
            disp_valid = 1; disp_writes_rd = 1; disp_rd_arch = 5'd10;
            #1;
            check_bit(stall, 1'b1, "Exhaustion: stall = 1 when free list empty");
        end

        idle;
        @(posedge clk);

        // ----------------------------------------------------------
        // TEST 7: Simultaneous dispatch and commit — fl_count unchanged
        //   While stalled (free list empty), commit one, and simultaneously
        //   attempt dispatch. The dispatch is still stalled this cycle
        //   (the spec says we accept a 1-cycle bubble), so fl_count goes
        //   +1 from the commit. On the NEXT cycle the dispatch can proceed.
        // ----------------------------------------------------------
        $display("\n[TEST 7] Simultaneous dispatch + commit");

        @(posedge clk);
        // Commit old_phys = P10 (some arbitrary value)
        commit_valid    <= 1;
        commit_old_phys <= 6'd10;
        // Also request a dispatch — it will stall this cycle because
        // fl_count is still 0 at the start of the cycle.
        disp_valid     <= 1;
        disp_writes_rd <= 1;
        disp_rd_arch   <= 5'd7;
        @(posedge clk);
        // After clock: fl_count = 1 (commit pushed one, dispatch was stalled so did not pop)
        commit_valid <= 0;
        #1;
        // Now fl_count = 1, dispatch is still requested -> should NOT stall anymore
        check_bit(stall, 1'b0, "After commit: stall clears (fl_count = 1)");

        @(posedge clk); // dispatch now fires without stall
        disp_valid <= 0; disp_writes_rd <= 0;

        idle;

        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
        $display("\n==============================================");
        if (errors == 0)
            $display("  ALL TESTS PASSED (%0d checks)", test_num);
        else
            $display("  FAILED %0d / %0d TESTS", errors, test_num);
        $display("==============================================");
        $finish;
    end

endmodule
