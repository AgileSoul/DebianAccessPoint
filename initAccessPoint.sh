#!/usr/bin/env bash

if [ $EUID -ne 0 ]; then
    echo -e "\e[31mExiting...\e[0m \e[36mAre you root ?\e[0m"
    exit 1
fi

clear

# Path to the directory containing the executable script
readonly AccessPointPath=$(dirname $(readlink -f $0))
readonly AccessPointLibPath="$AccessPointPath/lib"

# Original files to save later
readonly InterfacesOriginalFile="/etc/network/interfaces"
readonly DhcpDefaultConfigFile="/etc/default/isc-dhcp-server"
readonly DhcpServerConfigFile="/etc/dhcp/dhcpd.conf"

# ========== < Lib Utils > ============
source "$AccessPointLibPath/resolutionUtils.sh"
source "$AccessPointLibPath/colorUtils.sh"
source "$AccessPointLibPath/fileUtils.sh"

# ========== < Configure Variables > ============
AccessPointState="Not Ready"

# Access point interface and forwarding interface
declare -Ar AllInterfaces=( 
  ["AccessPoint"]="wlan1" 
  ["Forward"]="wlan0" 
)

check_interfaces_integrity()
{
    local interface
    for interface in "${AllInterfaces[@]}"
    do
        if ! ifconfig "$interface" &> /dev/null; then
            echo -e "$AccessPointDefaultError the interface [$Verde$interface$TerminarColor] isn't configured, please configure it"
            return 1
        fi
    done

    local -r ipRegex='[0-9]{2,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'

    readonly ForwardIp=$(ifconfig "${AllInterfaces["Forward"]}" | grep -E "$ipRegex" | awk '{print $2}')
    if [ ! $ForwardIp ]; then
        echo -e "$AccessPointDefaultError the forward interface [$Verde${AllInterfaces["Forward"]}$TerminarColor] hasn't Ip, please connect it to a wifi network"
        return 2
    fi
}

get_network_info()
{
    local -r idVlanForward=$(echo $ForwardIp | cut -d "." -f 3 )
    
    if [  $idVlanForward -gt 244 ]; then
        local -r idVlanAccessPoint=$(($idVlanForward - 10))
    else
        local -r idVlanAccessPoint=$(($idVlanForward + 10))
    fi

    readonly AccessPointIp="$(echo "$ForwardIp" |
      sed -r "s/^([0-9]+\.[0-9]+\.)$idVlanForward\.[0-9]+$/\1$idVlanAccessPoint.1/")"
    readonly AccessPointNetmask="255.255.255.0"
    readonly AccessPointBroadcast="$(echo "$AccessPointIp" | cut -d "." -f 1,2,3).255"
    readonly AccessPointSubnet="${AccessPointIp%.*}.0"
    readonly AccessPointDhcpRange="${AccessPointIp%.*}.2 ${AccessPointIp%.*}.254"
    readonly AccessPointDnsServer="8.8.8.8"
}

set_interfaces_config()
{
    readonly InterfacesOriginalCopyFile="$AccessPointPath/interfacesOriginalCopy"

    move_file "$InterfacesOriginalFile" "$InterfacesOriginalCopyFile" set_ 

    local -r configuration=(
      "auto lo" "iface lo inet loopback" "" "auto ${AllInterfaces["AccessPoint"]}" 
      "iface ${AllInterfaces["AccessPoint"]} inet static" "   address $AccessPointIp" 
      "   netmask $AccessPointNetmask" "   broadcast $AccessPointBroadcast" 
    )
    
    generate_config_file "$InterfacesOriginalFile" configuration[@]
}

unset_interfaces_config()
{
    if move_file "$InterfacesOriginalCopyFile" "$InterfacesOriginalFile" unset_; then
        echo -e "$RESTORESuccessLine Restoring $CyanCursiva$InterfacesOriginalFile$TerminarColor..."
    else
        echo -e "$RESTOREFailedLine Failed to restoring $CyanCursiva$InterfacesOriginalFile$TerminarColor..."
    fi
}

set_hostapd_config()
{
    readonly HostapdConfigFile="/etc/hostapd/hostapd.conf"

    readonly SSID="Password is 9876543210"
    local -r password="9876543210"
    local -r channel=5

    # I delete "wpa_key_mgmt=WPA­-PSK" becouse i have an error starting hostapd service.
    # Attempt uncomment it if you don't have errors with "wpa_key_mgmt=WPA­-PSK"
    local -r configuration=(
      "interface=${AllInterfaces["AccessPoint"]}" "driver=nl80211" 
      "ssid=$SSID" "channel=$channel" "hw_mode=g" "auth_algs=1" 
      "wpa=2" "wpa_passphrase=$password" #"wpa_key_mgmt=WPA­-PSK" 
      "wpa_pairwise=TKIP CCMP" "rsn_pairwise=CCMP" "ap_max_inactivity=21600"
    )
    
    generate_config_file "$HostapdConfigFile" configuration[@]

    # Assure the config file is previously loaded in the daemon
    local -r hostapdDaemon="/etc/init.d/hostapd"
    if ! cat "$hostapdDaemon" | grep -Eq "^DAEMON_CONF=$HostapdConfigFile$"; then
        echo -e "$AccessPointDefaultError the config file isn't loaded in $hostapdDaemon"
        echo "Please make sure to load this line: 'DAEMON_CONF=$HostapdConfigFile' in $hostapdDaemon"
        return 1
    fi
}

unset_hostapd_config()
{
    if [ -f "$HostapdConfigFile" ]; then
        rm "$HostapdConfigFile"
    fi
}

set_dhcp_config()
{
    readonly DhcpDefaultConfigCopyFile="$AccessPointPath/isc-dhcp-serverOriginal"
    if [ ! -f "$DhcpDefaultConfigFile" ]; then
        echo -e "$AccessPointDefaultError $DhcpDefaultConfigFile is missing"
        return 1  
    fi

    # Specify the access point interface for the dhcp server.
    local -r old_dhcp_interfacesv4="$(grep -E "^INTERFACESv4=\".*\"$" $DhcpDefaultConfigFile)"
    local -r new_dhcp_interfacesv4="$(echo "$old_dhcp_interfacesv4" | 
      sed -r "s/(^INTERFACESv4=)\".*\"$/\1\"${AllInterfaces["AccessPoint"]}\"/")"
    
    if [ ! "$old_dhcp_interfacesv4" -o ! "$new_dhcp_interfacesv4" ]; then
        echo -e "$AccessPointDefaultError Cannot find 'INTERFACESv4' in $DhcpDefaultConfigFile"
        return 2
    fi

    move_file "$DhcpDefaultConfigFile" "$DhcpDefaultConfigCopyFile" set_

    sed -r "s/^INTERFACESv4=\".*\"$/$new_dhcp_interfacesv4/g" $DhcpDefaultConfigCopyFile \
    > $DhcpDefaultConfigFile

    readonly DhcpServerConfigCopyFile="$AccessPointPath/dhcpdOriginal.conf"

    move_file "$DhcpServerConfigFile" "$DhcpServerConfigCopyFile" set_

    local -r dhcp_server_configuration=(
      "option domain-name \"example.org\";"
      "option domain-name-servers ns1.example.org, ns2.example.org;"
      "" 
      "default-lease-time 600;"
      "max-lease-time 7200;"
      ""
      "ddns-update-style none;"
      ""
      "authoritative;"
      ""
      "subnet $AccessPointSubnet netmask $AccessPointNetmask"
      "{"
      "    range $AccessPointDhcpRange;"
      "    option routers $ForwardIp;"
      "    option subnet-mask $AccessPointNetmask;"
      "    option domain-name-servers $AccessPointDnsServer;"
      "}"
    )

    generate_config_file "$DhcpServerConfigFile" dhcp_server_configuration[@]
}

unset_dhcp_config()
{
    if move_file "$DhcpDefaultConfigCopyFile" "$DhcpDefaultConfigFile" unset_; then
        echo -e "$RESTORESuccessLine Restoring $CyanCursiva$DhcpDefaultConfigFile$TerminarColor..."
    else
        echo -e "$RESTOREFailedLine Failed to restoring $CyanCursiva$DhcpDefaultConfigFile$TerminarColor..."
    fi

    if move_file "$DhcpServerConfigCopyFile" "$DhcpServerConfigFile" unset_; then
        echo -e "$RESTORESuccessLine Restoring $CyanCursiva$DhcpServerConfigFile$TerminarColor..."
    else
        echo -e "$RESTOREFailedLine Failed to restoring $CyanCursiva$DhcpServerConfigFile$TerminarColor..."
    fi
}

restart_services()
{
    if [ "$AccessPointState" != "Ready" ]; then return 1; fi

    local -r SERVICESLine="$AmarilloOscuro[$PurpuraOscuro*$AmarilloOscuro]$TerminarColor"
    local -r SERVICESSuccessLine="$Amarillo[$Purpura-$Amarillo]$TerminarColor"
    local -r SERVICESFailedLine="$Amarillo[$Rojo-$Amarillo]$TerminarColor"

    echo -e "$SERVICESLine Restarting the services!"

    if ip addr flush dev "${AllInterfaces["AccessPoint"]}"; then
        echo -e "$SERVICESSuccessLine Ready to reset $Purpura${AllInterfaces["AccessPoint"]}$TerminarColor Ip" 
    else
        echo -e "$SERVICESFailedLine Cannot delete current $Purpura${AllInterfaces["AccessPoint"]}$TerminarColor Ip. Error (${Purpura}2$TerminarColor)"
        return 1
    fi

    if systemctl restart networking; then 
        echo -e "$SERVICESSuccessLine Networking service ${Purpura}successfully$TerminarColor resumed"
    else
        echo -e "$SERVICESFailedLine Cannot restart networking service. Error (${Purpura}2$TerminarColor)"
        return 2
    fi

    if systemctl restart NetworkManager; then
        echo -e "$SERVICESSuccessLine NetworkManager service ${Purpura}successfully$TerminarColor resumed"
    else
        echo -e "$SERVICESFailedLine Cannot restart NetworkManager service. Error (${Purpura}3$TerminarColor)"
        return 3
    fi

    AccessPointState="Not Ready"
}

start_access_point()
{
    if ! systemctl is-enabled hostapd &> /dev/null && ! systemctl status hostapd &> /dev/null; then
        if ! systemctl unmask hostapd &> /dev/null ; then return 1; fi
        if ! systemctl enable hostapd &> /dev/null ; then return 2; fi
    fi

    xterm -title "Access point: $SSID" $TOPLEFT -fg "#ff5400" -bg "#03071e" -e \
      "systemctl start hostapd && systemctl status hostapd" & 
    readonly AccessPointPID=$!
}

stop_access_point()
{   
    if [ ! "$AccessPointPID" ]; then return 1; fi
    
    systemctl stop hostapd &> /dev/null
    systemctl disable hostapd &> /dev/null
    kill $AccessPointPID 2> /dev/null
}

start_dhcp_server()
{
    if ! systemctl is-enabled isc-dhcp-server &> /dev/null && \
      ! systemctl status isc-dhcp-server &> /dev/null; then
        if ! systemctl enable isc-dhcp-server &> /dev/null; then return 1; fi
    fi

    xterm -title "Dhcp service" $TOPRIGHT -fg "#ff0000" -bg "#03071e" -e \
      "systemctl start isc-dhcp-server && systemctl status isc-dhcp-server" &
    readonly DhcpServerPID=$!
}

stop_dhcp_server()
{
    if [ ! "$DhcpServerPID" ]; then return 1; fi

    systemctl stop isc-dhcp-server &> /dev/null
    systemctl disable isc-dhcp-server &> /dev/null
    kill $DhcpServerPID 2> /dev/null
}

readonly RESTORESuccessLine="$Gris[$Cyan-$Gris]$TerminarColor"
readonly RESTOREFailedLine="$Gris[$Rojo-$Gris]$TerminarColor"

restore_original_files()
{
    if [ "$AccessPointState" == "Not Ready" ]; then return 1; fi

    local -r RESTORELine="$GrisOscuro[$CyanOscuro*$GrisOscuro]$TerminarColor"

    echo -e "$RESTORELine Restoring original files!"
    
    unset_interfaces_config
    unset_hostapd_config
    unset_dhcp_config

    # This activate restart_services function
    AccessPointState="Ready"
}

stop_servers()
{
    if [ "$AccessPointState" != "Running" ]; then return 1; fi
    
    local -r SERVERSLine="$AzulOscuro[$AmarilloOscuro*$AzulOscuro]$TerminarColor"
    local -r SERVERSSuccessLine="$Azul[$Amarillo-$Azul]$TerminarColor"
    local -r SERVERSFailedLine="$Azul[$Rojo-$Azul]$TerminarColor"

    echo -e "$SERVERSLine Stopping all servers!"

    if stop_access_point; then
        echo -e "$SERVERSSuccessLine Stop access point \"$SSID\" ${AmarilloOscuro}Successfully$TerminarColor"
    fi

    if stop_dhcp_server; then
        echo -e "$SERVERSSuccessLine Stop dhcp server ${AmarilloOscuro}Successfully$TerminarColor"
    fi

    # Stop spinner
    kill "$spinnerPID" 2> /dev/null 

    AccessPointState="Ready"
}

set_access_point_config()
{
    if check_interfaces_integrity; then 
        get_network_info
        set_interfaces_config
    else
        return 1;
    fi

    if ! set_hostapd_config; then 
        unset_hostapd_config
        return 2
    fi

    if ! set_dhcp_config; then 
        unset_dhcp_config
        return 3
    fi
}

run_access_point()
{
    # Attempt restarting services
    if ! restart_services; then 
        echo -e "Failed to restarting the services, Exiting...\n"
        return 1
    fi
    echo
    if ! start_access_point; then
        echo - "Failed to start access point, Exiting..."
        return 2
    fi

    if ! start_dhcp_server; then
        echo -e "Failed to start dhcp server, Exiting..."
        return 3
    fi
}

access_point_running_spinner()
{
    local -r charSequence="-|+|*|/|\\|"
    printf '     '
    while true;
    do
    	for (( i=0; i<${#charSequence}; i++))
    	do
            sleep 0.6
            #printf "\b$RojoOscuro%s$VerdeOscuro%s$RojoOscuro%s$TerminarColor" "[ " "${charSequence:$i:1}" " ]"
    	    #printf "\b$RojoOscuro[ $VerdeOscuro${charSequence:i:1} $RojoOscuro]"
            echo -ne "\r\t\t$RojoOscuro[ $VerdeOscuro${charSequence:i:1} $RojoOscuro]"
        done 
    done
}

exit_script()
{
    echo -e "\n$AccessPointLine Exiting..."

    stop_servers
    sleep 0.9

    restore_original_files
    sleep 0.9

    restart_services
    sleep 0.9

    exit $1
}

access_point_main()
{
    readonly AccessPointLine="$RojoOscuro[$VerdeOscuro*$RojoOscuro]$TerminarColor"
    readonly AccessPointDefaultError="${RojoOscuro}Error:$TerminarColor"
    
    set_resolution

    if set_access_point_config; then 
        AccessPointState="Ready"
    else
        return 1
    fi

    if run_access_point; then
        AccessPointState="Running"
    else
        return 2
    fi
    
    echo -e "\t$AccessPointLine Access Point '$SSID' is ${Verde}running$TerminarColor $AccessPointLine"
    
    echo -e "\tPress [Ctrl + c] to shutdown the access point"
    access_point_running_spinner &
    local -r spinnerPID=$!
    
    while true
    do
        sleep 10
    done
}

trap exit_script "0" SIGINT SIGHUP

access_point_main 
exit_script $?

