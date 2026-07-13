// Board-level top for Arty A7-35T
module top (
    input  clk,       // 100 MHz E3
    input  btn0,      // Reset button D9 (active-high)
    output [3:0] led, // LD4-LD7
    output uart_tx,   // D10
    input  uart_rx,   // A9
    inout        i2c_sda, // JA1
    inout        i2c_scl  // JA2
);

    // Power-on + button reset (active-low for PicoRV32)
    reg [7:0] reset_cnt = 0;
    wire resetn = &reset_cnt;

    always @(posedge clk) begin
        if (btn0)
            reset_cnt <= 0;
        else if (!resetn)
            reset_cnt <= reset_cnt + 1;
    end

    simple_soc #(
        .CLK_FREQ(100_000_000)
    ) soc (
        .clk     (clk),
        .resetn  (resetn),
        .gpio    (led),
        .uart_tx (uart_tx),
        .uart_rx (uart_rx),
        .i2c_sda (i2c_sda),
        .i2c_scl (i2c_scl)
    );

endmodule
