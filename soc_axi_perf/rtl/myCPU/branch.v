module branch (
    input wire [31:0]			dec_pcplus4,
	input wire [2:0]			branch, // branch and jump
	input wire         		    inst_jr,
    input wire                  inst_eret,
    input wire                  exception_happen,	
    input wire [31:0]           sign_imm32,
	input wire [25:0]			imm26,
	input wire [31:0]			regfile_rs_read_val,
	input wire [31:0]			regfile_rt_read_val,
	output reg [1:0]  			PCSrc,
	output wire [31:0]			branch_target
);

	wire 						sign;
	wire						not_zero;
	wire						beq;
	wire						bgez;
	wire						bgtz;
	reg						    branch_happen;
	wire [31:0]					branch_address;
	wire [31:0]					jump_address;

	assign sign = regfile_rs_read_val[31];
	assign not_zero = |regfile_rs_read_val;

	assign beq = (regfile_rs_read_val == regfile_rt_read_val);
	assign bgez = ~sign;
	assign bgtz = ~sign && not_zero;
	
	always @(*)
	case (branch)
		//3'b000:	branch_happen = 0;
		3'b001: branch_happen = beq;
		3'b010: branch_happen = !beq;
		3'b011: branch_happen = bgez;
		3'b100: branch_happen = bgtz;
		3'b101: branch_happen = !bgtz;
		3'b110: branch_happen = !bgez;
		3'b111: branch_happen = 1;
		default:branch_happen = 0;
	endcase
//assign PCSrc = exception_happen ? 3 :  (inst_eret ? 2 : (branch_happen ? 1 : 0));
	always @(*)
	casex ({branch_happen, inst_eret, exception_happen})
		3'bxx1: PCSrc = 3;
		3'b010: PCSrc = 2;
		3'b100: PCSrc = 1;
		3'b000: PCSrc = 0;
		default:PCSrc = 0;
	endcase


	//assign branch_address = dec_pcplus4 + (sign_imm32 << 2);
	assign branch_address = dec_pcplus4 + {sign_imm32[29:0] ,2'b0};
	assign jump_address = inst_jr? regfile_rs_read_val: ({dec_pcplus4[31:28], imm26, 2'b00});
	assign branch_target = (branch == 3'b111) ? jump_address : branch_address;

endmodule