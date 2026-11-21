from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge, FallingEdge
from cocotb_tools.runner import get_runner
from control import control


def test_add():
    project = Path(__file__).resolve().parents[1]
    runner = get_runner("icarus")
    runner.build(
        sources=[project / "tinycpu.sv"],
        hdl_toplevel="datapath",
        build_dir=project / "build" / "tests" / "datapath",
        timescale=("1ns", "1ps"),
        waves=True,
        always=True,  # Icarus can otherwise reuse a build without waveform support.
    )
    runner.test(hdl_toplevel="datapath", test_module="test_add", waves=True)


@cocotb.test()
async def add_and_mul_a_b(dut):
    Clock(dut.clk, 10, "ns").start(start_high=False)

    dut.a.value = 39
    dut.b.value = 3
    dut.c.value = control(u_we=True, bus_src="SRC_A")

    await RisingEdge(dut.clk)
    await ReadOnly()

    assert int(dut.u.value) == 39

    await FallingEdge(dut.clk)

    dut.c.value = control(v_we=True, bus_src="SRC_B")

    
    await RisingEdge(dut.clk)
    await ReadOnly()

    assert int(dut.v.value) == 3

    await FallingEdge(dut.clk)

    dut.c.value = control(bus_src="SRC_ALU", alu_op=False)
    
    await RisingEdge(dut.clk)
    await ReadOnly()

    assert int(dut.bus) == 42

    await FallingEdge(dut.clk)

    dut.c.value = control(bus_src="SRC_ALU", alu_op=True)
    
    await RisingEdge(dut.clk)
    await ReadOnly()

    assert int(dut.bus) == 117
