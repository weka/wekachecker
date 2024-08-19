#!/usr/bin/awk -f

BEGIN {
    lowest_value_seen  = 0
    highest_value_seen = 0
}
{
    numbers[NR] = $1
    if ( $1 > highest_value_seen) { highest_value_seen = $1 }
    if ( $1 < lowest_value_seen)  { lowest_value_seen  = $1 }
}

END {
    # Sort the array
    n = asort(numbers, sorted_numbers)
    
    # Calculate positions for Q1 and Q3
    q1_pos = (n+1)*0.25
    q3_pos = (n+1)*0.75
    
    # Interpolate if needed
    if (q1_pos == int(q1_pos)) {
        Q1 = sorted_numbers[q1_pos]
    } else {
        Q1 = (sorted_numbers[int(q1_pos)] + sorted_numbers[int(q1_pos)+1]) / 2
    }
    
    if (q3_pos == int(q3_pos)) {
        Q3 = sorted_numbers[q3_pos]
    } else {
        Q3 = (sorted_numbers[int(q3_pos)] + sorted_numbers[int(q3_pos)+1]) / 2
    }
    
    # Calculate IQR
    IQR = Q3 - Q1

    # Determine the lower and upper bounds for outliers
    lower_bound = Q1 - 1.5 * IQR
    upper_bound = Q3 + 1.5 * IQR

    # Print the calculated quartiles and bounds
    printf "QUARTILE1=%.2f\n", Q1
    printf "QUARTILE3=%.2f\n", Q3
    printf "IQR=%.2f\n", IQR
    printf "LOWER_BOUND=%.2f\n", lower_bound
    printf "UPPER_BOUND=%.2f\n", upper_bound

    outliers = ""
    for (i = 1; i <= n; i++) {
        if (sorted_numbers[i] < lower_bound || sorted_numbers[i] > upper_bound) {
            outliers = outliers sorted_numbers[i] ","
        }
    }
    
    # Remove trailing comma and print the outliers
    if (length(outliers) > 0) {
        outliers = substr(outliers, 1, length(outliers) - 1)
        printf "OUTLIERS=%s\n", outliers
    } else {
        print "OUTLIERS="
    }
}
