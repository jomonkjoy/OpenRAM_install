# =============================================================================
#  sram_config.py
#  OpenRAM configuration for SkyWater SKY130
#
#  Edit the three values under "CONFIGURE YOUR SRAM" then run:
#    python3 $OPENRAM_HOME/openram.py sram_config.py
# =============================================================================


# ─── CONFIGURE YOUR SRAM ─────────────────────────────────────────────────────

word_size = 32      # Width  — bits per word        (e.g. 8, 16, 32, 64)
words_per_row = 4   #
num_words = 1024    # Depth  — number of words/rows  (e.g. 256, 512, 1024, 2048)
num_banks = 1       # Banks  — physical banks        (1 or 2)

# ─────────────────────────────────────────────────────────────────────────────


# Port type  (single-port RW is the most common choice)
num_rw_ports = 1    # Read-Write ports
num_r_ports  = 0    # Read-only ports
num_w_ports  = 0    # Write-only ports

# Technology
tech_name = "freepdk45"

# PVT corner  — start with TT/1.8V/25°C for fast iteration
process_corners = ["TT"]   # TT = typical  |  FF = fast  |  SS = slow
supply_voltages = [1.8]    # Volts  (SKY130 nominal = 1.8 V)
temperatures    = [25]     # Celsius

# Output
output_path = "output"
output_name = f"sram_{word_size}x{num_words}_{num_banks}bank"

# Speed vs accuracy
# True  → fast analytical model  (use during design exploration)
# False → full SPICE simulation  (use for final sign-off)
analytical_delay    = True
nominal_corner_only = True
