`timescale 1ns/1ps
module fft_in #(
    parameter CHANNEL_NUMBER = 4,       // AD数据交织通道数
    parameter AD_DATA_WIDTH = 14,       // AD数据有效位宽
    parameter FFT_POINT = 8192
) (
    input wire clk,
    input wire rstn_sync,               // 所有逻辑必须都是同步复位
    input wire [AD_DATA_WIDTH-1:0] ad_q [CHANNEL_NUMBER-1:0],
    input wire [AD_DATA_WIDTH-1:0] ad_i [CHANNEL_NUMBER-1:0],
    input wire s_axis_data_tready[CHANNEL_NUMBER-1:0],
    output reg [31:0] s_axis_data_tdata[CHANNEL_NUMBER-1:0],  //[29:16]: q ; [13:0]: i
    output reg s_axis_data_tvalid[CHANNEL_NUMBER-1:0],
    output reg s_axis_data_tlast [CHANNEL_NUMBER-1:0]
);


// 并行数据 深度FFT_POINT/ CHANNEL_NUMBER
localparam ADDR_WIDTH_A = $clog2(FFT_POINT/CHANNEL_NUMBER);
localparam ADDR_WIDTH_B = $clog2(FFT_POINT);
localparam MEMORY_SIZE = 2*AD_DATA_WIDTH*FFT_POINT;
localparam WRITE_WIDTH = 2*CHANNEL_NUMBER*AD_DATA_WIDTH;
localparam READ_WIDTH = 2*AD_DATA_WIDTH;

localparam RAM_LATENCY = 2;

genvar s;
reg init = 0; // 复位后, RAM每次重新写完一轮RAM的标志, 不复位就一直置高就行



// 填满RAM逻辑  made by chatgpt-5.5 noob
localparam WRITE_RAM_IDLE = 1'b0;
localparam WRITE_RAM_RUN  = 1'b1;

reg wea [2*CHANNEL_NUMBER-1:0];
reg [WRITE_WIDTH-1:0] dina[2*CHANNEL_NUMBER-1:0];
reg [ADDR_WIDTH_A-1:0] addra [2*CHANNEL_NUMBER-1:0];

reg write_ram_state = WRITE_RAM_IDLE;
reg [$clog2(2*CHANNEL_NUMBER)-1:0] write_ram_sel = 0;
reg [ADDR_WIDTH_A-1:0] write_addr = 0;
integer write_ram_i;
integer write_data_i;

always @(posedge clk) begin
    if(!rstn_sync) begin
        init <= 1'b0;
        write_ram_state <= WRITE_RAM_IDLE;
        write_ram_sel <= {$clog2(2*CHANNEL_NUMBER){1'b0}};
        write_addr <= {ADDR_WIDTH_A{1'b0}};

        for(write_ram_i = 0; write_ram_i < 2*CHANNEL_NUMBER; write_ram_i = write_ram_i + 1) begin
            wea[write_ram_i] <= 1'b0;
            dina[write_ram_i] <= {WRITE_WIDTH{1'b0}};
            addra[write_ram_i] <= {ADDR_WIDTH_A{1'b0}};
        end
    end
    else begin
        for(write_ram_i = 0; write_ram_i < 2*CHANNEL_NUMBER; write_ram_i = write_ram_i + 1) begin
            wea[write_ram_i] <= 1'b0;
        end

        case(write_ram_state)
            WRITE_RAM_IDLE: begin
                write_ram_state <= WRITE_RAM_RUN;
                write_ram_sel <= {$clog2(2*CHANNEL_NUMBER){1'b0}};
                write_addr <= {ADDR_WIDTH_A{1'b0}};
            end

            WRITE_RAM_RUN: begin
                wea[write_ram_sel] <= 1'b1;
                addra[write_ram_sel] <= write_addr;

                for(write_data_i = 0; write_data_i < 2*CHANNEL_NUMBER; write_data_i = write_data_i + 1) begin
                    dina[write_ram_sel][(2*AD_DATA_WIDTH*write_data_i) +: AD_DATA_WIDTH] <= ad_i[write_data_i];
                    dina[write_ram_sel][(2*AD_DATA_WIDTH*write_data_i + AD_DATA_WIDTH) +: AD_DATA_WIDTH] <= ad_q[write_data_i];
                end

                // 每个RAM的地址从0轮询到8191
                if(write_addr == FFT_POINT/CHANNEL_NUMBER-1) begin
                    write_addr <= {ADDR_WIDTH_A{1'b0}};
                end else begin
                    write_addr <= write_addr + 1'b1;
                end

                // 初始化完成, 所有RAM都写完了
                if((write_addr == FFT_POINT/CHANNEL_NUMBER-1) && (write_ram_sel == CHANNEL_NUMBER-1)) begin
                    init <= 1'b1;
                end

                if(write_addr == FFT_POINT/CHANNEL_NUMBER-1) begin
                    if( write_ram_sel == 2*CHANNEL_NUMBER-1 ) begin
                        write_ram_sel <= {$clog2(2*CHANNEL_NUMBER){1'b0}};
                    end
                    else begin
                        write_ram_sel <= write_ram_sel + 1'b1;
                    end
                end
            end
        endcase
    end
end

reg enb [2*CHANNEL_NUMBER-1:0];
wire [READ_WIDTH-1:0] doutb[2*CHANNEL_NUMBER-1:0];
reg [ADDR_WIDTH_B-1:0] addrb [2*CHANNEL_NUMBER-1:0];
/*
 加在这里
*/
localparam READ_IDLE = 0;
localparam READ_RAM = 1;
reg read_ram_state;

always @(posedge clk ) begin
    if(!rstn_sync) begin
        read_ram_state <= READ_IDLE;
    end else begin
        case (read_ram_state)
            READ_IDLE:
                begin
                    if(init) read_ram_state <= READ_RAM;
                    else     read_ram_state <= READ_IDLE;
                end 
            READ_RAM:
                begin
                    read_ram_state <= read_ram_state;
                end 
        endcase
    end
end

integer ram_read_i;
// for(ram_read_i = 0; ram_read_i < 2*CHANNEL_NUMBER; ram_read_i = ram_read_i + 1) begin
                    
// end
reg [ADDR_WIDTH_B-1:0] cnt_addrb;
reg ram_reverse;
wire [31:0] s_axis_data_tdata_pre [2*CHANNEL_NUMBER-1:0];  //[29:16]: q ; [13:0]: i
wire s_axis_data_tvalid_pre [2*CHANNEL_NUMBER-1:0];
wire s_axis_data_tlast_pre [2*CHANNEL_NUMBER-1:0];
wire ram_reverse_delayed;
delay #(
    .DATA_WIDTH ( 1 ),
    .DELAY_CLK  ( RAM_LATENCY + 1 ),
    .IMPL_TYPE  ( 0  ))
u_delay_tvalid (
    .clk                     ( clk                        ),
    .data_in                 ( ram_reverse ),
    .data_out                ( ram_reverse_delayed  )
);

always @(posedge clk ) begin
    case (read_ram_state)
        READ_IDLE:
            begin
                for(ram_read_i = 0; ram_read_i < 2*CHANNEL_NUMBER; ram_read_i = ram_read_i + 1) begin
                    enb[ram_read_i] <= 0;
                    addrb[ram_read_i] <= 0;
                    s_axis_data_tvalid[ram_read_i] <= 0;
                    s_axis_data_tlast[ram_read_i] <= 0;
                    s_axis_data_tdata[ram_read_i] <= 0;
                end
                cnt_addrb <= 0;
                ram_reverse <= 0;
                
            end 
        READ_RAM:
            begin
                for(ram_read_i = 0; ram_read_i < 2*CHANNEL_NUMBER; ram_read_i = ram_read_i + 1) begin
                    if(~ram_reverse) begin
                        if(ram_read_i < CHANNEL_NUMBER) begin
                            enb[ram_read_i] <= 1'b1;
                            addrb[ram_read_i] <= cnt_addrb;
                        end else begin
                            enb[ram_read_i] <= 1'b0;
                            addrb[ram_read_i] <= 0;
                        end
                    end else begin
                        if(ram_read_i >= CHANNEL_NUMBER) begin
                            enb[ram_read_i] <= 1'b1;
                            addrb[ram_read_i] <= cnt_addrb;
                        end else begin
                            enb[ram_read_i] <= 1'b0;
                            addrb[ram_read_i] <= 0;
                        end
                    end 
                end
                for(ram_read_i = 0; ram_read_i < CHANNEL_NUMBER; ram_read_i = ram_read_i + 1) begin
                    if(~ram_reverse_delayed) begin
                        s_axis_data_tvalid[ram_read_i] <= s_axis_data_tvalid_pre[ram_read_i];
                        s_axis_data_tlast[ram_read_i] <= s_axis_data_tlast_pre[ram_read_i];
                        s_axis_data_tdata[ram_read_i] <= s_axis_data_tdata_pre[ram_read_i];
                    end else begin
                        s_axis_data_tvalid[ram_read_i] <= s_axis_data_tvalid_pre[ram_read_i+CHANNEL_NUMBER];
                        s_axis_data_tlast[ram_read_i] <= s_axis_data_tlast_pre[ram_read_i+CHANNEL_NUMBER];
                        s_axis_data_tdata[ram_read_i] <= s_axis_data_tdata_pre[ram_read_i+CHANNEL_NUMBER];
                    end 
                end
                if(cnt_addrb == FFT_POINT - 1) begin
                    cnt_addrb <= 0;
                    ram_reverse <= ~ram_reverse;
                end else begin
                    cnt_addrb <= cnt_addrb + 1; 
                    ram_reverse <= ram_reverse;
                end
            end 
    endcase
end

wire [ADDR_WIDTH_B-1:0] addrb_delayed [2*CHANNEL_NUMBER-1:0];
generate
    for(s = 0; s < 2*CHANNEL_NUMBER; s = s + 1) begin
        delay #(
            .DATA_WIDTH ( 1 ),
            .DELAY_CLK  ( RAM_LATENCY  ),
            .IMPL_TYPE  ( 0  ))
        u_delay_tvalid (
            .clk                     ( clk                        ),
            .data_in                 ( enb[s] ),

            .data_out                ( s_axis_data_tvalid_pre  [s] )
        );
        delay #(
            .DATA_WIDTH ( ADDR_WIDTH_B ),
            .DELAY_CLK  ( RAM_LATENCY  ),
            .IMPL_TYPE  ( 0  ))
        u_delay_addrb (
            .clk                     ( clk                        ),
            .data_in                 ( addrb[s] ),

            .data_out                ( addrb_delayed  [s] )
        );
        assign s_axis_data_tdata_pre[s] = 
        { 
            {16-AD_DATA_WIDTH{1'b0}}, doutb[s][AD_DATA_WIDTH +: AD_DATA_WIDTH],
            {16-AD_DATA_WIDTH{1'b0}} ,doutb[s][0 +: AD_DATA_WIDTH]
        };
        assign s_axis_data_tlast_pre[s] = (addrb_delayed[s] == FFT_POINT - 1); 
    end
endgenerate


generate
    for(s=0;s<2*CHANNEL_NUMBER;s=s+1) begin
        xpm_memory_sdpram #(
            .ADDR_WIDTH_A(ADDR_WIDTH_A),               // DECIMAL
            .ADDR_WIDTH_B(ADDR_WIDTH_B),               // DECIMAL
            .AUTO_SLEEP_TIME(0),            // DECIMAL
            .BYTE_WRITE_WIDTH_A(WRITE_WIDTH),        // DECIMAL
            .CASCADE_HEIGHT(0),             // DECIMAL
            .CLOCKING_MODE("common_clock"), // String
            .ECC_BIT_RANGE("7:0"),          // String
            .ECC_MODE("no_ecc"),            // String
            .ECC_TYPE("none"),              // String
            .IGNORE_INIT_SYNTH(0),          // DECIMAL
            .MEMORY_INIT_FILE("none"),      // String
            .MEMORY_INIT_PARAM("0"),        // String
            .MEMORY_OPTIMIZATION("true"),   // String
            .MEMORY_PRIMITIVE("auto"),      // String
            .MEMORY_SIZE(MEMORY_SIZE),             // DECIMAL
            .MESSAGE_CONTROL(0),            // DECIMAL
            .RAM_DECOMP("auto"),            // String
            .READ_DATA_WIDTH_B(READ_WIDTH),         // DECIMAL
            .READ_LATENCY_B(RAM_LATENCY),             // DECIMAL
            .READ_RESET_VALUE_B("0"),       // String
            .RST_MODE_A("SYNC"),            // String
            .RST_MODE_B("SYNC"),            // String
            .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
            .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
            .USE_MEM_INIT(1),               // DECIMAL
            .USE_MEM_INIT_MMI(0),           // DECIMAL
            .WAKEUP_TIME("disable_sleep"),  // String
            .WRITE_DATA_WIDTH_A(WRITE_WIDTH),        // DECIMAL
            .WRITE_MODE_B("no_change"),     // String
            .WRITE_PROTECT(1)               // DECIMAL
        )
        xpm_memory_sdpram_inst (
            .dbiterrb(),             // 1-bit output: Status signal to indicate double bit error occurrence
                                            // on the data output of port B.

            .doutb(doutb[s]),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
            .sbiterrb(),             // 1-bit output: Status signal to indicate single bit error occurrence
                                            // on the data output of port B.

            .addra(addra[s]),                   // ADDR_WIDTH_A-bit input: Address for port A write operations.
            .addrb(addrb[s]),                   // ADDR_WIDTH_B-bit input: Address for port B read operations.
            .clka(clk),                     // 1-bit input: Clock signal for port A. Also clocks port B when
                                            // parameter CLOCKING_MODE is "common_clock".

            .clkb(clk),                     // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
                                            // "independent_clock". Unused when parameter CLOCKING_MODE is
                                            // "common_clock".

            .dina(dina[s]),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
            .ena(1'b1),                       // 1-bit input: Memory enable signal for port A. Must be high on clock
                                            // cycles when write operations are initiated. Pipelined internally.

            .enb(enb[s]),                       // 1-bit input: Memory enable signal for port B. Must be high on clock
                                            // cycles when read operations are initiated. Pipelined internally.

            .injectdbiterra(1'b0), // 1-bit input: Controls double bit error injection on input data when
                                            // ECC enabled (Error injection capability is not available in
                                            // "decode_only" mode).

            .injectsbiterra(1'b0), // 1-bit input: Controls single bit error injection on input data when
                                            // ECC enabled (Error injection capability is not available in
                                            // "decode_only" mode).

            .regceb(1'b1),                 // 1-bit input: Clock Enable for the last register stage on the output
                                            // data path.

            .rstb(1'b0),                     // 1-bit input: Reset signal for the final port B output register stage.
                                            // Synchronously resets output port doutb to the value specified by
                                            // parameter READ_RESET_VALUE_B.

            .sleep(1'b0),                   // 1-bit input: sleep signal to enable the dynamic power saving feature.
            .wea(wea[s])                        // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
                                            // for port A input data port dina. 1 bit wide when word-wide writes are
                                            // used. In byte-wide write configurations, each bit controls the
                                            // writing one byte of dina to address addra. For example, to
                                            // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
                                            // is 32, wea would be 4'b0010.
        );
    end
endgenerate
endmodule
