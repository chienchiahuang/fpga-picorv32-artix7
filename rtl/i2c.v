module i2c #(
    parameter CLK_FREQ = 100_000_000,
    parameter I2C_FREQ = 100_000
)(
    input             clk,
    input             resetn,
    input      [ 1:0] addr,
    input      [31:0] wdata,
    input      [ 3:0] wstrb,
    input             valid,
    output reg [31:0] rdata,
    output reg        ready,
    inout             sda,
    inout             scl
);

    // Bus period is split into 4 phases (setup / rise / hold / fall);
    // QUARTER system clocks elapse between each phase transition.
    localparam QUARTER = CLK_FREQ / (I2C_FREQ * 4);

    localparam CMD_START = 0;
    localparam CMD_STOP  = 1;
    localparam CMD_WR    = 2;
    localparam CMD_RD    = 3;
    localparam CMD_NACK  = 4;

    localparam SEQ_IDLE  = 3'd0;
    localparam SEQ_START = 3'd1;
    localparam SEQ_XFER  = 3'd2;
    localparam SEQ_ACK   = 3'd3;
    localparam SEQ_STOP  = 3'd4;

    reg        sda_oe, scl_oe;
    assign sda = sda_oe ? 1'b0 : 1'bz;
    assign scl = scl_oe ? 1'b0 : 1'bz;
    wire   sda_i = sda;

    reg        busy;
    reg        ack_error;
    reg [7:0]  tx_data;
    reg [7:0]  rx_data;

    reg        cmd_wr, cmd_rd, cmd_stop, cmd_nack;

    reg [2:0]  seq;
    reg [1:0]  phase;
    reg [31:0] tick;
    reg [2:0]  bitcnt;
    reg [7:0]  shift;

    wire tick_done = (tick == QUARTER - 1);

    always @(posedge clk) begin
        ready <= 0;

        if (!resetn) begin
            busy      <= 0;
            ack_error <= 0;
            sda_oe    <= 0;
            scl_oe    <= 0;
            seq       <= SEQ_IDLE;
            tick      <= 0;
            phase     <= 0;
            tx_data   <= 0;
        end else begin

            // -------------------------------------------------------
            // Register interface
            //   +0x00  CTRL     W: {NACK, RD, WR, STOP, START} command bits
            //   +0x04  TXDATA   W: byte to send on next WR
            //   +0x08  RXDATA   R: byte received by last RD
            //   +0x0C  STATUS   R: {ack_error, busy}
            // -------------------------------------------------------
            if (valid && !ready) begin
                ready <= 1;
                case (addr)
                    2'b00: begin
                        rdata <= 32'h0;
                        if (|wstrb && !busy) begin
                            cmd_wr   <= wdata[CMD_WR];
                            cmd_rd   <= wdata[CMD_RD];
                            cmd_stop <= wdata[CMD_STOP];
                            cmd_nack <= wdata[CMD_NACK];
                            busy     <= 1;
                            seq      <= wdata[CMD_START] ? SEQ_START : SEQ_XFER;
                            phase    <= 0;
                            tick     <= 0;
                            bitcnt   <= 7;
                            shift    <= tx_data;
                        end
                    end
                    2'b01: begin
                        rdata <= {24'b0, tx_data};
                        if (|wstrb)
                            tx_data <= wdata[7:0];
                    end
                    2'b10: rdata <= {24'b0, rx_data};
                    2'b11: rdata <= {30'b0, ack_error, busy};
                    default: rdata <= 32'h0;
                endcase
            end

            // -------------------------------------------------------
            // I2C sequencer — advances one phase every QUARTER clocks
            // -------------------------------------------------------
            if (busy) begin
                if (!tick_done) begin
                    tick <= tick + 1;
                end else begin
                    tick <= 0;

                    case (seq)
                        SEQ_START: begin
                            case (phase)
                                0: begin sda_oe <= 0; scl_oe <= 0; phase <= 1; end
                                1: begin sda_oe <= 1;               phase <= 2; end // SDA falls, SCL high -> START
                                2: begin
                                    scl_oe <= 1; // SCL falls
                                    phase  <= 0;
                                    bitcnt <= 7;
                                    shift  <= tx_data;
                                    seq    <= (cmd_wr || cmd_rd) ? SEQ_XFER :
                                              (cmd_stop ? SEQ_STOP : SEQ_IDLE);
                                end
                                default: phase <= 0;
                            endcase
                        end

                        SEQ_XFER: begin
                            case (phase)
                                0: begin sda_oe <= cmd_rd ? 1'b0 : ~shift[7]; phase <= 1; end
                                1: begin scl_oe <= 0;                        phase <= 2; end // SCL rises
                                2: begin
                                    if (cmd_rd)
                                        shift <= {shift[6:0], sda_i};
                                    phase <= 3;
                                end
                                3: begin
                                    scl_oe <= 1; // SCL falls
                                    if (!cmd_rd)
                                        shift <= {shift[6:0], 1'b0};
                                    if (bitcnt == 0) begin
                                        seq   <= SEQ_ACK;
                                        phase <= 0;
                                    end else begin
                                        bitcnt <= bitcnt - 1;
                                        phase  <= 0;
                                    end
                                end
                            endcase
                        end

                        SEQ_ACK: begin
                            case (phase)
                                0: begin
                                    // WR: release SDA for the slave's ACK. RD: drive ACK/NACK ourselves
                                    // -- ACK means SDA driven low, so cmd_nack=0 (ACK) needs sda_oe=1.
                                    sda_oe <= cmd_rd ? ~cmd_nack : 1'b0;
                                    phase  <= 1;
                                end
                                1: begin scl_oe <= 0; phase <= 2; end // SCL rises
                                2: begin
                                    if (cmd_rd)
                                        rx_data   <= shift;
                                    else
                                        ack_error <= sda_i; // 1 = slave NACKed
                                    phase <= 3;
                                end
                                3: begin
                                    scl_oe <= 1; // SCL falls
                                    seq    <= cmd_stop ? SEQ_STOP : SEQ_IDLE;
                                    phase  <= 0;
                                end
                            endcase
                        end

                        SEQ_STOP: begin
                            case (phase)
                                0: begin sda_oe <= 1; phase <= 1; end // ensure SDA low
                                1: begin scl_oe <= 0; phase <= 2; end // SCL released -> rises
                                2: begin sda_oe <= 0; phase <= 3; end // SDA released, SCL high -> STOP
                                3: begin seq <= SEQ_IDLE; phase <= 0; end
                            endcase
                        end

                        SEQ_IDLE: busy <= 0;

                        default: seq <= SEQ_IDLE;
                    endcase
                end
            end
        end
    end

endmodule
