# ⚡ OhMyCriterion

**Make Criterion benchmark results beautiful again**

## What is this?

Running `cargo bench` with [Criterion](https://github.com/bheisler/criterion.rs) generates detailed JSON output in `target/criterion/`, but reading those results manually is tedious. Results scroll away, confidence intervals are buried in nested JSON, and it's hard to spot performance regressions at a glance.

**OhMyCriterion** parses your Criterion benchmark results and displays them in a beautifully formatted, color-coded table. See latency and throughput metrics instantly, spot regressions/improvements, and get the insights you need—right in your terminal.

## Features

- **Smart unit scaling** – Latency results automatically scale from nanoseconds to seconds
- **Throughput support** – Display operations per second for throughput benchmarks
- **Confidence intervals** – See statistical bounds for each measurement
- **Regression detection** – Automatic % change comparison between baseline and new results
- **GPU benchmark detection** – Identify GPU-accelerated tests
- **Zero dependencies** – Works with pure bash; optional `jq` and `bc` for enhanced features (falls back gracefully)
- **Beautiful tables** – Unicode tables with color output (disable with `--no-color`)
- **JSON output** – Export results as JSON for automation
- **Monorepo support** – Auto-discovers `target/criterion` directories in subdirectories
- **Filtering & sorting** – Target specific benchmarks or sort by name, value, or suite
- **Simple aliasing** – Works great as a shell alias for quick access

## Quick Start

### One-line install (recommended)

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/pdroalves/OhMyCriterion/main/tools/install.sh)"
```

Or with wget:

```bash
sh -c "$(wget -qO- https://raw.githubusercontent.com/pdroalves/OhMyCriterion/main/tools/install.sh)"
```

This installs to `~/.ohmycriterion/` and creates an `omc` alias in your shell.

### Manual install

```bash
git clone https://github.com/pdroalves/OhMyCriterion.git
cd OhMyCriterion
chmod +x ohmycriterion.sh
alias omc='/path/to/ohmycriterion.sh'
```

### Usage

Run from any Rust project with Criterion benchmarks:

```bash
omc                    # auto-discovers target/criterion
omc --no-color         # disable colors (useful for CI)
omc --json             # export as JSON
omc /custom/path       # specify custom criterion path
```

### Uninstall

```bash
~/.ohmycriterion/tools/uninstall.sh
```

## Usage

```
ohmycriterion.sh [OPTIONS] [TARGET_DIR]

OPTIONS:
  -h, --help            Show help message and exit
  -v, --version         Show version and exit
  --no-color            Disable ANSI color output
  --json                Output results as JSON to stdout
  --sort <key>          Sort by: name | value | suite  (default: suite)
  --filter <pattern>    Only show benchmarks whose name contains <pattern>

ARGUMENTS:
  TARGET_DIR            Path to a target/criterion directory.
                        If omitted, auto-discovers in cwd and immediate subdirectories.
```

**Examples:**
```bash
# Display all benchmarks with colors
ohmycriterion.sh

# Disable colors (useful for CI/CD logs)
ohmycriterion.sh --no-color

# Export as JSON for further processing
ohmycriterion.sh --json > results.json

# Sort by latency value (highest to lowest)
ohmycriterion.sh --sort value

# Filter to show only "string" related benchmarks
ohmycriterion.sh --filter "string"

# Combine options
ohmycriterion.sh --filter "parse" --sort name --no-color
```

## Requirements

- **Bash** 4.0 or later
- **bc** (optional, for numeric calculations; falls back to grep/sed if unavailable)
- **jq** (optional, for enhanced JSON parsing; falls back to grep/sed if unavailable)

Most modern Linux and macOS systems have these pre-installed.

## Example Output

```
   ____  _     __  __        ____      _ _            _
  / __ \| |__ |  \/  |_   _ / ___|_ __(_) |_ ___ _ __(_) ___  _ __
 | |  | | '_ \| |\/| | | | | |   | '__| | __/ _ \ '__| |/ _ \| '_ \
 | |__| | | | | |  | | |_| | |___| |  | | ||  __/ |  | | (_) | | | |
  \____/|_| |_|_|  |_|\__, |\____|_|  |_|\__\___|_|  |_|\___/|_| |_|
                        |___/
  Criterion Benchmark Results — v0.1

+----------------------------+-------+------------+------------------+--------------+-------------------------------+
| Benchmark                  | GPU   | Type       | Value            | Change       | 95% CI                        |
+----------------------------+-------+------------+------------------+--------------+-------------------------------+
|  Suite: serialization                                                                                            |
+----------------------------+-------+------------+------------------+--------------+-------------------------------+
| parse_json                 |   -   | latency    | 245.310 us       | ^ 2.30%      | [234.100 us - 256.200 us]     |
| parse_large_json           |   -   | latency    | 1.234 ms         | v 5.10%      | [1.200 ms - 1.300 ms]         |
| serialize_struct           |   -   | latency    | 89.45 ns         | ~ 0.30%      | [87.00 ns - 92.00 ns]         |
+----------------------------+-------+------------+------------------+--------------+-------------------------------+
|  Suite: crypto                                                                                                   |
+----------------------------+-------+------------+------------------+--------------+-------------------------------+
| hash_sha256                |   -   | latency    | 234.560 us       | ^ 8.20%      | [220.000 us - 250.000 us]     |
+----------------------------+-------+------------+------------------+--------------+-------------------------------+

Summary
  Total benchmarks : 4
  Fastest (latency): 89.45 ns  serialize_struct
  Slowest (latency): 1.234 ms  parse_large_json
```

In the terminal, colors highlight key info: green for fast results (< 1ms) and improvements (v), red for slow results (> 100ms) and regressions (^), dim for neutral changes (~).

## How It Works

OhMyCriterion reads Criterion's JSON output structure:
1. **Auto-discovers** `target/criterion/` in your project (or a specified path)
2. **Parses** `benchmark.json` (metadata) and `estimates.json` (statistical data)
3. **Extracts** latency/throughput values, confidence intervals, and baselines
4. **Compares** new vs. base results to detect regressions and improvements
5. **Formats** results as a beautiful Unicode table (or JSON) for easy consumption

No compilation needed—pure bash with optional jq/bc for enhanced features.

## License

BSD 3-Clause License. See [LICENSE](./LICENSE) for details.

---

Made with care for the Rust benchmarking community. Inspired by projects like OhMyZsh that make developer tools delightful.
