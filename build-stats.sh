#!/usr/bin/env bash

while true; do
    echo -en "\e[0;37m"
    ps xfwau
    df -h
    free -h
    echo -en "\e[0m"
    sleep 60
done