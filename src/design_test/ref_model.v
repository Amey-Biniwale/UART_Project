module ref_model #(parameter WIDTH = 8)();
	task ref_tx;
		input [WIDTH-1:0] input_data;
		output [WIDTH+1:0] exp_stream;

		begin
			exp_stream[0] = 0;
			exp_stream[WIDTH:1] = input_data;
			exp_stream[WIDTH+1] = 1;
		end
	endtask

	task ref_rx;
		input [WIDTH+1:0] input_data;
		output [WIDTH-1:0] exp_stream;
		begin
			exp_stream = input_data[WIDTH:1];
		end
	endtask
endmodule
