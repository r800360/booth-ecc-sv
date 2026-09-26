// ecc12_formal.sv - rtl/ecc12_decoder.sv equals the closed-form specification for every input word and every
// start / reset pattern (the first cycle is a reset cycle):
//   P1  34 rising edges after an accepted start (the start edge counts): done and not busy; before that busy
//   P2  then err_weight  == (number of 1s != 6)
//            err_balance == (2S + W - 84 != 0),  S = sum of the indices of the 1s, W = number of 1s
//            corrected   == word with bit |2S + W - 84| / 2 flipped (when that is 1..12)
//            value       == (2 S6 + W6 - 25) / 2 over the low six bits of corrected (arithmetic shift)
// SINGLE = 1 restricts the inputs to one transaction: reset, then start in the next cycle, no further reset. A
// bounded check of 36 cycles then covers that transaction completely, for every word. Because an accepted start
// reloads every register the result depends on, and every output is rewritten before done, this covers every
// transaction in any start / reset pattern.
module ecc12_formal #(
  parameter bit SINGLE = 1'b0
) (
  input logic        clk,
  input logic        rst,
  input logic        start,
  input logic [11:0] word
);
  logic [11:0] corrected;
  logic [3:0]  value;
  logic        err_weight, err_balance, busy, done;
  ecc12_decoder dut (.clk, .rst, .start, .word, .corrected, .value, .err_weight, .err_balance, .busy, .done);

  logic        first = 1'b1, running = 1'b0;
  logic [5:0]  t;
  logic [11:0] w;
  always_ff @(posedge clk) begin
    first <= 1'b0;
    if (rst) running <= 1'b0;
    else if (start && !busy) begin running <= 1'b1; t <= 6'd1; w <= word; end
    else if (running && t != 6'd34) t <= t + 1'b1;
  end
  logic second = 1'b0;
  always_ff @(posedge clk) second <= first;
  always_comb begin
    if (first) assume (rst);
    if (SINGLE && second) assume (start && !rst);
    if (SINGLE && !first) assume (!rst);
  end

  // closed-form specification of the captured word
  function automatic logic [4:0] weight(input logic [11:0] x);
    weight = '0;
    for (int k = 0; k < 12; k++) weight = weight + 5'(x[k]);
  endfunction
  function automatic logic [7:0] isum(input logic [11:0] x);
    isum = '0;
    for (int k = 0; k < 12; k++) if (x[k]) isum = isum + 8'(k + 1);
  endfunction
  function automatic logic [5:0] isum6(input logic [11:0] x);
    isum6 = '0;
    for (int k = 0; k < 6; k++) if (x[k]) isum6 = isum6 + 6'(k + 1);
  endfunction
  function automatic logic [2:0] weight6(input logic [11:0] x);
    weight6 = '0;
    for (int k = 0; k < 6; k++) weight6 = weight6 + 3'(x[k]);
  endfunction
  logic signed [9:0] a2, a3;
  logic        [9:0] mag;
  logic        [3:0] j;
  logic       [11:0] fix;
  always_comb begin
    a2  = 10'(2 * isum(w)) + 10'(weight(w)) - 10'sd84;
    mag = a2[9] ? -a2 : a2;
    j   = mag[4:1];
    fix = w;
    if (j >= 4'd1 && j <= 4'd12) fix[j - 4'd1] = ~w[j - 4'd1];
    a3  = 10'(2 * isum6(fix)) + 10'(weight6(fix)) - 10'sd25;
  end

  always_comb begin
    if (!first) begin
      if (!running) assert (!busy && !done);
      else if (t != 6'd34) assert (busy && !done);
      else begin
        assert (!busy && done);
        assert (err_weight  == (weight(w) != 5'd6));
        assert (err_balance == (a2 != 10'sd0));
        assert (corrected   == fix);
        assert (value       == a3[4:1]);
      end
    end
  end
endmodule
