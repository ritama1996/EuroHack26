#!/usr/bin/env python3
"""Build paste-ready master-table rows and an overlaid speedup plot from the
combined CSV written by run_all_scaling.sh."""
import sys, csv
from collections import defaultdict, OrderedDict

comb = sys.argv[1]
table_out = sys.argv[2] if len(sys.argv) > 2 else "master_table_rows.tsv"
plot_out = sys.argv[3] if len(sys.argv) > 3 else "all_systems_speedup.png"

# data[system] = {threads: total_s}, plus molecule/basis
data = OrderedDict(); meta = {}
allthreads = set()
with open(comb) as f:
    for row in csv.DictReader(f):
        s = row["system"]; t = int(row["threads"]); tot = float(row["total_s"].replace(",", "."))
        data.setdefault(s, {}); data[s][t] = tot
        meta[s] = (row["molecule"], row["basis"])
        allthreads.add(t)
threads = sorted(allthreads)

# master-table rows: molecule, basis, time at each thread count
with open(table_out, "w") as f:
    f.write("molecule\tbasis\t" + "\t".join(f"t{t}" for t in threads) + "\n")
    for s, d in data.items():
        mol, bas = meta[s]
        cells = [f"{d[t]:.2f}" if t in d else "" for t in threads]
        f.write(f"{mol}\t{bas}\t" + "\t".join(cells) + "\n")

# overlaid speedup plot (one line per system, anchored to its own 1-thread time)
try:
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(7, 5))
    for s, d in data.items():
        ts = sorted(d)
        if 1 not in d:  # need a 1-thread anchor for speedup
            continue
        sp = [d[1] / d[t] for t in ts]
        mol, bas = meta[s]
        ax.plot(ts, sp, "o-", label=f"{mol} {bas}".strip())
    if threads:
        ax.plot(threads, threads, "k--", alpha=0.5, label="Ideal (linear)")
    ax.set_xlabel("Threads"); ax.set_ylabel("Speedup")
    ax.set_title("Strong scaling across systems"); ax.legend(fontsize=8); ax.grid(True, alpha=0.3)
    fig.tight_layout(); fig.savefig(plot_out, dpi=130)
    print(f"wrote {plot_out}")
except Exception as e:
    print(f"(plot skipped: {e})")
