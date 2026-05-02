#!/bin/bash
#
# install-thruk.sh
# Convenience script to install Thruk + Livestatus on Ubuntu 24.04
# alongside an existing Nagios Core 4.x installation.
#
# USAGE: sudo ./install-thruk.sh
#
# This script automates the steps documented in the README.
# Read the README first — understanding what each step does is more
# valuable than running this blindly.

set -e

echo "==> Checking requirements..."
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)."
   exit 1
fi

if [[ ! -f /usr/local/nagios/bin/nagios ]]; then
   echo "Nagios was not found at /usr/local/nagios/. Install Nagios first."
   exit 1
fi

echo "==> Adding ConSol Labs repository..."
curl -fsS "https://labs.consol.de/repo/stable/monitoring-repo-consol-de-gpg-2026.asc" \
  -o /etc/apt/trusted.gpg.d/monitoring-repo-consol-de-gpg-2026.asc

echo "deb [signed-by=/etc/apt/trusted.gpg.d/monitoring-repo-consol-de-gpg-2026.asc] \
http://labs.consol.de/repo/stable/ubuntu $(lsb_release -cs) main" \
> /etc/apt/sources.list.d/labs-consol-stable.list

apt-get update

echo "==> Installing Apache fcgid module (required by Thruk)..."
apt-get install -y libapache2-mod-fcgid
a2enmod fcgid
systemctl restart apache2

echo "==> Installing Thruk..."
apt-get install -y thruk

echo "==> Installing Livestatus build dependencies..."
apt-get install -y build-essential libboost-all-dev librrd-dev socat

echo "==> Building mk-livestatus..."
cd /tmp
if [[ ! -f mk-livestatus-1.5.0p25.tar.gz ]]; then
   wget https://checkmk.com/support/1.5.0p25/mk-livestatus-1.5.0p25.tar.gz
fi
tar xzf mk-livestatus-1.5.0p25.tar.gz
cd mk-livestatus-1.5.0p25
./configure --with-nagios4
make
make install

echo "==> Enabling broker module in Nagios..."
if ! grep -q "broker_module=/usr/local/lib/mk-livestatus" /usr/local/nagios/etc/nagios.cfg; then
   echo "broker_module=/usr/local/lib/mk-livestatus/livestatus.o /usr/local/nagios/var/rw/live" \
     >> /usr/local/nagios/etc/nagios.cfg
fi

echo "==> Configuring Thruk backend..."
if ! grep -q "Thruk::Backend" /etc/thruk/thruk_local.conf 2>/dev/null; then
   cat >> /etc/thruk/thruk_local.conf <<'EOF'

<Component Thruk::Backend>
  <peer>
    name   = Local Nagios
    type   = livestatus
    <options>
      peer = /usr/local/nagios/var/rw/live
    </options>
  </peer>
</Component>
EOF
fi

echo "==> Granting www-data access to the Livestatus socket..."
usermod -aG nagios www-data

echo "==> Restarting all services..."
systemctl restart nagios
sleep 2
systemctl restart thruk
systemctl restart apache2

echo ""
echo "================================================================"
echo " Done!"
echo ""
echo " Open Thruk at: http://$(hostname -I | awk '{print $1}')/thruk/"
echo "   Default user:     thrukadmin"
echo "   Default password: thrukadmin"
echo ""
echo " IMPORTANT: change the default password now:"
echo "   htpasswd /etc/thruk/htpasswd thrukadmin"
echo ""
echo " Verify the Livestatus socket exists:"
echo "   ls -la /usr/local/nagios/var/rw/live"
echo "================================================================"
