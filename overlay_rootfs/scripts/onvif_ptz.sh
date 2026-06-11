#!/bin/sh

POS_FILE=/tmp/onvif_ptz_moving

current_pos()
{
  /scripts/cmd move 2> /dev/null | awk '
    NF >= 2 {
      printf("%d,%d,0\n", int($1 + 0.5), int($2 + 0.5));
      ok = 1;
      exit;
    }
    END {
      if(!ok) print "0,0,0";
    }'
}

move_abs()
{
  pan=$1
  tilt=$2
  [ "$pan" = "" ] && pan=0
  [ "$tilt" = "" ] && tilt=0
  touch $POS_FILE
  /scripts/cmd move "$pan" "$tilt" 5 2 > /dev/null 2>&1
  rm -f $POS_FILE
}

move_delta()
{
  awk -v op="$1" -v value="$2" '
    BEGIN {
      cmd = "/scripts/cmd move";
      cmd | getline line;
      close(cmd);
      split(line, pos, " ");
      pan = int(pos[1] + 0.5);
      tilt = int(pos[2] + 0.5);
      if(value < 0) {
        value = -value;
        if(op == "left") op = "right";
        else if(op == "right") op = "left";
        else if(op == "up") op = "down";
        else if(op == "down") op = "up";
      }
      delta = int((value + 0.05) * 30);
      if(delta < 1) delta = 1;
      if(op == "left") pan -= delta;
      if(op == "right") pan += delta;
      if(op == "up") tilt += delta;
      if(op == "down") tilt -= delta;
      while(pan < 0) pan += 356;
      while(pan > 355) pan -= 356;
      if(tilt < 0) tilt = 0;
      if(tilt > 180) tilt = 180;
      printf("%d %d\n", pan, tilt);
    }' | while read pan tilt ; do
      move_abs "$pan" "$tilt"
    done
}

case "$1" in
  get_position)
    current_pos
    ;;
  is_moving)
    [ -f $POS_FILE ] && echo 1 || echo 0
    ;;
  move_left)
    move_delta left "$2"
    ;;
  move_right)
    move_delta right "$2"
    ;;
  move_up)
    move_delta up "$2"
    ;;
  move_down)
    move_delta down "$2"
    ;;
  absolute)
    move_abs "$2" "$3"
    ;;
  relative)
    move_delta right "$2"
    move_delta up "$3"
    ;;
  stop)
    rm -f $POS_FILE
    ;;
esac
