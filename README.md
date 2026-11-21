2 registers A and B 

in the testbench initialize A to some data, then do a transfer to B 

## Run the bus test

From this directory in WSL, run `uv run pytest -q`. The test in
`tests/test_bus.py` drives the `bus` module in `tinycpu.v` using Icarus Verilog.
You can leave the board unplugged. Keep the OSS CAD Suite tools on your PATH.

Each run writes `build/tests/bus/bus.fst`. Click it in VS Code to open it in Surfer.
Expand the `bus` scope and add `clk`, `b_we`, `a`, `bus`, and `b` to see the transfer.

Edit `tests/test_bus.py` to try another transfer, then rerun the same command.
Use `uv run ruff check tests` to lint the Python and `uv run ruff format tests` to format it.
uv manages Python and the packages in `.venv/` using `uv.lock`.



