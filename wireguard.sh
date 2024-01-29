#!/bin/bash

if [ -f "index.html" ]; then
    rm index.html
fi
cat >index.html <<INDEX_EOF
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<h1>WireGuard</h1>
<ul>
<li><a href="https://wireguard.sengshinlee.com/mirrors/wireguard-ubuntu-latest.sh">wireguard-ubuntu-latest.sh</a></li>
<li><a href="https://wireguard.sengshinlee.com/mirrors/wireguard-android-latest.apk">wireguard-android-latest.apk</a></li>
<li><a href="https://wireguard.sengshinlee.com/mirrors/wireguard-windows-installer-latest.exe">wireguard-windows-installer-latest.exe</a></li>
<li><a href="https://apps.apple.com/us/app/wireguard/id1451685025">wireguard-macos-latest (us)</a></li>
<li><a href="https://apps.apple.com/us/app/wireguard/id1441195209">wireguard-ios/ipados-latest (us)</a></li>
</ul>
INDEX_EOF


if [ -d "mirrors" ]; then
    rm -rf mirrors
fi
mkdir mirrors
cd mirrors

WG_WINDOWS_INSTALLER_URL="https://download.wireguard.com/windows-client/wireguard-installer.exe"
wget ${WG_WINDOWS_INSTALLER_URL} -O wireguard-windows-installer-latest.exe

WG_ANDROID_PATH="https://download.wireguard.com/android-client/"
WG_ANDROID_VER=$(curl -s ${WG_ANDROID_PATH} | \
                awk -F '.apk' '{print $2}' | \
                cut -d '-' -f 2)
WG_ANDROID_URL=${WG_ANDROID_PATH}"com.wireguard.android-"${WG_ANDROID_VER}".apk"
wget ${WG_ANDROID_URL} -O wireguard-android-latest.apk

cat >wireguard-ubuntu-latest.sh <<WG_UBUNTU_EO'F'
#!/bin/bash

function distrib() {
    local DISTRIB=""
    if [ -f "/etc/debian_version" ]; then
        source /etc/os-release
        DISTRIB="${ID}"
    else
        echo "> Distribution must be ubuntu!"
        exit 1
    fi
}

function kernel() {
    local VER="$(uname -r | cut -d- -f1)"
    if str1.str2.str3_lt ${VER} "5.6.0"; then
        echo "> Kernel version must be >= 5.6.0!"
        exit 1
    fi
}

function str1.str2.str3_lt() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"
}

function is_root() {
    if [ "$(echo $USER)" != "root" ]; then
        echo "> You need to be root to run this script!"
        exit 1
    fi
}

function is_installed() {
    if [ -f "/usr/bin/wg" ] && [ -f "/usr/bin/wg-quick" ]; then
        return 0
    else
        return 1
    fi
}

function version() {
    if [ ${IS_INSTALLED} -eq 0 ]; then
        wg -v
    else
        echo "> Uninstalled!"
    fi
}

function install_wg_tools() {
    if [ ${IS_INSTALLED} -eq 0 ]; then
        echo "> Installed!"
    else
        apt-get install wireguard-tools -y >/dev/null 2>&1
    fi
}

function create_wg_if() {
    if [ ${IS_INSTALLED} -eq 0 ]; then
        local SERVER_WG_NIC_NUM

        while true; do
            read -p "< Input a number [0,255]: " ARG
            if [ -z "${ARG}" ]; then
                echo "> Not be empty!"
            elif [[ ${ARG} == *[!0-9]* ]]; then
                echo "> Not a number!"
            elif [ ${ARG} -gt 255 ]; then
                echo "> Must be between [0,255]!"
            elif [ -f "/etc/wireguard/wg${ARG}*" ]; then
                echo "> Existed!"
            else
                SERVER_WG_NIC_NUM=${ARG} >/dev/null 2>&1
                break
            fi
        done

        local SERVER_PUBLIC_IPV4="$(wget -qO- -t1 -T2 ipv4.icanhazip.com)"
        local SERVER_PUBLIC_NIC="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"

        local SERVER_WG_PORT=$(expr 10000 + ${SERVER_WG_NIC_NUM})
        local SERVER_WG_NIC="wg${SERVER_WG_NIC_NUM}"

        local SERVER_WG_IF="/etc/wireguard/${SERVER_WG_NIC}.conf"
        local CLIENT_WG_IF="/etc/wireguard/${SERVER_WG_NIC}-client.conf"

        local SERVER_WG_IPV4="10.0.${SERVER_WG_NIC_NUM}.0"
        local SERVER_PRIVATE_KEY="$(wg genkey)"
        local SERVER_PUBLIC_KEY="$(echo ${SERVER_PRIVATE_KEY} | wg pubkey)"

        local CLIENT_WG_IPV4="10.0.${SERVER_WG_NIC_NUM}.1"
        local CLIENT_PRIVATE_KEY="$(wg genkey)"
        local CLIENT_PUBLIC_KEY="$(echo ${CLIENT_PRIVATE_KEY} | wg pubkey)"

        create_server_if
        create_client_if
    else
        echo "> Uninstalled!"
    fi
}

function create_server_if() {
    cat >${SERVER_WG_IF} <<EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${SERVER_WG_IPV4}
ListenPort = ${SERVER_WG_PORT}
PostUp = ufw route allow in on ${SERVER_WG_NIC} out on ${SERVER_PUBLIC_NIC}
PostUp = iptables -t nat -I POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PostUp = ufw allow ${SERVER_WG_PORT}/udp && ufw reload
PreDown = ufw route delete allow in on ${SERVER_WG_NIC} out on ${SERVER_PUBLIC_NIC}
PreDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PreDown = ufw delete allow ${SERVER_WG_PORT}/udp && ufw reload

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}
EOF
}

function create_client_if() {
    cat >${CLIENT_WG_IF} <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_WG_IPV4}
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
AllowedIPs = 0.0.0.0/0
Endpoint = ${SERVER_PUBLIC_IPV4}:${SERVER_WG_PORT}
PersistentKeepalive = 25
EOF
}

function show() {
    if [ ${IS_INSTALLED} -eq 0 ]; then
        wg | grep "interface" | awk '{print $2}'
    else
        echo "> Uninstalled!"
    fi
}

function up_wg() {
    if [ ${IS_INSTALLED} -eq 0 ]; then
        while true; do
            read -p "< Input a number [0,255]: " ARG
            if [ -z "${ARG}" ]; then
                echo "> Not be empty!"
            elif [[ ${ARG} == *[!0-9]* ]]; then
                echo "> Not a number!"
            elif [ ${ARG} -gt 255 ]; then
                echo "> Must be between [0,255]!"
            elif [ ! -f "/etc/wireguard/wg${ARG}.conf" ]; then
                echo "> Not be created!"
            else
                if [ "$(show | grep wg${ARG})" == "wg${ARG}" ]; then
                    echo "> Already up!"
                else
                    up_net
                    wg-quick up wg${ARG} >/dev/null 2>&1
                fi
                break
            fi
        done
    else
        echo "> Uninstalled!"
    fi
}

function up_net() {
    [ $(wg | wc -l) -eq 0 ] && sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
}

function down_wg() {
    local COUNT=1
    local SERVER_WG_ACTIVE_NIC_NUM

    if [ ${IS_INSTALLED} -eq 0 ]; then
        while [ ${COUNT} -le 256 ]; do
            local SERVER_WG_ACTIVE_NIC_NUM=$(wg | grep "interface" | awk '{print $2}' | cut -c 3- | head -${COUNT} | tail -1)
            if [ -z "${SERVER_WG_ACTIVE_NIC_NUM}" ]; then
                if [ ! -f "/etc/wireguard/wg${SERVER_WG_ACTIVE_NIC_NUM}.conf" ]; then
                    touch /etc/wireguard/wg${SERVER_WG_ACTIVE_NIC_NUM}.conf
                fi
            fi
            COUNT=$(expr ${COUNT} + 1)
        done

        while true; do
            read -p "< Input a number [0,255]: " ARG
            if [ -z "${ARG}" ]; then
                rm /etc/wireguard/wg.conf >/dev/null 2>&1
                echo "> Not be empty!"
            elif [[ ${ARG} == *[!0-9]* ]]; then
                echo "> Not a number!"
            elif [ ${ARG} -gt 255 ]; then
                echo "> Must be between [0,255]!"
            else
                if [ "$(show | grep wg${ARG})" == "wg${ARG}" ]; then
                    wg-quick down wg${ARG} >/dev/null 2>&1
                    if [ ! -f "/etc/wireguard/wg${ARG}.conf" ] && [ ! -f "/etc/wireguard/wg${ARG}-client.conf" ]; then
                        rm /etc/wireguard/wg${ARG}.conf /etc/wireguard/wg${ARG}-client.conf >/dev/null 2>&1
                    fi
                    down_net
                else
                    echo "> No need to down!"
                fi
                break
            fi
        done
    else
        echo "> Uninstalled!"
    fi
}

function down_net() {
    [ $(wg | wc -l) -eq 0 ] && sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1
}

function remove_wg_if() {
    if [ ${IS_INSTALLED} -eq 0 ]; then
        while true; do
            read -p "< Input a number [0,255]: " ARG
            if [ -z "${ARG}" ]; then
                echo "> Not be empty!"
            elif [[ ${ARG} == *[!0-9]* ]]; then
                echo "> Not a number!"
            elif [ ${ARG} -gt 255 ]; then
                echo "> Must be between [0,255]!"
            elif [ ! -f "/etc/wireguard/wg${ARG}.conf" ] && [ ! -f "/etc/wireguard/wg${ARG}-client.conf" ]; then
                echo "> Not exist!"
            else
                rm /etc/wireguard/wg${ARG}.conf /etc/wireguard/wg${ARG}-client.conf >/dev/null 2>&1
                break
            fi
        done
    else
        echo "> Uninstalled!"
    fi
}

function uninstall_wg_tools() {
    if [ ${IS_INSTALLED} -eq 0 ]; then
        local SERVER_WG_ACTIVE_NIC=$(wg | grep "interface" | awk '{print $2}' | head -1)
        while [ "${SERVER_WG_ACTIVE_NIC}" != "" ]; do
            if [ ! -f "/etc/wireguard/${SERVER_WG_ACTIVE_NIC}.conf" ]; then
                touch /etc/wireguard/${SERVER_WG_ACTIVE_NIC}.conf
            fi

            if [ ! -f "/etc/wireguard/${SERVER_WG_ACTIVE_NIC}-client.conf" ]; then
                touch /etc/wireguard/${SERVER_WG_ACTIVE_NIC}-client.conf
            fi
            wg-quick down ${SERVER_WG_ACTIVE_NIC} >/dev/null 2>&1
            SERVER_WG_ACTIVE_NIC=$(wg | grep "interface" | awk '{print $2}' | head -1)
        done
        apt-get remove wireguard-tools -y >/dev/null 2>&1
        rm -rf /etc/wireguard >/dev/null 2>&1
    else
        echo "> Uninstalled!"
    fi
}

function help() {
    echo '
USAGE
  bash wireguard-ubuntu-latest.sh [OPTION]

OPTION
  -h, --help    Show help manual
  -v, --version Show "wireguard-tools" version
  -i, --install Install "wireguard-tools"
  -c, --create  Create a new WireGuard interface configuration file
  -s, --show    Show the current active interface
  -u, --up      Enable IPv4 forward and up a specified interface
  -d, --down    Down a specified interface and disable IPv4 forward
  -r, --remove  Remove WireGuard a specified interface configuration file
  -p, --purge   Remove "wireguard-tools" and delete any associated configuration files
'
}

function main() {
    distrib
    kernel
    is_root
    is_installed
    local IS_INSTALLED=$?

    local ARG="$1"
    if [ -z "${ARG}" ]; then
        help
        exit 0
    fi

    case "${ARG}" in
    -h | --help)
        help
        ;;
    -v | --version)
        version
        ;;
    -i | --install)
        install_wg_tools
        ;;
    -c | --create)
        create_wg_if
        ;;
    -s | --show)
        show
        ;;
    -u | --up)
        up_wg
        ;;
    -d | --down)
        down_wg
        ;;
    -r | --remove)
        remove_wg_if
        ;;
    -p | --purge)
        uninstall_wg_tools
        ;;
    *)
        help
        ;;
    esac
}

main "$@"
WG_UBUNTU_EOF