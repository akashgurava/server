#!/usr/bin/env bash
set -euo pipefail

# ANSI colors
GREEN=$'\033[32m'
RED=$'\033[31m'
BLUE=$'\033[34m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

DEFAULT_TARGETS=(
  "main.traefik:443"

  "utilities.filebrowser:6800"
  "utilities.vaultwarden:8100"
  "utilities.wud:3888"

  "monitor.beszel:8090"
  
  "media.qbit:8088"
  "media.prowlarr:9696"
  "media.radarr:7878"
  "media.sonarr:8989"
  "media.jellyfin:8096"
)

INPUTS=("$@")
if [ ${#INPUTS[@]} -eq 0 ]; then
  INPUTS=("${DEFAULT_TARGETS[@]}")
fi

rows=()

trim() { awk '{$1=$1;print}'; }

is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }

parse_target() {
  local token="$1"
  local type name port
  if [[ "$token" =~ ^([^.:]+)\.([^.:]+):([0-9]+)$ ]]; then
    type="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"; port="${BASH_REMATCH[3]}"
  elif [[ "$token" =~ ^([^.:]+):([0-9]+)$ ]]; then
    type=""; name="${BASH_REMATCH[1]}"; port="${BASH_REMATCH[2]}"
  elif is_number "$token"; then
    type=""; name=""; port="$token"
  else
    printf ""; return 1
  fi
  printf "%s|%s|%s" "$type" "$name" "$port"
}

test_one() {
  local service_type="$1"
  local service_name="$2"
  local port="$3"
  local url="http://localhost:$port"
  local http_code note proto final_code
  local out headers loc
  local http_code4 http_code6 ec4 ec6 ip4_note ip6_note

  out="$(curl -4 -s -D - -o /dev/null -w 'HTTP_CODE:%{http_code}' --max-time 5 "$url" || true)"
  ec=$?
  headers="$(printf "%s" "$out" | sed -n '/^HTTP\//,$p' | sed '/HTTP_CODE:/d')"
  http_code="$(printf "%s" "$out" | awk -F'HTTP_CODE:' 'END{print $2}')"
  note=""
  proto="HTTP"
  final_code="$http_code"

  if [ $ec -ne 0 ]; then
    case $ec in
      7)  note="Connection refused";;
      56) note="Connection reset by peer";;
      28) note="Timeout";;
      *)  note="Curl error $ec";;
    esac
  else
    loc="$(printf "%s" "$headers" | grep -i '^Location:' | head -n1 | cut -d' ' -f2- | tr -d '\r' | trim || true)"
    if [[ "$http_code" =~ ^3[0-9][0-9]$ ]]; then
      if [[ "$loc" == */web/ || "$loc" == web/ ]]; then
        note="Redirect to web/"
      elif [[ "$loc" == *"/login"* ]]; then
        note="Auth redirect"
      else
        note="Redirect -> $loc"
      fi
    elif [[ "$http_code" == "401" ]]; then
      note="Unauthorized"
    elif [[ "$http_code" == "403" ]]; then
      note="Forbidden"
    elif [[ "$http_code" =~ ^5[0-9][0-9]$ ]]; then
      note="Server error"
    elif [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
      note="OK"
    fi
  fi

  if { [ "$note" = "Connection refused" ] || [ "$note" = "Connection reset by peer" ] || [ "$note" = "Timeout" ]; }; then
    https_url="https://localhost:$port"
    out_tls="$(curl -s -k -D - -o /dev/null -w 'HTTP_CODE:%{http_code}' --max-time 5 "$https_url" || true)"
    ec_tls=$?
    headers_tls="$(printf "%s" "$out_tls" | sed -n '/^HTTP\//,$p' | sed '/HTTP_CODE:/d')"
    http_code_tls="$(printf "%s" "$out_tls" | awk -F'HTTP_CODE:' 'END{print $2}')"
    if [ $ec_tls -eq 0 ] && [[ "$http_code_tls" =~ ^[0-9][0-9][0-9]$ ]]; then
      proto="HTTPS"
      final_code="$http_code_tls"
      if [[ "$http_code_tls" =~ ^3[0-9][0-9]$ ]]; then
        loc="$(printf "%s" "$headers_tls" | grep -i '^Location:' | head -n1 | cut -d' ' -f2- | tr -d '\r' | trim || true)"
        if [[ "$loc" == *"/login"* ]]; then
          note="HTTPS OK (auth redirect)"
        else
          note="HTTPS OK (redirect)"
        fi
      elif [[ "$http_code_tls" =~ ^2[0-9][0-9]$ ]]; then
        note="HTTPS OK"
      else
        note="HTTPS responded"
      fi
    fi
  fi

  # IPv4 and IPv6 probes (concise per-family status)
  out4="$(curl -4 -s -D - -o /dev/null -w 'HTTP_CODE:%{http_code}' --connect-timeout 3 --max-time 5 "$url" || true)"; ec4=$?
  http_code4="$(printf "%s" "$out4" | awk -F'HTTP_CODE:' 'END{print $2}')"
  if [ $ec4 -ne 0 ]; then
    case $ec4 in
      7)  ip4_note="Refused";;
      56) ip4_note="Reset";;
      28) ip4_note="Timeout";;
      *)  ip4_note="Err$ec4";;
    esac
  else
    ip4_note="$http_code4"
  fi

  out6="$(curl -6 -s -D - -o /dev/null -w 'HTTP_CODE:%{http_code}' --connect-timeout 3 --max-time 5 "$url" || true)"; ec6=$?
  http_code6="$(printf "%s" "$out6" | awk -F'HTTP_CODE:' 'END{print $2}')"
  if [ $ec6 -ne 0 ]; then
    case $ec6 in
      7)  ip6_note="Refused";;
      56) ip6_note="Reset";;
      28) ip6_note="Timeout";;
      *)  ip6_note="Err$ec6";;
    esac
  else
    ip6_note="$http_code6"
  fi

  local status

  if [[ "$final_code" =~ ^[0-9][0-9][0-9]$ ]]; then
    if [[ "$final_code" =~ ^2 ]]; then status="Healthy"
    elif [[ "$final_code" =~ ^3 ]]; then status="Reachable"
    elif [[ "$final_code" =~ ^4 ]]; then status="Auth/Client"
    else status="ServerErr"; fi
  else
    status="$note"
    final_code="-"
  fi

  # If no note yet and HTTP code is 000 (no response), provide a helpful note
  if [[ "$final_code" == "000" && -z "$note" ]]; then
    note="No HTTP response (connection closed/reset or TLS mismatch)"
  fi

  # Downgrade Healthy if either IPv4 or IPv6 probe is not 2xx
  if [[ "$status" == "Healthy" ]]; then
    v4_ok=0; v6_ok=0
    [[ "$ip4_note" =~ ^2[0-9][0-9]$ ]] && v4_ok=1
    [[ "$ip6_note" =~ ^2[0-9][0-9]$ ]] && v6_ok=1
    if [[ $v4_ok -eq 0 || $v6_ok -eq 0 ]]; then
      status="Degraded"
      reason_parts=()
      if [[ $v4_ok -eq 0 ]]; then reason_parts+=("IPv4:$ip4_note"); fi
      if [[ $v6_ok -eq 0 ]]; then reason_parts+=("IPv6:$ip6_note"); fi
      reasons="$(IFS=','; echo "${reason_parts[*]}")"
      if [[ -z "$note" ]]; then
        note="Degraded ($reasons)"
      else
        note="$note; Degraded ($reasons)"
      fi
    fi
  fi

  rows+=("$service_type|$service_name|$port|$proto|$status|$final_code|$ip4_note|$ip6_note|$note")
}

parsed_targets=()
for t in "${INPUTS[@]}"; do
  parsed="$(parse_target "$t" || true)"
  [ -n "$parsed" ] && parsed_targets+=("$parsed")
done

for triple in "${parsed_targets[@]}"; do
  IFS='|' read -r _type _name _port <<< "$triple"
  test_one "$_type" "$_name" "$_port"
done

printf "\n"
header=("ServiceType" "Service" "Port" "Proto" "Status" "HTTP" "IPv4" "IPv6" "Note")
w1=11; w2=7; w3=4; w4=5; w5=6; w6=4; w7=4; w8=4; w9=4
for r in "${rows[@]}"; do
  IFS='|' read -r c1 c2 c3 c4 c5 c6 c7 c8 c9 <<< "$r"
  [ ${#c1} -gt $w1 ] && w1=${#c1}
  [ ${#c2} -gt $w2 ] && w2=${#c2}
  [ ${#c3} -gt $w3 ] && w3=${#c3}
  [ ${#c4} -gt $w4 ] && w4=${#c4}
  [ ${#c5} -gt $w5 ] && w5=${#c5}
  [ ${#c6} -gt $w6 ] && w6=${#c6}
  [ ${#c7} -gt $w7 ] && w7=${#c7}
  [ ${#c8} -gt $w8 ] && w8=${#c8}
  [ ${#c9} -gt $w9 ] && w9=${#c9}

done

printf "%-${w1}s  %-${w2}s  %-${w3}s  %-${w4}s  %-${w5}s  %-${w6}s  %-${w7}s  %-${w8}s  %s\n" "${header[@]}"
printf "%-${w1}s  %-${w2}s  %-${w3}s  %-${w4}s  %-${w5}s  %-${w6}s  %-${w7}s  %-${w8}s  %s\n" "$(printf '─%.0s' $(seq 1 $w1))" "$(printf '─%.0s' $(seq 1 $w2))" "$(printf '─%.0s' $(seq 1 $w3))" "$(printf '─%.0s' $(seq 1 $w4))" "$(printf '─%.0s' $(seq 1 $w5))" "$(printf '─%.0s' $(seq 1 $w6))" "$(printf '─%.0s' $(seq 1 $w7))" "$(printf '─%.0s' $(seq 1 $w8))" "$(printf '─%.0s' $(seq 1 $w9))"

for r in "${rows[@]}"; do
  IFS='|' read -r c1 c2 c3 c4 c5 c6 c7 c8 c9 <<< "$r"
  # Build the plain (non-colored) line first to preserve alignment
  printf -v line "%-${w1}s  %-${w2}s  %-${w3}s  %-${w4}s  %-${w5}s  %-${w6}s  %-${w7}s  %-${w8}s  %s\n" \
    "$c1" "$c2" "$c3" "$c4" "$c5" "$c6" "$c7" "$c8" "$c9"

  # Prepare colored status and substitute only the first occurrence
  status_colored="$c5"
  case "$c5" in
    Healthy) status_colored="${GREEN}$c5${RESET}";;
    Reachable) status_colored="${BLUE}$c5${RESET}";;
    ServerErr) status_colored="${RED}$c5${RESET}";;
    Degraded) status_colored="${YELLOW}$c5${RESET}";;
    "Auth/Client") status_colored="${YELLOW}$c5${RESET}";;
  esac
  line="${line/$c5/$status_colored}"
  printf "%s" "$line"

done

printf "\n"
