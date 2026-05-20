`include "ref_model.v"
`include "uart.v"

module tb_uart;
    parameter WIDTH = 8;
    parameter BAUD_RATE = 2400;
    parameter XTAL_CLK = 50000000;

    // Timing calculations
    localparam CLK_PER = (1000000000 / XTAL_CLK);
    localparam BIT_PERIOD = (1000000000 / BAUD_RATE);
    
    // DUT Pins
    reg sys_clk, sys_rst_l;
    
    // TX Pins
    reg xmitH;
    reg [WIDTH-1:0] xmit_dataH;
    wire xmit_doneH, xmit_active, uart_XMIT_dataH;

    // RX Pins
    reg uart_REC_dataH;
    wire [WIDTH-1:0] rec_dataH;
    wire rec_readyH, rec_busy;

    // Testbench Variables    
    integer test_count, pass_count, fail_count;
    integer pc, w;
    
    // Expected/Actual Data
    reg [WIDTH+1:0] exp_tx_frame, act_tx_frame;
    reg [WIDTH-1:0] act_rx_data;

    // Test Opcodes
    localparam CMD_RST            = 0;
    localparam CMD_TX_SEND        = 1;
    localparam CMD_RX_SEND        = 2;
    localparam CMD_FULL_DUP       = 3;
    localparam CMD_WAIT           = 4;
    localparam CMD_RX_GLITCH      = 5;
    localparam CMD_END            = 6;
    localparam CMD_TX_ABORT_START = 7;
    localparam CMD_TX_ABORT_SAMP  = 8;
    localparam CMD_TX_SPAM_TRIG   = 9;
    localparam CMD_RX_FRAME_ERR   = 10;
    localparam CMD_RX_DEFAULT     = 11;
    
    // Command ROM
    reg [2:0] plan_cmds [0:49];
    reg [WIDTH-1:0] plan_data [0:49];
    reg [2:0] curr_cmd;
    reg [WIDTH-1:0] curr_data;

    // Module Instantiations
    uart #(.WORD_LEN(WIDTH), .XTAL_CLK(XTAL_CLK), .BAUD(BAUD_RATE)) duv(
        .sys_clk(sys_clk), .sys_rst_1(sys_rst_l),
        .xmitH(xmitH), .xmit_dataH(xmit_dataH), .uart_XMIT_dataH(uart_XMIT_dataH),
        .xmit_doneH(xmit_doneH), .xmit_active(xmit_active),
        .uart_REC_dataH(uart_REC_dataH), .rec_dataH(rec_dataH),
        .rec_readyH(rec_readyH), .rec_busy(rec_busy)
    );

    ref_model #(.WIDTH(WIDTH)) reff();

    // Clock Generation
    initial begin
        sys_clk = 0;
        forever #(CLK_PER / 2.0) sys_clk = ~sys_clk;
    end

    // Global Watchdog
    initial begin
        for (w = 0; w < 15000; w = w + 1) begin
            #(BIT_PERIOD);
        end
        $display("\n-----------------------------------------------");
        $display(" [FATAL] Global Timeout Reached. Simulation Hung.");
        $display("-------------------------------------------------\n");
        $finish;
    end

    // TASKS

    task tx_driver(input [WIDTH-1:0] tx_in);
        begin
            wait(xmit_active == 0);
            @(negedge sys_clk);
            xmit_dataH <= tx_in;
            xmitH <= 1;
            wait(xmit_active == 1); 
            @(negedge sys_clk);
            xmitH <= 0;
            wait (xmit_doneH == 1);
        end
    endtask

    task rx_driver(input [WIDTH-1:0] rx_in);
        integer j;
        begin
            @(negedge sys_clk);
            uart_REC_dataH = 0;
            #(BIT_PERIOD);        
            for (j = 0; j < WIDTH; j = j + 1) begin
                uart_REC_dataH = rx_in[j];
                #(BIT_PERIOD);
            end
            uart_REC_dataH = 1;
            #(BIT_PERIOD); 
        end
    endtask

    task rx_glitch();
        begin
            @(negedge sys_clk);
            uart_REC_dataH = 0;
            #(BIT_PERIOD / 2.0);
            uart_REC_dataH = 1;
        end
    endtask
    
    task tx_monitor(output [WIDTH+1:0] tx_out);
        integer i;
        begin
            @(negedge uart_XMIT_dataH);
            #(BIT_PERIOD / 2.0);
            for (i = 0; i < WIDTH + 2; i = i + 1) begin
                tx_out[i] = uart_XMIT_dataH;
                #(BIT_PERIOD);
            end
        end
    endtask
            
    task rx_monitor(output [WIDTH-1:0] rx_out);
        begin
            @(posedge rec_readyH);
            rx_out = rec_dataH;
        end
    endtask

    task tx_scoreboard(input [WIDTH+1:0] expected, input [WIDTH+1:0] actual);
        begin
            test_count = test_count + 1;
            if (actual === expected) begin
                $display("    [SCOREBOARD] TX PASS! Match: %b", actual);
                pass_count = pass_count + 1;
            end else begin
                $display("    [SCOREBOARD] TX FAIL! Exp: %b, Got: %b", expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    task rx_scoreboard(input [WIDTH-1:0] expected, input [WIDTH-1:0] actual);
        begin
            test_count = test_count + 1;
            if (expected === actual) begin
                $display("    [SCOREBOARD] RX PASS! Got 8'h%h", actual);
                pass_count = pass_count + 1;
            end else begin
                $display("    [SCOREBOARD] RX FAIL! Expected %h, Got %h", expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Coverage Tasks
    task tx_abort_in_start(input [WIDTH-1:0] tx_in);
        begin
            wait(xmit_active == 0);
            @(negedge sys_clk);
            xmit_dataH <= tx_in;
            xmitH <= 1;
            wait(xmit_active == 1);
            @(negedge sys_clk);
            xmitH <= 0;
            wait(uart_XMIT_dataH == 0);
            
            #(BIT_PERIOD / 4.0); 
            $display("    [INJECT] Asserting reset during START bit");
            sys_rst_l = 0;
            #(BIT_PERIOD / 2.0); 
            sys_rst_l = 1;
            #(BIT_PERIOD);
        end
    endtask
    
    task tx_abort_in_sample(input [WIDTH-1:0] tx_in);
        begin
            wait(xmit_active == 0);
            @(negedge sys_clk);
            xmit_dataH <= tx_in;
            xmitH <= 1;
            wait(xmit_active == 1);
            @(negedge sys_clk);
            xmitH <= 0;
            wait(uart_XMIT_dataH == 0);
            
            #(BIT_PERIOD * 3.5);
            $display("    [INJECT] Asserting reset during DATA state");
            sys_rst_l = 0;
            #(BIT_PERIOD); 
            sys_rst_l = 1;
            #(BIT_PERIOD * 2);
        end
    endtask
    
    task tx_spam_trigger(input [WIDTH-1:0] tx_in);
        begin
            wait(xmit_active == 0);
            @(negedge sys_clk);
            xmit_dataH <= tx_in;
            xmitH <= 1;
            wait(xmit_active == 1);
            @(negedge sys_clk);
            xmitH <= 0; 
            
            wait(uart_XMIT_dataH == 0);
            #(BIT_PERIOD * 2.5);
            
            $display("    [INJECT] Asserting redundant trigger mid-transmission");
            @(negedge sys_clk);
            xmitH <= 1; 
            #(BIT_PERIOD); 
            @(negedge sys_clk);
            xmitH <= 0;
            
            wait(xmit_doneH == 1);
        end
    endtask

    task rx_framing_error(input [WIDTH-1:0] rx_in);
        integer j;
        begin
            @(negedge sys_clk);
            uart_REC_dataH = 0; 
            #(BIT_PERIOD);
            
            for (j = 0; j < WIDTH; j = j + 1) begin
                uart_REC_dataH = rx_in[j];
                #(BIT_PERIOD);
            end
            
            // Inject Framing Error: Send 0 for the Stop Bit
            uart_REC_dataH = 0; 
            #(BIT_PERIOD);
            uart_REC_dataH = 1; 
        end
    endtask

    task rx_force_default();
        begin
            $display("    [INJECT] Forcing FSM to undefined state (2'bXX)");
            @(negedge sys_clk);
            force duv.rec.PS = 2'bxx;
            #(CLK_PER * 5);
            release duv.rec.PS;
            #(CLK_PER * 5);
        end
    endtask
    
    // MASTER LOOP

    initial begin
	$dumpfile("uart_waves.vcd"); 
	$dumpvars(0, tb_uart);	
        sys_rst_l = 0;
        xmitH = 0;
        xmit_dataH = 0;
        uart_REC_dataH = 1;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Base Tests
        plan_cmds[0]  = CMD_RST;            plan_data[0]  = 8'h00; 
        plan_cmds[1]  = CMD_WAIT;           plan_data[1]  = 8'h0A;
        plan_cmds[2]  = CMD_TX_SEND;        plan_data[2]  = 8'hA5; 
        plan_cmds[3]  = CMD_WAIT;           plan_data[3]  = 8'h05;
        plan_cmds[4]  = CMD_RX_SEND;        plan_data[4]  = 8'hA5;
        plan_cmds[5]  = CMD_TX_SEND;        plan_data[5]  = 8'h00; 
        plan_cmds[6]  = CMD_TX_SEND;        plan_data[6]  = 8'hFF; 
        plan_cmds[7]  = CMD_RX_SEND;        plan_data[7]  = 8'h55;
        plan_cmds[8]  = CMD_RX_SEND;        plan_data[8]  = 8'hAA; 
        plan_cmds[9]  = CMD_RX_GLITCH;      plan_data[9]  = 8'h00; 
        plan_cmds[10] = CMD_WAIT;           plan_data[10] = 8'h05;
        plan_cmds[11] = CMD_RX_SEND;        plan_data[11] = 8'h3C; 
        plan_cmds[12] = CMD_FULL_DUP;       plan_data[12] = 8'h87; 
        plan_cmds[13] = CMD_FULL_DUP;       plan_data[13] = 8'h4B;
        plan_cmds[14] = CMD_FULL_DUP;       plan_data[14] = 8'hE2; 
        plan_cmds[15] = CMD_TX_SEND;        plan_data[15] = 8'h11;
        plan_cmds[16] = CMD_TX_SEND;        plan_data[16] = 8'h22;
        plan_cmds[17] = CMD_TX_SEND;        plan_data[17] = 8'h33;
        
        // TX Coverage Tests
        plan_cmds[18] = CMD_TX_ABORT_START; plan_data[18] = 8'hFF;
        plan_cmds[19] = CMD_TX_ABORT_SAMP;  plan_data[19] = 8'hA5; 
        plan_cmds[20] = CMD_TX_SPAM_TRIG;   plan_data[20] = 8'hCC;
        
        // RX Coverage Tests
        plan_cmds[21] = CMD_RX_FRAME_ERR;   plan_data[21] = 8'hA5;
        plan_cmds[22] = CMD_RX_DEFAULT;     plan_data[22] = 8'h00; 

        // End Sequence
        plan_cmds[23] = CMD_WAIT;           plan_data[23] = 8'h10;
        plan_cmds[24] = CMD_END;            plan_data[24] = 8'h00;

        $display("\n----- STARTING UART VERIFICATION -----");
        for (pc = 0; pc <= 24; pc = pc + 1) begin
            curr_cmd = plan_cmds[pc];
            curr_data = plan_data[pc];
            
            case(curr_cmd)
                CMD_RST: begin
                    $display("\n[STEP %0d] System Reset", pc);
                    sys_rst_l = 0;
                    #(CLK_PER * 20);
                    sys_rst_l = 1;
                end
                
                CMD_TX_SEND: begin
                    $display("\n[STEP %0d] TX Send: 8'h%h", pc, curr_data);
                    reff.ref_tx(curr_data, exp_tx_frame);
                    fork
                        tx_driver(curr_data);
                        tx_monitor(act_tx_frame);
                    join
                    tx_scoreboard(exp_tx_frame, act_tx_frame);
                end
                
                CMD_RX_SEND: begin
                    $display("\n[STEP %0d] RX Receive: 8'h%h", pc, curr_data);
                    fork
                        rx_driver(curr_data);
                        rx_monitor(act_rx_data);
                    join
                    rx_scoreboard(curr_data, act_rx_data);
                end
                
                CMD_FULL_DUP: begin
                    $display("\n[STEP %0d] Full Duplex Test. Payload: 8'h%h", pc, curr_data);
                    reff.ref_tx(curr_data, exp_tx_frame);
                    fork
                        tx_driver(curr_data);
                        tx_monitor(act_tx_frame);
                        rx_driver(curr_data);
                        rx_monitor(act_rx_data);
                    join
                    tx_scoreboard(exp_tx_frame, act_tx_frame);
                    rx_scoreboard(curr_data, act_rx_data);
                end

                CMD_RX_GLITCH: begin
                    $display("\n[STEP %0d] Injecting Receiver Glitch...", pc);
                    rx_glitch();
                end

                CMD_TX_ABORT_START: begin
                    $display("\n[STEP %0d] TX Abort during START state", pc);
                    tx_abort_in_start(curr_data);
                end
                
                CMD_TX_ABORT_SAMP: begin
                    $display("\n[STEP %0d] TX Abort during SAMPLE state", pc);
                    tx_abort_in_sample(curr_data);
                end

                CMD_TX_SPAM_TRIG: begin
                    $display("\n[STEP %0d] TX Trigger Redundancy Test (Coverage)", pc);
                    reff.ref_tx(curr_data, exp_tx_frame);
                    fork
                        tx_spam_trigger(curr_data);
                        tx_monitor(act_tx_frame);
                    join
                    tx_scoreboard(exp_tx_frame, act_tx_frame);
                end

                CMD_RX_FRAME_ERR: begin
                    $display("\n[STEP %0d] RX Framing Error Test", pc);
                    rx_framing_error(curr_data);
                end

                CMD_RX_DEFAULT: begin
                    $display("\n[STEP %0d] RX Default State Test (Coverage)", pc);
                    rx_force_default();
                end

                CMD_WAIT: begin
                    $display("\n[STEP %0d] Waiting for %0d bit periods...", pc, curr_data);
                    #(BIT_PERIOD * curr_data);
                end
                
                CMD_END: begin
                    $display("\n--------------------------------------------------");
                    $display("               VERIFICATION SUMMARY               ");
                    $display("--------------------------------------------------");
                    $display(" Total Assertions Checked : %0d", test_count);
                    $display(" Tests Passed             : %0d", pass_count);
                    $display(" Tests Failed             : %0d", fail_count);
                    $display("--------------------------------------------------\n");
                    $finish;
                end
            endcase
        end
    end
endmodule
