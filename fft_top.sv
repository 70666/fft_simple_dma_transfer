`timescale 1ns/1ps
// 每次更改FFT点数时, FFT接口位宽需要改变以及缩放策略, 其他不用动, 本次设计默认最大点数8192
// FFT输出位宽与输入位宽保持一致, < 16, 不溢出, 尽量小缩放系数
module fft_top #(
    parameter CHANNEL_NUMBER = 4,       // AD数据交织通道数
    parameter AD_DATA_WIDTH = 14,       // AD数据有效位宽, 一定小于等于16
    parameter FFT_POINT = 8192
) (
    input wire clk,                     // 该模块逻辑均与此时钟同步
    input wire rstn_aysnc,              // axi lite下发寄存器, 非同步复位
    input wire timestamp_change,
    input wire [AD_DATA_WIDTH-1:0] ad_q[CHANNEL_NUMBER-1:0],
    input wire [AD_DATA_WIDTH-1:0] ad_i[CHANNEL_NUMBER-1:0],

    input wire clk_dma,        
    input wire ram_intr,      
    input wire axis_s2mm_tready,
    output wire axis_s2mm_tvalid,                          
    output wire [1:0] axis_s2mm_tkeep,   
    output wire [15:0] axis_s2mm_tdata,       
    output wire axis_s2mm_tlast,
    output wire reverse_sign_dma        // 软件每次读到这个反转后, 下发一次ram_intr告诉逻辑可以上传   
);

wire rstn_sync;
   xpm_cdc_sync_rst #(
      .DEST_SYNC_FF(4),   // DECIMAL; range: 2-10
      .INIT(1),           // DECIMAL; 0=initialize synchronization registers to 0, 1=initialize synchronization
                          // registers to 1
      .INIT_SYNC_FF(0),   // DECIMAL; 0=disable simulation init values, 1=enable simulation init values
      .SIM_ASSERT_CHK(0)  // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
   )
   xpm_cdc_sync_rst_inst (
      .dest_rst(rstn_sync), // 1-bit output: src_rst synchronized to the destination clock domain. This output
                           // is registered.

      .dest_clk(clk), // 1-bit input: Destination clock.
      .src_rst(rstn_aysnc)    // 1-bit input: Source reset signal.
   );

    
// 因为要测频谱, 使用正向FFT        pad    scale-sch                 forw/inw
wire [15:0] s_axis_config_tdata = {1'b0, 14'b01_10_10_10_10_10_11, 1'b1};
wire s_axis_config_tvalid = 1'b1;
wire s_axis_config_tready [CHANNEL_NUMBER-1:0];

// debug接口, 只有仿真时使用, 调好后, 实际模块内不需要依据这四个信号来决定其他信号的值
wire [CHANNEL_NUMBER-1:0] event_frame_started;
wire [CHANNEL_NUMBER-1:0] event_tlast_unexpected;
wire [CHANNEL_NUMBER-1:0] event_tlast_missing;
wire [CHANNEL_NUMBER-1:0] event_data_in_channel_halt;

// FFT输入端
wire s_axis_data_tready [CHANNEL_NUMBER-1:0];
wire [31:0] s_axis_data_tdata[CHANNEL_NUMBER-1:0];  //[29:16]: q ; [13:0]: i
wire s_axis_data_tvalid [CHANNEL_NUMBER-1:0];
wire s_axis_data_tlast[CHANNEL_NUMBER-1:0] ;

fft_in #(
    .CHANNEL_NUMBER ( CHANNEL_NUMBER ),
    .AD_DATA_WIDTH  ( AD_DATA_WIDTH  ),
    .FFT_POINT      ( FFT_POINT      ))
 u_fft_in (
    .clk                 ( clk                  ),
    .rstn_sync           ( rstn_sync            ),
    .ad_q                ( ad_q                 ),
    .ad_i                ( ad_i                 ),
    .s_axis_data_tready  ( s_axis_data_tready   ),

    .s_axis_data_tdata   ( s_axis_data_tdata    ),
    .s_axis_data_tvalid  ( s_axis_data_tvalid   ),
    .s_axis_data_tlast   ( s_axis_data_tlast    )
);



// FFT输出端
wire [31:0] m_axis_data_tdata[CHANNEL_NUMBER-1:0];  //[59:32]: q ; [27:0]: i
wire m_axis_data_tvalid[CHANNEL_NUMBER-1:0];
wire m_axis_data_tlast[CHANNEL_NUMBER-1:0];
wire [$clog2(FFT_POINT)-1:0] m_axis_data_tuser[CHANNEL_NUMBER-1:0];  //0~8191 
// 8192点unscaled bit-reversed order FFT
genvar s;
generate
    for(s = 0; s < CHANNEL_NUMBER; s = s + 1) begin
        xfft_0 xfft_0 (
            .aclk(clk),                                                 // input wire aclk
            .aresetn(rstn_sync),                                          // input wire aresetn
            .s_axis_config_tdata(s_axis_config_tdata),                  // input wire [7 : 0] s_axis_config_tdata
            .s_axis_config_tvalid(s_axis_config_tvalid),                // input wire s_axis_config_tvalid
            .s_axis_config_tready(s_axis_config_tready[s]),              // output wire s_axis_config_tready
            .s_axis_data_tdata(s_axis_data_tdata[s]),                    // input wire [31 : 0] s_axis_data_tdata
            .s_axis_data_tvalid(s_axis_data_tvalid[s]),                  // input wire s_axis_data_tvalid
            .s_axis_data_tready(s_axis_data_tready[s]),                  // output wire s_axis_data_tready
            .s_axis_data_tlast(s_axis_data_tlast[s]),                    // input wire s_axis_data_tlast
            .m_axis_data_tdata(m_axis_data_tdata[s]),                    // output wire [31 : 0] m_axis_data_tdata
            .m_axis_data_tvalid(m_axis_data_tvalid[s]),                  // output wire m_axis_data_tvalid
            .m_axis_data_tlast(m_axis_data_tlast[s]),                    // output wire m_axis_data_tlast
            .m_axis_data_tuser(m_axis_data_tuser[s]),                    // output wire [12 : 0] m_axis_data_tuser
            .event_frame_started(event_frame_started[s]),                // output wire event_frame_started
            .event_tlast_unexpected(event_tlast_unexpected[s]),          // output wire event_tlast_unexpected
            .event_tlast_missing(event_tlast_missing[s]),                // output wire event_tlast_missing
            .event_data_in_channel_halt(event_data_in_channel_halt[s])  //  output wire event_data_in_channel_halt
        );
    end
endgenerate
fft_out #(
    .CHANNEL_NUMBER ( CHANNEL_NUMBER ),
    .AD_DATA_WIDTH  ( AD_DATA_WIDTH  ),
    .FFT_POINT      ( FFT_POINT      ))
 u_fft_out (
    .clk                 ( clk                ),
    .timestamp_change    ( timestamp_change   ),
    .m_axis_data_tdata   ( m_axis_data_tdata   ),
    .m_axis_data_tvalid  ( m_axis_data_tvalid ),
    .m_axis_data_tlast   ( m_axis_data_tlast   ),
    .m_axis_data_tuser   ( m_axis_data_tuser[0]  ),
    .clk_dma             ( clk_dma            ),
    .ram_intr            ( ram_intr           ),
    .axis_s2mm_tready    ( axis_s2mm_tready   ),

    .axis_s2mm_tvalid    ( axis_s2mm_tvalid   ),
    .axis_s2mm_tkeep     ( axis_s2mm_tkeep    ),
    .axis_s2mm_tdata     ( axis_s2mm_tdata    ),
    .axis_s2mm_tlast     ( axis_s2mm_tlast    ),
    .reverse_sign_dma    ( reverse_sign_dma   )
);
endmodule