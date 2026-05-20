module u_xmit #(parameter WORD_LEN = 8)(
        input uart_clk, sys_rst_1, xmitH,
        input [WORD_LEN-1:0] xmit_dataH,
        output reg uart_XMIT_dataH, xmit_doneH, xmit_active
);

        localparam IDLE = 0, START = 1, DATA = 2, STOP = 3;
        reg [1:0] PS, NS;
        reg tx_en;
        reg [3:0] count_tx;
        reg [2:0] count_word;
        reg [WORD_LEN-1:0] data;

        always @(posedge uart_clk or negedge sys_rst_1) begin
                if(!sys_rst_1) begin
                        count_tx <= 0;
                        tx_en <= 0;
                end
                else if(PS == IDLE) begin
                        tx_en <= 0;
                        count_tx <= 0;
                end
                else if((PS == START || PS == STOP) && count_tx == 14) begin
                        tx_en <= 1;
                        count_tx <= 0;
                end
                /*else if(PS != NS) begin
                        tx_en <= 0;
                        count_tx <= 0;
                end*/
                else if(count_tx == 15) begin
                        tx_en <= 1;
                        count_tx <= 0;
                end
                else begin
                        count_tx <= count_tx + 1;
                        tx_en <= 0;
                end
        end

        always @(posedge uart_clk or negedge sys_rst_1) begin
                if(!sys_rst_1) begin
                        PS <= IDLE;
                end
                else begin
                        PS <= NS;
                end
        end


          always @(*) begin
                case(PS)
                        IDLE: NS = xmitH ? START : IDLE;
                        START: NS = (tx_en) ? DATA : START;
                        DATA: NS = (tx_en) ? (count_word < WORD_LEN-1) ? DATA : STOP : DATA;
                        STOP: NS = (tx_en) ? IDLE : STOP;
                        default: NS = IDLE;
                endcase
          end
          
          always @(posedge uart_clk or negedge sys_rst_1) begin
                if(!sys_rst_1) begin
                        uart_XMIT_dataH <= 1;
                        xmit_doneH <= 1;
                        xmit_active <= 0;
                        count_word <= 0;
                end
                else begin
                        case(PS)
                                IDLE: begin
                                        uart_XMIT_dataH <= 1;
                                        xmit_doneH <= 1;
                                        xmit_active <= 0;
                                        count_word <= 0;
                                        data <= xmitH ? xmit_dataH : 0;
                                end
                                START: begin
                                        uart_XMIT_dataH <= 0;
                                        xmit_doneH <= 0;
                                        xmit_active <= 1;
                                        count_word <= 0;
                                        data <= data;
                                end
                                DATA: begin
                                        xmit_doneH <= 0;
                                        xmit_active <= 1;
                                        uart_XMIT_dataH <= data[0];
                                        //data <= data >> 1;
                                        //count_word = count_word + 1;
                                        if(tx_en) begin
                                                //uart_XMIT_dataH <= data[0];
                                                data <= data >> 1;
                                                count_word <= count_word + 1;
                                        end
                                end
                                STOP: begin
                                        if(tx_en) xmit_doneH <= 1;
                                        xmit_active <= 1;
                                        uart_XMIT_dataH <= 1;
                                        count_word <= 0;
                                        data <= data;
                                end
                        endcase
                end
          end
endmodule



