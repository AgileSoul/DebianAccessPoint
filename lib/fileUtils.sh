#!/usr/bin/env bash

function generate_config_file()
{
    if [ ${#@} -ne 2 ]; then return 1; fi
    if [ -f "$1" ]; then return 0; fi

    local -r name_file=$1
    local -r configuration_file=("${!2}")
    
    local configuration_file_line
    for configuration_file_line in "${configuration_file[@]}"
    do
        echo "$configuration_file_line" >> "$name_file"
    done
}

function move_file()
{
    if [ ${#@} -ne 3 ]; then return 1; fi

    local -r initial_path_file=$1
    local -r final_path_file=$2
    local -r operator_file=$3

    if [ -z "$initial_path_file" -o -z "$final_path_file" ]; then
        return 2
    fi

    case "$operator_file" in 
      "set_")
        if [ ! -f "$final_path_file" ]; then
            mv "$initial_path_file" "$final_path_file"
        fi
        ;;
      "unset_")
        if [ -f "$initial_path_file" ]; then
            mv "$initial_path_file" "$final_path_file"
        fi
        ;;
      *)
        return 3
        ;;
    esac
}