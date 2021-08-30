#!/usr/bin/env bash

function printCenteredText()
{
    if [ ${#@} -ne 2 ]; then return 1; fi

    local -r text=$1
    local -ri colorColumnsNumber=$2
    local -ri terminalNumberOfColumns=$(tput cols)

    local -ri numberOfColumnsForCenter=$(($terminalNumberOfColumns/2 + \
      ${#text}/2 + $colorColumnsNumber/2))
    printf "%*s" $numberOfColumnsForCenter "$text"
}