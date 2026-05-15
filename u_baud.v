module u_baud#(parameter XTAL_CLK = 50000000, BAUD = 9600)(
        input sys_clk, sys_rst_1,
        output reg uart_clk
);
        localparam CW = $clog2(XTAL_CLK/ (BAUD * 16 * 2));
        reg [CW:0]count;

        always @(posedge sys_clk or negedge sys_rst_1) begin
                if(!sys_rst_1) begin
                        uart_clk <= 0;
                        count <= 0;
                end
                else begin
                        if(count == ( XTAL_CLK / (BAUD * 16 * 2) ) ) begin
                                uart_clk <= ~uart_clk;
                                count <= 0;
                        end
                        else begin
                                count <= count + 1;
                        end
                end
        end

endmodule
