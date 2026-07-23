module simple_soc #(
    parameter CLK_FREQ     = 100_000_000,
    parameter BAUD         = 115200,
    parameter MEM_SIZE     = 16384,
    parameter FIRMWARE_HEX = "build/firmware.hex"
)(
    input  clk,
    input  resetn,
    output [3:0] gpio,
    output uart_tx,
    input  uart_rx,
    inout        i2c_sda,
    inout        i2c_scl
);

    // --- PicoRV32 CPU signals ---
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [ 3:0] mem_wstrb;
    wire [31:0] mem_rdata;

    picorv32 #(
        .STACKADDR       (32'h0000_0000 + MEM_SIZE),
        .PROGADDR_RESET  (32'h0000_0000),
        .PROGADDR_IRQ    (32'h0000_0010),
        .BARREL_SHIFTER  (1),
        .COMPRESSED_ISA  (0),
        .ENABLE_COUNTERS (0),
        .ENABLE_MUL      (0),
        .ENABLE_DIV      (0),
        .ENABLE_IRQ      (0),
        .ENABLE_TRACE    (0),
        .CATCH_MISALIGN  (0),
        .CATCH_ILLINSN   (0)
    ) cpu (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),
        .irq       (32'b0)
    );

    // --- Address decode ---
    //   0x00000000 .. 0x00003FFF  BRAM (16 KB)
    //   0x10000000                GPIO
    //   0x20000000 .. 0x20000008  UART
    //   0x30000000 .. 0x3000000C  I2C
    wire sel_bram = mem_valid && (mem_addr[31:24] == 8'h00);
    wire sel_gpio = mem_valid && (mem_addr[31:24] == 8'h10);
    wire sel_uart = mem_valid && (mem_addr[31:24] == 8'h20);
    wire sel_i2c  = mem_valid && (mem_addr[31:24] == 8'h30);

    // --- BRAM ---
    wire [31:0] bram_rdata;
    wire        bram_ready;

    bram #(
        .MEM_SIZE     (MEM_SIZE),
        .FIRMWARE_HEX (FIRMWARE_HEX)
    ) mem_inst (
        .clk   (clk),
        .addr  (mem_addr),
        .wdata (mem_wdata),
        .wstrb (sel_bram ? mem_wstrb : 4'b0),
        .valid (sel_bram),
        .rdata (bram_rdata),
        .ready (bram_ready)
    );

    // --- GPIO ---
    wire [31:0] gpio_rdata;
    wire        gpio_ready;

    gpio gpio_inst (
        .clk    (clk),
        .resetn (resetn),
        .addr   (mem_addr[3:2]),
        .wdata  (mem_wdata),
        .wstrb  (sel_gpio ? mem_wstrb : 4'b0),
        .valid  (sel_gpio),
        .rdata  (gpio_rdata),
        .ready  (gpio_ready),
        .gpio_o (gpio)
    );

    // --- UART ---
    wire [31:0] uart_rdata;
    wire        uart_ready;

    uart #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (BAUD)
    ) uart_inst (
        .clk     (clk),
        .resetn  (resetn),
        .addr    (mem_addr[3:2]),
        .wdata   (mem_wdata),
        .wstrb   (sel_uart ? mem_wstrb : 4'b0),
        .valid   (sel_uart),
        .rdata   (uart_rdata),
        .ready   (uart_ready),
        .uart_tx (uart_tx),
        .uart_rx (uart_rx)
    );

    // --- I2C ---
    wire [31:0] i2c_rdata;
    wire        i2c_ready;

    i2c i2c_inst (
        .clk    (clk),
        .resetn (resetn),
        .addr   (mem_addr[3:2]),
        .wdata  (mem_wdata),
        .wstrb  (sel_i2c ? mem_wstrb : 4'b0),
        .valid  (sel_i2c),
        .rdata  (i2c_rdata),
        .ready  (i2c_ready),
        .sda    (i2c_sda),
        .scl    (i2c_scl)
    );

    // --- Bus mux ---
    assign mem_rdata = sel_bram ? bram_rdata :
                       sel_gpio ? gpio_rdata :
                       sel_uart ? uart_rdata :
                       sel_i2c  ? i2c_rdata  :
                       32'h0000_0000;

    assign mem_ready = bram_ready | gpio_ready | uart_ready | i2c_ready;

endmodule
