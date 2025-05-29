# Rocky Linux 9 Kickstart configuration
install
text
reboot
lang en_US.UTF-8
keyboard us
timezone America/New_York
rootpw --plaintext rocky
selinux --enforcing
firewall --enabled
network --bootproto=dhcp --device=eth0 --activate
bootloader --location=mbr --boot-drive=vda
zerombr
clearpart --all --initlabel

# Create partitions for UEFI boot
part /boot/efi --fstype=efi --size=600
part /boot --fstype=xfs --size=1024
part pv.01 --size=1 --grow
volgroup vg0 pv.01
logvol / --vgname=vg0 --size=1 --grow --name=root
logvol swap --vgname=vg0 --size=2048 --name=swap

auth --enableshadow --passalgo=sha512

%packages
@^minimal-environment
@core
openssh-server
%end

%post
# Enable SSH
systemctl enable sshd
# Disable root SSH login
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
%end 