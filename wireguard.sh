#!/bin/bash

declare -g SERVER_WG_IF_CONF_ROOT_DIR="/etc/wireguard"

function distribution() {
    if [ ! -f "/etc/debian_version" ]; then
        echo "ERROR: Linux distribution must be Ubuntu!"
        exit 1
    fi
}

function num1.num2.num3_lt() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"
}

function kernel() {
    if num1.num2.num3_lt "$(uname -r | cut -d- -f1)" "5.6.0"; then
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

function wg_tools_status() {
    if [ -f "/usr/bin/wg" ] && [ -f "/usr/bin/wg-quick" ]; then
        return 0
    else
        return 1
    fi
}

function install_wg_tools() {
    if [ ! -f "/usr/bin/wg" ] && [ ! -f "/usr/bin/wg-quick" ]; then
        apt-get install wireguard-tools -y >/dev/null 2>&1
    else
        echo "NOTICE: wireguard-tools is installed, no need to reinstall!"
    fi
    exit 0
}

function generate_wg_ifs() {
    local WG_TOOLS_STATUS="$?"

    if [ ${WG_TOOLS_STATUS} -eq 0 ]; then
        local SERVER_PUBLIC_IPV6="$(curl -s -6 https://cloudflare.com/cdn-cgi/trace | grep ip | awk -F '=' '{ print $2 }')"
        local SERVER_PUBLIC_NIC="$(ip -4 -o route get 1.1.1.1 | awk '{ print $5 }')"

        local SERVER_WG_NIC="wg0"
        local SERVER_WG_PORT="51820"
        local WG_MTU="1280"

        local SERVER_WG_IF_CONF="${SERVER_WG_IF_CONF_ROOT_DIR}/${SERVER_WG_NIC}.conf"
        local CLIENT_WG_IF_CONF="${SERVER_WG_IF_CONF_ROOT_DIR}/${SERVER_WG_NIC}-client.conf"
        local CLIENT_WG_SPLIT_TUNNELING_IF_CONF="${SERVER_WG_IF_CONF_ROOT_DIR}/${SERVER_WG_NIC}-client.split-tunneling.conf"

        local SERVER_WG_IPV4="10.0.0.1"
        local SERVER_WG_IPV6="fd00::1"
        local SERVER_PRIVATE_KEY="$(wg genkey)"
        local SERVER_PUBLIC_KEY="$(echo ${SERVER_PRIVATE_KEY} | wg pubkey)"

        local CLIENT_WG_IPV4="10.0.0.2"
        local CLIENT_WG_IPV6="fd00::2"
        local CLIENT_PRIVATE_KEY="$(wg genkey)"
        local CLIENT_PUBLIC_KEY="$(echo ${CLIENT_PRIVATE_KEY} | wg pubkey)"
        local CLIENT_PRESHARED_KEY="$(wg genpsk)"

        generate_server_wg_if
        generate_client_wg_if
        generate_client_wg_split_tunneling_if
        chmod -R 400 SERVER_WG_IF_CONF_ROOT_DIR

        echo ${SERVER_WG_IF_CONF}
        echo ${CLIENT_WG_IF_CONF}
        echo ${CLIENT_WG_SPLIT_TUNNELING_IF_CONF}
        exit 0
    else
        echo "ERROR: Not installed, you must install wireguard-tools!"
        exit 1
    fi
}

function generate_server_wg_if() {
    cat >${SERVER_WG_IF_CONF} <<EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${SERVER_WG_IPV4}/32, ${SERVER_WG_IPV6}/128
ListenPort = ${SERVER_WG_PORT}
MTU = ${WG_MTU}
PreUp = sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
PreUp = sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1
PreUp = sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
PreUp = sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
PostUp = iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP
PostUp = iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PostUp = iptables -A FORWARD -i ${SERVER_WG_NIC} -o ${SERVER_PUBLIC_NIC} -j ACCEPT
PostUp = iptables -A FORWARD -i ${SERVER_PUBLIC_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PostUp = ip6tables -A FORWARD -m conntrack --ctstate INVALID -j DROP
PostUp = ip6tables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PostUp = ip6tables -A FORWARD -i ${SERVER_WG_NIC} -o ${SERVER_PUBLIC_NIC} -j ACCEPT
PostUp = ip6tables -A FORWARD -i ${SERVER_PUBLIC_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PreDown = iptables -D FORWARD -m conntrack --ctstate INVALID -j DROP
PreDown = iptables -D FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PreDown = iptables -D FORWARD -i ${SERVER_WG_NIC} -o ${SERVER_PUBLIC_NIC} -j ACCEPT
PreDown = iptables -D FORWARD -i ${SERVER_PUBLIC_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PreDown = iptables -t nat -D POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PreDown = ip6tables -D FORWARD -m conntrack --ctstate INVALID -j DROP
PreDown = ip6tables -D FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PreDown = ip6tables -D FORWARD -i ${SERVER_WG_NIC} -o ${SERVER_PUBLIC_NIC} -j ACCEPT
PreDown = ip6tables -D FORWARD -i ${SERVER_PUBLIC_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
PreDown = ip6tables -t nat -D POSTROUTING -o ${SERVER_PUBLIC_NIC} -j MASQUERADE
PostDown = sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1
PostDown = sysctl -w net.ipv6.conf.all.forwarding=0 >/dev/null 2>&1
PostDown = sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1
PostDown = sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32, ${CLIENT_WG_IPV6}/128
EOF
}

function generate_client_wg_if() {
    cat >${CLIENT_WG_IF_CONF} <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_WG_IPV4}/32, ${CLIENT_WG_IPV6}/128
DNS = 1.1.1.1, 1.0.0.1, 1.1.1.2, 1.0.0.2, 1.1.1.3, 1.0.0.3
DNS = 2606:4700:4700::1111, 2606:4700:4700::1001, 2606:4700:4700::1112, 2606:4700:4700::1002, 2606:4700:4700::1113, 2606:4700:4700::1003
MTU = ${WG_MTU}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = [${SERVER_PUBLIC_IPV6}]:${SERVER_WG_PORT}
PersistentKeepalive = 25
EOF
}

function generate_client_wg_split_tunneling_if() {
    cat >${CLIENT_WG_SPLIT_TUNNELING_IF_CONF} <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_WG_IPV4}/32, ${CLIENT_WG_IPV6}/128
DNS = 127.0.0.1, ::1
MTU = ${WG_MTU}
PreUp = "C:\\Program Files\\WireGuard\\wireguard-hook\\hooks\\routes-up.bat"
PostUp = "C:\\Program Files\\WireGuard\\wireguard-hook\\hooks\\dns-up.bat"
PreDown = "C:\\Program Files\\WireGuard\\wireguard-hook\\hooks\\dns-down.bat"
PostDown = "C:\\Program Files\\WireGuard\\wireguard-hook\\hooks\\routes-down.bat"

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = 0.0.0.0/1, 128.0.0.0/1, ::/1, 8000::/1
Endpoint = [${SERVER_PUBLIC_IPV6}]:${SERVER_WG_PORT}
PersistentKeepalive = 25
EOF
}

function generate_all_clients_wg_ifs() {
    if [ -d "${SERVER_WG_IF_CONF_ROOT_DIR}" ]; then
        cd ${SERVER_WG_IF_CONF_ROOT_DIR}
    else
        echo "ERROR: No such a directory!"
        echo "  - /etc/wireguard"
        exit 1
    fi

    if [ -f "wg0.conf" ] && [ -f "wg0-client.conf" ] && [ -f "wg0-client.split-tunneling.conf" ]; then
        local CLIENT_WG_IF_CONFS=(
            "3 asuswrt.conf"
            "4 ubuntu.conf"
            "5 macos.conf"
            "6 windows.conf"
            "6 windows.split-tunneling.conf"
            "7 ios.conf"
            "8 ipados.conf"
            "9 android.conf"
        )

        for A_CLIENT_WG_IF_CONF in "${CLIENT_WG_IF_CONFS[@]}"; do
            local NUM=$(echo ${A_CLIENT_WG_IF_CONF} | cut -d ' ' -f1)
            local OS=$(echo ${A_CLIENT_WG_IF_CONF} | sed 's/^[0-9]* //; s/\.split-tunneling.*//')
            local FILENAME=$(echo ${A_CLIENT_WG_IF_CONF} | cut -d ' ' -f2)

            if [[ "${FILENAME}" == *"split-tunneling"* ]]; then
                cp wg0-client.split-tunneling.conf "${FILENAME}"

                sed -i "/PrivateKey/c\\$(grep "PrivateKey" ${OS}.conf)" "${FILENAME}"
                sed -i "/Address/c\\$(grep "Address" ${OS}.conf)" "${FILENAME}"
                sed -i "/PresharedKey/c\\$(grep "PresharedKey" ${OS}.conf)" "${FILENAME}"
            else
                cp wg0-client.conf "${FILENAME}"

                local CLIENT_WG_IPV4="10.0.0.${NUM}"
                local CLIENT_WG_IPV6="fd00::${NUM}"
                local CLIENT_PRIVATE_KEY="$(wg genkey)"
                local CLIENT_PUBLIC_KEY="$(echo ${CLIENT_PRIVATE_KEY} | wg pubkey)"
                local CLIENT_PRESHARED_KEY="$(wg genpsk)"

                sed -i "s|^\(PrivateKey\s*=\s*\).*|\1${CLIENT_PRIVATE_KEY}|" "${FILENAME}"
                sed -i "s|^\(Address\s*=\s*\).*|\1${CLIENT_WG_IPV4}/32, ${CLIENT_WG_IPV6}/128|" "${FILENAME}"
                sed -i "s|^\(PresharedKey\s*=\s*\).*|\1${CLIENT_PRESHARED_KEY}|" "${FILENAME}"

                cat >>wg0.conf <<EOF

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32, ${CLIENT_WG_IPV6}/128
EOF
            fi
        done
        chmod -R 400 SERVER_WG_IF_CONF_ROOT_DIR
        exit 0
    else
        echo "ERROR: No such files!"
        echo "  - /etc/wireguard/wg0.conf"
        echo "  - /etc/wireguard/wg0-client.conf"
        echo "  - /etc/wireguard/wg0-client.split-tunneling.conf"
        exit 1
    fi
}

function remove() {
    if [ -f "/usr/bin/wg" ] && [ -f "/usr/bin/wg-quick" ]; then
        wg-quick down ${SERVER_WG_NIC} >/dev/null 2>&1
        apt-get purge wireguard-tools -y >/dev/null 2>&1
        rm -rf ${SERVER_WG_IF_CONF_ROOT_DIR} >/dev/null 2>&1
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
  -h, --help         Show help manual
  -i, --install      Install "wireguard-tools"
  -g, --generate     Generate a pair of new WireGuard interface configuration files
  -G, --generate-all Generate some new WireGuard interface configuration files for all clients
                       - 3 asuswrt.conf
                       - 4 ubuntu.conf
                       - 5 macos.conf
                       - 6 windows.conf
                       - 6 windows.split-tunneling.conf
                       - 7 ios.conf
                       - 8 ipados.conf
                       - 9 android.conf
  -r, --remove       Remove "wireguard-tools"
EOF
    exit 0
}

function main() {
    distribution
    kernel
    root
    wg_tools_status

    if [ "$#" -eq 0 ]; then
        help
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                help
                ;;
            -i|--install)
                install_wg_tools
                ;;
            -g|--generate)
                generate_wg_ifs
                ;;
            -G|--generate-all)
                generate_all_clients_wg_ifs
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
