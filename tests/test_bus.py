from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge, ReadOnly
from cocotb_tools.runner import get_runner

def test_bus():
    project = Path(__file__).resolve().parents[1]
    runner = get_runner("icarus")
    runner.build(
        sources=[project / "bus.sv"],
        hdl_toplevel="top",
        build_dir=project / "build" / "tests" / "bus",
        timescale=("1ns", "1ps"),
        waves=True,
        always=True,  # Icarus can otherwise reuse a build without waveform support.
    )
    runner.test(hdl_toplevel="top", test_module="test_bus", waves=True)# test_filter="copy_a_to_b")

@cocotb.test(name="copy_a_to_b")
async def copy_a_to_b(dut):
    a = dut.bus.a
    b = dut.bus.b

    Clock(dut.clk, 10, unit="ns").start(start_high=False)
    a.value = 0x55
    b.value = 0xAA
    dut.a_we.value = 0
    dut.b_we.value = 0
    dut.bus_src.value = 0

    await RisingEdge(dut.clk)
    await ReadOnly()

    assert int(a.value) == 0
    assert int(b.value) == 0
    assert int(dut.rst.value) == 0

    await FallingEdge(dut.clk)
    a.value = 0x55
    b.value = 0xAA

    await ReadOnly()
    assert int(dut.bus_out.value) == 0x55

    await Timer(1, unit="step") # epsilon step
    dut.bus_src.value = 1

    await ReadOnly()
    assert int(dut.bus_out.value) == 0xAA

    await Timer(1, unit="step") # epsilon step
    dut.bus_src.value = 0
    dut.b_we.value = 1

    await RisingEdge(dut.clk)
    await ReadOnly()

    assert int(b.value) == 0x55
    
