#!/usr/bin/env bash

# Normal colors
BLACK="$(tput setaf 0)"
RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
YELLOW="$(tput setaf 3)"
BLUE="$(tput setaf 4)"
PURPLE="$(tput setaf 5)"
CYAN="$(tput setaf 6)"
GRAY="$(tput setaf 7)"
NORMAL="$(tput sgr 0)"

# Bold font colors
BOLDBLACK="$(tput bold)$(tput setaf 0)"
BOLDRED="$(tput bold)$(tput setaf 1)"
BOLDGREEN="$(tput bold)$(tput setaf 2)"
BOLDYELLOW="$(tput bold)$(tput setaf 3)"
BOLDBLUE="$(tput bold)$(tput setaf 4)"
BOLDPURPLE="$(tput bold)$(tput setaf 5)"
BOLDCYAN="$(tput bold)$(tput setaf 6)"
BOLDGRAY="$(tput bold)$(tput setaf 7)"

# Italics colors
ITALICBLACK="$(tput sitm)$(tput setaf 0)"
ITALICRED="$(tput sitm)$(tput setaf 1)"
ITALICGREEN="$(tput sitm)$(tput setaf 2)"
ITALICYELLOW="$(tput sitm)$(tput setaf 3)"
ITALICBLUE="$(tput sitm)$(tput setaf 4)"
ITALICPURPLE="$(tput sitm)$(tput setaf 5)"
ITALICCYAN="$(tput sitm)$(tput setaf 6)"
ITALICGRAY="$(tput sitm)$(tput setaf 7)"

# Blinking colors
BLINKBLACK="$(tput blink)$(tput setaf 0)"
BLINKRED="$(tput blink)$(tput setaf 1)"
BLINKGREEN="$(tput blink)$(tput setaf 2)"
BLINKYELLOW="$(tput blink)$(tput setaf 3)"
BLINKBLUE="$(tput blink)$(tput setaf 4)"
BLINKPURPLE="$(tput blink)$(tput setaf 5)"
BLINKCYAN="$(tput blink)$(tput setaf 6)"
BLINKGRAY="$(tput blink)$(tput setaf 7)"