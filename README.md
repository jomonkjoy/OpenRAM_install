# OpenRAM + SKY130 — Usage Guide

Generate a custom SRAM macro (GDS, LEF, Verilog, LIB) from three parameters:
**word width**, **depth**, and **number of banks**.

---

## 1. Install

Run the installer once on a fresh Ubuntu 20.04 / 22.04 machine:

```bash
chmod +x install_openram.sh
./install_openram.sh
```

When it finishes, reload your shell:

```bash
source ~/.bashrc    # or: source ~/.zshrc
```

The installer sets up three environment variables you'll need:

```
OPENRAM_HOME  →  ~/OpenRAM/compiler
OPENRAM_TECH  →  ~/OpenRAM/technology
PYTHONPATH    →  includes both of the above
```

---

## 2. Project Layout

Copy the `my_sram_project/` folder anywhere you like and work from inside it:

```
my_sram_project/
├── sram_config.py   ← edit this to size your SRAM
├── run.sh           ← convenience wrapper to run the compiler
└── output/          ← generated files appear here after a run
    ├── sram_32x1024_1bank.gds
    ├── sram_32x1024_1bank.lef
    ├── sram_32x1024_1bank.v
    ├── sram_32x1024_1bank.lib
    └── sram_32x1024_1bank.sp
```

---

## 3. Configure Your SRAM

Open `sram_config.py` and change the three values at the top:

```python
word_size = 32      # Width  — bits per word
num_words = 1024    # Depth  — number of words (rows)
num_banks = 1       # Banks  — 1 or 2
```

That's all you need to touch for a standard single-port SRAM.

**Total memory size** = `word_size × num_words` bits

| word_size | num_words | num_banks | Total   |
|-----------|-----------|-----------|---------|
| 8         | 256       | 1         | 2 Kbit  |
| 16        | 512       | 1         | 8 Kbit  |
| 32        | 1024      | 1         | 32 Kbit |
| 32        | 1024      | 2         | 32 Kbit (split across 2 banks) |
| 64        | 2048      | 2         | 128 Kbit |

> The address bus width = `log₂(num_words)` bits.
> For 1024 words that is 10 address lines.

---

## 4. Run the Compiler

```bash
cd my_sram_project
./run.sh
```

Or call OpenRAM directly:

```bash
python3 $OPENRAM_HOME/openram.py sram_config.py
```

A successful run looks like this:

```
▶ Running OpenRAM with: sram_config.py

|================================================|
|  OpenRAM v2.x   Technology: sky130            |
|  Total size: 32768 bits   Word size: 32       |
|  Words: 1024              Banks: 1            |
|================================================|
Creating bitcell array ...     [OK]
Creating sense amps ...        [OK]
Creating write drivers ...     [OK]
Creating row decoder ...       [OK]
Writing GDS ...                [OK]
Writing LEF ...                [OK]
Writing Verilog ...            [OK]
Writing LIB ...                [OK]
Completed in 142 seconds.
```

Outputs land in the `output/` folder, named after your config values.

---

## 5. Output Files

| File | What it's for |
|------|---------------|
| `.gds` | Physical layout — DRC, LVS, tape-out |
| `.lef` | Abstract layout — place & route (P&R) |
| `.v`   | Verilog model — RTL simulation |
| `.lib` | Liberty timing file — synthesis |
| `.sp`  | SPICE netlist — analog/timing simulation |

---

## 6. Full Config Reference

`sram_config.py` accepts these parameters (everything except the three core
ones has a sensible default):

```python
# Core — change these
word_size = 32
num_words = 1024
num_banks = 1

# Ports
num_rw_ports = 1   # read-write ports (use 1 for single-port)
num_r_ports  = 0   # read-only ports
num_w_ports  = 0   # write-only ports

# Technology
tech_name = "sky130"

# PVT corners
process_corners = ["TT"]    # "TT" | "FF" | "SS"
supply_voltages = [1.8]     # volts
temperatures    = [25]      # celsius

# Output
output_path = "output"
output_name = f"sram_{word_size}x{num_words}_{num_banks}bank"

# Speed vs accuracy
analytical_delay    = True  # False = full SPICE (slow, accurate)
nominal_corner_only = True  # False = simulate all corners (slow)
```

To run all PVT corners for final sign-off:

```python
process_corners    = ["TT", "FF", "SS"]
supply_voltages    = [1.6, 1.8, 2.0]
temperatures       = [0, 25, 85]
analytical_delay   = False
nominal_corner_only= False
```

---

## 7. Troubleshooting

**`OPENRAM_HOME is not set`**
```bash
source ~/.bashrc
```

**`sky130.lib.spice not found`**
The PDK was not fully installed. Go to the OpenRAM source and re-run:
```bash
cd ~/OpenRAM && make pdk && make install
```

**Compile takes too long**
Keep `analytical_delay = True` and `nominal_corner_only = True` during
exploration. Only switch to full SPICE for the final sign-off run.

**Running on macOS or Windows**
Use Docker:
```bash
docker pull vlsida/openram-ubuntu:latest
docker run \
  -v ~/OpenRAM:/openram \
  -v $(pwd):/project \
  -e OPENRAM_HOME=/openram/compiler \
  -e OPENRAM_TECH=/openram/technology \
  vlsida/openram-ubuntu:latest \
  python3 /openram/compiler/openram.py /project/sram_config.py
```
