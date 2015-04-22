## Remote access Jetson TK1 device with micro USB cable

since Jetson TK1 has a USB device(OTG) port, we can enable network access via USB with RNDIS/NCM protocol which is same as Android's 'USB tethering' function.

Below is the steps to enable RNDIS, which is well supported by Linux and Windows Host.


### L4T Kernel Change

* Prebuilt zImage:https://github.com/DavidPu/jetsontk1-rndis-config/raw/master/tk1/zImage.CONFIG_USB_G_ANDROID

* Enable Android USB Composite driver

```bash
$ git diff
diff --git a/arch/arm/configs/tegra12_defconfig b/arch/arm/configs/tegra12_defconfig
index 8c86912..d255005 100644
--- a/arch/arm/configs/tegra12_defconfig
+++ b/arch/arm/configs/tegra12_defconfig
@@ -470,8 +470,7 @@ CONFIG_USB_TEGRA_OTG=y
 CONFIG_USB_GADGET=y
 CONFIG_USB_GADGET_VBUS_DRAW=500
 CONFIG_USB_TEGRA=y
-CONFIG_USB_ETH=m
-CONFIG_USB_MASS_STORAGE=m
+CONFIG_USB_G_ANDROID=y
 CONFIG_MMC=y
 CONFIG_MMC_UNSAFE_RESUME=y
 CONFIG_MMC_BLOCK_MINORS=16
diff --git a/drivers/usb/phy/tegra-otg.c b/drivers/usb/phy/tegra-otg.c
index 7e9307c..737c45e 100644
--- a/drivers/usb/phy/tegra-otg.c
+++ b/drivers/usb/phy/tegra-otg.c
@@ -939,8 +939,8 @@ static int tegra_otg_probe(struct platform_device *pdev)
 	}
 
 	tegra = tegra_clone;
-	if (!tegra->support_usb_id && !tegra->support_pmu_id
-					&& !tegra->support_gpio_id) {
+	if (1/*!tegra->support_usb_id && !tegra->support_pmu_id
+					&& !tegra->support_gpio_id*/) {
 		err = device_create_file(&pdev->dev, &dev_attr_enable_host);
 		if (err) {
 			dev_warn(&pdev->dev,
```

### Device Side Ubuntu (14.04) Configuration

* Add init script to bringup up rndis0 interface

add /etc/init/rndis.conf:

```bash
$cat /etc/init/rndis.conf
# RNDIS interface

description     "RNDIS interface init script"

start on started udev

task

script
        echo 1 > /sys/devices/platform/tegra-otg/enable_device
        echo 0 > /sys/devices/platform/tegra-otg/enable_host
        if [ -e /sys/class/android_usb/android0/enable ]; then
                echo 0 > /sys/class/android_usb/android0/enable
                #/sys/class/android_usb/android0/iSerial
                echo NVIDIA > /sys/class/android_usb/android0/f_rndis/manufacturer
                echo 0955 > /sys/class/android_usb/android0/f_rndis/vendorID
                echo 1 > /sys/class/android_usb/android0/f_rndis/wceis
                echo d4:01:29:9d:10:e2 >  /sys/class/android_usb/android0/f_rndis/ethaddr
                echo NVIDIA > /sys/class/android_usb/android0/iManufacturer
                echo L4T > /sys/class/android_usb/android0/iProduct
                echo 0 >  /sys/class/android_usb/android0/enable
                echo 0955 > /sys/class/android_usb/android0/idVendor
                echo cf03 > /sys/class/android_usb/android0/idProduct
                echo "rndis" > /sys/class/android_usb/android0/functions
                echo 224 > /sys/class/android_usb/android0/bDeviceClass
                echo 1 > /sys/class/android_usb/android0/enable
                sleep 4
                ifconfig rndis0 hw ether fa:de:73:32:0c:31
                ifconfig rndis0 192.168.137.2 netmask 255.255.255.0 up
                route add default gw 192.168.137.1 dev rndis0
        fi

end script
```

* change rndis0 interface to fixed MAC in order to prevent NetworkManager control it

```bash
$cat /etc/network/interfaces
#auto rndis0
iface rndis0 inet static
    address 192.168.137.2
    gateway 192.168.137.1
    broadcast 192.168.137.255
    netmask 255.255.255.0
    hwaddress ether fa:de:73:32:0c:31
    dns-nameservers 10.19.185.252 10.19.185.253 10.18.26.252
    up route add default gw 192.168.137.1 dev rndis0
```

* set above fixed MAC address as unmanaged device
```bash
$cat /etc/NetworkManager/NetworkManager.conf
[main]
plugins=ifupdown,keyfile,ofono
dns=dnsmasq

[ifupdown]
managed=false

[keyfile]
unmanaged-devices=mac:fa:de:73:32:0c:31
```

* Device Side: Edit /etc/resolv.conf to add your DNS server

```bash
sudo sh -c "echo nameserver 10.19.185.252 > /etc/resolv.conf"

```

Note: it would be overwritten by NetworkManager after boot, you can save above modified /etc/resolv.conf to somewhere(e.g:~/rndis.resolv.conf) and use below command to mount it after boot each time:
```bash
$sudo mount --bind ~/rndis.resolv.conf /etc/resolv.conf
```

### Host Ubuntu(14.04) Configuration

* Add static usb0 interface

```bash
$cat /etc/network/interfaces
#auto usb0
iface usb0 inet static
    address 192.168.137.1
    netmask 255.255.255.0
    hwaddress ether aa:ab:5d:e5:63:67
```

* Prevent Host side NetworkManager to control usb0:
```bash
$cat /etc/NetworkManager/NetworkManager.conf
[main]
plugins=ifupdown,keyfile,ofono
dns=dnsmasq

[ifupdown]
managed=false

[keyfile]
unmanaged-devices=mac:aa:ab:5d:e5:63:67
```

* Host side script to enable NAT

added below script into your ~/.bashrc:
```bash
function usb0up()
{
   sudo ifconfig usb0 hw ether aa:ab:5d:e5:63:67
   sudo ifconfig usb0 192.168.137.1 netmask 255.255.255.0 up
   sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
   sudo iptables -t nat -F
   sudo iptables -t nat -A POSTROUTING -j MASQUERADE

}
```

take effect:
```bash
$source ~/.bashrc 
```

* run usb0up after device is booted up and showing usb0 network interface from host side:
```
$usb0up
```

* Check SSH /Internet access
```bash
from PC　host:
#ping 192.168.137.2

#ssh ubuntu@192.168.137.2

run firefox via SSH X11 forwarding:
#ssh -X ubuntu@192.168.137.2
#firefox

from device:
#dig www.google.com

```

### Access from Windows 7/8

* Windows 7/8 has built-in RNDIS driver, plug usb cable to your PC after L4T boot up, there is a RNDIS device shows up as below:

![search path](host-win7/win_devmgr.png?raw=true)


* go to Control Panel --> Network and Internet --> Network and Sharing Center --> Change Adapter Settings, select RNDIS adapter and change to a fixed IP address(192.168.137.1):

![search path](host-win7/win_rndis_adapter_fixip.png?raw=true)

* Share Internet access with other adapter(wifi or ethernet):

![search path](host-win7/win_rndis_share_eth.png?raw=true)


* Verify If ping/ssh is working

![search path](host-win7/ping_putty.png?raw=true)

* Config Device side DNS:

![search path](host-win7/l4t_dns.png?raw=true)

Have Fun!

