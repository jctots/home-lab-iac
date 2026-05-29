# e1000e 0000:00:1f.6 enp0s31f6: Detected Hardware Unit Hang


The Direct OS Fix (Most Effective)
You need to disable the "Offloading" features that are crashing the card. We will do this by modifying your network configuration so it applies every time the server boots.

Identify your interface name: Run ip link or ip a. Look for the name of your physical Ethernet port (it will likely be eno1 or enp0s31f6).

Edit the network interfaces file:

``` Bash
nano /etc/network/interfaces
```

Find your interface entry: Locate the section for your physical card (usually right above auto vmbr0).

Add the post-up line: Add a line at the end of that specific interface section to disable the buggy features:

``` Plaintext
iface eno1 inet manual
    post-up /usr/sbin/ethtool -K $IFACE tso off gso off gro off
```

(Note: Using $IFACE automatically targets that specific port.)

Save and Exit: Press Ctrl+O, Enter, then Ctrl+X.

Apply the changes: Reboot your server.

To verify that your changes have been successfully applied to your Lenovo M720q after the reboot, you will use the ethtool command to query the live status of the network card.

Identify Your Interface
First, make sure you are checking the correct network card.

```Bash
ip link show
```

Look for your primary interface name (e.g., eno1 or enp0s31f6).

Verify Offloading Status

Run the following command to see the "Features" list for that interface:

``` Bash
ethtool -k <your_interface_name> | grep -E 'segmentation|receive-offload'
```

What you want to see in the output: If the fix worked, the following items should be marked as off:

tcp-segmentation-offload: off (This is TSO)

generic-segmentation-offload: off (This is GSO)

generic-receive-offload: off (This is GRO)

Note: If you see [fixed] next to a setting, it means that specific sub-feature is locked by the driver or hardware, but as long as the main "off" status is visible, the fix is active.