`timescale 1ns / 1ps

module tb_reservation_station();

    // Parameters
    localparam NUM_RS      = 4;
    localparam PHYS_ADDR_W = 6;
    localparam ROB_ADDR_W  = 3;
    localparam OP_WIDTH    = 4;

    // Clock & reset
    reg clk = 0;
    reg reset = 1;
    always #5 clk = ~clk;

    // Dispatch port
    reg disp_valid;
    reg [OP_WIDTH-1:0] disp_op;
    reg [PHYS_ADDR_W-1:0] disp_pj;
    reg [PHYS_ADDR_W-1:0] disp_pk;
    reg [PHYS_ADDR_W-1:0] disp_pd;
    reg [ROB_ADDR_W-1:0] disp_rob_idx;
    wire disp_stall;

    // Snoop ports (Flattened to match module)
    wire [(NUM_RS * PHYS_ADDR_W)-1:0] snoop_pj_addr;
    wire [(NUM_RS * PHYS_ADDR_W)-1:0] snoop_pk_addr;
    reg [NUM_RS-1:0] snoop_pj_ready;
    reg [NUM_RS-1:0] snoop_pk_ready;

    // Issue port (we capture)
    wire issue_valid;
    wire [OP_WIDTH-1:0] issue_op;
    wire [PHYS_ADDR_W-1:0] issue_pj;
    wire [PHYS_ADDR_W-1:0] issue_pk;
    wire [PHYS_ADDR_W-1:0] issue_pd;
    wire [ROB_ADDR_W-1:0] issue_rob_idx;

    // Fake PRF: track which physical registers are ready
    reg [47:0] prf_ready_bits; 

    // Drive snoop ready inputs based on fake PRF state using sliced addresses
    integer s;
    reg [PHYS_ADDR_W-1:0] temp_pj;
    reg [PHYS_ADDR_W-1:0] temp_pk;
    
    always @(*) begin
        for (s = 0; s < NUM_RS; s = s + 1) begin
            temp_pj = snoop_pj_addr[(s * PHYS_ADDR_W) +: PHYS_ADDR_W];
            temp_pk = snoop_pk_addr[(s * PHYS_ADDR_W) +: PHYS_ADDR_W];
            
            snoop_pj_ready[s] = prf_ready_bits[temp_pj];
            snoop_pk_ready[s] = prf_ready_bits[temp_pk];
        end
    end

    // Instantiate DUT
    reservation_station dut (
        .clk_i(clk),
        .reset_i(reset),
        .disp_valid_i(disp_valid),
        .disp_op_i(disp_op),
        .disp_pj_i(disp_pj),
        .disp_pk_i(disp_pk),
        .disp_pd_i(disp_pd),
        .disp_rob_idx_i(disp_rob_idx),
        .disp_stall_o(disp_stall),
        .snoop_pj_addr_o(snoop_pj_addr),
        .snoop_pk_addr_o(snoop_pk_addr),
        .snoop_pj_ready_i(snoop_pj_ready),
        .snoop_pk_ready_i(snoop_pk_ready),
        .issue_valid_o(issue_valid),
        .issue_op_o(issue_op),
        .issue_pj_o(issue_pj),
        .issue_pk_o(issue_pk),
        .issue_pd_o(issue_pd),
        .issue_rob_idx_o(issue_rob_idx)
    );

    // Self-checking helper
    integer errors = 0;
    task check_eq;
        input [31:0] actual;
        input [31:0] expected;
        input [255:0] label;
        begin
            if (actual === expected)
                $display("PASS: %s (got %0d)", label, actual);
            else begin
                $display("FAIL: %s (expected %0d, got %0d)", label, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    // Test sequence
    initial begin
        // Init
        disp_valid = 0; disp_op = 0;
        disp_pj = 0; disp_pk = 0; disp_pd = 0; disp_rob_idx = 0;
        prf_ready_bits = 48'hFFFF_FFFF_FFFF; 

        #20; reset = 0;

        // Test 1: Dispatch one ready instruction
        @(posedge clk);
        disp_valid <= 1;
        disp_op <= 4'd1; 
        disp_pj <= 6'd1;
        disp_pk <= 6'd2;
        disp_pd <= 6'd32;
        disp_rob_idx <= 3'd0;
        @(posedge clk);
        disp_valid <= 0;

        #1;
        check_eq(issue_valid, 1'b1, "T1: issue_valid after dispatch");
        check_eq(issue_op, 4'd1, "T1: issue_op = ADD");
        check_eq(issue_pj, 6'd1, "T1: issue_pj = P1");
        check_eq(issue_pk, 6'd2, "T1: issue_pk = P2");
        check_eq(issue_pd, 6'd32, "T1: issue_pd = P32");

        // Test 2: Dispatch with a not-ready source
        prf_ready_bits[5] = 1'b0; 
        @(posedge clk);
        disp_valid <= 1;
        disp_op <= 4'd2; 
        disp_pj <= 6'd5; 
        disp_pk <= 6'd6; 
        disp_pd <= 6'd33;
        disp_rob_idx <= 3'd1;
        @(posedge clk);
        disp_valid <= 0;
        
        #1;
        check_eq(issue_valid, 1'b0, "T2: issue_valid = 0 (waiting for P5)");
        
        prf_ready_bits[5] = 1'b1;
        #1;
        check_eq(issue_valid, 1'b1, "T2: issue_valid = 1 after P5 ready");
        check_eq(issue_pj, 6'd5, "T2: issue_pj = P5");
        @(posedge clk);
        #1;

        // Test 3: Fill all 4 RSs 
        prf_ready_bits[10] = 1'b0;
        prf_ready_bits[11] = 1'b0;
        prf_ready_bits[12] = 1'b0;
        prf_ready_bits[13] = 1'b0;

        @(posedge clk); disp_valid <= 1;
        disp_op <= 4'd1; disp_pj <= 6'd10; disp_pk <= 6'd2; disp_pd <= 6'd34; disp_rob_idx <= 3'd2;
        @(posedge clk);
        disp_op <= 4'd1; disp_pj <= 6'd11; disp_pk <= 6'd2; disp_pd <= 6'd35; disp_rob_idx <= 3'd3;
        @(posedge clk);
        disp_op <= 4'd1; disp_pj <= 6'd12; disp_pk <= 6'd2; disp_pd <= 6'd36; disp_rob_idx <= 3'd4;
        @(posedge clk);
        disp_op <= 4'd1; disp_pj <= 6'd13; disp_pk <= 6'd2; disp_pd <= 6'd37; disp_rob_idx <= 3'd5;
        @(posedge clk);
        disp_valid <= 0;

        #1;
        check_eq(issue_valid, 1'b0, "T3: no issue (all waiting)");

        @(posedge clk);
        disp_valid <= 1;
        disp_op <= 4'd1; disp_pj <= 6'd2; disp_pk <= 6'd2; disp_pd <= 6'd38; disp_rob_idx <= 3'd6;
        #1;
        check_eq(disp_stall, 1'b1, "T3: disp_stall when array full");
        @(posedge clk);
        disp_valid <= 0;

        prf_ready_bits[12] = 1'b1;
        #1;
        check_eq(issue_valid, 1'b1, "T3: issue after P12 ready");
        check_eq(issue_pj, 6'd12, "T3: P12 issued first");

        // FIX: Let P12 issue BEFORE waking up the rest of the array!
        @(posedge clk); 

        // Test 4: Multiple ready in same cycle
        prf_ready_bits[10] = 1'b1;
        prf_ready_bits[11] = 1'b1;
        prf_ready_bits[13] = 1'b1;
        
        #1;
        check_eq(issue_valid, 1'b1, "T4: lowest-index wins (P10)");
        check_eq(issue_pj, 6'd10, "T4: P10 issued (lowest free index)");

        // Continue issuing one per cycle
        @(posedge clk);
        #1;
        check_eq(issue_pj, 6'd11, "T4: P11 issued next");

        @(posedge clk);
        #1;
        check_eq(issue_pj, 6'd13, "T4: P13 issued last");

        @(posedge clk);
        #1;
        check_eq(issue_valid, 1'b0, "T4: all issued, no more");

        if (errors == 0)
            $display("ALL TESTS PASSED (%0d errors)", errors);
        else
            $display("FAILED %0d TESTS", errors);
        $finish;
    end
endmodule