# fft_simple_dma_transfer

A very simple demo to show how to use axi_dma and fft ipcore
The whole datapath is:
interleaved signal data -> RAM -> FFT -> RAM -> simple_dma_transfer -> PS -> draw FFT spectrum 

This design is for 
1.performance rather than resources
2.interleaved data that HAVE TO use parallel FFT
3.SimpleDmaTransfer function in bare-metal MPSOC

Any question is welcome
