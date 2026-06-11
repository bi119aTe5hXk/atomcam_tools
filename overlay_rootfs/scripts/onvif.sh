#!/bin/sh

HACK_INI=/tmp/hack.ini
CONF=/tmp/onvif_simple_server.conf
LOG_DIR=/tmp/log
LOG=$LOG_DIR/onvif.log
ONVIF_SERVER_LOG=$LOG_DIR/onvif_simple_server.log
WSD_SERVER_LOG=$LOG_DIR/wsd_simple_server.log
WSD_PID=/var/run/wsd_simple_server.pid
NOTIFY_PID=/var/run/onvif_notify_server.pid

log()
{
  mkdir -p $LOG_DIR
  echo `date +"%Y/%m/%d %H:%M:%S"` ": $*" >> $LOG
}

get_ini()
{
  awk -F "=" -v key="$1" '$1 ~ "^[ \t]*" key "[ \t]*$" { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' $HACK_INI
}

active_if()
{
  for ifs in eth0 wlan0 ; do
    if ifconfig $ifs 2> /dev/null | grep 'inet addr' > /dev/null ; then
      echo $ifs
      return
    fi
  done
}

stop_onvif()
{
  if [ -f $WSD_PID ]; then
    kill -15 `cat $WSD_PID` > /dev/null 2>&1
    rm -f $WSD_PID
  fi
  if [ -f $NOTIFY_PID ]; then
    kill -15 `cat $NOTIFY_PID` > /dev/null 2>&1
    rm -f $NOTIFY_PID
  fi
  killall wsd_simple_server > /dev/null 2>&1
  killall onvif_notify_server > /dev/null 2>&1
}

if [ "$1" = "off" -o "$1" = "restart" ]; then
  stop_onvif
  log "onvif stop"
  [ "$1" = "off" ] && exit 0
fi

ONVIF_ENABLE=$(get_ini ONVIF_ENABLE)
[ "$1" != "on" -a "$1" != "restart" -a "$ONVIF_ENABLE" != "on" ] && exit 0

RTSP_VIDEO0=$(get_ini RTSP_VIDEO0)
RTSP_AUDIO0=$(get_ini RTSP_AUDIO0)
RTSP_VIDEO1=$(get_ini RTSP_VIDEO1)
RTSP_VIDEO2=$(get_ini RTSP_VIDEO2)
[ "$RTSP_VIDEO0" = "on" ] || {
  log "onvif requires RTSP main stream"
  exit 0
}

IFACE=$(active_if)
[ "$IFACE" = "" ] && {
  log "no active network interface"
  exit 1
}

mkdir -p $LOG_DIR
mkdir -p /tmp/onvif_notify_server
touch $LOG $ONVIF_SERVER_LOG $WSD_SERVER_LOG
chmod 666 $LOG $ONVIF_SERVER_LOG $WSD_SERVER_LOG > /dev/null 2>&1
/scripts/rtspserver.sh on

HOSTNAME=`hostname`
MODEL=$(awk -F "=" '/^PRODUCT_MODEL=/ { print $2; exit }' /atom/configs/.product_config 2> /dev/null)
[ "$MODEL" = "" ] && MODEL="ATOMCam"
SERIAL=$(awk -F "=" '/^(CONFIG_INFO|NETRELATED_MAC)=/ { print $2; exit }' /atom/configs/.product_config 2> /dev/null)
[ "$SERIAL" = "" ] && SERIAL="$HOSTNAME"

RTSP_OVER_HTTP=$(get_ini RTSP_OVER_HTTP)
RTSP_PORT=8554
[ "$RTSP_OVER_HTTP" = "on" ] && RTSP_PORT=8080

RTSP_AUTH=$(get_ini RTSP_AUTH)
RTSP_USER=$(get_ini RTSP_USER)
RTSP_PASSWD=$(get_ini RTSP_PASSWD)
AUTH=""
if [ "$RTSP_AUTH" = "on" -a "$RTSP_USER" != "" -a "$RTSP_PASSWD" != "" ]; then
  AUTH="$RTSP_USER:$RTSP_PASSWD@"
fi

ONVIF_USER=$(get_ini ONVIF_USER)
ONVIF_PASSWD=$(get_ini ONVIF_PASSWD)

AUDIO_ENCODER=NONE
if [ "$RTSP_AUDIO0" = "AAC" ]; then
  AUDIO_ENCODER=AAC
elif [ "$RTSP_AUDIO0" = "S16_BE" ]; then
  AUDIO_ENCODER=G711
fi

PTZ=0
if [ "$MODEL" = "ATOM_CAKP1JZJP" ]; then
  PTZ=1
fi

{
  echo "model=$MODEL"
  echo "manufacturer=ATOMTech"
  echo "firmware_ver=`cat /etc/atomhack.ver 2> /dev/null`"
  echo "hardware_id=$MODEL"
  echo "serial_num=$SERIAL"
  echo "ifs=$IFACE"
  echo "port=80"
  echo "scope=onvif://www.onvif.org/Profile/Streaming"
  echo "scope=onvif://www.onvif.org/Profile/S"
  echo "scope=onvif://www.onvif.org/name/$HOSTNAME"
  echo "scope=onvif://www.onvif.org/hardware/$MODEL"
  echo "user=$ONVIF_USER"
  echo "password=$ONVIF_PASSWD"
  echo "adv_enable_media2=0"
  echo "adv_fault_if_unknown=0"
  echo "adv_fault_if_set=0"
  echo "adv_synology_nvr=1"

  echo "name=Profile_0"
  echo "width=1920"
  echo "height=1080"
  echo "url=rtsp://${AUTH}%s:$RTSP_PORT/video0_unicast"
  echo "snapurl=http://%s/cgi-bin/get_jpeg.cgi"
  echo "type=H264"
  echo "audio_encoder=$AUDIO_ENCODER"
  echo "audio_decoder=NONE"

  echo "ptz=$PTZ"
  if [ "$PTZ" = "1" ]; then
    echo "min_step_x=0"
    echo "max_step_x=355"
    echo "min_step_y=0"
    echo "max_step_y=180"
    echo "min_step_z=0"
    echo "max_step_z=0"
    echo "get_position=/scripts/onvif_ptz.sh get_position"
    echo "is_moving=/scripts/onvif_ptz.sh is_moving"
    echo "move_left=/scripts/onvif_ptz.sh move_left %f > /dev/null"
    echo "move_right=/scripts/onvif_ptz.sh move_right %f > /dev/null"
    echo "move_up=/scripts/onvif_ptz.sh move_up %f > /dev/null"
    echo "move_down=/scripts/onvif_ptz.sh move_down %f > /dev/null"
    echo "move_stop=/scripts/onvif_ptz.sh stop %s > /dev/null"
    echo "jump_to_abs=/scripts/onvif_ptz.sh absolute %f %f %f > /dev/null"
    echo "jump_to_rel=/scripts/onvif_ptz.sh relative %f %f %f > /dev/null"
  fi

  echo "events=1"
  echo "topic=tns1:VideoSource/MotionAlarm"
  echo "source_name=Source"
  echo "source_type=tt:ReferenceToken"
  echo "source_value=VideoSourceToken"
  echo "input_file=/tmp/onvif_notify_server/motion_alarm"
  echo "topic=tns1:AudioAnalytics/Audio/DetectedSound"
  echo "source_name=AudioSourceConfigurationToken"
  echo "source_type=tt:ReferenceToken"
  echo "source_value=AudioSourceToken"
  echo "input_file=/tmp/onvif_notify_server/sound_detection"
} > $CONF

pidof wsd_simple_server > /dev/null || \
  /usr/bin/wsd_simple_server -i $IFACE -x "http://%s/onvif/device_service" -m "$MODEL" -n "ATOMTech" -p $WSD_PID -d 5 >> $LOG 2>&1

log "onvif start on $IFACE"
