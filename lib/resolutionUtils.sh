#!/usr/bin/env bash

readonly WindowRatio=7.5

set_resolution() { # Windows + Resolution

  # SCREEN_SIZE_X="$LINES"
  # SCREEN_SIZE_Y="$COLUMNS"

  SCREEN_SIZE=$(xdpyinfo | grep dimension | awk '{print $4}' | tr -d "(")
  SCREEN_SIZE_X=$(printf '%.*f\n' 0 $(echo $SCREEN_SIZE | sed -e s'/x/ /'g | awk '{print $1}'))
  SCREEN_SIZE_Y=$(printf '%.*f\n' 0 $(echo $SCREEN_SIZE | sed -e s'/x/ /'g | awk '{print $2}'))

  # Calculate proportional windows
  if hash bc ;then
    NEW_SCREEN_SIZE_X=$(echo $(awk "BEGIN {print $SCREEN_SIZE_X/$WindowRatio}")/1 | bc)
    NEW_SCREEN_SIZE_Y=$(echo $(awk "BEGIN {print $SCREEN_SIZE_Y/$WindowRatio}")/1 | bc)

    NEW_SCREEN_SIZE_BIG_X=$(echo $(awk "BEGIN {print 1.5*$SCREEN_SIZE_X/$WindowRatio}")/1 | bc)
    NEW_SCREEN_SIZE_BIG_Y=$(echo $(awk "BEGIN {print 1.5*$SCREEN_SIZE_Y/$WindowRatio}")/1 | bc)

    SCREEN_SIZE_MID_X=$(echo $(($SCREEN_SIZE_X + ($SCREEN_SIZE_X - 2 * $NEW_SCREEN_SIZE_X) / 2)))
    SCREEN_SIZE_MID_Y=$(echo $(($SCREEN_SIZE_Y + ($SCREEN_SIZE_Y - 2 * $NEW_SCREEN_SIZE_Y) / 2)))

    # Upper windows
    TOPLEFT="-geometry ${NEW_SCREEN_SIZE_X}x$NEW_SCREEN_SIZE_Y+0+0"
    TOPRIGHT="-geometry ${NEW_SCREEN_SIZE_X}x$NEW_SCREEN_SIZE_Y-0+0"
    TOP="-geometry ${NEW_SCREEN_SIZE_X}x$NEW_SCREEN_SIZE_Y+$SCREEN_SIZE_MID_X+0"

    # Lower windows
    BOTTOMLEFT="-geometry ${NEW_SCREEN_SIZE_X}x$NEW_SCREEN_SIZE_Y+0-0"
    BOTTOMRIGHT="-geometry ${NEW_SCREEN_SIZE_X}x$NEW_SCREEN_SIZE_Y-0-0"
    BOTTOM="-geometry ${NEW_SCREEN_SIZE_X}x$NEW_SCREEN_SIZE_Y+$SCREEN_SIZE_MID_X-0"

    # Y mid
    LEFT="-geometry ${NEW_SCREEN_SIZE_X}x$NEW_SCREEN_SIZE_Y+0-$SCREEN_SIZE_MID_Y"
    RIGHT="-geometry ${NEW_SCREEN_SIZE_X}x$NEW_SCREEN_SIZE_Y-0+$SCREEN_SIZE_MID_Y"

    # Big
    TOPLEFTBIG="-geometry ${NEW_SCREEN_SIZE_BIG_X}x$NEW_SCREEN_SIZE_BIG_Y+0+0"
    TOPRIGHTBIG="-geometry ${NEW_SCREEN_SIZE_BIG_X}x$NEW_SCREEN_SIZE_BIG_Y-0+0"
  fi
}