`include "define.vh"


/**
 * Data Path for MIPS 5-stage pipelined CPU.
 * Author: Zhao, Hongyu  <power_zhy@foxmail.com>
 */
module datapath (
	input wire clk,  // main clock
	// debug
	`ifdef DEBUG
	input wire [5:0] debug_addr,  // debug address
	output wire [31:0] debug_data,  // debug data
	`endif
	// control signals
	output wire [31:0] inst_data_ctrl,  // instruction
	input wire [2:0] pc_src_ctrl,  // how would PC change to next
	input wire imm_ext_ctrl,  // whether using sign extended to immediate data
	input wire [1:0] exe_a_src_ctrl,  // data source of operand A for ALU
	input wire [1:0] exe_b_src_ctrl,  // data source of operand B for ALU
	input wire [3:0] exe_alu_oper_ctrl,  // ALU operation type
	input wire mem_ren_ctrl,  // memory read enable signal
	input wire mem_wen_ctrl,  // memory write enable signal
	input wire [1:0] wb_addr_src_ctrl,  // address source to write data back to registers
	input wire wb_data_src_ctrl,  // data source of data being written back to registers
	input wire wb_wen_ctrl,  // register write enable signal
	// memory signals
	output reg inst_ren,  // instruction read enable signal
	output reg [31:0] inst_addr,  // address of instruction needed
	input wire [31:0] inst_data,  // instruction fetched
	output wire mem_ren,  // memory read enable signal
	output wire mem_wen,  // memory write enable signal
	output wire [31:0] mem_addr,  // address of memory
	output wire [31:0] mem_dout,  // data writing to memory
	input wire [31:0] mem_din,  // data read from memory
	// debug control
	input wire cpu_rst,  // cpu reset signal
	input wire cpu_en  // cpu enable signal

	// 这里的信号都是新加的 需要在controller里面进行改动
	//input wire is_branch;
	//output reg[4:0] ID_EX_regw_addr;
	);
	
	`include "mips_define.vh"
	
	// data signals
	wire [31:0] inst_addr_next;
	wire is_branch;
	
	

	//IF->ID
	reg [31:0] IF_ID_IR;
	reg [31:0] IF_ID_IR_addr,IF_ID_IR_addr_next;
	reg [31:0] IF_ID_trg_addr;
	reg [4:0] regw_addr;
	wire [4:0] addr_rs, addr_rt, addr_rd;
	wire [31:0] data_rs, data_rt, data_imm;
	wire rs_rt_equal;
	
	
	//ID->EX
	reg[31:0] ID_EX_IR,ID_EX_IR_addr,ID_EX_IR_addr_next;
	reg[31:0] ID_EX_opb;
	reg[2:0] ID_EX_pc_src;
	reg[1:0] ID_EX_a_src,ID_EX_b_src;
	reg[3:0] ID_EX_aluop;
	reg ID_EX_mem_ren,ID_EX_mem_wen,wb_wen;
	reg ID_EX_wb_data_src;
	reg[4:0] ID_EX_addr_rs,ID_EX_addr_rt;
	reg[4:0] ID_EX_regw_addr;
	reg[31:0] ID_EX_data_rs,ID_EX_data_rt,ID_EX_data_imm;
	reg [31:0] opa, opb;
	wire [31:0] alu_out;
	reg ID_EX_rs_rt_equal;	


	//EX->MEM
	reg[31:0] EX_MEM_IR,EX_MEM_IR_addr,EX_MEM_IR_addr_next;
	reg[31:0] EX_MEM_data_rs,EX_MEM_data_rt,EX_MEM_aluout;
	reg[2:0] EX_MEM_pc_src;
	reg EX_MEM_mem_ren,EX_MEM_mem_wen;
	reg EX_MEM_wb_data_src;
	reg [31:0] regw_data;
	reg EX_MEM_wb_wen;

	//MEM->WB
	//reg[31:0] MEM_WB_IR,MEM_WB_IR_addr;
	reg[31:0] MEM_WB_aluout;
	reg MEM_WB_mem_ren,MEM_WB_mem_wen;
	reg MEM_WB_wb_data_src;
	reg MEM_WB_wb_wen;
	reg[31:0] MEM_WB_mem_din;
	reg[31:0] MEM_WB_regw_addr,MEM_WB_regw_data;

	// debug
	`ifdef DEBUG
	wire [31:0] debug_data_reg;
	reg [31:0] debug_data_signal;
	
	always @(posedge clk) begin
		case (debug_addr[4:0])
			0: debug_data_signal <= inst_addr;
			1: debug_data_signal <= inst_data;
			2: debug_data_signal <= IF_ID_IR_addr;
			3: debug_data_signal <= IF_ID_IR;
			4: debug_data_signal <= ID_EX_IR_addr;
			5: debug_data_signal <= ID_EX_IR;
			6: debug_data_signal <= EX_MEM_IR_addr;
			7: debug_data_signal <= EX_MEM_IR;
			8: debug_data_signal <= {27'b0, addr_rs};
			9: debug_data_signal <= data_rs;
			10: debug_data_signal <= {27'b0, addr_rt};
			11: debug_data_signal <= data_rt;
			12: debug_data_signal <= data_imm;
			13: debug_data_signal <= opa;
			14: debug_data_signal <= opb;
			15: debug_data_signal <= alu_out;
			16: debug_data_signal <= 0;
			17: debug_data_signal <= 0;
			18: debug_data_signal <= {19'b0, inst_ren, 7'b0, mem_ren, 3'b0, mem_wen};
			19: debug_data_signal <= mem_addr;
			20: debug_data_signal <= mem_din;
			21: debug_data_signal <= mem_dout;
			22: debug_data_signal <= {27'b0, regw_addr};
			23: debug_data_signal <= regw_data;
			default: debug_data_signal <= 32'hFFFF_FFFF;
		endcase
	end
	
	assign
		debug_data = debug_addr[5] ? debug_data_signal : debug_data_reg;
	`endif
	
	//IF
	assign 
		inst_addr_next = inst_addr + 4; // PC=PC+4
	
	always @(posedge clk) begin
		if (cpu_rst) begin
			inst_addr <= 0;
		end
		else if (cpu_en) begin
			if(is_branch)	// this signal is new, CHECK CONTROLLER.V!!!!!!
			// is_branch（input wire) 应该是表示是否跳转，包括j类和branch类，controller里面应该有这个信号的相关改动，要改一�
				inst_addr<=IF_ID_trg_addr;
			else
				inst_addr<=inst_addr_next;
		end
	end
	
	//ID
	always @(posedge clk) begin
		if(cpu_rst) begin
			IF_ID_IR_addr<=0;
			IF_ID_IR<=0;
			IF_ID_IR_addr_next<=0;
		end
		else if(cpu_en) begin
			IF_ID_IR_addr<=inst_addr;
			IF_ID_IR<=inst_data;
			IF_ID_IR_addr_next<=inst_addr_next;
		end
	end
	assign
		inst_data_ctrl = IF_ID_IR,
		addr_rs = IF_ID_IR[25:21],
		addr_rt = IF_ID_IR[20:16],
		addr_rd = IF_ID_IR[15:11],
		data_imm = imm_ext_ctrl ? {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]} : {16'b0, IF_ID_IR[15:0]};// 32-bit ext
		//imm_ext 1: sign_ext 0:zero_ext


	always @(*) begin
		regw_addr = inst_data[15:11];
		case (wb_addr_src_ctrl)
			WB_ADDR_RD: regw_addr = addr_rd;
			WB_ADDR_RT: regw_addr = addr_rt;
			WB_ADDR_LINK: regw_addr = GPR_RA;
		endcase
	end
	
	regfile REGFILE (
		.clk(clk),
		`ifdef DEBUG
		.debug_addr(debug_addr[4:0]),
		.debug_data(debug_data_reg),
		`endif
		.addr_a(addr_rs),
		.data_a(data_rs),
		.addr_b(addr_rt),
		.data_b(data_rt),
		.en_w(MEM_WB_wb_wen & cpu_en & ~cpu_rst),
		.addr_w(MEM_WB_regw_addr),
		.data_w(MEM_WB_regw_data)
		);

	assign
		rs_rt_equal = (data_rs == data_rt);
	wire[31:0] branch_trg;
	assign 
		branch_trg = IF_ID_IR_addr_next + (data_imm << 2);	// branch target address
	assign 
		is_branch = (pc_src_ctrl==PC_JUMP)||(pc_src_ctrl==PC_JR)||(pc_src_ctrl==PC_BEQ)||(pc_src_ctrl==PC_BNE);
	always @( *) begin
		case(pc_src_ctrl)
			PC_JUMP:IF_ID_trg_addr<={IF_ID_IR_addr[31:28],IF_ID_IR[25:0],2'b0};// jump address
			PC_JR:IF_ID_trg_addr<=data_rs;
			PC_BEQ:begin
				if(rs_rt_equal)
					IF_ID_trg_addr<=branch_trg;
				else
					IF_ID_trg_addr<=IF_ID_IR_addr_next;
			end
			PC_BNE:begin 
				if(!rs_rt_equal)
					IF_ID_trg_addr<=branch_trg;
				else
					IF_ID_trg_addr<=IF_ID_IR_addr_next;
			end
			default:begin
				IF_ID_trg_addr<=IF_ID_IR_addr_next;
			end
		endcase
	end
	//EXE
	always @(posedge clk) begin
		if(cpu_rst) begin
			ID_EX_IR_addr<=0;
			ID_EX_IR<=0;
			ID_EX_IR_addr_next<=0;
			ID_EX_regw_addr<=0;
			ID_EX_pc_src<=0;
			ID_EX_a_src<=0;
			ID_EX_b_src<=0;
			ID_EX_addr_rs<=0;
			ID_EX_addr_rt<=0;
			ID_EX_data_rs<=0;
			ID_EX_data_rt<=0;
			ID_EX_data_imm<=0;
			ID_EX_aluop<=0;
			ID_EX_mem_ren<=0;
			ID_EX_mem_wen<=0;
			ID_EX_wb_data_src<=0;
			wb_wen<=0;
			ID_EX_rs_rt_equal<=0;
		end
		else if(cpu_en)begin
			ID_EX_IR_addr<=IF_ID_IR_addr;
			ID_EX_IR<=IF_ID_IR;
			ID_EX_IR_addr_next<=IF_ID_IR_addr_next;
			ID_EX_regw_addr<=regw_addr;
			ID_EX_pc_src<=pc_src_ctrl;
			ID_EX_a_src<=exe_a_src_ctrl;
			ID_EX_b_src<=exe_b_src_ctrl;
			ID_EX_addr_rs<=addr_rs;
			ID_EX_addr_rt<=addr_rt;
			ID_EX_data_rs<=data_rs;
			ID_EX_data_rt<=data_rt;
			ID_EX_data_imm<=data_imm;
			ID_EX_aluop<=exe_alu_oper_ctrl;
			ID_EX_mem_ren<=mem_ren_ctrl;
			ID_EX_mem_wen<=mem_wen_ctrl;
			ID_EX_wb_data_src<=wb_data_src_ctrl;
			wb_wen<=wb_wen_ctrl;
			ID_EX_rs_rt_equal<=rs_rt_equal;			
		end
	end

	always @(*) begin
		opa = ID_EX_data_rs;
		opb = ID_EX_data_rt;
		case (ID_EX_a_src)
			EXE_A_RS: opa = ID_EX_data_rs;
			EXE_A_LINK: opa = ID_EX_IR_addr_next;
			//EXE_A_BRANCH: opa = ID_EX_inst_addr_next;
		endcase
		case (ID_EX_b_src)
			EXE_B_RT: opb = ID_EX_data_rt;
			EXE_B_IMM: opb = ID_EX_data_imm;
			EXE_B_LINK: opb = 4;
			//EXE_B_BRANCH: opb = ID_EX_data_imm << 2;
		endcase
	end
	alu ALU (
		.a(opa),
		.b(opb),
		.oper(ID_EX_aluop),
		.result(alu_out)
		);

	
	//MEM
	always@(posedge clk) begin
		if(cpu_rst) begin
			EX_MEM_IR<=0;
			EX_MEM_IR_addr<=0;
			EX_MEM_IR_addr_next<=0;

			EX_MEM_data_rs<=0;
			EX_MEM_data_rt<=0;
			EX_MEM_aluout<=0;

			EX_MEM_pc_src<=0;

			EX_MEM_mem_ren<=0;
			EX_MEM_mem_wen<=0;
			EX_MEM_wb_wen<=0;

			EX_MEM_wb_data_src<=0;
			//regw_data<=0;
		end
		else if(cpu_en)begin
			EX_MEM_IR<=ID_EX_IR;
			EX_MEM_IR_addr<=ID_EX_IR_addr;
			EX_MEM_IR_addr_next<=ID_EX_IR_addr_next;

			EX_MEM_data_rs<=ID_EX_data_rs;
			EX_MEM_data_rt<=ID_EX_data_rt;
			EX_MEM_aluout<=alu_out;//aluout first time use

			EX_MEM_pc_src<=ID_EX_pc_src;

			EX_MEM_mem_ren<=ID_EX_mem_ren;
			EX_MEM_mem_wen<=ID_EX_mem_wen;
			EX_MEM_wb_wen<=wb_wen;

			EX_MEM_wb_data_src<=ID_EX_wb_data_src;
			//regw_data<=;//!!!! ??
			
		end
	end
	assign 
		mem_ren = EX_MEM_mem_ren,
		mem_wen = EX_MEM_mem_wen,
		mem_addr = EX_MEM_aluout;
	assign
		mem_dout=EX_MEM_data_rt;
	
	always @( *) begin
		regw_data = EX_MEM_aluout;
		case (EX_MEM_wb_data_src)
			WB_DATA_ALU:regw_data = EX_MEM_aluout;
			WB_DATA_MEM:regw_data = mem_din;
		endcase
	end
	//reg[31:0] MEM_WB_aluout;
	//reg MEM_WB_mem_ren,MEM_WB_mem_wen;
	//reg MEM_WB_wb_data_src;
	//reg MEM_WB_wb_wen;
	//reg[31:0] MEM_WB_mem_din;
	//reg[31:0] MEM_WB_regw_addr,MEM_WB_regw_data;

	//WB
	always@(posedge clk) begin
		if(cpu_rst) begin
			MEM_WB_aluout<=0;
			MEM_WB_wb_data_src<=0;
			MEM_WB_wb_wen<=0;
			MEM_WB_mem_din<=0;
			MEM_WB_regw_addr<=0;
			MEM_WB_regw_data<=0;
		end
		else if(cpu_en)begin
			MEM_WB_aluout<=EX_MEM_aluout;
			MEM_WB_wb_data_src<=EX_MEM_wb_data_src;
			MEM_WB_wb_wen<=EX_MEM_wb_wen;
			MEM_WB_mem_din<=mem_din;
			MEM_WB_regw_addr<=regw_addr;
			MEM_WB_regw_data<=regw_data;

		end

	end	
	
endmodule
