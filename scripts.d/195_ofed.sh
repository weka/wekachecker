#!/usr/bin/env bash

DESCRIPTION="Check if Mellanox OFED is installed"
SCRIPT_TYPE="parallel"

# fail immediately if no ofed installed
which ofed_info &> /dev/null
if [ $? != 0 ]; then
    echo "OFED not installed"
    exit 1
fi

# is it a supported ofed version?
OFEDVER=`ofed_info | sed -n '1s/^.*LINUX-//p' | sed 's/ .*//'`


case "$OFEDVER" in 
    4.7-1.0.0.1 | 4.7-3.2.9.0 | 5.0-2.1.8.0 | 5.1-2.5.8.0)
        #continue
        ;;
    *)
        echo "Unsupported ofed version $OFEDVER"
        exit 1
        ;;
esac

#
# check the loaded modules.   Correct OFED might be installed, but not running (kernel mismatch, for example)
#
MLX5_VER=""
ERR_NO_MLX5=0
ret="0"
modinfo mlx5_core &> /dev/null
if [ $? == 0 ]; then
    MLX5_VER=`modinfo mlx5_core | awk '/^version:/{ print $2 }'`
else
    echo "No mlx5_core loaded"
    ret="254"
    ERR_NO_MLX5=1
fi

MLX4_VER=""
ERR_NO_MLX4=0

modinfo mlx4_core &> /dev/null
if [ $? == 0 ]; then
    MLX4_VER=`modinfo mlx4_core | awk '/^version:/{ print $2 }'`
else
    echo "No mlx4_core loaded"
    ret="254"
    ERR_NO_MLX4=1
fi

# make sure loaded drivers match the installed OFED
if [ "$MLX5_VER" != "" ]; then
    if [ "$MLX5_VER" != "${OFEDVER:0:9}" ]; then
        echo "Loaded Mellanox 5 driver $MLX5_VER does not match OFED version $OFEDVER!"
        ret="254"
    fi
fi
if [ "$MLX4_VER" != "" ]; then
    if [ "$MLX4_VER" != "${OFEDVER:0:9}" ]; then
        echo "Loaded Mellanox 4 driver $MLX4_VER does not match OFED version $OFEDVER!"
        ret="254"
    fi
fi

echo "Valid OFED configuration observed"
exit $ret


