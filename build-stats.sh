#!/usr/bin/env bash

while true; do
    sleep 300
    echo
    ps xfwau 2>/dev/null || ps -ef
    echo
    df -h
    echo
    free -h 2>/dev/null || top -l 1 -s 0 | grep PhysMem
    echo
done