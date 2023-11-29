# wekachecker (source/build repository)


# NOTE: See github.com/weka/tools/wekachecker for the binary version of this tool

# Do not run from this repository directly

This repository is the source/build code for weka/tools/wekachecker


# General Architecture:

The `scripts.d/` directory contains a number of subdirectories that contain `bash` scripts.  Use `-w` or `--workload` to specify which set of scripts to execute.  Of course, if not specified, the `default/` directory will be used.

Currently, there is `scripts.d/default`, `scripts.d/client` and `scripts.d/ta`.

Example would be `./wekachecker -w ta` to run the scripts in the `scripts.d/ta` directory.

# Developer info

The scripts are written in `bash`.   The return code indicates pass/fail of the tests.

## Return Codes

Specifically, the scripts can return:

|   Return Code |  Meaning |
|---------------|----------|
|           0   | PASS     |
|         255   | HARDFAIL |
|         254   | WARN     |
| anything else | FAIL     |

Simply use `return 0` for a passing grade, or `return 254` for a warning, etc.

## Common code - preamble

There is a `preamble` script in each directory.   The preable is injected before the test script, and handles some standard argument parsing and such (take a look for details).

## Execution Scheme

`wekachecker` can run the scripts in 4 ways - single host, sequentially on all hosts, parallel on all hosts, and parallel comparing (to compare items from all hosts).

The run method is specified by defining `SCRIPT_TYPE` in the script.   For example, `SCRIPT_TYPE="parallel-compare-backends"` or `SCRIPT_TYPE=parallel`

## Setting Description

By setting the `DESCRIPTION` variable in the script, `wekachecker` will display the value of `DESCRIPTION` first, the the result (PASS/FAIL, etc) as it executes the scripts.

## Other items

That's about all there is to it... your script is free to do most anything on the target system(s); but please avoid modifying things that might upset customers. ;)
  
