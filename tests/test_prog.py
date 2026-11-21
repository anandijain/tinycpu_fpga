import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, FallingEdge
from cocotb_tools.runner import get_runner
from control import control


def test_add():
    project = Path(__file__).resolve().parents[1]
    sim = os.environ.get("SIM", "icarus")
    runner = get_runner(sim)
    build_dir = project / "build" / "tests" / "tinycpu"
    build_args = []
    if sim == "verilator":
        build_dir = build_dir.with_name("tinycpu-verilator")
        # Expose packed struct fields in Surfer and keep lint warnings visible.
        build_args = ["--trace-structs", "-Wno-fatal"]
    runner.build(
        sources=[project / "tinycpu.sv"],
        hdl_toplevel="tinycpu",
        build_dir=build_dir,
        build_args=build_args,
        timescale=("1ns", "1ps"),
        waves=True,
        always=True,  # Icarus can otherwise reuse a build without waveform support.
    )
    runner.test(hdl_toplevel="tinycpu", test_module="test_prog", waves=True)


@cocotb.test()
async def run_prog_to_hlt(dut):
    # load prog.ram
    program = (Path(__file__).resolve().parents[1] / "prog.ram").read_bytes()
    assert len(program) == len(dut.datapath.ram)
    dut.datapath.ram.value = list(program)
    
    Clock(dut.clk, 10, "ns").start(start_high=False)
    step = 0
    while (dut.c.value != control(hlt=True)) and (step < 1e2):
        step += 1
        await RisingEdge(dut.clk)
        await ReadOnly()
    print(f"the program stopped in {step} number of steps")
