// tb_ecc12.sv - self-checking testbench for rtl/ecc12_decoder.sv.
//
// All 4096 input words are decoded through the ports and compared with a closed-form reference:
//   phase 1 counts the 1s:                              A1 = W                   (W = number of 1s)
//   phase 2, with c_i c_(i-1) - c_i' c_(i-1)' = c_i + c_(i-1) - 1:
//                                                       A2 = 7 + sum_{i=1..13} i (c_i + c_(i-1) - 1) = 2S + W - 84
//                                                       (S = sum of the indices of the 1s)
//   phase 3, over the low 6 bits of the corrected word: A3 = 2 S6 + W6 - 25
// so the reference is written from these sums, not from the bit-serial algorithm. On top of that the code's
// promises are checked semantically:
//   codewords: no error flag, word unchanged, value = v;  every single error: flagged and corrected, value = v;
//   every double and triple error: flagged;  four errors: a pattern goes undetected exactly when the received word
//   satisfies both invariants (weight 6, balanced) - either another codeword or one of the 48 balanced words that
//   are not codewords - and is then passed through unchanged.
// Timing: done exactly 34 rising edges after the start edge, busy until then, start ignored while busy.
`timescale 1ns/10ps
`include "tb_common.svh"

module tb_ecc12;
  logic clk = 1'b0, rst = 1'b0, start = 1'b0;
  logic [11:0] word = '0;
  logic [11:0] corrected;
  logic [3:0]  value;
  logic        err_weight, err_balance, busy, done;
  ecc12_decoder dut (.clk, .rst, .start, .word, .corrected, .value, .err_weight, .err_balance, .busy, .done);

  task automatic tick(); #1 clk = 1'b1; #1 clk = 1'b0; #1; endtask

  // ---------------------------------------------------------------- the code
  function automatic logic [11:0] codeword(input int v);     // v = -5..4
    case (v)
      -5: return 12'hE07; -4: return 12'hD0B; -3: return 12'hC93; -2: return 12'hC63; -1: return 12'hA65;
       0: return 12'h59A;  1: return 12'h39C;  2: return 12'h36C;  3: return 12'h2F4; default: return 12'h1F8;
    endcase
  endfunction
  function automatic int value_of(input logic [11:0] w);     // -5..4, or 99 if w is not a codeword
    int r; r = 99;
    for (int v = -5; v <= 4; v++) if (codeword(v) == w) r = v;
    return r;
  endfunction

  // ---------------------------------------------------------------- closed-form reference
  function automatic int wt(input logic [11:0] w, input int n);    // number of 1s in the low n bits
    int c; c = 0;
    for (int k = 0; k < n; k++) c += w[k];
    return c;
  endfunction
  function automatic int isum(input logic [11:0] w, input int n);  // sum of the indices (1-based) of those 1s
    int s; s = 0;
    for (int k = 0; k < n; k++) if (w[k]) s += k + 1;
    return s;
  endfunction
  logic [11:0] r_corr; logic [3:0] r_val; logic r_e1, r_e2;
  task automatic reference(input logic [11:0] w);
    int a2, mag, j, a3;
    r_e1 = (wt(w, 12) != 6);
    a2 = 2 * isum(w, 12) + wt(w, 12) - 84;
    r_e2 = (a2 != 0);
    mag = (a2 < 0) ? -a2 : a2;
    j = (mag >> 1) & 15;
    r_corr = w;
    if (j >= 1 && j <= 12) r_corr[j - 1] = ~w[j - 1];
    a3 = 2 * isum(r_corr, 6) + wt(r_corr, 6) - 25;
    r_val = 4'((a3 >>> 1) & 15);
  endtask

  // ---------------------------------------------------------------- one decode through the ports
  int e_timing;
  task automatic decode(input logic [11:0] w, input bit noise = 0);
    word = w; start = 1'b1;
    tick();
    start = 1'b0;
    for (int c = 1; c < 34; c++) begin
      if (busy !== 1'b1 || done !== 1'b0) e_timing++;
      if (noise) begin word = 12'(tb_rand()); start = tb_rand() & 1; end
      tick();
    end
    start = 1'b0;
    if (busy !== 1'b0 || done !== 1'b1) e_timing++;
  endtask

  logic [11:0] o_corr [4096];
  logic [3:0]  o_val  [4096];
  logic        o_e1 [4096], o_e2 [4096];
  int errs; string first;
  task automatic fail(input string m); errs++; if (errs == 1) first = m; endtask
  string msg;
  task automatic group(input string cat, input string name);
    if (errs != 0) msg = first;
    else msg = "done/busy timing wrong";
    `CHECK(cat, name, errs == 0 && e_timing == 0, msg)
    errs = 0; first = ""; e_timing = 0;
  endtask

  int n2, n3, n4, und4, und4_cw, und4_ok;
  initial begin
    errs = 0; e_timing = 0;
    rst = 1'b1; tick(); rst = 1'b0;
    if (busy !== 1'b0 || done !== 1'b0) fail("busy/done wrong after reset");

    // the code itself
    for (int v = -5; v <= 4; v++) begin
      logic [11:0] w; w = codeword(v);
      if (wt(w, 12) != 6 || isum(w, 12) != 39 || 2 * isum(w, 6) - 21 != 2 * v + 1 || value_of(~w) != -(v + 1))
        fail($sformatf("codeword %03h does not have the code properties", w));
      for (int k = 0; k < 12; k++) if (w[k] != w[11 - k]) fail($sformatf("codeword %03h is not mirror-symmetric", w));
      for (int u = -5; u < v; u++) if (wt(w ^ codeword(u), 12) < 4) fail("minimum distance below 4");
    end
    group("FUNC", "code: weight 6, balanced indices, value embedding, mirror symmetry, complement v -> -(v+1), distance >= 4");

    // every input word, compared with the closed-form reference
    for (int w = 0; w < 4096; w++) begin
      decode(12'(w));
      reference(12'(w));
      o_corr[w] = corrected; o_val[w] = value; o_e1[w] = err_weight; o_e2[w] = err_balance;
      if (corrected !== r_corr || value !== r_val || err_weight !== r_e1 || err_balance !== r_e2)
        fail($sformatf("word %03h: corrected %03h value %0d flags %b%b, reference %03h %0d %b%b", w, corrected,
                       value, err_weight, err_balance, r_corr, r_val, r_e1, r_e2));
    end
    group("FUNC", "all 4096 words match the closed-form reference; done exactly 34 edges after start");

    for (int v = -5; v <= 4; v++) begin
      int w; w = int'(codeword(v));
      if (o_e1[w] || o_e2[w] || o_corr[w] != codeword(v) || o_val[w] != 4'(v))
        fail($sformatf("codeword %03h (v = %0d) decoded as %03h, value %0d, flags %b%b", w, v, o_corr[w], o_val[w],
                       o_e1[w], o_e2[w]));
    end
    group("FUNC", "the 10 codewords: no error, unchanged, value -5..4");

    for (int v = -5; v <= 4; v++) for (int b = 0; b < 12; b++) begin
      int w; w = int'(codeword(v) ^ (12'h1 << b));
      if (!o_e1[w] || !o_e2[w] || o_corr[w] != codeword(v) || o_val[w] != 4'(v))
        fail($sformatf("codeword %0d with bit %0d flipped (%03h): corrected %03h, value %0d, flags %b%b", v, b + 1, w,
                       o_corr[w], o_val[w], o_e1[w], o_e2[w]));
    end
    group("FUNC", "all 120 single errors: detected, corrected, value recovered");

    n2 = 0; n3 = 0; n4 = 0; und4 = 0; und4_cw = 0; und4_ok = 1;
    for (int v = -5; v <= 4; v++)
      for (int p = 1; p < 4096; p++) begin
        int k, w;
        k = wt(12'(p), 12);
        w = int'(codeword(v) ^ 12'(p));
        if (k == 2) begin n2++; if (!o_e1[w] && !o_e2[w]) fail($sformatf("double error %03h undetected", w)); end
        if (k == 3) begin n3++; if (!o_e1[w] && !o_e2[w]) fail($sformatf("triple error %03h undetected", w)); end
        if (k == 4) begin
          n4++;
          // undetected <=> both invariants hold; then the word is passed through unchanged
          if ((!o_e1[w] && !o_e2[w]) != (wt(12'(w), 12) == 6 && isum(12'(w), 12) == 39)) und4_ok = 0;
          if (!o_e1[w] && !o_e2[w]) begin
            und4++;
            if (value_of(12'(w)) != 99) und4_cw++;
            if (o_corr[w] != 12'(w)) und4_ok = 0;
          end
        end
      end
    group("FUNC", $sformatf("all %0d double and %0d triple errors detected", n2, n3));
    if (und4 != 190 || und4_cw != 40 || !und4_ok)
      fail($sformatf("%0d undetected 4-bit patterns, %0d onto codewords (expected 190 and 40)", und4, und4_cw));
    group("FUNC", $sformatf({"4-bit errors: %0d of %0d undetected (%0d reach another codeword, %0d a balanced ",
                             "weight-6 non-codeword)"}, und4, n4, und4_cw, und4 - und4_cw));

    // robustness: start pulses and a changing input while busy are ignored; reset in the middle
    tb_rng_state = 32'd12;
    for (int i = 0; i < 300; i++) begin
      logic [11:0] w; w = 12'(tb_rand());
      decode(w, 1'b1);
      reference(w);
      if (corrected !== r_corr || value !== r_val || err_weight !== r_e1 || err_balance !== r_e2)
        fail($sformatf("word %03h decoded wrongly while the input changed", w));
    end
    group("ROBUST", "300 decodes with start pulses and a changing word while busy");
    for (int i = 0; i < 100; i++) begin
      logic [11:0] w;
      word = 12'(tb_rand()); start = 1'b1; tick(); start = 1'b0;
      repeat (tb_rand() % 34) tick();
      rst = 1'b1; tick(); rst = 1'b0;
      if (busy !== 1'b0 || done !== 1'b0) e_timing++;
      w = 12'(tb_rand());
      decode(w);
      reference(w);
      if (corrected !== r_corr || value !== r_val) fail($sformatf("word %03h wrong after a reset", w));
    end
    group("ROBUST", "reset in the middle of a decode, then a clean one");
    `REPORT
    $finish;
  end
endmodule
