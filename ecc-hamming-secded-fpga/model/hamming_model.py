#!/usr/bin/env python3
"""
Golden software model of the Hamming SECDED codes implemented in RTL.

Mirrors the RTL decision rule exactly (including its behaviour when the
syndrome points outside the codeword), so its fault-injection statistics can be
compared against the simulator logs. Generic in the data width k:
    k = 8  -> Hamming(13,8)    k = 64 -> Hamming(72,64)

Codeword layout used by the model: index 0 = overall parity bit,
indices 1..n_ham = classic Hamming positions (parity at powers of two).
"""
import itertools
import sys
from collections import Counter


class SecdedCode:
    def __init__(self, k):
        self.k = k
        r = 1
        while 2 ** r < k + r + 1:
            r += 1
        self.r = r
        self.n_ham = k + r                      # positions 1..n_ham
        self.n = self.n_ham + 1                 # + overall parity bit
        self.data_pos = [p for p in range(1, self.n_ham + 1) if p & (p - 1)]
        assert len(self.data_pos) == k

    def encode(self, data):
        c = [0] * (self.n_ham + 1)
        for i, p in enumerate(self.data_pos):
            c[p] = (data >> i) & 1
        for i in range(self.r):
            par = 0
            for p in self.data_pos:
                if p & (1 << i):
                    par ^= c[p]
            c[1 << i] = par
        c[0] = sum(c[1:]) & 1
        return c

    def syndrome(self, c):
        s = 0
        for p in range(1, self.n_ham + 1):
            if c[p]:
                s ^= p
        return s

    def decode(self, c):
        """Returns (data, sec, ded) exactly as the RTL decoder does."""
        c = list(c)
        syndrome = self.syndrome(c)
        overall = sum(c) & 1
        sec = ded = False
        if syndrome == 0 and overall == 0:
            pass
        elif syndrome == 0 and overall == 1:
            sec = True                          # error in overall-parity bit only
        elif syndrome != 0 and overall == 1:
            sec = True
            if syndrome <= self.n_ham:          # RTL: out-of-range index is a no-op
                c[syndrome] ^= 1
        else:
            ded = True
        data = 0
        for i, p in enumerate(self.data_pos):
            data |= c[p] << i
        return data, sec, ded

    def sweep(self, nflips, data):
        """Exhaustive sweep of every nflips-bit error pattern on one codeword."""
        base = self.encode(data)
        tally = Counter()
        invalid_syndrome = 0
        for bits in itertools.combinations(range(self.n), nflips):
            c = list(base)
            for b in bits:
                c[b] ^= 1
            out, sec, ded = self.decode(c)
            if ded:
                tally["detected"] += 1
            elif sec:
                tally["corrected_ok" if out == data else "miscorrected"] += 1
            else:
                tally["noflag_ok" if out == data else "noflag_wrong"] += 1
            if self.syndrome(c) > self.n_ham:
                invalid_syndrome += 1
        return tally, sum(tally.values()), invalid_syndrome


def main():
    for k, data in ((8, 0b10100110), (64, 0xDEADBEEF12345678)):
        code = SecdedCode(k)
        print(f"\nHamming({code.n},{k})  parity bits = {code.r}+1  "
              f"overhead = {100 * (code.n - k) / k:.1f}%")
        for nflips in (1, 2, 3):
            tally, total, inv = code.sweep(nflips, data)
            print(f"  {nflips}-bit errors, exhaustive over {total:>6} patterns: "
                  f"corrected_ok={tally['corrected_ok']:>6}  "
                  f"detected={tally['detected']:>6}  "
                  f"miscorrected={tally['miscorrected']:>6}  "
                  f"no-flag-wrong={tally['noflag_wrong']}  "
                  f"(syndrome out of range: {inv})")
            if nflips == 1:
                assert tally["corrected_ok"] == total, "1-bit errors must always be corrected"
            if nflips == 2:
                assert tally["detected"] == total, "2-bit errors must always be detected"
    return 0


if __name__ == "__main__":
    sys.exit(main())
