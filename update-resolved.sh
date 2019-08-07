#!/bin/bash

# __up__

up(){
  local n i b c j x e s
  local -A m=()
  local -a o=() a=() h=()

  SetLinkDNS=('ia(iay)' $ifindex 0)
  SetLinkDNSOverTLS=('is' $ifindex)
  SetLinkDNSSEC=('is' $ifindex)
  SetLinkDNSSECNegativeTrustAnchors=('ias' $ifindex 0)
  SetLinkDefaultRoute=('ib' $ifindex)
  SetLinkDomains=('ia(sb)' $ifindex 0)
  SetLinkLLMNR=('is' $ifindex)
  SetLinkMulticastDNS=('is' $ifindex)

  # turn foreign options into key value list.
  for n in ${!foreign_option_@}; do
    if [[ ${!n} =~ ^dhcp-option[[:space:]](DNS|DOMAIN)[[:space:]](.*)$ ]]; then
      o+=("${BASH_REMATCH[@]:1:2}")
    fi
  done

  # Append custom resolved options.
  if ((${#resolve_options[@]} < 2 && ${#resolve_options[@]} % 2)); then
    mesg '<3>Error: Could not append $resolve_options'
  else
    o+=("${resolve_options[@]}")
  fi

  # Build associative arrays for method calls.
  for ((i=0; i < ${#o[@]}; i+=2)); do
    n=${o[i]}
    b=${o[i+1]}
    case $n in
      DNS)
        if ((${#b} == 0)); then
          m[SetLinkDNS]=$b
          mesg '<6>Info: Removing dns servers'
        elif [[ ! $b =~ (:::+|.*::.*::.*|[^[:xdigit:]:]) ]]; then
          IFS=: read -r -a a <<< ${b/#::/:}
          if ((${#a[@]} < 8)); then
            c=:
            for ((j=0; j <= (8 - ${#a[@]}); j++)); do
              c+=0000:
            done
            b=${b//::/$c}
          fi
          h=()
          for x in ${b//:/ }; do
            printf -v x %04x 0x$x
            h+=($((16#${x:0:2})) $((16#${x:2:2})))
          done
          if ((${#h[@]} == 16)); then
            m[SetLinkDNS]="${m[SetLinkDNS]} 10 16 ${h[@]}"
            ((SetLinkDNS[2]++))
            mesg "<6>Info: Adding dns: $b"
          fi
        elif [[ ${b//[^.]} = ... ]]; then
          m[SetLinkDNS]="${m[SetLinkDNS]} 2 4 ${b//./ }"
          ((SetLinkDNS[2]++))
          mesg "<6>Info: Adding dns: $b"
        else
          mesg "<4>Warning: $n: Unsupported value: $b"
        fi
      ;;
      DNSSECNegativeTrustAnchors)
        if ((${#b} == 0)); then
          m[SetLinkDNSSECNegativeTrustAnchors]=$b
          mesg '<6>Info: Removing negative trust anchors'
        elif [[ ! $b =~ [^_a-Z0-9\.\-] ]]; then
          m[SetLinkDNSSECNegativeTrustAnchors]="${m[SetLinkDNSSECNegativeTrustAnchors]} $b"
          ((SetLinkDNSSECNegativeTrustAnchors[2]++))
          mesg "<6>Info: Adding negative trust anchor: $b"
        else
          mesg "<4>Warning: $n: Unsupported value: $b"
        fi
      ;;
      DOMAIN)
        if ((${#b} == 0)); then
          m[SetLinkDomains]=$b
          mesg '<6>Info: Removing domain names'
        elif [[ ! $b =~ [^_a-Z0-9\.\-\~] ]]; then
          if [[ ${b::1} = '~' ]]; then
            m[SetLinkDomains]="${m[SetLinkDomains]} ${b:1} 1"
          else
            m[SetLinkDomains]="${m[SetLinkDomains]} ${b:0} 0"
          fi
          ((SetLinkDomains[2]++))
          mesg "<6>Info: Adding domain: $b"
        else
          mesg "<4>Warning: $n: Unsupported value: $b"
        fi
      ;;
      DNSOverTLS|DNSSEC|DefaultRoute|LLMNR|MulticastDNS)
        if ((${#b} == 0)); then
          if [[ $n != DefaultRoute ]]; then
            m[SetLink$n]=$b
            mesg "<6>Info: Removing $n setting"
          else
            mesg '<6>Info: DefaultRoute only takes boolean'
          fi
        else
          case $b in
            allow-downgrade|no|opportunistic|resolve|yes)
              m[SetLink$n]=$b
              mesg "<6>Info: Setting $n: $b"
            ;;
            *)
              mesg "<4>Warning: $n: Unsupported value: $b"
            ;;
          esac
        fi
      ;;
      *)
        mesg "<4>Warning: Unsupported option: $n"
      ;;
    esac
  done

  s=0

  # Let the magic begin
  for n in ${!m[@]}; do
    b=${n}[@]
    c=${!b}
    e=$(busctl --quiet call org.freedesktop.resolve1 /org/freedesktop/resolve1 org.freedesktop.resolve1.Manager $n $c ${m[$n]# } 2>&1) || s=1
    (($d >= 6)) && mesg "<7>Debug: $n: $c ${m[$n]# }"
    (($s != 0)) && mesg "<3>Error: $n: $e"
  done
  if (( $s == 0 )); then
    mesg "<5>Note: Successfully configured resolved on link $ifindex ($dev)"
  fi
}

# __down__

down(){
  # bye bye
  local e=$(busctl --quiet call org.freedesktop.resolve1 /org/freedesktop/resolve1 org.freedesktop.resolve1.Manager RevertLink i $ifindex 2>&1)
  if (( $? == 0 )); then
    mesg "<5>Note: Reverting resolved settings on link $ifindex ($dev)"
  else
    mesg "<3>Error: RevertLink: $e"
  fi
}

# __log__

# Use syslog level prefixes
# and verb/debug output verbosity.
# emerg, alert, crit, err, warning, notice, info, debug
mesg(){
  local x=${1:1:1}
  if (( ($d >= 6 && $x <= 7) || \
        ($d >= 4 && $x <= 6) || \
        ($d >= 3 && $x <= 5) || \
        ($d >= 1 && $x <= 4) || \
        ($d >= 0 && $x <= 3) )); then
    if (($logger == 1)); then
      logger --priority user.$x --tag=update-resolved "${1:3}"
    else
      echo "${1:3}"
    fi
  fi
}

# __start__

config=${BASH_SOURCE%.*}.conf

if [[ ! -r $config ]]; then
  mesg "<3>Error: Missing $config, exit..."
  exit 0
fi

# Load settings.
. $config

# Override verbosity with debug level.
d=${debug:-$verb}

# args 0 uses environment variables.
if [[ $args == 1 ]]; then
  dev=$1
  script_type=$2
fi

if [[ -z ${dev} ]] || [[ -z ${script_type} ]]; then
  mesg '<3>Error: Missing dev or script type, exit...'
  exit 0
fi

# __main__

ifindex=0
for x in /sys/class/net/*; do
  if [[ $x = "/sys/class/net/$dev" ]]; then
    read -r ifindex < $x/ifindex
    break
  fi
done

if ((! $ifindex > 0)); then
    mesg '<3>Error: Failed getting link ifindex, exit...'
    exit 0
fi

case $script_type in
  up|down)
     $script_type ;;
  *)
    mesg '<3>Error: Invalid script type, exit...'
    exit 0
    ;;
esac

# Flush all local dns caches.
busctl --quiet --expect-reply=0 call org.freedesktop.resolve1 /org/freedesktop/resolve1 org.freedesktop.resolve1.Manager FlushCaches

# __main__

exit 0
