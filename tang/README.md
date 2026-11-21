
## Tang Nano 20K CLI

In Ubuntu, run these commands from the project root (the directory containing `blink.v`).
Install the command with `cargo install --path tang --locked`.
The OSS CAD Suite tools must be on your PATH. On Windows, share the Tang once with
`usbipd bind --busid <BUSID>` from an administrator PowerShell. After a replug,
`tang run` and `tang load` reconnect the shared USB programmer to WSL automatically.
If multiple FTDI adapters with ID `0403:6010` are connected, use
`usbipd attach --wsl --busid <BUSID>` in PowerShell to select the Tang.

In this project, keep `uv` on your WSL PATH. Both `tang build` and `tang run`
use it to run the packer from the project's locked Python environment.

```sh
tang check blink.v    # Check syntax and module connections with Icarus Verilog
tang run blink.v      # Build build/blink.fs and load it into SRAM
tang build blink.v    # Build only
tang load blink.fs    # Loads build/blink.fs when present
```

The default top module is `top`. The first source file determines the output name.
For example, `blink.v` produces `build/blink.fs`. Designs share `tang/pins/nano20k.cst`.
Each build reads the nearest project map above the main source directory or in it.
Edits to that map take effect on the next build. Outside the project the CLI uses its bundled copy.

| Top-level port | Board connection | FPGA pin |
| --- | --- | --- |
| `clk` | 27 MHz oscillator | 4 |
| `led_n` | LED0, low lights it | 15 |
| `led_n[0]` through `led_n[5]` | LED0 through LED5, low lights each one | 15 through 20, respectively |
| `rgb_data` | WS2812 RGB LED serial data | 79 |
| `l_btn` | S1, high when pressed | 88 |
| `r_btn` | S2, high when pressed | 87 |

Left and right are from the component side with USB-C at the top. Each design
declares only the ports it uses. [Sipeed schematic](https://dl.sipeed.com/fileList/TANG/Nano_20K/2_Schematic/Tang_Nano_20K_3921_Schematics.pdf)

To drive the row together, declare `output wire [5:0] led_n`. For example,
`assign led_n = {6{~(l_btn & r_btn)}};` drives all six LEDs low when both buttons are pressed.

A matching file such as `blink.cst` takes precedence, and `--cst` overrides both defaults.
To load a specific bitstream, give its path, for example `tang load ./other.fs`.
For multiple source files or a different pin file, use
`tang run main.v counter.v --top my_top --cst board.cst`.
If Ubuntu requires USB permission, the CLI retries the loader with `sudo`.
Power-cycling the board restores the design in flash.

## Manual commands

Create the output directory once with `mkdir -p build/manual`.

check verilog for errors:

`iverilog -Wall -tnull -s top [FILENAME].v`

synthesis

`yosys -p "read_verilog [FILENAME].v; synth_gowin -top top -json build/manual/[FILENAME].json"`

place and route:
```
nextpnr-himbaechel --device GW2AR-LV18QN88C8/I7 \
  --vopt family=GW2A-18C --vopt cst=tang/pins/nano20k.cst --freq 27 \
  --json build/manual/blink.json --write build/manual/blink-routed.json
  
  ```

pack the bitstream for loading:

`uv run gowin_pack -d GW2A-18C -o build/blink.fs build/manual/blink-routed.json`

load onto fpga 

`sudo (command -s openFPGALoader) -b tangnano20k build/blink.fs`
