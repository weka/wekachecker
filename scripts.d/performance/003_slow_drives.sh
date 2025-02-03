#!/bin/bash

declare -A DRIVE_TESTS
declare -A CLUSTER_TESTS

DESCRIPTION="Examine WEKA stats for poorly-performing drives"
SCRIPT_TYPE="single"
INTERNAL_REFERENCE="WEKAPP-XXXXX"
CLUSTER_TESTS["ops_driver/READ_LATENCY"]="average:more_than:10ms:-2m"
CLUSTER_TESTS["rpc/CLIENT_ROUNDTRIP_AVG"]="individual:more_than:10ms:-2m"
CLUSTER_TESTS["rpc/SERVER_PROCESSING_AVG"]="individual:less_than:1ms:-2m"
DRIVE_TESTS["ssd/SSD_READ_LATENCY"]="individual:more_than:1ms:-2m"
DRIVE_TESTS["ssd/DRIVE_READ_LATENCY"]="individual:more_than:1ms:-2m"
DRIVE_TESTS["ssd/DRIVE_UTILIZATION"]="individual:more_than:94:-2m"
DRIVE_TESTS["ssd/DRIVE_LOAD"]="individual:more_than:250:-2m"
CLUSTER_TESTS["DRIVE_READ_RATIO_PER_SSD_READ"]="average:less_than:5:-2m"
DRIVE_TESTS["ssd/DRIVE_IO_TOO_LONG"]="individual:more_than:700:-2m"
CLUSTER_TESTS["network/GOODPUT_TX_RATIO"]="average:more_than:90:-2m"
CLUSTER_TESTS["network/PUMPS_TXQ_FULL"]="average:less_than:0.0005:-2m"

# How this works:
#   It starts out assuming the test matches (i.e. the result is true).
#   For every condition that is found above: if any is found to be false, it then marks the entire test as "not matching"
#    In other words: assume it's matching, until it encounters something that says it doesn't apply.
TEST_RESULTS_MATCHED="1"
RESULT=0

convert_to_standard_units() {
    local VALUE="$1"
    # Now we need to convert VALUE to standardised units. We can't rely on the existence of units(1) or $(systemd-analyze timestamp), unfortunately
    #   This means we're going to convert using sed and awk, for which I apologize
    # right now we're only calculating based on units of time, and we only seem to see micro- and milliseconds.
    VALUE_CALC=$(echo ${VALUE} | sed 's! *µs!/1000000!g;s! *ms!/1000!g;s! *!!g;s!s$!!g;s!%!!g')
    STANDARDIZED_VALUE=$(echo | awk "{print ${VALUE_CALC}"})
    echo ${STANDARDIZED_VALUE}
}

#there's a chance we will need to break this down into very different structures of testing, so
# keeping DRIVE vs CLUSTER tests very separate at the moment, despite the fact it looks ripe
# for re-factoring.
for DRIVE_TEST in ${!DRIVE_TESTS[@]} ; do
    echo Running ${DRIVE_TEST}
    TEST_MODE=$(  echo ${DRIVE_TESTS[${DRIVE_TEST}]} | awk -F: '{print $1}')
    COMPARISON=$( echo ${DRIVE_TESTS[${DRIVE_TEST}]} | awk -F: '{print $2}')
    TEST_VALUE=$( echo ${DRIVE_TESTS[${DRIVE_TEST}]} | awk -F: '{print $3}')
    TIME_PERIOD=$(echo ${DRIVE_TESTS[${DRIVE_TEST}]} | awk -F: '{print $4}')
    #set default values
    TEST_MODE="${TEST_MODE:-individual}"
    COMPARISON="${COMPARISON:-more_than}"
    TEST_VALUE="${TEST_VALUE:-1}"
    TIME_PERIOD="${TIME_PERIOD:-"-1m"}"
    TEST_VALUE=$(convert_to_standard_units "${TEST_VALUE}" )

    # is this a per-disk test?
    DISK_PARAM=""
    if [[ ${TEST_MODE} == "individual" ]] ; then
        DISK_PARAM="--param disk:*"
    fi

    echo "Now checking to see if an individual value for ${DRIVE_TEST} is ${COMPARISON} than ${TEST_VALUE} over the last ${TIME_PERIOD}"
    if [[ ${COMPARISON} == "more_than" ]] ; then
        HIGHEST_VALUE=$(weka stats --show-internal --stat ${DRIVE_TEST} ${DISK_PARAM} --sort value --start-time ${TIME_PERIOD}  --output value --raw-units | tail -n 1)
        HIGHEST_VALUE=$(convert_to_standard_units "${HIGHEST_VALUE}" )
        # Because of the "assume the test matches" logic, we only need to mark the test as not matching if the current comparison fails. Otherwise do nothing
        if (( $(echo ${HIGHEST_VALUE} ${TEST_VALUE} | awk '{if ($1 < $2) print 1;}') )); then
            TEST_RESULTS_MATCHED="0"
        fi
    elif [[ ${COMPARISON} == "less_than" ]] ; then
        LOWEST_VALUE=$(weka stats --show-internal --stat ${DRIVE_TEST} ${DISK_PARAM} --sort -value --start-time ${TIME_PERIOD}  --output value --raw-units | tail -n 1)
        LOWEST_VALUE=$(convert_to_standard_units "${LOWEST_VALUE}" )
        # Because of the "assume the test matches" logic, we only need to mark the test as not matching if the current comparison fails. Otherwise do nothing
        if (( $(echo ${LOWEST_VALUE} ${TEST_VALUE} | awk '{if ($1 > $2) print 1;}') )); then
            TEST_RESULTS_MATCHED="0"
        fi
    fi
done
for CLUSTER_TEST in ${!CLUSTER_TESTS[@]} ; do
    echo Running ${CLUSTER_TEST}
    TEST_MODE=$(  echo ${CLUSTER_TESTS[${CLUSTER_TEST}]} | awk -F: '{print $1}')
    COMPARISON=$( echo ${CLUSTER_TESTS[${CLUSTER_TEST}]} | awk -F: '{print $2}')
    TEST_VALUE=$( echo ${CLUSTER_TESTS[${CLUSTER_TEST}]} | awk -F: '{print $3}')
    TIME_PERIOD=$(echo ${CLUSTER_TESTS[${CLUSTER_TEST}]} | awk -F: '{print $4}')
    #set default values
    TEST_MODE="${TEST_MODE:-individual}"
    COMPARISON="${COMPARISON:-more_than}"
    TEST_VALUE="${TEST_VALUE:-1}"
    TIME_PERIOD="${TIME_PERIOD:-"-1m"}"
    TEST_VALUE=$(convert_to_standard_units "${TEST_VALUE}" )

    # is this a per-process test?
    PROCESS_PARAM=""
    if [[ ${TEST_MODE} == "individual" ]] ; then
        PROCESS_PARAM="--per-process"
    fi

    echo "Now checking to see if an individual value for ${CLUSTER_TEST} is ${COMPARISON} than ${TEST_VALUE} over the last ${TIME_PERIOD}"
    if [[ ${COMPARISON} == "more_than" ]] ; then
        HIGHEST_VALUE=$(weka stats --show-internal --stat ${CLUSTER_TEST} ${PROCESS_PARAM} --sort value --start-time ${TIME_PERIOD}  --output value --raw-units | tail -n 1)
        HIGHEST_VALUE=$(convert_to_standard_units "${HIGHEST_VALUE}" )
        # Because of the "assume the test matches" logic, we only need to mark the test as not matching if the current comparison fails. Otherwise do nothing
        if (( $(echo ${HIGHEST_VALUE} ${TEST_VALUE} | awk '{if ($1 < $2) print 1;}') )); then
            TEST_RESULTS_MATCHED="0"
        fi
    elif [[ ${COMPARISON} == "less_than" ]] ; then
        LOWEST_VALUE=$(weka stats --show-internal --stat ${CLUSTER_TEST} ${PROCESS_PARAM} --sort -value --start-time ${TIME_PERIOD}  --output value --raw-units | tail -n 1)
        LOWEST_VALUE=$(convert_to_standard_units "${LOWEST_VALUE}" )
        # Because of the "assume the test matches" logic, we only need to mark the test as not matching if the current comparison fails. Otherwise do nothing
        if (( $(echo ${LOWEST_VALUE} ${TEST_VALUE} | awk '{if ($1 > $2) print 1;}') )); then
            TEST_RESULTS_MATCHED="0"
        fi
    fi
done

if [[ ${TEST_RESULTS_MATCHED} == "1" ]] ; then
    RESULT=254
    echo "The cluster statistics appeared to match this known performance impact - please review ${INTERNAL_REFERENCE} for details"
else
    RESULT=0
    echo "The cluster statistics do match this known performance impact"
fi

exit ${RESULT}

