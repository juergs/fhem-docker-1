#!/bin/bash

STATE=0
TELNETPORT="${TELNETPORT:-7072}"

FHEMWEB=$( cd /opt/fhem; perl fhem.pl ${TELNETPORT} "jsonlist2 TYPE=FHEMWEB:FILTER=TEMPORARY!=1" 2>/dev/null )
if [ $? -ne 0 ] || [ -z "${FHEMWEB}" ]; then
  RETURN="Telnet(${TELNETPORT}): FAILED;"
  STATE=1
else
  RETURN="Telnet(${TELNETPORT}): OK;"

  LEN=$( echo ${FHEMWEB} | jq -r '.Results | length' )
  i=0
  until [ "$i" == "${LEN}" ]; do
    NAME=$( echo ${FHEMWEB} | jq -r ".Results[$i].Internals.NAME" )
    PORT=$( echo ${FHEMWEB} | jq -r ".Results[$i].Internals.PORT" )
    HTTPS=$( echo ${FHEMWEB} | jq -r ".Results[$i].Attributes.HTTPS" )
    [[ -n "${HTTPS}" && "${HTTPS}" == "1" ]] && PROTO=https || PROTO=http

    FHEMWEB_STATE=$( curl \
                      --silent \
                      --insecure \
                      --output /dev/null \
                      --write-out "%{http_code}" \
                      --user-agent 'FHEM-Docker/1.0 Health Check' \
                      "${PROTO}://localhost:${PORT}/" )
    if [ $? -ne 0 ] ||
       [ -z "${FHEMWEB_STATE}" ] ||
       [ "${FHEMWEB_STATE}" == "000" ] ||
       [ "${FHEMWEB_STATE:0:1}" == "5" ]; then
      RETURN="${RETURN} ${NAME}(${PORT}): FAILED;"
      STATE=1
    else
      RETURN="${RETURN} ${NAME}(${PORT}): OK;"
    fi
    (( i++ ))
  done

  # Update docker module data
  if [ -s /image_info ]; then
    touch /image_info.tmp
    RET=$( cd /opt/fhem; perl fhem.pl ${TELNETPORT} "{ DockerImageInfo_GetImageInfo();; }" 2>/dev/null )
    [ -n "${RET}" ] && RETURN="${RETURN} DockerImageInfo:FAILED;" || RETURN="${RETURN} DockerImageInfo:OK;"
    rm /image_info.tmp
  fi

fi

echo -n ${RETURN}
exit ${STATE}
