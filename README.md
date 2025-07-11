# Asynchronous-FIFO
Asynchronous FIFO with separate read/write clocks, programmable depth, full/empty flags, and one-cycle read latency. Suitable for clock domain crossing and buffered data transfer.

## Overview

This project implements a dual-clock FIFO buffer, useful for crossing data between asynchronous clock domains. It includes a synthesizable Verilog module and a comprehensive testbench to validate functionality.

---

## Features

- **Asynchronous Operation**  
  Supports independent read and write clocks for reliable clock domain crossing.

- **Configurable Parameters**  
  Easily adjust `DATA_WIDTH`, `DEPTH`, and `PTR_WIDTH` for custom FIFO sizing.

- **Full and Empty Status Flags**  
  Real-time indicators to manage data flow and prevent overflow or underflow.

- **One-Cycle Read Latency**  
  Includes pipelined output for predictable data timing.

- **Comprehensive Testbench**  
  Includes tests for fill, empty, simultaneous read/write, random access, and edge cases.

- **Timeout-Protected Operations**  
  Testbench includes safeguards to prevent hanging simulations during error conditions.
