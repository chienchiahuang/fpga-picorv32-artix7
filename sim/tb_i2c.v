`timescale 1ns/1ps

// Self-checking testbench for rtl/i2c.v. Drives the register interface like
// firmware would and checks the resulting bus transactions against a small
// bit-banged I2C slave BFM (ACKs address 0x50; on write captures the byte;
// on read returns 0xA5 then 0x5A on successive reads).
module tb_i2c;

    reg clk = 0;
    reg resetn = 0;
    reg [1:0] addr;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg valid;
    wire [31:0] rdata;
    wire ready;

    wire sda, scl;
    pullup(sda);
    pullup(scl);

    always #5 clk = ~clk; // 100 MHz

    i2c #(
        .CLK_FREQ(100_000_000),
        .I2C_FREQ(1_000_000)   // fast divider so the sim finishes quickly
    ) dut (
        .clk(clk), .resetn(resetn),
        .addr(addr), .wdata(wdata), .wstrb(wstrb), .valid(valid),
        .rdata(rdata), .ready(ready),
        .sda(sda), .scl(scl)
    );

    // -------------------------------------------------------------
    // Minimal I2C slave BFM
    // -------------------------------------------------------------
    reg [7:0] slave_shift;
    reg [7:0] slave_rxbyte;
    reg [7:0] slave_txbyte;
    integer   read_count;

    reg sda_drv;
    assign sda = sda_drv ? 1'b0 : 1'bz;

    initial begin
        sda_drv = 0;
        read_count = 0;
        slave_txbyte = 8'hA5;
    end

    reg [3:0] sstate;
    localparam S_ADDR=0, S_ADDR_ACK=1, S_DATA_W=2, S_DATA_W_ACK=3,
               S_DATA_R=4, S_DATA_R_ACK=5, S_WAIT=6, S_START_SEEN=7;
    reg [2:0] bitpos;
    reg       have_addr_dir; // 0 = write, 1 = read
    reg       master_ack;    // sampled ack/nack bit the master drives during a read

    always @(negedge sda) if (scl === 1'b1 && resetn) begin
        sstate      <= S_START_SEEN;
        slave_shift <= 8'h0;
    end

    always @(posedge sda) if (scl === 1'b1 && resetn) begin
        sstate <= S_WAIT; // STOP condition
    end

    always @(posedge scl) begin
        if (sstate == S_ADDR || sstate == S_DATA_W)
            slave_shift <= {slave_shift[6:0], sda};
        else if (sstate == S_DATA_R_ACK)
            master_ack <= sda; // 0 = ACK (continue), 1 = NACK (stop)
    end

    always @(negedge scl) begin
        case (sstate)
            S_START_SEEN: begin
                // This negedge just ends the START condition itself (no bit
                // transmitted yet) -- don't consume it as a data-bit clock.
                sstate <= S_ADDR;
                bitpos <= 7;
            end
            S_ADDR: begin
                if (bitpos == 0) begin
                    have_addr_dir <= slave_shift[0];
                    if (slave_shift[7:1] == 7'h50) begin
                        sda_drv <= 1; // ACK
                        sstate  <= S_ADDR_ACK;
                    end else begin
                        sstate <= S_WAIT;
                    end
                end else begin
                    bitpos <= bitpos - 1;
                end
            end
            S_ADDR_ACK: begin
                if (have_addr_dir) begin
                    slave_txbyte <= (read_count == 0) ? 8'hA5 : 8'h5A;
                    read_count   <= read_count + 1;
                    // Drive bit7 immediately -- this same negedge is the
                    // start of bit7's low phase, there's no further edge
                    // before the master samples it.
                    // bit7 of 0xA5 (1010_0101) = 1, of 0x5A (0101_1010) = 0
                    sda_drv <= (read_count == 0) ? 1'b0 : 1'b1;
                    sstate  <= S_DATA_R;
                    bitpos  <= 7;
                end else begin
                    sda_drv <= 0;
                    sstate  <= S_DATA_W;
                    bitpos  <= 7;
                end
            end
            S_DATA_W: begin
                if (bitpos == 0) begin
                    slave_rxbyte <= slave_shift;
                    sda_drv <= 1; // ACK
                    sstate  <= S_DATA_W_ACK;
                end else begin
                    bitpos <= bitpos - 1;
                end
            end
            S_DATA_W_ACK: begin
                sda_drv <= 0;
                sstate  <= S_WAIT;
            end
            S_DATA_R: begin
                // This negedge ends the bit at the OLD bitpos and starts the
                // next one; set up that next bit's value in this same event.
                if (bitpos == 0) begin
                    sda_drv <= 0; // release for master's ack/nack
                    sstate  <= S_DATA_R_ACK;
                end else begin
                    bitpos  <= bitpos - 1;
                    sda_drv <= ~slave_txbyte[bitpos - 1];
                end
            end
            S_DATA_R_ACK: begin
                // By this negedge, the posedge-scl handler above has already
                // sampled the master's real ack/nack bit into master_ack --
                // this is what actually catches ack/nack polarity bugs,
                // unlike blindly assuming the master always wants more data.
                if (master_ack) begin
                    // NACK: master doesn't want more data.
                    sda_drv <= 0;
                    sstate  <= S_WAIT;
                end else begin
                    // ACK: continue: pre-drive the next byte's bit7
                    // immediately, same reasoning as after S_ADDR_ACK.
                    slave_txbyte <= (read_count == 0) ? 8'hA5 : 8'h5A;
                    read_count   <= read_count + 1;
                    sda_drv      <= (read_count == 0) ? 1'b0 : 1'b1;
                    sstate       <= S_DATA_R;
                    bitpos       <= 7;
                end
            end
            default: ;
        endcase
    end

    // -------------------------------------------------------------
    // Register-interface helper tasks
    // -------------------------------------------------------------
    task automatic reg_write(input [1:0] a, input [31:0] d);
        begin
            @(posedge clk);
            addr  = a; wdata = d; wstrb = 4'hF; valid = 1;
            @(posedge clk);
            while (!ready) @(posedge clk);
            valid = 0; wstrb = 0;
            @(posedge clk);
        end
    endtask

    task automatic reg_read(input [1:0] a, output [31:0] d);
        begin
            @(posedge clk);
            addr = a; wstrb = 0; valid = 1;
            @(posedge clk);
            while (!ready) @(posedge clk);
            d = rdata;
            valid = 0;
            @(posedge clk);
        end
    endtask

    task automatic wait_idle;
        reg [31:0] st;
        begin
            st = 32'h1;
            while (st[0]) reg_read(2'b11, st);
        end
    endtask

    localparam CTRL_START = 32'h1;
    localparam CTRL_STOP  = 32'h2;
    localparam CTRL_WR    = 32'h4;
    localparam CTRL_RD    = 32'h8;
    localparam CTRL_NACK  = 32'h10;

    reg [31:0] status, rxbyte;
    integer errors = 0;

    initial begin
        addr = 0; wdata = 0; wstrb = 0; valid = 0;
        sstate = S_WAIT;
        #100;
        resetn = 1;
        #100;

        // --- Write transaction: START, addr(W), data byte, STOP ---
        reg_write(2'b01, 8'h50 << 1);           // TXDATA = addr<<1 | W
        reg_write(2'b00, CTRL_START | CTRL_WR);
        wait_idle;
        reg_read(2'b11, status);
        if (status[1]) begin errors = errors + 1; $display("FAIL: addr write NACKed unexpectedly"); end

        reg_write(2'b01, 8'h3C);                // data byte
        reg_write(2'b00, CTRL_WR | CTRL_STOP);
        wait_idle;
        reg_read(2'b11, status);
        if (status[1]) begin errors = errors + 1; $display("FAIL: data byte NACKed unexpectedly"); end
        if (slave_rxbyte !== 8'h3C) begin errors = errors + 1; $display("FAIL: slave got %h, expected 3C", slave_rxbyte); end
        else $display("PASS: slave received 0x%h", slave_rxbyte);

        #1000;

        // --- Read transaction: START, addr(R), RD (ack), RD (nack+stop) ---
        reg_write(2'b01, (8'h50 << 1) | 1);     // TXDATA = addr<<1 | R
        reg_write(2'b00, CTRL_START | CTRL_WR);
        wait_idle;
        reg_read(2'b11, status);
        if (status[1]) begin errors = errors + 1; $display("FAIL: addr read NACKed unexpectedly"); end

        reg_write(2'b00, CTRL_RD);              // ACK after this byte (more to come)
        wait_idle;
        reg_read(2'b10, rxbyte);
        if (rxbyte[7:0] !== 8'hA5) begin errors = errors + 1; $display("FAIL: first read byte = %h, expected A5", rxbyte[7:0]); end
        else $display("PASS: first read byte = 0x%h", rxbyte[7:0]);

        reg_write(2'b00, CTRL_RD | CTRL_NACK | CTRL_STOP); // NACK final byte + STOP
        wait_idle;
        reg_read(2'b10, rxbyte);
        if (rxbyte[7:0] !== 8'h5A) begin errors = errors + 1; $display("FAIL: second read byte = %h, expected 5A", rxbyte[7:0]); end
        else $display("PASS: second read byte = 0x%h", rxbyte[7:0]);

        #1000;

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

    initial begin
        $dumpfile("tb_i2c.vcd");
        $dumpvars(0, tb_i2c);
    end

    initial begin
        #2_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
