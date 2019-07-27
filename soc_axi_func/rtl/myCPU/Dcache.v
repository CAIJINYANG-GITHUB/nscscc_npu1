module Dcache(
    input wire              clk,
    input wire              reset,
    input wire              complete,
    input wire              I_ready,
    input wire              exception_inst_exchappen,
    input wire              dmm_write,
    input wire              dmm_read,
    input wire [3:0]        wen,
    input wire [31:0]       mem_dmm_addr,
    input wire [2:0]        mem_lw_sw_type,
    input wire [31:0]       dmm_data,
    input wire              arready,
    input wire              awready,
    input wire              wready,
    input wire              rvalid,
    input wire              rlast,
    input wire [31:0]       rdata,
    input wire              bvalid,

    output reg [31:0]       araddr,
    output reg [3:0]        arlen,
    output reg              arvalid,
    output reg [31:0]       awaddr,
    output reg [3:0]        awlen,
    output reg              awvalid,
    output reg [31:0]       wdata,
    output reg              wlast,
    output reg              wvalid,
    output wire             ready,
    output wire[3:0]         state,
    output wire[31:0]       dcache_rdata,
    output wire             not_dfetch_idle
);
    wire [31:0]             dcache_addr;
    wire                    hit;
    wire                    uncache_access;
    wire                    cache_access;
    reg [6:0]               counter;
    wire[6:0]               tab_addr;
    wire[20:0]              rd_tab;
    wire[20:0]              tab_wrdata;
    wire                    dirty;
    wire[3:0]               wword_shift;
    reg [3:0]               wr_off;
    wire[31:0]              write_data;
    wire[3:0]               rword_shift;
    reg[3:0]                rd_off;
    wire[31:0]              dcache_rdata_tmp;
    
    parameter   [3:0]   // synopsys enum code
                        DFETCH_IDLE             = 4'd0, 
                        DCACHE_SB_SH_STORE      = 4'd1,
                        DCACHE_MEMREAD_FIRST    = 4'd2,
                        DCACHE_MEMREAD          = 4'd3,
                        DCACHE_WRITEBACK_FIRST  = 4'd4, 
                        DCACHE_WRITEBACK_SECOND = 4'd5, 
                        DCACHE_WRITEBACK        = 4'd6,
                        DDIRECT_MEMREAD_FIRST   = 4'd7,
                        DDIRECT_MEMREAD         = 4'd8,
                        DDIRECT_END             = 4'd9,
                        DDIRECT_MEMWRITE_FIRST  = 4'd10,
                        DDIRECT_MEMWRITE        = 4'd11;
                        
    
    // synopsys state_vector state
    reg     [3:0]   // synopsys enum code
                    CS, NS;
    always @(posedge clk)
    if (reset)
        CS <= DFETCH_IDLE;
    else 
        CS <= NS;

    always @(*)
    begin
        NS = DFETCH_IDLE;
        case(CS)     // synopsys full_case parallel_case
            DFETCH_IDLE:
                if (!hit&&rd_tab[1]&&cache_access)
                    NS = DCACHE_WRITEBACK_FIRST;
                else if (!hit && !rd_tab[1]&&cache_access)
                    NS = DCACHE_MEMREAD_FIRST;
                else if (cache_access && hit && rd_tab[1] && dmm_write && (mem_lw_sw_type == 3'd5 || mem_lw_sw_type == 3'd6))
                    NS = DCACHE_SB_SH_STORE;
                else if (uncache_access && dmm_read)
                    NS = DDIRECT_MEMREAD_FIRST;
                else if (uncache_access && dmm_write)
                    NS =DDIRECT_MEMWRITE_FIRST;
                else 
                    NS = DFETCH_IDLE;
            DCACHE_SB_SH_STORE: 
                NS = DFETCH_IDLE;
            DCACHE_WRITEBACK_FIRST:
                if (awready)
                    NS = DCACHE_WRITEBACK_SECOND;  
                else 
                    NS = DCACHE_WRITEBACK_FIRST; 
            DCACHE_WRITEBACK_SECOND:
                if (wlast && wready)
                    NS = DCACHE_WRITEBACK;
                else    
                    NS = DCACHE_WRITEBACK_SECOND;
            DCACHE_WRITEBACK:
                if (bvalid)
                    NS = DCACHE_MEMREAD_FIRST;
                else 
                    NS = DCACHE_WRITEBACK;
            DCACHE_MEMREAD_FIRST:
                if (arready)
                    NS = DCACHE_MEMREAD;
                else 
                    NS = DCACHE_MEMREAD_FIRST;
            DCACHE_MEMREAD:    
                if (rvalid && rlast)
                    NS = DFETCH_IDLE;
                else 
                    NS = DCACHE_MEMREAD;
            DDIRECT_MEMREAD_FIRST:
                if (arready)
                    NS = DDIRECT_MEMREAD;
                else 
                    NS = DDIRECT_MEMREAD_FIRST;
            DDIRECT_MEMREAD:
                if (rvalid && rlast)
                    NS = DDIRECT_END;
                else 
                    NS = DDIRECT_MEMREAD;
            DDIRECT_END:
                if (I_ready && complete)
                    NS = DFETCH_IDLE;
                else 
                    NS = DDIRECT_END;
            DDIRECT_MEMWRITE_FIRST:
                if (awready)
                    NS = DDIRECT_MEMWRITE;
                else 
                    NS = DDIRECT_MEMWRITE_FIRST;
            DDIRECT_MEMWRITE: 
                if (bvalid)
                    NS = DDIRECT_END;
                else    
                    NS = DDIRECT_MEMWRITE;
            default: 
                    NS = DFETCH_IDLE;
        endcase
    end

    always @(posedge clk)
    if (reset)
    begin 
        araddr <= 0;
        arlen  <= 0;
        arvalid <= 0;
        awaddr <= 0;
        awlen  <= 0;
        awvalid <= 0;
        wdata  <= 0;
        wlast  <= 0;
        wvalid <= 0;
    end
    else 
    begin 
        case (NS)
            DFETCH_IDLE:
            begin 
                araddr <= 0;
                arlen  <= 0;
                arvalid <= 0;
                awaddr <= 0;
                awlen  <= 0;
                awvalid <= 0;
                wdata  <= 0;
                wlast  <= 0;
                wvalid <= 0;
            end
            DCACHE_WRITEBACK_FIRST:
            begin 
                awaddr <= {rd_tab[20: 2],mem_dmm_addr[12:6],6'd0};
                awlen  <= 4'b1111;
                awvalid <= 1'b1;
            end 
            DCACHE_WRITEBACK_SECOND:
            begin 
                awaddr <= 0;
                awlen <= 0;
                awvalid <= 1'b0;
                wvalid <= 1'b1;
                wdata <= dcache_rdata;
                if (rd_off == 4'd15 && wready)
                    wlast <= 1;
            end
            DCACHE_WRITEBACK:
            begin 
                wvalid <= 1'b0;
                wdata <= 0;
                wlast <= 0;
            end
            DCACHE_MEMREAD_FIRST:
            begin 
                araddr <= {dcache_addr[31:6],6'd0};
                arlen <= 4'b1111;
                arvalid <= 1'b1;
            end
            DCACHE_MEMREAD:
            begin 
                araddr <= 0;
                arlen <= 0;
                arvalid <= 1'b0;
            end 
            DDIRECT_MEMREAD_FIRST:
            begin 
                araddr <= dcache_addr;
                arlen <= 4'b0000;
                arvalid <= 1'b1;
            end 
            DDIRECT_MEMREAD: 
            begin 
                araddr <= 0;
                arlen <= 0;
                arvalid <= 1'b0;
            end 
            DDIRECT_MEMWRITE_FIRST:
            begin 
                awaddr <= dcache_addr;
                awlen  <= 4'b0000;
                awvalid <= 1'b1;
            end       
            DDIRECT_MEMWRITE:
            begin 
                awaddr <= 0;
                awlen <= 0;
                awvalid <= 0;
                wvalid <= 1'b1;
                wdata <= dmm_data;
                wlast <= 1;
            end 
            default:
            begin 
                araddr <= 0;
            end
        endcase
    end
    
        assign dcache_addr =  (mem_dmm_addr[31:29] == 3'b100 || mem_dmm_addr[31:29] == 3'b101) 
                                                ? {3'b000, mem_dmm_addr[28:0]} : mem_dmm_addr;
//        assign uncache_access = mem_dmm_addr[31:29] == 3'b101&&(dmm_write || dmm_read)&&!exception_inst_exchappen;
//        assign cache_access = mem_dmm_addr[31:29] != 3'b101 &&(dmm_write || dmm_read)&&!exception_inst_exchappen;
        assign uncache_access = !exception_inst_exchappen&&mem_dmm_addr[31:29] == 3'b101&&(dmm_write || dmm_read);
assign cache_access = !exception_inst_exchappen&&mem_dmm_addr[31:29] != 3'b101 &&(dmm_write || dmm_read);
        assign hit =  (rd_tab[20: 2] == dcache_addr[31: 13]) && rd_tab[0];
        always @(posedge clk)
        if(~reset)
        counter <= 0;
        else
            if(reset && counter != 7'b1111111)
            counter =counter +1;
            
        assign tab_addr= reset? counter : mem_dmm_addr[12:6];
        assign tab_wrdata = reset ? 21'd0 : {dcache_addr[31:13],dirty,1'b1};
    
        assign  dirty = dmm_write&& hit;
        dist_mem_gen_2 tab (
        .a(tab_addr),      // input wire [6 : 0] a
        .d(tab_wrdata),      // input wire [20 : 0] d
        .clk(clk),  // input wire clk
        .we(rvalid&&rlast&&state== DCACHE_MEMREAD || hit && dmm_write && cache_access ||reset),    // input wire we
        .spo(rd_tab)  // output wire [20 : 0] spo
        );
        
        reg [31:0] dcache_rdata_tmp_save;
        reg [31:0] sb_sh_write_data;
        always @(posedge clk)
            dcache_rdata_tmp_save <= dcache_rdata_tmp;
        assign wword_shift =rvalid ? wr_off :  mem_dmm_addr[5: 2]; 
        assign write_data =  (hit && dmm_write) ? ( mem_lw_sw_type == 3'd7 ? dmm_data : 
                                                                                wen == 4'b0001 ? {dcache_rdata_tmp_save[31:8],dmm_data[7:0]} :
                                                                                wen == 4'b0010 ? {dcache_rdata_tmp_save[31:16],dmm_data[7:0],dcache_rdata_tmp_save[7:0]} :
                                                                                wen == 4'b0100 ? {dcache_rdata_tmp_save[31:24],dmm_data[7:0],dcache_rdata_tmp_save[15:0]} :
                                                                                wen == 4'b1000 ? {dmm_data[7:0],dcache_rdata_tmp_save[23:0]} :
                                                                                wen == 4'b0011 ? {dcache_rdata_tmp_save[31:16],dmm_data[15:0]} :
                                                                                wen == 4'b1100 ? {dmm_data[15:0],dcache_rdata_tmp_save[15:0]}: 0) :rvalid ? rdata:0 ;

        assign rword_shift =  (state == DCACHE_WRITEBACK_FIRST ||  state == DCACHE_WRITEBACK_SECOND) ? rd_off : mem_dmm_addr[5: 2] ;
    
        dist_mem_gen_3 data(
        .a({mem_dmm_addr[12:6],wword_shift}),        // input wire [10 : 0] a
        .d(write_data),        // input wire [31 : 0] d
        .dpra({mem_dmm_addr[12:6],rword_shift}),  // input wire [10 : 0] dpra
        .clk(clk),    // input wire clk
        .we(rvalid&&state ==DCACHE_MEMREAD  || hit&&dmm_write && cache_access && mem_lw_sw_type == 3'd7 || state == DCACHE_SB_SH_STORE),      // input wire we
        .dpo(dcache_rdata_tmp)    // output wire [31 : 0] dpo
        );
        reg [31:0] direct_data;
        always @(posedge clk)
        if(reset)
            direct_data <= 0;
         else if(rlast && rvalid)
            direct_data <= rdata;
            
       assign dcache_rdata = cache_access ? dcache_rdata_tmp : direct_data;
    
        always @(posedge clk)
        if (reset)
        begin 
            rd_off <= 0;
        end
        else if (awready || wready)
        begin 
            rd_off <= rd_off + 1;
        end
        else if (bvalid)
        begin 
            rd_off <= 0;
        end
    
        always@(posedge clk)
        begin
            if(reset)
                wr_off<= 0;
            else if (!uncache_access)
            begin
                if(rlast&&rvalid)
                    wr_off <= 0;
                else if(rvalid)
                    wr_off <= wr_off + 1;
             end
        end
        
        
    assign ready = uncache_access? state == DDIRECT_END  
            : (cache_access ? ( (mem_lw_sw_type == 3'd5 || mem_lw_sw_type == 3'd6) ? state  == DCACHE_SB_SH_STORE :  hit) : 1);
    assign state = CS;
    assign not_dfetch_idle =  state != DFETCH_IDLE;
    endmodule
                
                




            
            

