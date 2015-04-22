
function usb0up()
{
   sudo ifconfig usb0 hw ether aa:ab:5d:e5:63:67
   sudo ifconfig usb0 192.168.137.1 netmask 255.255.255.0 up
   sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
   sudo iptables -t nat -F
   sudo iptables -t nat -A POSTROUTING -j MASQUERADE
}
