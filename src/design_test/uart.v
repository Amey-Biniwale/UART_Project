`include "u_baud.v"
`include "u_xmit.v"
`include "u_rec.v"

module uart #(parameter XTAL_CLK = 50000000, WORD_LEN = 8, BAUD = 9600)(
        input sys_clk, sys_rst_1,
        input xmitH,
        input [WORD_LEN-1:0] xmit_dataH,
        input uart_REC_dataH,
        output uart_XMIT_dataH, xmit_doneH, xmit_active,
        output [WORD_LEN-1:0] rec_dataH,
        output rec_readyH, rec_busy
);
        wire uart_clk;

        u_baud #(XTAL_CLK, BAUD)baud(
                .sys_clk(sys_clk),.sys_rst_1(sys_rst_1),
                .uart_clk(uart_clk)
        );
       

        u_xmit #(WORD_LEN)xmit(
                .uart_clk(uart_clk),.sys_rst_1(sys_rst_1),.xmitH(xmitH),.xmit_dataH(xmit_dataH),
                .uart_XMIT_dataH(uart_XMIT_dataH),.xmit_doneH(xmit_doneH),.xmit_active(xmit_active)
        );

        u_rec #(WORD_LEN)rec(
                .uart_clk(uart_clk),.sys_rst_1(sys_rst_1),.uart_REC_dataH(uart_REC_dataH),
                .rec_dataH(rec_dataH),.rec_readyH(rec_readyH),.rec_busy(rec_busy)
        );

endmodule
