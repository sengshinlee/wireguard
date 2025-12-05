#!/bin/bash

function distribution() {
    local DISTRIBUTION=""

    if [ -f "/etc/debian_version" ]; then
        source /etc/os-release
        DISTRIBUTION="${ID}"
    else
        echo "ERROR: Distribution must be ubuntu!"
        exit 1
    fi
}

function num1.num2.num3_lt() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"
}

function kernel() {
    if num1.num2.num3_lt $(uname -r | cut -d- -f1) "5.6.0"; then
        echo "ERROR: Kernel version must be >= 5.6.0!"
        exit 1
    fi
}

function root() {
    if [ "$(echo ${USER})" != "root" ]; then
        echo "WARNING: You must be root to run the script!"
        exit 1
    fi
}

WG_TOOLS="$?"

function wg_tools() {
    if [ -f "/usr/bin/wg" ] && [ -f "/usr/bin/wg-quick" ]; then
        return 0
    else
        return 1
    fi
}

function generate_server_if() {
    cat >${SERVER_WG_IF_CONF} <<EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${SERVER_WG_IPV4}/24
ListenPort = ${SERVER_WG_PORT}
PostUp = iptables -A FORWARD -i ${SERVER_WG_NIC} -o ${SERVER_PUBLIC_NIC} -j ACCEPT
PostUp = iptables -A FORWARD -i ${SERVER_PUBLIC_NIC} -o ${SERVER_WG_NIC} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PostUp = ufw allow proto udp from 0.0.0.0/0 to 0.0.0.0/0 port ${SERVER_WG_PORT} >/dev/null 2>&1
PostUp = sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
PreDown = iptables -D FORWARD -i ${SERVER_WG_NIC} -o ${SERVER_PUBLIC_NIC} -j ACCEPT
PreDown = iptables -D FORWARD -i ${SERVER_PUBLIC_NIC} -o ${SERVER_WG_NIC} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
PreDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PreDown = ufw delete allow proto udp from 0.0.0.0/0 to 0.0.0.0/0 port ${SERVER_WG_PORT} >/dev/null 2>&1
PreDown = if [ \$(wg show | grep "interface" | awk '{ print \$2 }' | wc -l) -eq 1 ]; then sysctl -w net.ipv4.ip_forward=0; else :; fi >/dev/null 2>&1

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32
EOF
}

function generate_client_if() {
    cat >${CLIENT_WG_IF_CONF} <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_WG_IPV4}/24
DNS = 1.1.1.1, 1.0.0.1, 1.1.1.2, 1.0.0.2, 1.1.1.3, 1.0.0.3

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = 0.0.0.0/0
Endpoint = ${SERVER_PUBLIC_IPV4}:${SERVER_WG_PORT}
PersistentKeepalive = 25
EOF
}

function generate_client_split_tunneling_if() {
    cat >${CLIENT_WG_SPLIT_TUNNELING_IF_CONF} <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_WG_IPV4}/24
DNS = 127.0.0.1
PreUp = "C:\\Program Files\\WireGuard\\wireguard-hook\\hooks\\routes-up.bat"
PostUp = "C:\\Program Files\\WireGuard\\wireguard-hook\\hooks\\dns-up.bat"
PreDown = "C:\\Program Files\\WireGuard\\wireguard-hook\\hooks\\routes-down.bat"
PostDown = "C:\\Program Files\\WireGuard\\wireguard-hook\\hooks\\dns-down.bat"

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = 0.0.0.0/1, 128.0.0.0/1
Endpoint = ${SERVER_PUBLIC_IPV4}:${SERVER_WG_PORT}
PersistentKeepalive = 25
EOF
}

function generate_wg_if() {
    if [ ! -f "/usr/bin/wg" ] && [ ! -f "/usr/bin/wg-quick" ]; then
        apt install wireguard-tools -y >/dev/null 2>&1
    fi

    if [ ${WG_TOOLS} -eq 0 ]; then
        local SERVER_PUBLIC_IPV4="$(curl -s -4 https://cloudflare.com/cdn-cgi/trace | grep ip | awk -F '=' '{ print $2 }')"
        local SERVER_PUBLIC_NIC="$(ip -4 -o route get 1.1.1.1 | awk '{ print $5 }')"

        local SERVER_WG_NIC="wg0"
        local SERVER_WG_PORT="51820"

        local SERVER_WG_IF_CONF="/etc/wireguard/${SERVER_WG_NIC}.conf"
        local CLIENT_WG_IF_CONF="/etc/wireguard/${SERVER_WG_NIC}-client.conf"
        local CLIENT_WG_SPLIT_TUNNELING_IF_CONF="/etc/wireguard/${SERVER_WG_NIC}-client.split-tunneling.conf"

        local SERVER_WG_IPV4="10.0.0.0"
        local SERVER_PRIVATE_KEY="$(wg genkey)"
        local SERVER_PUBLIC_KEY="$(echo ${SERVER_PRIVATE_KEY} | wg pubkey)"

        local CLIENT_WG_IPV4="10.0.0.1"
        local CLIENT_PRIVATE_KEY="$(wg genkey)"
        local CLIENT_PUBLIC_KEY="$(echo ${CLIENT_PRIVATE_KEY} | wg pubkey)"
        local CLIENT_PRESHARED_KEY="$(wg genpsk)"

        generate_server_if
        generate_client_if
        generate_client_split_tunneling_if

        echo ${SERVER_WG_IF_CONF}
        echo ${CLIENT_WG_IF_CONF}
        echo ${CLIENT_WG_SPLIT_TUNNELING_IF_CONF}
        exit 0
    else
        echo "ERROR: Not installed!"
        exit 1
    fi
}

function remove() {
    if [ -f "/usr/bin/wg" ] && [ -f "/usr/bin/wg-quick" ]; then
        apt remove wireguard-tools -y >/dev/null 2>&1
        rm -rf /etc/wireguard >/dev/null 2>&1
    else
        echo "NOTICE: Not installed, no need to remove!"
    fi
    exit 0
}

function help() {
    cat <<EOF
USAGE
  bash wireguard.sh [OPTION]

OPTION
  -h, --help     Show help manual
  -g, --generate Generate a pair of new WireGuard interface configuration files
  -r, --remove   Remove "wireguard-tools" 
EOF
    exit 0
}

function main() {
    distribution
    kernel
    root
    wg_tools

    if [ "$#" -eq 0 ]; then
        help
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                help
                ;;
            -g|--generate)
                generate_wg_if
                ;;
            -r|--remove)
                remove
                ;;
            *)
                echo "ERROR: Invalid option \"$1\"!"
                exit 1
                ;;
        esac
        shift
    done
}

main "$@"
