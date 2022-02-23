#!/bin/bash
prefix="00:10:18:00"
for (( num = 0; num <= 512; num++ )); do
  printf '%s:%02X:%02X\n' $prefix $((num>>8)) $((num&255))
done
