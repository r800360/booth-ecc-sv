// ecc12_decoder.sv - sequential decoder for a 12-bit constant-weight code, built on a Booth-multiplier datapath.
//
// The code has ten codewords, for the values -5..4. Every codeword has
//   (1) exactly six 1s, and
//   (2) balanced indices: the indices (1..12, LSB = 1) of its 1s and of its 0s both sum to 39,
// and the low six bits embed the value: sum of indices of 1s - sum of indices of 0s over bits 1..6 = 2v + 1.
// The minimum distance is 4: every single error is corrected, and every double and triple error is detected.
//
// Like Booth's algorithm, the datapath scans bit pairs (c_i, c_(i-1)) from the LSB (c_0 = 0, and a 0 is appended at
// index 13), but it adds or subtracts the *index* i instead of the multiplicand, and never shifts the accumulator:
//   phase 1   A = 0, 13 steps, 01: A += i, 10: A -= i           -> A = number of 1s (each run of 1s adds its length)
//   phase 2   A = 7, 13 steps, 11: A += i, 00: A -= i           -> A = 0 for a codeword; a single error in bit j
//                                                                  gives A = +-(2j + 1), so j = |A| / 2
//   phase 3   A = 3, 7 steps over the low 6 bits of the corrected word (bit 7 read as 0), same rule as phase 2
//                                                                  -> A = 2v, so value = A / 2
// err_weight = (phase-1 result != 6), err_balance = (phase-2 result != 0); corrected = word with bit |A2|/2 flipped.
// For a double or triple error the "corrected" word is not a codeword; the error flags report it.
// Latency: done is high 1 + 13 + 13 + 7 = 34 rising edges after the start edge (counting the start edge).
module ecc12_decoder (
  input  logic        clk,
  input  logic        rst,            // synchronous: idle
  input  logic        start,          // ignored while busy
  input  logic [11:0] word,
  output logic [11:0] corrected,      // valid while done = 1
  output logic [3:0]  value,          // embedded value, two's complement (-5..4 for a correctable word)
  output logic        err_weight,     // not six 1s
  output logic        err_balance,    // index sums not balanced
  output logic        busy,
  output logic        done
);
  typedef enum logic [1:0] { IDLE, WEIGHT, BALANCE, VALUE } phase_t;
  phase_t      phase;
  logic [12:0] a;        // accumulator, 13-bit two's complement
  logic [12:0] m;        // bits still to scan, LSB first
  logic        f;        // previous bit c_(i-1)
  logic [3:0]  idx;      // i = 1..13
  logic [11:0] w;        // the word being decoded

  // one step: Booth-style recoding of (c_i, c_(i-1)), then A +- i
  logic        add, sub, last;
  logic [12:0] a_next;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [12:0] mag;      // |A2|; only bits 4:1 (= |A2| / 2 for |A2| < 32) are used
  /* verilator lint_on UNUSEDSIGNAL */
  logic [3:0]  j;
  logic [11:0] fixed;
  always_comb begin
    // (c_i, c_(i-1)) = (m[0], f)
    if (phase == WEIGHT) begin add = (!m[0] &&  f); sub = ( m[0] && !f); end   // 01: +i, 10: -i
    else                 begin add = ( m[0] &&  f); sub = (!m[0] && !f); end   // 11: +i, 00: -i
    a_next = add ? a + 13'(idx) : sub ? a - 13'(idx) : a;
    last   = (phase == VALUE) ? (idx == 4'd7) : (idx == 4'd13);
    // correction from the phase-2 result: flip bit j = |A| / 2 (j = 1..12; 0, 13..15 flip nothing visible)
    mag    = a_next[12] ? -a_next : a_next;
    j      = mag[4:1];
    fixed  = w;
    if (j >= 4'd1 && j <= 4'd12) fixed[j - 4'd1] = ~w[j - 4'd1];
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      phase <= IDLE; busy <= 1'b0; done <= 1'b0;
      a <= '0; m <= '0; f <= 1'b0; idx <= '0; w <= '0;
      corrected <= '0; value <= '0; err_weight <= 1'b0; err_balance <= 1'b0;
    end else if (start && !busy) begin
      phase <= WEIGHT; busy <= 1'b1; done <= 1'b0;
      w <= word; m <= {1'b0, word}; a <= '0; f <= 1'b0; idx <= 4'd1;
    end else if (busy) begin
      a <= a_next; m <= m >> 1; f <= m[0]; idx <= idx + 1'b1;
      if (last) begin
        f <= 1'b0; idx <= 4'd1;
        case (phase)
          WEIGHT: begin
            err_weight <= (a_next != 13'd6);
            phase <= BALANCE; m <= {1'b0, w}; a <= 13'd7;
          end
          BALANCE: begin
            err_balance <= (a_next != 13'd0);
            corrected <= fixed;
            phase <= VALUE; m <= {7'b0, fixed[5:0]}; a <= 13'd3;
          end
          default: begin
            value <= a_next[4:1];
            phase <= IDLE; busy <= 1'b0; done <= 1'b1;
          end
        endcase
      end
    end
  end
endmodule
