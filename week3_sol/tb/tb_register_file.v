// tb_register_file.v
// Self-checking testbench for register_file.v
// Covers all 7 required test cases from the spec.
// Run in ModelSim: vlog tb_register_file.v register_file.v && vsim -c tb_register_file -do "run -all"

`timescale 1ns/1ps

module tb_register_file;

    // =========================================================
    // DUT signals
    // =========================================================
    reg         clk;
    reg         reset;

    // Read ports
    reg  [5:0]  rd_addr1, rd_addr2, rd_addr3, rd_addr4;
    wire [31:0] rd_data1, rd_data2, rd_data3, rd_data4;
    wire        rd_ready1, rd_ready2, rd_ready3, rd_ready4;

    // Write ports
    reg         wr_en1;
    reg  [5:0]  wr_addr1;
    reg  [31:0] wr_data1;

    reg         wr_en2;
    reg  [5:0]  wr_addr2;
    reg  [31:0] wr_data2;

    // Allocate port
    reg         alloc_en;
    reg  [5:0]  alloc_addr;

    // =========================================================
    // DUT instantiation
    // =========================================================
    register_file #(
        .NUM_PHYS_REGS(48),
        .DATA_WIDTH(32),
        .ADDR_WIDTH(6)
    ) dut (
        .clk_i       (clk),
        .reset_i     (reset),
        .rd_addr1_i  (rd_addr1),  .rd_data1_o  (rd_data1),  .rd_ready1_o (rd_ready1),
        .rd_addr2_i  (rd_addr2),  .rd_data2_o  (rd_data2),  .rd_ready2_o (rd_ready2),
        .rd_addr3_i  (rd_addr3),  .rd_data3_o  (rd_data3),  .rd_ready3_o (rd_ready3),
        .rd_addr4_i  (rd_addr4),  .rd_data4_o  (rd_data4),  .rd_ready4_o (rd_ready4),
        .wr_en1_i    (wr_en1),    .wr_addr1_i  (wr_addr1),  .wr_data1_i  (wr_data1),
        .wr_en2_i    (wr_en2),    .wr_addr2_i  (wr_addr2),  .wr_data2_i  (wr_data2),
        .alloc_en_i  (alloc_en),  .alloc_addr_i(alloc_addr)
    );

    // =========================================================
    // Clock: 10 ns period (100 MHz)
    // =========================================================
    initial clk = 0;
    always  #5 clk = ~clk;

    // =========================================================
    // Error counter
    // =========================================================
    integer errors = 0;
    integer test_num = 0;

    // =========================================================
    // Helper tasks
    // =========================================================
    task check_data;
        input [31:0]  actual;
        input [31:0]  expected;
        input [255:0] label;
        begin
            test_num = test_num + 1;
            if (actual === expected)
                $display("  PASS [T%0d]: %s  (got 0x%08h)", test_num, label, actual);
            else begin
                $display("  FAIL [T%0d]: %s  (expected 0x%08h, got 0x%08h)",
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

    // De-assert all inputs
    task idle;
        begin
            wr_en1 = 0; wr_addr1 = 0; wr_data1 = 0;
            wr_en2 = 0; wr_addr2 = 0; wr_data2 = 0;
            alloc_en = 0; alloc_addr = 0;
            rd_addr1 = 0; rd_addr2 = 0; rd_addr3 = 0; rd_addr4 = 0;
        end
    endtask

    // =========================================================
    // Test stimulus
    // =========================================================
    initial begin
        $display("==============================================");
        $display("  register_file Testbench");
        $display("==============================================");

        // Initialise
        idle;
        reset = 1;
        @(posedge clk); @(posedge clk);  // hold reset for 2 cycles
        @(negedge clk);                   // sample on falling edge after 2nd posedge
        reset = 0;

        // ----------------------------------------------------------
        // TEST 1: Reset clears storage — every address reads 0
        //         and ready bit is 1 (register is available).
        // ----------------------------------------------------------
        $display("\n[TEST 1] Reset: read any address -> 0, ready = 1");
        @(posedge clk); #1;
        rd_addr1 = 6'd5;
        #1;
        check_data(rd_data1,  32'h0,  "Addr 5 data after reset");
        check_bit (rd_ready1, 1'b1,   "Addr 5 ready after reset");

        rd_addr1 = 6'd47;
        #1;
        check_data(rd_data1,  32'h0,  "Addr 47 data after reset");
        check_bit (rd_ready1, 1'b1,   "Addr 47 ready after reset");

        idle;

        // ----------------------------------------------------------
        // TEST 2: Single write then read returns the written value.
        // ----------------------------------------------------------
        $display("\n[TEST 2] Single write then read");
        @(posedge clk);
        wr_en1 <= 1; wr_addr1 <= 6'd5; wr_data1 <= 32'hDEAD_BEEF;
        @(posedge clk);
        wr_en1 <= 0;
        #1;
        rd_addr1 = 6'd5;
        #1;
        check_data(rd_data1,  32'hDEAD_BEEF, "Write1 then read data");
        check_bit (rd_ready1, 1'b1,           "Write1 sets ready = 1");

        idle;

        // ----------------------------------------------------------
        // TEST 3: Write-before-read bypass
        //         Same-cycle write + read to the same address must
        //         return the NEW value and ready = 1.
        // ----------------------------------------------------------
        $display("\n[TEST 3] Write-before-read bypass (same cycle)");
        @(posedge clk);
        // Simultaneously drive write and read to address 10
        wr_en1   <= 1; wr_addr1 <= 6'd10; wr_data1 <= 32'hCAFE_BABE;
        rd_addr1  = 6'd10;
        #1; // let combinational paths settle
        check_data(rd_data1,  32'hCAFE_BABE, "Bypass: correct data same cycle");
        check_bit (rd_ready1, 1'b1,           "Bypass: ready = 1 same cycle");
        @(posedge clk);
        wr_en1 <= 0;

        idle;

        // ----------------------------------------------------------
        // TEST 4: Two simultaneous writes to different addresses
        // ----------------------------------------------------------
        $display("\n[TEST 4] Two simultaneous writes to different addresses");
        @(posedge clk);
        wr_en1 <= 1; wr_addr1 <= 6'd20; wr_data1 <= 32'h1111_1111;
        wr_en2 <= 1; wr_addr2 <= 6'd21; wr_data2 <= 32'h2222_2222;
        @(posedge clk);
        wr_en1 <= 0; wr_en2 <= 0;
        #1;
        rd_addr1 = 6'd20; rd_addr2 = 6'd21;
        #1;
        check_data(rd_data1, 32'h1111_1111, "Simult write port 1 data");
        check_data(rd_data2, 32'h2222_2222, "Simult write port 2 data");
        check_bit (rd_ready1, 1'b1,          "Simult write port 1 ready");
        check_bit (rd_ready2, 1'b1,          "Simult write port 2 ready");

        idle;

        // ----------------------------------------------------------
        // TEST 5: Four simultaneous reads from four different addresses
        // ----------------------------------------------------------
        $display("\n[TEST 5] Four simultaneous reads");
        @(posedge clk);
        rd_addr1 = 6'd5;  rd_addr2 = 6'd10;
        rd_addr3 = 6'd20; rd_addr4 = 6'd21;
        #1;
        check_data(rd_data1, 32'hDEAD_BEEF, "4-way read port 1");
        check_data(rd_data2, 32'hCAFE_BABE, "4-way read port 2");
        check_data(rd_data3, 32'h1111_1111, "4-way read port 3");
        check_data(rd_data4, 32'h2222_2222, "4-way read port 4");

        idle;

        // ----------------------------------------------------------
        // TEST 6: Allocate clears the ready bit.
        //         After alloc on addr 5, rd_ready1 must be 0.
        // ----------------------------------------------------------
        $display("\n[TEST 6] Allocate clears ready bit");
        @(posedge clk);
        alloc_en <= 1; alloc_addr <= 6'd5;
        @(posedge clk);
        alloc_en <= 0;
        #1;
        rd_addr1 = 6'd5;
        #1;
        check_bit(rd_ready1, 1'b0, "Alloc clears ready bit");
        // Data is still the old value; we only care about ready here.

        idle;

        // ----------------------------------------------------------
        // TEST 7: Write after allocate sets the ready bit back to 1.
        // ----------------------------------------------------------
        $display("\n[TEST 7] Write after allocate sets ready = 1");
        @(posedge clk);
        wr_en1 <= 1; wr_addr1 <= 6'd5; wr_data1 <= 32'h0000_0099;
        @(posedge clk);
        wr_en1 <= 0;
        #1;
        rd_addr1 = 6'd5;
        #1;
        check_data(rd_data1,  32'h0000_0099, "Write after alloc: correct data");
        check_bit (rd_ready1, 1'b1,           "Write after alloc: ready = 1");

        idle;

        // ----------------------------------------------------------
        // BONUS: Write port 2 bypass (same cycle)
        // ----------------------------------------------------------
        $display("\n[BONUS] Write port 2 bypass");
        @(posedge clk);
        wr_en2   <= 1; wr_addr2 <= 6'd30; wr_data2 <= 32'hBEEF_CAFE;
        rd_addr3  = 6'd30;
        #1;
        check_data(rd_data3,  32'hBEEF_CAFE, "Port-2 bypass: correct data same cycle");
        check_bit (rd_ready3, 1'b1,           "Port-2 bypass: ready = 1 same cycle");
        @(posedge clk);
        wr_en2 <= 0;

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
