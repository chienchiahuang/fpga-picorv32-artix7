module gpio (
    input             clk,
    input             resetn,
    input      [ 1:0] addr,
    input      [31:0] wdata,
    input      [ 3:0] wstrb,
    input             valid,
    output reg [31:0] rdata,
    output reg        ready,
    output reg [ 3:0] gpio_o
);

    always @(posedge clk) begin
        ready <= 0;
        if (!resetn) begin
            gpio_o <= 4'b0;
        end else if (valid && !ready) begin
            ready <= 1;
            if (|wstrb)
                gpio_o <= wdata[3:0];
            rdata <= {28'b0, gpio_o};
        end
    end

endmodule
