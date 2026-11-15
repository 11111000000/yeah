#!/usr/bin/env bash
# compute.sh - print the sum of the numbers in numbers.txt.
# benchmark-compute-v1
sum=0
while read -r number; do
  sum=$((sum + number))
done < numbers.txt
printf 'sum=%s\n' "$sum"
