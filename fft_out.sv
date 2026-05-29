`timescale 1ns/1ps
module fft_out #(
    parameter CHANNEL_NUMBER = 4,
    parameter AD_DATA_WIDTH = 14,
    parameter FFT_POINT = 8192
) (
    input wire clk,
    input wire timestamp_change,    // 时间戳改变标志
    input wire [31:0] m_axis_data_tdata[CHANNEL_NUMBER-1:0],  
    input wire m_axis_data_tvalid[CHANNEL_NUMBER-1:0],
    input wire m_axis_data_tlast[CHANNEL_NUMBER-1:0],
    input wire [$clog2(FFT_POINT)-1:0] m_axis_data_tuser,

    input wire clk_dma,
    input wire ram_intr,
    input wire axis_s2mm_tready,
    output wire axis_s2mm_tvalid,                          
    output wire [1:0] axis_s2mm_tkeep,   
    output wire [15:0] axis_s2mm_tdata,       
    output wire axis_s2mm_tlast,
    output wire reverse_sign_dma                          
);

// 延时5
wire [2*AD_DATA_WIDTH-1:0] i2q2[CHANNEL_NUMBER-1:0];

genvar s;
generate
    for(s=0;s<CHANNEL_NUMBER;s=s+1) begin
        sum_square #(
            .DATA_WIDTH ( AD_DATA_WIDTH ))
        u_sum_square (
            .clk                     ( clk                                      ),
            .i                       ( m_axis_data_tdata[s][0+:AD_DATA_WIDTH]   ),
            .q                       ( m_axis_data_tdata[s][16+:AD_DATA_WIDTH]  ),

            .i2q2                    ( i2q2[s]                                  )
        );
    end
endgenerate

// 找出i2q2最大值, 延时$clog2(CHANNEL_NUMBER)
wire [2*AD_DATA_WIDTH-1:0] max_i2q2;
compare #(
    .DATA_NUM   ( CHANNEL_NUMBER   ),
    .DATA_WIDTH ( 2*AD_DATA_WIDTH ))
 u_compare (
    .clk       ( clk        ),
    .data      ( i2q2       ),

    .max_data  ( max_i2q2   )
);


wire                         wea_dma    ;         
wire [$clog2(FFT_POINT)-1:0] addra_dma  ;         
wire [31:0]                  dina_dma   ;                 
compare_ram #(
    .FFT_POINT      ( FFT_POINT      ),
    .AD_DATA_WIDTH  ( AD_DATA_WIDTH  ),
    .CHANNEL_NUMBER ( CHANNEL_NUMBER ))
 u_compare_ram (
    .clk                     ( clk                                        ),
    .timestamp_change        ( timestamp_change                           ),
    .max_i2q2                ( max_i2q2           [2*AD_DATA_WIDTH-1:0]   ),
    .m_axis_data_tuser       ( m_axis_data_tuser  [$clog2(FFT_POINT)-1:0] ),

    .wea_dma                 ( wea_dma                                    ),
    .addra_dma               ( addra_dma          [$clog2(FFT_POINT)-1:0] ),
    .dina_dma                ( dina_dma           [31:0]                  ),
    .reverse_sign            ( reverse_sign                               )
);

xpm_cdc_single #(
   .DEST_SYNC_FF(4),   // DECIMAL; range: 2-10
   .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
   .SIM_ASSERT_CHK(0), // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
   .SRC_INPUT_REG(1)   // DECIMAL; 0=do not register input, 1=register input
)
xpm_cdc_single_inst (
   .dest_out(reverse_sign_dma), // 1-bit output: src_in synchronized to the destination clock domain. This output is
                        // registered.
   .dest_clk(clk_dma), // 1-bit input: Clock signal for the destination clock domain.
   .src_clk(clk),   // 1-bit input: optional; required when SRC_INPUT_REG = 1
   .src_in(reverse_sign)      // 1-bit input: Input signal to be synchronized to dest_clk domain.
);

localparam RAM_LATENCY_DMA = 2;
wire [15:0] doutb_dma;
wire [$clog2(FFT_POINT):0] addrb_dma;
wire enb_dma;

xpm_memory_sdpram #(
    .ADDR_WIDTH_A($clog2(FFT_POINT)),               // DECIMAL
    .ADDR_WIDTH_B($clog2(FFT_POINT)+1),               // DECIMAL
    .AUTO_SLEEP_TIME(0),            // DECIMAL
    .BYTE_WRITE_WIDTH_A(32),        // DECIMAL
    .CASCADE_HEIGHT(0),             // DECIMAL
    .CLOCKING_MODE("independent_clock"), // String
    .ECC_BIT_RANGE("7:0"),          // String
    .ECC_MODE("no_ecc"),            // String
    .ECC_TYPE("none"),              // String
    .IGNORE_INIT_SYNTH(0),          // DECIMAL
    .MEMORY_INIT_FILE("none"),      // String
    .MEMORY_INIT_PARAM("0"),        // String
    .MEMORY_OPTIMIZATION("true"),   // String
    .MEMORY_PRIMITIVE("auto"),      // String
    .MEMORY_SIZE(32*FFT_POINT),             // DECIMAL
    .MESSAGE_CONTROL(0),            // DECIMAL
    .RAM_DECOMP("auto"),            // String
    .READ_DATA_WIDTH_B(16),         // DECIMAL
    .READ_LATENCY_B(RAM_LATENCY_DMA),             // DECIMAL
    .READ_RESET_VALUE_B("0"),       // String
    .RST_MODE_A("SYNC"),            // String
    .RST_MODE_B("SYNC"),            // String
    .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
    .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
    .USE_MEM_INIT(1),               // DECIMAL
    .USE_MEM_INIT_MMI(0),           // DECIMAL
    .WAKEUP_TIME("disable_sleep"),  // String
    .WRITE_DATA_WIDTH_A(32),        // DECIMAL
    .WRITE_MODE_B("no_change"),     // String
    .WRITE_PROTECT(1)               // DECIMAL
)
xpm_memory_sdpram_inst (
    .dbiterrb(),             // 1-bit output: Status signal to indicate double bit error occurrence
                                    // on the data output of port B.
    .doutb(doutb_dma),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
    .sbiterrb(),             // 1-bit output: Status signal to indicate single bit error occurrence
                                    // on the data output of port B.
    .addra(addra_dma),                   // ADDR_WIDTH_A-bit input: Address for port A write operations.
    .addrb(addrb_dma),                   // ADDR_WIDTH_B-bit input: Address for port B read operations.
    .clka(clk),                     // 1-bit input: Clock signal for port A. Also clocks port B when
                                    // parameter CLOCKING_MODE is "common_clock".
    .clkb(clk_dma),                     // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is
                                    // "independent_clock". Unused when parameter CLOCKING_MODE is
                                    // "common_clock".
    .dina(dina_dma),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
    .ena(1'b1),                       // 1-bit input: Memory enable signal for port A. Must be high on clock
                                    // cycles when write operations are initiated. Pipelined internally.
    .enb(enb_dma),                       // 1-bit input: Memory enable signal for port B. Must be high on clock
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
    .wea(wea_dma)                        // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector
                                    // for port A input data port dina. 1 bit wide when word-wide writes are
                                    // used. In byte-wide write configurations, each bit controls the
                                    // writing one byte of dina to address addra. For example, to
                                    // synchronously write only bits [15-8] of dina when WRITE_DATA_WIDTH_A
                                    // is 32, wea would be 4'b0010.
);


// clk_dma 
wire reset_n = 1;
ram_s2mm #(
    .RAM_DOUT_WIDTH  ( 16                   ),
    .RAM_DOUT_LENGTH ( 2*FFT_POINT          ),
    .RAM_ADDRB_WIDTH ( $clog2(FFT_POINT)+1    ),
    .READ_LATENCY_B  ( RAM_LATENCY_DMA      ))
 u_ram_s2mm (
    .clk_dma                 ( clk_dma                          ),
    .reset_n                 ( reset_n                          ),
    .ram_intr                ( ram_intr                         ),
    .doutb                   ( doutb_dma             [15:0]     ),
    .axis_s2mm_tready        ( axis_s2mm_tready                       ),

    .enb                     ( enb_dma                                ),
    .addrb                   ( addrb_dma         [$clog2(FFT_POINT):0]),
    .axis_s2mm_tvalid        ( axis_s2mm_tvalid             ),
    .axis_s2mm_tkeep         ( axis_s2mm_tkeep   [1:0]      ),
    .axis_s2mm_tdata         ( axis_s2mm_tdata   [15:0]     ),
    .axis_s2mm_tlast         ( axis_s2mm_tlast              )
);
endmodule