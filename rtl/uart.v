module uart #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input             clk,
    input             resetn,
    input      [ 1:0] addr,
    input      [31:0] wdata,
    input      [ 3:0] wstrb,
    input             valid,
    output reg [31:0] rdata,
    output reg        ready,
    output reg        uart_tx,
    input             uart_rx
);

    localparam CLKDIV = CLK_FREQ / BAUD;

    // -------------------------------------------------------
    // TX
    // -------------------------------------------------------
    reg [ 9:0] tx_shift;    // {stop, d7..d0, start}
    reg [ 3:0] tx_bitcnt;
    reg [15:0] tx_clkdiv;
    reg        tx_busy;

    always @(posedge clk) begin
        if (!resetn) begin
            tx_busy   <= 0;
            tx_shift  <= 10'h3ff;
            tx_bitcnt <= 0;
            tx_clkdiv <= 0;
            uart_tx   <= 1;
        end else if (tx_busy) begin
            if (tx_clkdiv == CLKDIV - 1) begin
                tx_clkdiv <= 0;
                uart_tx   <= tx_shift[0];
                tx_shift  <= {1'b1, tx_shift[9:1]};
                if (tx_bitcnt == 0)
                    tx_busy <= 0;
                else
                    tx_bitcnt <= tx_bitcnt - 1;
            end else begin
                tx_clkdiv <= tx_clkdiv + 1;
            end
        end else if (valid && |wstrb && addr == 2'b00) begin
            tx_shift  <= {1'b1, wdata[7:0], 1'b0};
            tx_bitcnt <= 9;
            tx_clkdiv <= 0;
            tx_busy   <= 1;
        end
    end

    // -------------------------------------------------------
    // RX
    // -------------------------------------------------------
    reg [ 1:0] rx_sync;
    reg [ 7:0] rx_shift;
    reg [ 3:0] rx_bitcnt;
    reg [15:0] rx_clkdiv;
    reg        rx_active;
    reg        rx_valid;
    reg [ 7:0] rx_data;

    wire rx_pin = rx_sync[1];

    always @(posedge clk) begin
        if (!resetn) begin
            rx_sync   <= 2'b11;
            rx_active <= 0;
            rx_valid  <= 0;
            rx_bitcnt <= 0;
            rx_clkdiv <= 0;
            rx_data   <= 0;
        end else begin
            rx_sync <= {rx_sync[0], uart_rx};

            if (!rx_active) begin
                if (!rx_pin) begin
                    rx_active <= 1;
                    rx_clkdiv <= CLKDIV / 2 - 1;
                    rx_bitcnt <= 9;
                end
            end else begin
                if (rx_clkdiv == CLKDIV - 1) begin
                    rx_clkdiv <= 0;
                    if (rx_bitcnt == 0) begin
                        rx_active <= 0;
                        if (rx_pin) begin
                            rx_valid <= 1;
                            rx_data  <= rx_shift;
                        end
                    end else begin
                        rx_shift  <= {rx_pin, rx_shift[7:1]};
                        rx_bitcnt <= rx_bitcnt - 1;
                    end
                end else begin
                    rx_clkdiv <= rx_clkdiv + 1;
                end
            end

            // Clear rx_valid when firmware reads it
            if (valid && !ready && addr == 2'b01 && wstrb == 4'b0)
                rx_valid <= 0;
        end
    end

    // -------------------------------------------------------
    // Register interface
    //   +0x00  TX_DATA   W: send byte
    //   +0x04  RX_DATA   R: received byte (clears rx_valid)
    //   +0x08  STATUS    R: {30'b0, rx_valid, tx_busy}
    // -------------------------------------------------------
    always @(posedge clk) begin
        ready <= 0;
        if (valid && !ready) begin
            ready <= 1;
            case (addr)
                2'b00: rdata <= 32'h0;
                2'b01: rdata <= {24'b0, rx_data};
                2'b10: rdata <= {30'b0, rx_valid, tx_busy};
                default: rdata <= 32'h0;
            endcase
        end
    end

endmodule
