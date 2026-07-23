module bram #(
    parameter MEM_SIZE     = 16384,
    parameter FIRMWARE_HEX = "build/firmware.hex"
)(
    input             clk,
    input      [31:0] addr,
    input      [31:0] wdata,
    input      [ 3:0] wstrb,
    input             valid,
    output reg [31:0] rdata,
    output reg        ready
);

    localparam WORDS = MEM_SIZE / 4;
    localparam ABITS = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];

    initial $readmemh(FIRMWARE_HEX, mem);

    wire [ABITS-1:0] word_addr = addr[ABITS+1:2];

    always @(posedge clk) begin
        rdata <= mem[word_addr];
        if (valid) begin
            if (wstrb[0]) mem[word_addr][ 7: 0] <= wdata[ 7: 0];
            if (wstrb[1]) mem[word_addr][15: 8] <= wdata[15: 8];
            if (wstrb[2]) mem[word_addr][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[word_addr][31:24] <= wdata[31:24];
        end
    end

    always @(posedge clk)
        ready <= valid && !ready;

endmodule
