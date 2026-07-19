#!/usr/bin/env bash

# The objective is find largest and most effective size of memory copy
# To know what would be the best largest size of a message

# Copy different memory sizes between 1024 bytes and 507 KB, 1000 times
# Collect top 5 on bytes per tick
# Sort by number of times one size reached top 5
V="${1:-./bin/memcopy-release}"
echo $V

for i in `seq 1 1000`; do $V|sort -h -k 5|tail -n 5; done|sort -h|cut -d',' -f1|uniq -c|sort -h|tail -5|sort -h -k 2

#  Results
#
#  i5-1240P/LPDDR5 5200MHz
#    569     4096 bytes
#    657     7168 bytes
#    901     7680 bytes
#    965     7936 bytes
#    902     8192 bytes
#
#  i5-1240P/LPDDR5 5200MHz (GCC -march=native/alderlake)
#    846     7168 bytes
#    935     7680 bytes
#    978     7936 bytes
#    962     8192 bytes
#    901    12288 bytes
#
#  i5-1135G7/SODIMM DDR4 3200MHz
#    552     4096 bytes
#    633     6144 bytes
#    798     7168 bytes
#    854     7680 bytes
#    838     7936 bytes
#
#  Xeon-6148/DIMM DRAM EDO (VM)
#    561     3584 bytes
#    678     3840 bytes
#    803     3968 bytes
#    560     7680 bytes
#    570     7936 bytes


#  Conclusion:
#  While 7936 would be the best average size,
#  8192 is 2 page size (most likelly to allocate it anyway)
#  and I hope most messages uses less than that
