#!/usr/bin/env bash

if [ $EUID -ne 0 ]; then
    echo -e "\e[31mExiting...\e[0m \e[36mAre you root ?\e[0m"
    exit 1
fi

# path to the directory containing the executable script
readonly AccessPointPath=$(dirname $(readlink -f $0))
readonly AccessPointLibPath="$AccessPointPath/lib"

readonly InterfaceAccessPoint="wlan1"
readonly InterfaceForward="wlan0" # this interface should have internet connection

# ========== < Lib Utils > ============
source "$AccessPointLibPath/resolutionUtils.sh"
source "$AccessPointLibPath/colorUtils.sh"
source "$AccessPointLibPath/fileUtils.sh"

get_network_info()
{
    local -r ipRegex='[0-9]{2,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'

    readonly ForwardIp=$(ifconfig "$InterfaceForward" | grep -E "$ipRegex" | awk '{print $2}')
    if [ ! "$ForwardIp" ]; then
        echo -e "$AccessPointDefaultError the interface [$Verde$InterfaceForward$TerminarColor] isn't configured, please connect it to internet"
        return 1
    fi

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
    readonly AccessPointDnsServers="8.8.8.8 8.8.4.4"

    set_interfaces_config
}

set_interfaces_config()
{
    readonly InterfacesOriginalFile="/etc/network/interfaces"
    readonly InterfacesOriginalCopyFile="$AccessPointPath/interfacesOriginalCopy"

    move_file "$InterfacesOriginalFile" "$InterfacesOriginalCopyFile" set_ 

    local -r configuration=(
      "auto lo" "iface lo inet loopback" "" "auto $InterfaceAccessPoint" \
      "iface $InterfaceAccessPoint inet static" "   address $AccessPointIp" \
      "   netmask $AccessPointNetmask" "   broadcast $AccessPointBroadcast" )
    
    generate_config_file "$InterfacesOriginalFile" configuration[@]
}

unset_interfaces_config()
{
    if move_file "$InterfacesOriginalCopyFile" "$InterfacesOriginalFile" unset_; then
        echo -e "$ExitSuccessLine Restoring $CyanCursiva$InterfacesOriginalFile$TerminarColor..."
    else
        echo -e "$ExitFailedLine Failed to restoring $CyanCursiva$InterfacesOriginalFile$TerminarColor..."
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
        "interface=$InterfaceAccessPoint" "driver=nl80211" \
        "ssid=$SSID" "channel=$channel" "hw_mode=g" "auth_algs=1" \
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
    readonly DhcpDefaultConfigFile="/etc/default/isc-dhcp-server"
    readonly DhcpDefaultConfigCopyFile="$AccessPointPath/isc-dhcp-serverOriginal"
    if [ ! -f "$DhcpDefaultConfigFile" ]; then
        echo -e "$AccessPointDefaultError $DhcpDefaultConfigFile is missing"
        return 1  
    fi

    # Specify the access point interface for the dhcp server.
    local -r old_dhcp_interfacesv4="$(grep -E "^INTERFACESv4=\".*\"$" $DhcpDefaultConfigFile)"
    local -r new_dhcp_interfacesv4="$(echo "$old_dhcp_interfacesv4" | 
      sed -r "s/(^INTERFACESv4=)\".*\"$/\1\"$InterfaceAccessPoint\"/")"
    
    if [ ! "$old_dhcp_interfacesv4" -o ! "$new_dhcp_interfacesv4" ]; then
        echo -e "$AccessPointDefaultError Cannot find 'INTERFACESv4' in $DhcpDefaultConfigFile"
        return 2
    fi

    move_file "$DhcpDefaultConfigFile" "$DhcpDefaultConfigCopyFile" set_

    sed -r "s/^INTERFACESv4=\".*\"$/$new_dhcp_interfacesv4/g" $DhcpDefaultConfigCopyFile \
    > $DhcpDefaultConfigFile
}

unset_dhcp_config()
{
    if move_file "$DhcpDefaultConfigCopyFile" "$DhcpDefaultConfigFile" unset_; then
        echo -e "$ExitSuccessLine Restoring $CyanCursiva$DhcpDefaultConfigFile$TerminarColor..."
    else
        echo -e "$ExitFailedLine Failed to restoring $CyanCursiva$DhcpDefaultConfigFile$TerminarColor..."
    fi
}

restart_services()
{
    echo -e "$AccessPointVLine Resarting the services..."
    if ! ip addr flush "$InterfaceAccessPoint"; then return 1; fi

    if ! systemctl restart networking; then return 2; fi

    if ! systemctl restart NetworkManager; then return 3; fi
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

    sleep 20
}

stop_access_point()
{   
    if [ ! "$AccessPointPID" ]; then return 1; fi
    
    systemctl stop hostapd &> /dev/null
    systemctl disable hostapd &> /dev/null
    kill $AccessPointPID
}

stop_servers()
{
    if stop_access_point; then
        echo -e "$ExitSuccessLine Stop access point \"$SSID\" ${VerdeOscuro}Successfully$TerminarColor"
    fi
}

exit_script()
{
    local -r ExitSuccessLine="$Rojo[$Verde-$Rojo]${TerminarColor}"
    local -r ExitFailedLine="$Rojo[-]${TerminarColor}"

    unset_interfaces_config
    unset_hostapd_config
    unset_dhcp_config
    stop_servers
    echo -e "$ExitSuccessLine Exiting..."; sleep 0.2
}

prep_access_point()
{
    if ! get_network_info; then return 1; fi

    if ! set_hostapd_config; then return 2; fi

    if ! set_dhcp_config; then return 3; fi
}

run_access_point()
{
    # Attempt restarting services
    if ! restart_services; then 
        echo -e "Failed to restarting the services [Error $Rojo$?$TerminarColor], Exiting..."
        return 1
    fi

    if ! start_access_point; then
        echo - "Failed to start access point [Error $Rojo$?$TerminarColor], Exiting..."
        return 2
    fi
}

access_point_main()
{
    readonly AccessPointVLine="$RojoOscuro[$VerdeOscuro*$RojoOscuro]$TerminarColor"
    readonly AccessPointDefaultError="${RojoOscuro}Error:$TerminarColor"
    
    set_resolution

    if ! prep_access_point; then return 1; fi
    if ! run_access_point; then return 2; fi

    exit_script
}

if ! access_point_main; then exit_script; fi