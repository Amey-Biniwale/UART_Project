module u_rec #(parameter WORD_LEN = 8)(
        input uart_clk, sys_rst_1, uart_REC_dataH,
        output reg [WORD_LEN-1:0] rec_dataH,
        output reg rec_readyH, rec_busy
);

        reg [3:0] count;
        reg [WORD_LEN-1:0] temp;
        reg [2:0] count_word;
        reg flag;
        reg sync_data,data;
        reg prev_data;
        reg [1:0] PS, NS;
        localparam IDLE = 0, START = 1, DATA = 2, STOP = 3;

        always @(posedge uart_clk or negedge sys_rst_1) begin
                if(!sys_rst_1) begin
                        sync_data <= 0;
                        data <= 0;
                end
                else begin
                        sync_data <= uart_REC_dataH;
                        data <= sync_data;
                end
        end


        always @(posedge uart_clk or negedge sys_rst_1) begin
                if(!sys_rst_1) begin
                        count <= 0;
                end
                else if(PS == IDLE) begin 
                        count <= 0;
                end
                else if(PS != NS) begin
                        count <= 0;
                end
                else begin
                        count <= count + 1;
                end
        end

        always @(posedge uart_clk or negedge sys_rst_1) begin
                if(!sys_rst_1) begin
                        prev_data <= 0;
                end
                else begin
                        prev_data <= data;
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

        always @(posedge uart_clk or  negedge sys_rst_1) begin
                if(!sys_rst_1) begin
                        flag = 0;
                end
                else begin
                        if(PS == IDLE || PS == DATA) flag <= 0;
                        else begin
                                if(PS == START && count == 7 && data == 0) flag = 1;
                                if(PS == STOP && count == 7 && data == 1) flag = 1;
                        end
                end
        end
        
        always @(*) begin
                case(PS)
                        IDLE: begin
                                if(prev_data && !data) NS = START;
                                else NS = IDLE;                       
                        end
                        START: begin
                                if(count == 15) begin
                                        if(flag) NS = DATA;
                                        else NS = IDLE;
                                end 
                                else NS = START;
                        end
                        DATA: begin
                                if(count == 15) begin
                                        if(count_word < WORD_LEN-1) NS = DATA;
                                        else NS = STOP;
                                end
                                else NS = DATA;
                        end
                        STOP: begin
                                if(count == 13) begin
                                        NS = IDLE;
                                end
                                else NS = STOP;
                        end
                endcase
        end
        
        always @(posedge uart_clk or negedge sys_rst_1) begin
                if(!sys_rst_1) begin
                        rec_dataH = 0;
                        rec_readyH = 1;
                        rec_busy = 0;
                        count_word = 0;
                end
                else begin
                        case(PS)
                                IDLE: begin
                                        rec_dataH = rec_dataH;
                                        rec_readyH = ~(prev_data && !data);
                                        rec_busy = (prev_data && !data);
                                        count_word = 0;
                                end
                                START: begin
                                        rec_dataH = 0;
                                        rec_readyH = 0;
                                        rec_busy = 1;
                                        count_word = 0;
                                end
                                DATA: begin
                                        rec_readyH = 0;
                                        rec_busy = 1;
                                        if(count == 5) begin
                                                temp = {data,temp[WORD_LEN-1:1]};
                                        end
                                        if(count == 15) count_word = count_word + 1;
                                end
                                STOP: begin
                                        if(count == 13) begin
                                                if(flag) begin
                                                        rec_dataH = temp;
                                                        rec_readyH = 1;
                                                        rec_busy = 0;
                                                end
                                                else begin
                                                        rec_dataH = 0;
                                                        rec_readyH = 0;
                                                        rec_busy = 1;
                                                end
                                        end
                                        count_word = 0;
                                end
                                default: begin
                                        rec_dataH = 0;
                                        rec_readyH = 1;
                                        rec_busy = 0;
                                        count_word = 0;
                                end
                        endcase
                end
        end

endmodule
