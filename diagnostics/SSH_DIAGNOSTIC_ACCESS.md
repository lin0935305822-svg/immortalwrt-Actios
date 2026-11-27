# Workstation diagnostic access

`ssh_authorized_keys` contains one public Ed25519 key for this diagnostic session.
The private key stays on the operator's workstation and is not part of Git or
the Actions artifact. The fingerprint is
`SHA256:jtOYtnKBSZH0Rx+zaraQj+wdEsU6WxeEC8t2vJTR2JY`.

The workflow installs the public key as `/etc/dropbear/authorized_keys`, mode
`0600`, only when `ramoops_diag=true`. Ordinary builds do not stage this file.
The existing Dropbear LAN firewall and disabled password authentication remain
in force. The final image gate compares the installed key to the source file
and checks its permissions.

This access is used to read pstore, boot ID, uptime, scan events and kmsg after
the device reboots. It does not change the kernel, Wi-Fi/BT driver or firmware,
or protected storage. It is development access, not production acceptance.
Revoke it by removing the diagnostic authorized key on the device or flashing
an ordinary build; remove the workstation private key after the investigation.
