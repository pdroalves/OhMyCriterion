#!/bin/bash
# =============================================================================
#  OhMyCriterion v0.1
#  A polished Criterion benchmark results parser for Rust projects.
#
#  Reads Criterion output from target/criterion, auto-discovers workspace
#  setups, applies smart unit scaling, color-coded output, change tracking,
#  and supports JSON export — all with a clean, themeable CLI interface.
#
#  Usage: ohmycriterion.sh [OPTIONS] [TARGET_DIR]
#  Run with --help for full usage information.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
readonly VERSION="0.1"
readonly SCRIPT_NAME="OhMyCriterion"

# Record field separator — must not appear in benchmark names or formatted values
readonly FS=$'\x01'

# ---------------------------------------------------------------------------
# ANSI color / style codes (overridden to empty strings by --no-color)
# ---------------------------------------------------------------------------
setup_colors() {
    if [[ "$NO_COLOR" == "true" ]]; then
        C_RESET=""; C_BOLD=""; C_DIM=""
        C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_WHITE=""
    else
        C_RESET="\033[0m"
        C_BOLD="\033[1m"
        C_DIM="\033[2m"
        C_RED="\033[0;31m"
        C_GREEN="\033[0;32m"
        C_YELLOW="\033[1;33m"
        C_BLUE="\033[0;34m"
        C_MAGENTA="\033[0;35m"
        C_CYAN="\033[0;36m"
        C_WHITE="\033[0;37m"
    fi
}

# ---------------------------------------------------------------------------
# Defaults / globals
# ---------------------------------------------------------------------------
NO_COLOR="false"
OUTPUT_JSON="false"
SORT_BY="suite"       # name | value | suite
FILTER_PATTERN=""
TARGET_DIRS=()        # populated by auto-discovery or explicit arg
EXPLICIT_DIR=""

declare -a RESULTS    # pipe-delimited records stored here

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
print_banner() {
    [[ "$OUTPUT_JSON" == "true" ]] && return
    echo -e "${C_MAGENTA}${C_BOLD}"
    cat << 'BANNER'
   ____  _     __  __        ____      _ _            _
  / __ \| |__ |  \/  |_   _ / ___|_ __(_) |_ ___ _ __(_) ___  _ __
 | |  | | '_ \| |\/| | | | | |   | '__| | __/ _ \ '__| |/ _ \| '_ \
 | |__| | | | | |  | | |_| | |___| |  | | ||  __/ |  | | (_) | | | |
  \____/|_| |_|_|  |_|\__, |\____|_|  |_|\__\___|_|  |_|\___/|_| |_|
                       |___/
BANNER
    echo -e "${C_CYAN}  Criterion Benchmark Results — v${VERSION}${C_RESET}"
    echo -e "${C_DIM}  Powered by Rust's Criterion.rs${C_RESET}"
    echo ""
}

# ---------------------------------------------------------------------------
# Usage / help
# ---------------------------------------------------------------------------
print_help() {
    echo -e "${C_BOLD}${SCRIPT_NAME} v${VERSION}${C_RESET} — Criterion benchmark results parser"
    echo ""
    echo -e "${C_BOLD}USAGE${C_RESET}"
    echo "  $(basename "$0") [OPTIONS] [TARGET_DIR]"
    echo ""
    echo -e "${C_BOLD}ARGUMENTS${C_RESET}"
    echo "  TARGET_DIR    Path to a target/criterion directory."
    echo "                If omitted, the script searches the current directory"
    echo "                and immediate subdirectories for target/criterion."
    echo ""
    echo -e "${C_BOLD}OPTIONS${C_RESET}"
    printf "  %-28s %s\n" "-h, --help"       "Show this help message and exit"
    printf "  %-28s %s\n" "-v, --version"    "Show version and exit"
    printf "  %-28s %s\n" "--no-color"       "Disable ANSI color output"
    printf "  %-28s %s\n" "--json"           "Output results as JSON to stdout"
    printf "  %-28s %s\n" "--sort <key>"     "Sort by: name | value | suite  (default: suite)"
    printf "  %-28s %s\n" "--filter <pat>"   "Show only benchmarks whose name contains <pat>"
    echo ""
    echo -e "${C_BOLD}EXAMPLES${C_RESET}"
    echo "  $(basename "$0")"
    echo "  $(basename "$0") target/criterion"
    echo "  $(basename "$0") --sort name --filter sha"
    echo "  $(basename "$0") --json | jq '.[] | select(.metric_type==\"latency\")'"
    echo ""
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                setup_colors
                print_help
                exit 0
                ;;
            -v|--version)
                echo "${SCRIPT_NAME} v${VERSION}"
                exit 0
                ;;
            --no-color)
                NO_COLOR="true"
                shift
                ;;
            --json)
                OUTPUT_JSON="true"
                shift
                ;;
            --sort)
                if [[ -z "${2-}" ]]; then
                    echo "Error: --sort requires an argument (name|value|suite)" >&2
                    exit 1
                fi
                case "$2" in
                    name|value|suite) SORT_BY="$2" ;;
                    *)
                        echo "Error: invalid --sort value '$2'. Choose: name | value | suite" >&2
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --filter)
                if [[ -z "${2-}" ]]; then
                    echo "Error: --filter requires a pattern argument" >&2
                    exit 1
                fi
                FILTER_PATTERN="$2"
                shift 2
                ;;
            -*)
                echo "Error: unknown option '$1'. Run with --help for usage." >&2
                exit 1
                ;;
            *)
                if [[ -n "$EXPLICIT_DIR" ]]; then
                    echo "Error: unexpected argument '$1'" >&2
                    exit 1
                fi
                EXPLICIT_DIR="$1"
                shift
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Auto-discovery: find target/criterion in cwd and immediate subdirectories
# ---------------------------------------------------------------------------
discover_criterion_dirs() {
    local -a found=()

    # Current directory
    if [[ -d "target/criterion" ]]; then
        found+=("$(pwd)/target/criterion")
    fi

    # Immediate subdirectories (workspace/monorepo members)
    for subdir in */; do
        [[ -d "$subdir" ]] || continue
        local candidate="${subdir}target/criterion"
        if [[ -d "$candidate" ]]; then
            found+=("$(pwd)/${candidate}")
        fi
    done

    TARGET_DIRS=("${found[@]+"${found[@]}"}")
}

# ---------------------------------------------------------------------------
# Unit scaling: nanoseconds -> human-readable string
# ---------------------------------------------------------------------------
format_ns() {
    local ns="$1"
    awk -v ns="$ns" 'BEGIN {
        if      (ns < 1000)         { printf "%.2f ns",  ns }
        else if (ns < 1000000)      { printf "%.3f us",  ns/1000 }
        else if (ns < 1000000000)   { printf "%.3f ms",  ns/1000000 }
        else                        { printf "%.4f s",   ns/1000000000 }
    }'
}

# ---------------------------------------------------------------------------
# Format ops/sec with magnitude suffix (K, M, G)
# ---------------------------------------------------------------------------
format_ops() {
    local ops="$1"
    awk -v ops="$ops" 'BEGIN {
        if      (ops >= 1e9)  { printf "%.3f G ops/s", ops/1e9 }
        else if (ops >= 1e6)  { printf "%.3f M ops/s", ops/1e6 }
        else if (ops >= 1e3)  { printf "%.3f K ops/s", ops/1e3 }
        else                  { printf "%.2f ops/s",   ops }
    }'
}

# ---------------------------------------------------------------------------
# Color a latency value based on magnitude (ns input)
# Returns ANSI escape sequence string
# ---------------------------------------------------------------------------
color_for_ns() {
    local ns="$1"
    local ms
    ms=$(awk -v ns="$ns" 'BEGIN { printf "%.6f", ns / 1000000 }')
    if awk -v ms="$ms" 'BEGIN { exit !(ms < 1) }'; then
        printf '%s' "$C_GREEN"
    elif awk -v ms="$ms" 'BEGIN { exit !(ms < 100) }'; then
        printf '%s' "$C_YELLOW"
    else
        printf '%s' "$C_RED"
    fi
}

# ---------------------------------------------------------------------------
# Core parser for a single benchmark suite directory
#
# Record format (FS-separated, 10 fields):
#   1  full_id
#   2  gpu_flag
#   3  metric_type
#   4  display_value
#   5  raw_sort_value      (zero-padded for numeric sort)
#   6  confidence_interval
#   7  bench_suite
#   8  pct_change          (empty string if no comparison available)
#   9  change_dir          (better | worse | neutral | "" )
#   10 mean_ns             (raw nanoseconds float)
# ---------------------------------------------------------------------------
parse_criterion_results() {
    local bench_suite_name="$1"
    local criterion_dir="$2"
    local bench_dir="${criterion_dir}/${bench_suite_name}"

    [[ -d "$bench_dir" ]] || return

    for bench_id_dir in "$bench_dir"/*/; do
        [[ -d "$bench_id_dir" ]] || continue

        local new_dir="${bench_id_dir}new"
        local base_dir="${bench_id_dir}base"
        local active_dir=""
        local has_new=false
        local has_base=false

        [[ -d "$new_dir" ]]  && has_new=true
        [[ -d "$base_dir" ]] && has_base=true

        if [[ "$has_new" == "true" ]]; then
            active_dir="$new_dir"
        elif [[ "$has_base" == "true" ]]; then
            active_dir="$base_dir"
        else
            continue
        fi

        local benchmark_json="${active_dir}/benchmark.json"
        local estimates_json="${active_dir}/estimates.json"

        [[ -f "$benchmark_json" && -f "$estimates_json" ]] || continue

        # --- Extract function_id / full_id ---
        local function_id full_id
        if command -v jq >/dev/null 2>&1; then
            function_id=$(jq -r '.function_id // empty' "$benchmark_json" 2>/dev/null || true)
            full_id=$(jq -r '.full_id // .function_id // empty' "$benchmark_json" 2>/dev/null || true)
        else
            function_id=$(grep -o '"function_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$benchmark_json" \
                | sed 's/.*"function_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1 || true)
            full_id=$(grep -o '"full_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$benchmark_json" \
                | sed 's/.*"full_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1 || true)
            [[ -z "$full_id" ]] && full_id="$function_id"
        fi

        [[ -z "$function_id" ]] && continue

        # --- Apply filter ---
        if [[ -n "$FILTER_PATTERN" ]]; then
            if [[ "$full_id" != *"$FILTER_PATTERN"* && "$bench_suite_name" != *"$FILTER_PATTERN"* ]]; then
                continue
            fi
        fi

        # --- Extract mean point estimate (nanoseconds) ---
        local mean_ns
        if command -v jq >/dev/null 2>&1; then
            mean_ns=$(jq -r '.mean.point_estimate // empty' "$estimates_json" 2>/dev/null || true)
        else
            mean_ns=$(grep -o '"mean"[[:space:]]*:[[:space:]]*{[^}]*"point_estimate"[[:space:]]*:[[:space:]]*[0-9.]*' \
                "$estimates_json" | grep -o '[0-9.]*$' | head -1 || true)
        fi
        [[ -z "$mean_ns" || "$mean_ns" == "null" || "$mean_ns" == "0" ]] && continue

        # --- Confidence interval ---
        local lower_bound="" upper_bound=""
        if command -v jq >/dev/null 2>&1; then
            lower_bound=$(jq -r '.mean.confidence_interval.lower_bound // empty' "$estimates_json" 2>/dev/null || true)
            upper_bound=$(jq -r '.mean.confidence_interval.upper_bound // empty' "$estimates_json" 2>/dev/null || true)
        else
            local ci_block
            ci_block=$(grep -o '"confidence_interval"[[:space:]]*:[[:space:]]*{[^}]*}' "$estimates_json" || true)
            if [[ -n "$ci_block" ]]; then
                lower_bound=$(echo "$ci_block" | grep -o '"lower_bound"[[:space:]]*:[[:space:]]*[0-9.]*' \
                    | grep -o '[0-9.]*$' | head -1 || true)
                upper_bound=$(echo "$ci_block" | grep -o '"upper_bound"[[:space:]]*:[[:space:]]*[0-9.]*' \
                    | grep -o '[0-9.]*$' | head -1 || true)
            fi
        fi

        # --- Throughput detection ---
        local throughput_elements=""
        if command -v jq >/dev/null 2>&1; then
            throughput_elements=$(jq -r '.throughput.Elements // empty' "$benchmark_json" 2>/dev/null || true)
        else
            throughput_elements=$(grep -o '"throughput"[[:space:]]*:[[:space:]]*{[^}]*"Elements"[[:space:]]*:[[:space:]]*[0-9]*' \
                "$benchmark_json" | grep -o '[0-9]*$' | head -1 || true)
        fi

        local metric_type display_value raw_sort_value confidence_interval=""

        if [[ -n "$throughput_elements" && "$throughput_elements" != "null" && "$throughput_elements" != "0" ]]; then
            metric_type="throughput"
            local ops_per_sec
            ops_per_sec=$(awk "BEGIN {printf \"%.6f\", ($throughput_elements * 1000000000) / $mean_ns}")
            display_value=$(format_ops "$ops_per_sec")
            raw_sort_value=$(awk "BEGIN {printf \"%020.4f\", $ops_per_sec}")

            if [[ -n "$lower_bound" && -n "$upper_bound" \
               && "$lower_bound" != "null" && "$upper_bound" != "null" ]]; then
                local lo_ops hi_ops lo_fmt hi_fmt
                lo_ops=$(awk "BEGIN {printf \"%.6f\", ($throughput_elements * 1e9) / $upper_bound}")
                hi_ops=$(awk "BEGIN {printf \"%.6f\", ($throughput_elements * 1e9) / $lower_bound}")
                lo_fmt=$(format_ops "$lo_ops")
                hi_fmt=$(format_ops "$hi_ops")
                confidence_interval="[${lo_fmt} - ${hi_fmt}]"
            fi
        else
            metric_type="latency"
            display_value=$(format_ns "$mean_ns")
            raw_sort_value=$(awk "BEGIN {printf \"%025.4f\", $mean_ns}")

            if [[ -n "$lower_bound" && -n "$upper_bound" \
               && "$lower_bound" != "null" && "$upper_bound" != "null" ]]; then
                local lo_fmt hi_fmt
                lo_fmt=$(format_ns "$lower_bound")
                hi_fmt=$(format_ns "$upper_bound")
                confidence_interval="[${lo_fmt} - ${hi_fmt}]"
            fi
        fi

        # --- Change detection: compare new vs base if both exist ---
        local pct_change="" change_dir=""
        if [[ "$has_new" == "true" && "$has_base" == "true" ]]; then
            local base_estimates="${base_dir}/estimates.json"
            if [[ -f "$base_estimates" ]]; then
                local base_mean_ns=""
                if command -v jq >/dev/null 2>&1; then
                    base_mean_ns=$(jq -r '.mean.point_estimate // empty' "$base_estimates" 2>/dev/null || true)
                else
                    base_mean_ns=$(grep -o '"mean"[[:space:]]*:[[:space:]]*{[^}]*"point_estimate"[[:space:]]*:[[:space:]]*[0-9.]*' \
                        "$base_estimates" | grep -o '[0-9.]*$' | head -1 || true)
                fi
                if [[ -n "$base_mean_ns" && "$base_mean_ns" != "null" && "$base_mean_ns" != "0" ]]; then
                    pct_change=$(awk "BEGIN {printf \"%.2f\", (($mean_ns - $base_mean_ns) / $base_mean_ns) * 100}")
                    change_dir=$(awk -v p="$pct_change" 'BEGIN {
                        if      (p < -0.5)  print "better"
                        else if (p >  0.5)  print "worse"
                        else                print "neutral"
                    }')
                fi
            fi
        fi

        # --- GPU detection ---
        local gpu_flag="  -  "
        if [[ "$function_id" =~ (cuda::|gpu::|CUDA|GPU) \
           || "$full_id"     =~ (cuda::|gpu::|CUDA|GPU) \
           || "$bench_id_dir" =~ GPU ]]; then
            gpu_flag=" GPU "
        fi

        # Store record — use FS (ASCII SOH) as delimiter; safe against all text values
        # Fields: full_id FS gpu_flag FS metric_type FS display_value FS raw_sort_value FS
        #         confidence_interval FS bench_suite FS pct_change FS change_dir FS mean_ns
        RESULTS+=("${full_id}${FS}${gpu_flag}${FS}${metric_type}${FS}${display_value}${FS}${raw_sort_value}${FS}${confidence_interval}${FS}${bench_suite_name}${FS}${pct_change}${FS}${change_dir}${FS}${mean_ns}")
    done
}

# ---------------------------------------------------------------------------
# Read a RESULTS record into named variables
# ---------------------------------------------------------------------------
read_record() {
    local rec="$1"
    IFS="$FS" read -r REC_FULL_ID REC_GPU REC_TYPE REC_VALUE REC_SORT REC_CI \
        REC_SUITE REC_PCT REC_DIR REC_NS <<< "$rec"
}

# ---------------------------------------------------------------------------
# Sort helper: re-order RESULTS array according to $SORT_BY
# ---------------------------------------------------------------------------
sort_results() {
    [[ ${#RESULTS[@]} -eq 0 ]] && return

    local sort_field
    case "$SORT_BY" in
        name)  sort_field=1 ;;
        value) sort_field=5 ;;   # raw_sort_value (zero-padded)
        suite) sort_field=7 ;;
        *)     sort_field=7 ;;
    esac

    # Secondary sort is always name (field 1)
    IFS=$'\n' RESULTS=($(printf '%s\n' "${RESULTS[@]}" \
        | sort -t"$FS" -k${sort_field},${sort_field} -k1,1))
    unset IFS
}

# ---------------------------------------------------------------------------
# Change column: format pct_change + change_dir into a display string
# Returns a string with embedded ANSI (caller is responsible for printing)
# ---------------------------------------------------------------------------
format_change_col() {
    local pct="$1"
    local dir="$2"

    if [[ -z "$pct" ]]; then
        printf '%s    n/a    %s' "$C_DIM" "$C_RESET"
        return
    fi

    local abs_pct
    abs_pct=$(awk -v p="$pct" 'BEGIN { printf "%.2f", (p < 0 ? -p : p) }')

    case "$dir" in
        better)  printf '%s%s %s%%%s' "$C_GREEN" "v" "$abs_pct" "$C_RESET" ;;
        worse)   printf '%s%s %s%%%s' "$C_RED"   "^" "$abs_pct" "$C_RESET" ;;
        *)       printf '%s%s %s%%%s' "$C_DIM"   "~" "$abs_pct" "$C_RESET" ;;
    esac
}

# ---------------------------------------------------------------------------
# Strip ANSI escape sequences — used to measure visible string width
# ---------------------------------------------------------------------------
strip_ansi() {
    printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# ---------------------------------------------------------------------------
# Pad a string (which may contain ANSI codes) to a visible width
# ---------------------------------------------------------------------------
pad_to_width() {
    local str="$1"
    local width="$2"
    local visible
    visible=$(strip_ansi "$str")
    local pad=$(( width - ${#visible} ))
    [[ $pad -lt 0 ]] && pad=0
    printf '%s%*s' "$str" "$pad" ""
}

# ---------------------------------------------------------------------------
# Unicode box-drawing table renderer
# ---------------------------------------------------------------------------
display_results_table() {
    if [[ ${#RESULTS[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}No benchmark results found.${C_RESET}"
        return
    fi

    # --- Dynamic column widths ---
    local max_name=9      # "Benchmark" header minimum
    local max_ci=6        # "95% CI" header minimum
    for rec in "${RESULTS[@]}"; do
        read_record "$rec"
        (( ${#REC_FULL_ID} > max_name )) && max_name=${#REC_FULL_ID}
        (( ${#REC_CI}      > max_ci   )) && max_ci=${#REC_CI}
    done
    (( max_name += 2 ))
    (( max_ci   += 2 ))

    local col_gpu=5
    local col_type=10
    local col_val=16
    local col_change=12

    # --- Box-drawing row builders ---
    repeat_h() { printf '%*s' "$1" '' | tr ' ' '-'; }

    local h_name;   h_name=$(repeat_h $((max_name + 2)))
    local h_gpu;    h_gpu=$(repeat_h $((col_gpu + 2)))
    local h_type;   h_type=$(repeat_h $((col_type + 2)))
    local h_val;    h_val=$(repeat_h $((col_val + 2)))
    local h_chg;    h_chg=$(repeat_h $((col_change + 2)))
    local h_ci;     h_ci=$(repeat_h $((max_ci + 2)))

    top_border()    { echo -e "${C_CYAN}+${h_name}+${h_gpu}+${h_type}+${h_val}+${h_chg}+${h_ci}+${C_RESET}"; }
    mid_border()    { echo -e "${C_CYAN}+${h_name}+${h_gpu}+${h_type}+${h_val}+${h_chg}+${h_ci}+${C_RESET}"; }
    bottom_border() { echo -e "${C_CYAN}+${h_name}+${h_gpu}+${h_type}+${h_val}+${h_chg}+${h_ci}+${C_RESET}"; }

    table_row() {
        local c1="$1" c2="$2" c3="$3" c4="$4" c5="$5" c6="$6"
        local sep="${C_CYAN}|${C_RESET}"
        printf '%s %-*s %s %-*s %s %-*s %s %-*s %s' \
            "$sep" "$max_name"   "$c1" \
            "$sep" "$col_gpu"    "$c2" \
            "$sep" "$col_type"   "$c3" \
            "$sep" "$col_val"    "$c4"
        # change column may contain ANSI; pad it manually
        local chg_padded; chg_padded=$(pad_to_width "$c5" $col_change)
        printf ' %s %s %s %-*s %s\n' \
            "$sep" "$chg_padded" \
            "$sep" "$max_ci" "$c6" \
            "$sep"
    }

    # --- Table header ---
    top_border
    table_row \
        "${C_BOLD}Benchmark${C_RESET}" \
        "${C_BOLD}GPU${C_RESET}" \
        "${C_BOLD}Type${C_RESET}" \
        "${C_BOLD}Value${C_RESET}" \
        "${C_BOLD}Change${C_RESET}" \
        "${C_BOLD}95% CI${C_RESET}"
    mid_border

    local current_suite=""
    local first_suite=true

    for rec in "${RESULTS[@]}"; do
        read_record "$rec"

        # --- Suite header ---
        if [[ "$REC_SUITE" != "$current_suite" ]]; then
            [[ "$first_suite" != "true" ]] && mid_border
            first_suite=false
            current_suite="$REC_SUITE"

            # Full-width suite label spanning all columns
            local inner_width=$(( max_name + col_gpu + col_type + col_val + col_change + max_ci + 14 ))
            local suite_label="  Suite: ${REC_SUITE}"
            local suite_sep="${C_CYAN}|${C_RESET}"
            printf '%s%s%-*s%s\n' \
                "$suite_sep" \
                "${C_BOLD}${C_BLUE}" \
                "$inner_width" \
                "$suite_label" \
                "${C_RESET}${suite_sep}"
            mid_border
        fi

        # --- Value color ---
        local val_color="${C_RESET}"
        if [[ "$REC_TYPE" == "latency" ]]; then
            val_color=$(color_for_ns "$REC_NS")
        else
            val_color="${C_CYAN}"
        fi

        local colored_val="${val_color}${REC_VALUE}${C_RESET}"
        local change_cell
        change_cell=$(format_change_col "$REC_PCT" "$REC_DIR")

        table_row \
            "$REC_FULL_ID" \
            "$REC_GPU" \
            "${C_DIM}${REC_TYPE}${C_RESET}" \
            "$colored_val" \
            "$change_cell" \
            "$REC_CI"
    done

    bottom_border
}

# ---------------------------------------------------------------------------
# Summary footer
# ---------------------------------------------------------------------------
display_summary() {
    [[ ${#RESULTS[@]} -eq 0 ]] && return

    local total=${#RESULTS[@]}
    local fastest_name="" fastest_ns="9999999999999999"
    local slowest_name="" slowest_ns="-1"

    for rec in "${RESULTS[@]}"; do
        read_record "$rec"
        [[ "$REC_TYPE" != "latency" ]] && continue
        [[ -z "$REC_NS" ]] && continue

        if awk -v a="$REC_NS" -v b="$fastest_ns" 'BEGIN { exit !(a < b) }'; then
            fastest_ns="$REC_NS"
            fastest_name="$REC_FULL_ID"
        fi
        if awk -v a="$REC_NS" -v b="$slowest_ns" 'BEGIN { exit !(a > b) }'; then
            slowest_ns="$REC_NS"
            slowest_name="$REC_FULL_ID"
        fi
    done

    echo ""
    echo -e "${C_BOLD}${C_CYAN}Summary${C_RESET}"
    echo -e "  Total benchmarks : ${C_BOLD}${total}${C_RESET}"

    if [[ -n "$fastest_name" ]]; then
        local fmt; fmt=$(format_ns "$fastest_ns")
        echo -e "  Fastest (latency): ${C_GREEN}${fmt}${C_RESET}  ${C_DIM}${fastest_name}${C_RESET}"
    fi
    if [[ -n "$slowest_name" && "$slowest_name" != "$fastest_name" ]]; then
        local fmt; fmt=$(format_ns "$slowest_ns")
        echo -e "  Slowest (latency): ${C_RED}${fmt}${C_RESET}  ${C_DIM}${slowest_name}${C_RESET}"
    fi

    if [[ -n "$FILTER_PATTERN" ]]; then
        echo -e "  Filter applied   : ${C_YELLOW}\"${FILTER_PATTERN}\"${C_RESET}"
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# JSON output
# ---------------------------------------------------------------------------
output_json() {
    local first=true
    echo "["
    for rec in "${RESULTS[@]}"; do
        read_record "$rec"

        local gpu_bool="false"
        [[ "$REC_GPU" == " GPU " ]] && gpu_bool="true"

        local change_json="null"
        if [[ -n "$REC_PCT" ]]; then
            change_json="{\"percent\":${REC_PCT},\"direction\":\"${REC_DIR}\"}"
        fi

        local mean_safe="${REC_NS:-0}"

        [[ "$first" == "true" ]] && first=false || printf ',\n'
        printf '  {"benchmark":"%s","suite":"%s","gpu":%s,"metric_type":"%s","value":"%s","mean_ns":%s,"confidence_interval":"%s","change":%s}' \
            "$REC_FULL_ID" "$REC_SUITE" "$gpu_bool" "$REC_TYPE" "$REC_VALUE" \
            "$mean_safe" "$REC_CI" "$change_json"
    done
    printf '\n]\n'
}

# ---------------------------------------------------------------------------
# Process a single criterion directory
# ---------------------------------------------------------------------------
process_target_dir() {
    local criterion_dir="$1"

    if [[ ! -d "$criterion_dir" ]]; then
        echo -e "${C_RED}Error: directory not found: '${criterion_dir}'${C_RESET}" >&2
        return 1
    fi

    local found_any=false
    for bench_dir in "$criterion_dir"/*/; do
        [[ -d "$bench_dir" ]] || continue
        local bench_name; bench_name=$(basename "$bench_dir")
        local has_results=false

        for subdir in "$bench_dir"/*/; do
            if [[ -d "$subdir" && ( -d "${subdir}new" || -d "${subdir}base" ) ]]; then
                has_results=true
                break
            fi
        done

        if [[ "$has_results" == "true" ]]; then
            found_any=true
            parse_criterion_results "$bench_name" "$criterion_dir"
        fi
    done

    if [[ "$found_any" == "false" ]]; then
        echo -e "${C_YELLOW}Warning: no benchmark results found in '${criterion_dir}'.${C_RESET}" >&2
        echo -e "${C_DIM}  Expected: ${criterion_dir}/<suite>/<bench>/new/benchmark.json${C_RESET}" >&2
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    setup_colors

    # --- Determine target directories ---
    if [[ -n "$EXPLICIT_DIR" ]]; then
        TARGET_DIRS=("$EXPLICIT_DIR")
    else
        discover_criterion_dirs
        if [[ ${#TARGET_DIRS[@]} -eq 0 ]]; then
            echo -e "${C_RED}Error: no target/criterion directory found.${C_RESET}" >&2
            echo -e "${C_DIM}Run inside a Rust project, or pass TARGET_DIR explicitly.${C_RESET}" >&2
            echo -e "${C_DIM}Try: $(basename "$0") --help${C_RESET}" >&2
            exit 1
        fi
    fi

    # --- Banner (table mode only) ---
    if [[ "$OUTPUT_JSON" == "false" ]]; then
        print_banner

        if command -v jq >/dev/null 2>&1; then
            echo -e "${C_GREEN}  JSON parser : jq${C_RESET}"
        else
            echo -e "${C_YELLOW}  JSON parser : grep/sed fallback (install jq for accuracy)${C_RESET}"
        fi
        echo -e "${C_DIM}  Sort        : ${SORT_BY}${C_RESET}"
        [[ -n "$FILTER_PATTERN" ]] && echo -e "${C_DIM}  Filter      : \"${FILTER_PATTERN}\"${C_RESET}"
        echo ""
    fi

    # --- Parse all target directories ---
    if [[ "$OUTPUT_JSON" == "false" && ${#TARGET_DIRS[@]} -gt 1 ]]; then
        echo -e "${C_BOLD}  Discovered criterion directories:${C_RESET}"
        for dir in "${TARGET_DIRS[@]}"; do
            echo -e "  ${C_CYAN}>${C_RESET} ${dir}"
        done
        echo ""
    fi

    for dir in "${TARGET_DIRS[@]}"; do
        process_target_dir "$dir"
    done

    if [[ ${#RESULTS[@]} -eq 0 ]]; then
        [[ "$OUTPUT_JSON" == "false" ]] && echo -e "${C_YELLOW}No results to display.${C_RESET}"
        exit 0
    fi

    sort_results

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_json
    else
        display_results_table
        display_summary
    fi
}

main "$@"
