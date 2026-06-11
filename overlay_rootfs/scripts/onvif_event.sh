#!/bin/sh

EVENT_DIR=/tmp/onvif_notify_server
LOG_DIR=/tmp/log
LOG=$LOG_DIR/onvif_event.log
PID=/var/run/onvif_event.pid
HACK_INI=/tmp/hack.ini

log()
{
  mkdir -p $LOG_DIR
  echo `date +"%Y/%m/%d %H:%M:%S"` ": $*" >> $LOG
}

pulse()
{
  file="$1"
  [ "$file" = "" ] && return
  mkdir -p $EVENT_DIR
  touch $EVENT_DIR/$file
  ( sleep 15; rm -f $EVENT_DIR/$file ) > /dev/null 2>&1 &
  log "trigger $file"
}

get_ini()
{
  awk -F "=" -v key="$1" '$1 ~ "^[ \t]*" key "[ \t]*$" { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' $HACK_INI
}

all_as_motion()
{
  [ "$(get_ini ONVIF_EVENT_ALL_AS_MOTION)" != "off" ]
}

trigger()
{
  case "$1" in
    motion|motion_alarm)
      pulse motion_alarm
    ;;
    sound|sound_detection|caution|fire|co|smoke|alarm_sound)
      pulse sound_detection
      all_as_motion && pulse motion_alarm
    ;;
    *)
      pulse motion_alarm
    ;;
  esac
}

start_event()
{
  mkdir -p $LOG_DIR $EVENT_DIR
  touch $LOG
  chmod 666 $LOG > /dev/null 2>&1
  log "event bridge ready"
}

stop_event()
{
  rm -f $PID
  log "event bridge stop"
}

case "$1" in
  trigger)
    trigger "$2"
  ;;
  start)
    start_event
  ;;
  stop)
    stop_event
  ;;
  restart)
    stop_event
    start_event
  ;;
  *)
    echo "Usage: $0 {trigger <motion|sound|caution>|start|stop|restart}"
    exit 1
  ;;
esac
