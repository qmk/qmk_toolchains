#!/usr/bin/env bash

while true; do
    sleep 300
    echo
    ps xfwau
    echo
    df -h
    echo
    free -h
    echo
done