#!/usr/bin/awk -f

BEGIN {
    lowest_value_seen  = 0
    highest_value_seen = 0
}
{
    # Read each number into the array x
    x[NR] = $1
    sum += $1
    if ( $1 > highest_value_seen) { highest_value_seen = $1 }
    if ( $1 < lowest_value_seen)  { lowest_value_seen  = $1 }
}

END {
    n = NR

    # Compute the mean
    mean = sum / n

    # Compute the standard deviation - assuming sample rather than population as
    # this is partial data from a time interval
    # Tested against the implementation from R's "tseries" package - they get the same result
    # if the below code is changed to use "n" rather than "n-1". Keeping as "n-1" as this should be more
    # correct for partial (sample) data rather than an entire population
    for (i = 1; i <= n; i++) {
        sumsq += (x[i] - mean)^2
        m3    += (x[i] - mean)^3 # start calculating 3rd central moment/cumulant (equivalent in this order)
        m4    += (x[i] - mean)^4 
    }
    variance = sumsq / (n - 1)  # sample rather than entire population
    stddev   = sqrt(variance)

    skewness = ( m3 / (n - 1 ) ) / (variance^1.5) 

    kurtosis = ( m4 / (n - 1 ) ) / (variance^2)

    # https://en.wikipedia.org/wiki/Jarque%E2%80%93Bera_test
    # Calculate Jarque-Bera statistic
    JB = (n / 6) * (skewness^2 + (kurtosis-3)^2 / 4)

    # Print the results
    printf "STDDEV=%.2f\n", stddev
    printf "VARIANCE=%.9f\n", variance
    printf "SKEWNESS=%.2f\n", skewness
    printf "KURTOSIS=%.2f\n", kurtosis + 3  # to get the actual kurtosis
    printf "JARQUE_BERA=%.2f\n", JB
    printf "LOWEST_VALUE_SEEN=%.2f\n", lowest_value_seen
    printf "HIGHEST_VALUE_SEEN=%.2f\n", highest_value_seen
}
