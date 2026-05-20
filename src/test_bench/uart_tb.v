`timescale 1ns/1ps
`include "kart.v"
`include "ref_model2.v"

module uart_tb;
    parameter WORD_LEN = 8;
    parameter XTAL_CLK = 50_000_000;
    parameter BAUD = 9600;

    localparam BIT_CLKS = XTAL_CLK / BAUD;
    localparam FRAME_CLKS = BIT_CLKS * 10;

    reg sys_clk;
    reg sys_rst_l;
    reg xmitH;
    reg [WORD_LEN-1:0] xmit_dataH;
    wire uart_XMIT_dataH_dut;
    wire xmit_doneH_dut;
    wire xmit_active_dut;

    reg uart_REC_dataH;
    wire [WORD_LEN-1:0] rec_dataH_dut;
    wire rec_readyH_dut;
    wire rec_busy_dut;

    wire uart_XMIT_dataH_ref;
    wire xmit_doneH_ref;
    wire xmit_active_ref;

    wire [WORD_LEN-1:0] rec_dataH_ref;
    wire rec_readyH_ref;
    wire rec_busy_ref;
    wire uart_clk_1;

    //Test Counters
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_count = 0;

    //DUT instantiation
    top #(
        .WORD(WORD_LEN),
        .XTAL(XTAL_CLK),
        .BAUD(BAUD)
    ) dut (
        .sys_clk(sys_clk),
        .sys_rst(sys_rst_l),
        .xmitH(xmitH),
        .xmit_dataH(xmit_dataH),
        .uart_xmit_datah(uart_XMIT_dataH_dut),
        .xmit_doneH(xmit_doneH_dut),
        .xmit_active(xmit_active_dut),

        .uart_rec_datah(uart_REC_dataH),
        .rec_datah(rec_dataH_dut),
        .rec_readyh(rec_readyH_dut),
        .rec_busyh(rec_busy_dut),
	.uart_clk(uart_clk_1)
    );

    //REF instantiation
    ref_model #(
        .WORD_LEN(WORD_LEN),
        .XTAL_CLK(XTAL_CLK),
        .BAUD(BAUD)
    ) reff (
        .sys_clk(sys_clk),
        .sys_rst_l(sys_rst_l),
        .xmitH(xmitH),
        .xmit_dataH(xmit_dataH),
        .uart_XMIT_dataH(uart_XMIT_dataH_ref),
        .xmit_doneH(xmit_doneH_ref),
        .xmit_active(xmit_active_ref),

        .uart_REC_dataH(uart_REC_dataH),
        .rec_dataH(rec_dataH_ref),
        .rec_readyH(rec_readyH_ref),
        .rec_busy(rec_busy_ref)
    );

    //Clock
    initial begin
        sys_clk = 0;
        forever #5 sys_clk = ~sys_clk;
    end

    //Main Test stimulus
    initial begin
        $display("\n===Testing Start===");

        sys_rst_l = 1;
        xmitH = 0;
        xmit_dataH = 0;
        uart_REC_dataH = 1;
        reset_dut;
        test_uart;

        $display("\n=== Test Summary");
        $display("Total Tests: %0d", test_count);
        $display("PASS: %0d", pass_count);
        $display("FAIL: %0d", fail_count);

        if (fail_count == 0)
            $display("\n*** ALL TESTS PASSED ***\n");
        else
            $display("\n*** SOME TESTS FAILED ***\n");
        #100;
        $finish;
    end

    task test_uart;
        integer i;
        begin
            $display("\n--- Group 1: Reset ---");
            reset_dut;

            $display("\n--- Group 2: TX single bytes ---");
            tx_task(8'hA5, "TX_0xA5");
            tx_task(8'hF7, "BIT3_0");

            $display("\n--- Group 3: TX idle (xmitH never asserted) ---");
            tx_without_xmith(8'hAA, "TX_NO_XMIT_AA");

            $display("\n--- Group 4: TX data lock (change data mid-frame) ---");
            tx_change_data_mid(8'hB3, 8'hFF, "TX_DATA_LOCK_B3");

            $display("\n--- Group 5: TX mid-frame xmitH assert ---");
            tx_mid_xmith_test(8'hA5, 8'h5A, "TX_MID_XMIT_A5");

            $display("\n--- Group 6: RX valid frames ---");
            rx_test(8'hFF, 1'b0, "RX_0xA5");
            rx_test(8'h00, 1'b0, "RX_0x00");

            $display("\n--- Group 7: RX false start rejection ---");
            false_start_test("RX_FALSE_START_1");

            $display("\n--- Group 8: RX bad stop bit ---");
            stop_bit_error_test(8'hA5, "RX_BAD_STOP_A5");

            uart_REC_dataH = 1;

            repeat(20)@(posedge dut.br.uart_clk);
            #1;
            compare_tx_only("PRE_B2B_IDLE");

            $display("\n--- Group 9: Back-to-back TX ---");
            tx_task(8'h11, "B2B_0x11");
            tx_task(8'h22, "B2B_0x22");
            tx_task(8'h33, "B2B_0x33");

            $display("\n--- Group 10: Mid-TX reset ---");
            xmit_dataH = 8'hCC;
            xmitH = 1;
            @(posedge dut.br.uart_clk);
            @(posedge dut.br.uart_clk);
            wait(xmit_active_dut == 1);
            #1; xmitH = 0;
            repeat(BIT_CLKS * 2) @(posedge sys_clk);
            reset_dut;
            compare_tx_only("MID_TX_RESET");

            $display("\n--- Group 11: START reset ---");
            reset_during_start();

            $display("\n--- Group 12: DATA reset ---");
            reset_during_data();

            $display("\n--- Group 13: RX DATA reset ---");
            rx_reset_during_data();
	    rx_reset_during_data_1();
        end
    endtask

    //Checks for Pass Fail and increment counts
    task check;
        input cond;
        input [200*8:1] msg;
        begin
            test_count = test_count + 1;
            if (cond) begin
                pass_count = pass_count + 1;
                $display("  [PASS] %0s", msg);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s", msg);
            end
        end
    endtask

    //Holds reset for 5 cycles then releases
    task reset_dut;
        begin
            sys_rst_l      = 0;
            xmitH          = 0;
            xmit_dataH     = 0;
            uart_REC_dataH = 1;
            repeat(5) @(posedge sys_clk);
            #1;
            compare_tx_only("RESET_HELD");
            sys_rst_l = 1;
            @(posedge sys_clk); #1;
            compare_tx_only("RESET_RELEASE");
        end
    endtask

    task compare_tx_only;
        input [100*8:1] label;
        begin
            $display("[CHK] %0s", label);
            check(uart_XMIT_dataH_dut === uart_XMIT_dataH_ref, {label, " TX_DATA"  });
            check(xmit_doneH_dut      === xmit_doneH_ref,      {label, " TX_DONE"  });
            check(xmit_active_dut     === xmit_active_ref,     {label, " TX_ACTIVE"});
            $display("DUT: TX_DATA=%b TX_DONE=%b TX_ACTIVE=%b",
                uart_XMIT_dataH_dut, xmit_doneH_dut, xmit_active_dut);
            $display("REF: TX_DATA=%b TX_DONE=%b TX_ACTIVE=%b",
                uart_XMIT_dataH_ref, xmit_doneH_ref, xmit_active_ref);
        end
    endtask

    task compare_rx_only;
        input [100*8:1] label;
        begin
            $display("[CHK] %0s", label);
            check(rec_dataH_dut  === rec_dataH_ref,  {label, " RX_DATA" });
            check(rec_readyH_dut === rec_readyH_ref, {label, " RX_READY"});
            check(rec_busy_dut   === rec_busy_ref,   {label, " RX_BUSY" });
            $display("DUT: RX_DATA=%h RX_READY=%b RX_BUSY=%b",
                rec_dataH_dut, rec_readyH_dut, rec_busy_dut);
            $display("REF: RX_DATA=%h RX_READY=%b RX_BUSY=%b",
                rec_dataH_ref, rec_readyH_ref, rec_busy_ref);
        end
    endtask

    task compare_outputs;
        input [100*8:1] label;
        begin
            $display("[CHK] %0s", label);
            check(uart_XMIT_dataH_dut === uart_XMIT_dataH_ref, {label, " TX_DATA"  });
            check(xmit_doneH_dut      === xmit_doneH_ref,      {label, " TX_DONE"  });
            check(xmit_active_dut     === xmit_active_ref,     {label, " TX_ACTIVE"});
            check(rec_dataH_dut       === rec_dataH_ref,       {label, " RX_DATA"  });
            check(rec_readyH_dut      === rec_readyH_ref,      {label, " RX_READY" });
            check(rec_busy_dut        === rec_busy_ref,        {label, " RX_BUSY"  });
            $display("DUT: TX_DATA=%b TX_DONE=%b TX_ACTIVE=%b | RX_DATA=%h RX_READY=%b RX_BUSY=%b",
                uart_XMIT_dataH_dut, xmit_doneH_dut, xmit_active_dut,
                rec_dataH_dut, rec_readyH_dut, rec_busy_dut);
            $display("REF: TX_DATA=%b TX_DONE=%b TX_ACTIVE=%b | RX_DATA=%h RX_READY=%b RX_BUSY=%b",
                uart_XMIT_dataH_ref, xmit_doneH_ref, xmit_active_ref,
                rec_dataH_ref, rec_readyH_ref, rec_busy_ref);
        end
    endtask

    task reset_during_start;
        begin
            @(posedge sys_clk);
            xmit_dataH = 8'hA5;
            xmitH = 1;
            @(posedge dut.br.uart_clk);
            @(posedge dut.br.uart_clk);
            @(posedge dut.br.uart_clk);
            #1;
            compare_tx_only("START_RESET_BEFORE");
            xmitH = 0;
	    repeat(10) @(posedge sys_clk);
            sys_rst_l = 0;
            repeat(5) @(posedge sys_clk); #1;
            compare_tx_only("START_RESET_DURING");
            sys_rst_l = 1;
            repeat(20) @(posedge sys_clk); #1;
            compare_tx_only("START_RESET_AFTER");
        end
    endtask

    task reset_during_data;
        begin
            @(posedge sys_clk);
            xmit_dataH = 8'h3C;
            xmitH = 1;
            @(posedge dut.br.uart_clk);
            @(posedge dut.br.uart_clk);

            wait(xmit_active_dut == 1);
            #1;
            xmitH = 0;

            repeat(10) @(posedge dut.br.uart_clk);
            #1;
            $display("[CHK] DATA_RESET_BEFORE");
            check(xmit_active_dut == 1'b1, "DATA_RESET_BEFORE DUT_ACTIVE");
            check(xmit_doneH_dut  == 1'b0, "DATA_RESET_BEFORE DUT_DONE");
            repeat(5) @(posedge sys_clk);
	    sys_rst_l = 0;
            repeat(5) @(posedge sys_clk);
            #1;
            compare_tx_only("DATA_RESET_DURING");
            sys_rst_l = 1;
            repeat(20) @(posedge sys_clk);
            #1;
            compare_tx_only("DATA_RESET_AFTER");
        end
    endtask

    task rx_reset_during_data;
        integer i;
        begin
            $display("\n--- RX RESET DURING DATA ---");
            uart_REC_dataH = 1;
            @(posedge sys_clk);
            uart_REC_dataH = 0;
            repeat(BIT_CLKS) @(posedge sys_clk);
            for(i=0; i<3; i=i+1) begin
                uart_REC_dataH = 1'b1;
                repeat(BIT_CLKS) @(posedge sys_clk);
            end
            wait(dut.rx.ct == 2'b10);
            repeat(20) @(posedge dut.br.uart_clk);
            #1;
            $display("[CHK] RX_DATA_RESET_BEFORE");
            check(rec_busy_dut   == 1'b1, "RX_DATA_RESET_BEFORE BUSY");
            check(rec_readyH_dut == 1'b0, "RX_DATA_RESET_BEFORE READY");
            //sys_rst_l = 0;
            repeat(5) @(posedge sys_clk);
            #1;
            compare_rx_only("RX_DATA_RESET_DURING");
            sys_rst_l = 1;
            repeat(20) @(posedge sys_clk);
            #1;
            compare_rx_only("RX_DATA_RESET_AFTER");
            uart_REC_dataH = 1;
        end
    endtask
    
    task rx_reset_during_data_1;
        integer i;
        begin
            $display("\n--- RX RESET DURING DATA ---");
            uart_REC_dataH = 1;
            @(posedge sys_clk);
            uart_REC_dataH = 0;
            repeat(BIT_CLKS) @(posedge sys_clk);
            for(i=0; i<3; i=i+1) begin
                uart_REC_dataH = 1'b1;
                repeat(BIT_CLKS) @(posedge sys_clk);
            end
            wait(dut.rx.ct == 2'b10);
            repeat(20) @(posedge dut.br.uart_clk);
            #1;
            $display("[CHK] RX_DATA_RESET_BEFORE");
            check(rec_busy_dut   == 1'b1, "RX_DATA_RESET_BEFORE BUSY");
            check(rec_readyH_dut == 1'b0, "RX_DATA_RESET_BEFORE READY");
	    repeat(5) @(posedge sys_clk);
            sys_rst_l = 0;
            repeat(5) @(posedge sys_clk);
            #1;
            compare_rx_only("RX_DATA_RESET_DURING");
            sys_rst_l = 1;
            repeat(20) @(posedge sys_clk);
            #1;
            compare_rx_only("RX_DATA_RESET_AFTER");
            uart_REC_dataH = 1;
        end
    endtask

    task tx_task;
        input [WORD_LEN-1:0] data;
        input [100*8:1] test_name;
        begin
            @(posedge sys_clk);
            xmit_dataH = data;
            xmitH = 1;

            @(posedge dut.br.uart_clk);
            @(posedge dut.br.uart_clk);

            wait(xmit_active_dut == 1);
            @(posedge dut.br.uart_clk);
            #1;
            compare_tx_only({test_name, " STARTED"});

            xmitH = 0;

            wait(xmit_doneH_dut === 1'b1);
            #1;
            compare_tx_only({test_name, " DONE"});

            @(posedge sys_clk);
            #1;
            compare_tx_only({test_name, " POST_DONE"});
        end
    endtask

    task tx_without_xmith;
        input [WORD_LEN-1:0] data;
        input [100*8:1] test_name;
        integer i;
        begin
            @(posedge sys_clk);
            xmit_dataH = data;
            xmitH = 0;
            repeat(10) @(posedge dut.br.uart_clk);
            #1;
            compare_tx_only({test_name, " IDLE_END"});
        end
    endtask

    task tx_mid_xmith_test;
        input [WORD_LEN-1:0] first_data;
        input [WORD_LEN-1:0] second_data;
        input [100*8:1] test_name;
        begin
            @(posedge sys_clk);

            xmit_dataH = first_data;
            xmitH = 1;

            @(posedge dut.br.uart_clk);
            @(posedge dut.br.uart_clk);

            wait(xmit_active_dut == 1);
            #1;
            xmitH = 0;

            repeat(10) @(posedge dut.br.uart_clk);

            xmit_dataH = second_data;
            xmitH = 1;

            @(posedge dut.br.uart_clk);
            @(posedge dut.br.uart_clk);
            #1;

            compare_tx_only({test_name, " MID_FRAME"});
            xmitH = 0;

            wait(xmit_doneH_dut === 1'b1);
            #1;
            compare_tx_only({test_name, " FIRST_DONE"});

            @(posedge sys_clk);
            #1;

            if (xmit_active_dut) begin
                wait(xmit_doneH_dut === 1'b1);
                #1;
                compare_tx_only({test_name, " SECOND_DONE"});
            end
        end
    endtask

    task tx_change_data_mid;
        input [WORD_LEN-1:0] first_data;
        input [WORD_LEN-1:0] second_data;
        input [100*8:1] test_name;
        begin
            @(posedge sys_clk);

            xmit_dataH = first_data;
            xmitH = 1;

            @(posedge dut.br.uart_clk);
            @(posedge dut.br.uart_clk);

            wait(xmit_active_dut == 1);
            #1;
            xmitH = 0;

            repeat(10) @(posedge dut.br.uart_clk);

            xmit_dataH = second_data;
            #1;
            compare_tx_only({test_name, " MID_FRAME"});

            wait(xmit_doneH_dut === 1'b1);
            #1;
            compare_tx_only({test_name, " DONE"});
        end
    endtask

    task rx_test;
        input [WORD_LEN-1:0] data;
        input bad_stop;
        input [100*8:1] test_name;
        integer i;
        begin
            uart_REC_dataH = 1;
            @(posedge sys_clk);
            uart_REC_dataH = 0;
            repeat(BIT_CLKS + (BIT_CLKS/4)) @(posedge sys_clk);
            #1;
            $display("[CHK] %0s START", test_name);
            check(rec_readyH_dut === rec_readyH_ref, {test_name, " START RX_READY"});
            check(rec_busy_dut   === rec_busy_ref,   {test_name, " START RX_BUSY"});
            for (i = 0; i < WORD_LEN; i = i+1) begin
                uart_REC_dataH = data[i];
                repeat(BIT_CLKS) @(posedge sys_clk);
            end
            repeat(BIT_CLKS/2) @(posedge sys_clk);
            #1;
            compare_rx_only({test_name, " AFTER_DATA"});
            uart_REC_dataH = bad_stop ? 1'b0 : 1'b1;
            repeat(BIT_CLKS + (BIT_CLKS/2)) @(posedge sys_clk);
            #1;
            if (bad_stop) begin
                $display("[CHK] %0s STOP", test_name);
                check(rec_readyH_dut === rec_readyH_ref, {test_name, " STOP RX_READY"});
                check(rec_busy_dut   === rec_busy_ref,   {test_name, " STOP RX_BUSY"});
            end else begin
                compare_rx_only({test_name, " STOP"});
            end
            uart_REC_dataH = 1;
            repeat(BIT_CLKS/2) @(posedge sys_clk);
            #1;
            compare_rx_only({test_name, " IDLE"});
        end
    endtask

    task false_start_test;
        input [100*8:1] test_name;
        begin
            uart_REC_dataH = 1;
            @(posedge sys_clk);
            uart_REC_dataH = 0;
            repeat(BIT_CLKS / 2) @(posedge sys_clk);
            uart_REC_dataH = 1;
            repeat(BIT_CLKS) @(posedge sys_clk);
            #1;
            compare_rx_only({test_name, " AFTER_FALSE_START"});
        end
    endtask

    task stop_bit_error_test;
        input [WORD_LEN-1:0] data;
        input [100*8:1] test_name;
        begin
            rx_test(data, 1'b1, test_name);
        end
    endtask

    task display_mismatch;
        begin
            $display("DUT: TX_DATA=0x%h TX_DONE=%b TX_ACTIVE=%b RX_DATA=%h RX_READY=%b RX_BUSY=%b",
                uart_XMIT_dataH_dut, xmit_doneH_dut, xmit_active_dut,
                rec_dataH_dut, rec_readyH_dut, rec_busy_dut);
            $display("REF: TX_DATA=0x%h TX_DONE=%b TX_ACTIVE=%b RX_DATA=%h RX_READY=%b RX_BUSY=%b",
                uart_XMIT_dataH_ref, xmit_doneH_ref, xmit_active_ref,
                rec_dataH_ref, rec_readyH_ref, rec_busy_ref);
        end
    endtask

    initial begin
        #(FRAME_CLKS * 200 * 10);
        $display("[WATCHDOG] Simulation timed out!");
        $finish;
    end

    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, uart_tb);
    end

endmodule
