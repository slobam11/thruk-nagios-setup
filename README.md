Thruk + Nagios + NSClient++ Monitoring Setup

Complete step-by-step guide for installing Thruk web interface on top of an existing Nagios Core installation, integrating Windows servers via NSClient++ over a Tailscale VPN mesh network. Includes all problems encountered during real-world deployment and their solutions.

Table of Contents

Environment Overview
Installing Thruk
Installing the Livestatus Module
Configuring Thruk to Read Nagios Data
Nagstamon Desktop Client Integration
Configuring NSClient++ Agents on Windows
Per-Host Password Custom Variables
What Can Be Monitored
Troubleshooting & Useful Commands


1. Environment Overview
Setup

Monitoring Host (Ubuntu 24.04.4 LTS Noble Numbat)

Local IP: 192.168.X.XX
Tailscale IP: 100.X.X.XX
Nagios Core 4.4.6 already installed at /usr/local/nagios/
Existing Nagios web UI: http://192.168.X.XX/nagios/


Goal: Add Thruk as a modern web interface alongside the classic Nagios CGI

Verify Ubuntu version
bashlsb_release -a
Verify Nagios version
bash/usr/local/nagios/bin/nagios --version | head -3

2. Installing Thruk
2.1 Add the ConSol Labs Repository
ConSol Labs maintains official Thruk packages for Ubuntu Noble (24.04).
bash# 1) Import the GPG key
curl -fsS "https://labs.consol.de/repo/stable/monitoring-repo-consol-de-gpg-2026.asc" \
  -o /etc/apt/trusted.gpg.d/monitoring-repo-consol-de-gpg-2026.asc

# 2) Add the repository
echo "deb [signed-by=/etc/apt/trusted.gpg.d/monitoring-repo-consol-de-gpg-2026.asc] \
http://labs.consol.de/repo/stable/ubuntu $(lsb_release -cs) main" \
> /etc/apt/sources.list.d/labs-consol-stable.list

# 3) Update and install
apt-get update
apt-get install -y thruk
2.2 ISSUE: thruk-base post-install script fails
Error:
dpkg: error processing package thruk-base (--configure):
 installed thruk-base package post-installation script subprocess returned error exit status 1
Cause: Apache mod_fcgid module is required by Thruk but not installed.
SOLUTION:
bashapt-get install -y libapache2-mod-fcgid
a2enmod fcgid
systemctl restart apache2

# Now thruk-base configures cleanly
dpkg --configure thruk-base
apt-get install -f
After successful installation:
Thruk has been configured for http://<HOSTNAME>/thruk/.
The default user is 'thrukadmin' with password 'thrukadmin'.

3. Installing the Livestatus Module
Thruk does not read Nagios state files directly — it talks to a Livestatus broker module loaded inside the Nagios process, which exposes a Unix socket.
3.1 Build dependencies
bashapt-get install -y build-essential libboost-all-dev librrd-dev
3.2 Build and install mk-livestatus
bashcd /tmp
wget https://checkmk.com/support/1.5.0p25/mk-livestatus-1.5.0p25.tar.gz
tar xzf mk-livestatus-1.5.0p25.tar.gz
cd mk-livestatus-1.5.0p25
./configure --with-nagios4
make
make install
3.3 ISSUE: configure fails on rrd_xport
Error:
configure: error: unable to find the rrd_xport function
SOLUTION:
bashapt-get install -y librrd-dev
./configure --with-nagios4
make && make install
3.4 Enable the broker module in Nagios
bashecho "broker_module=/usr/local/lib/mk-livestatus/livestatus.o /usr/local/nagios/var/rw/live" \
  >> /usr/local/nagios/etc/nagios.cfg

systemctl restart nagios

# Verify the socket exists
ls -la /usr/local/nagios/var/rw/live
Expected output:
srw-rw---- 1 nagios nagios 0 May  2 15:39 /usr/local/nagios/var/rw/live

4. Configuring Thruk to Read Nagios Data
4.1 Backend configuration
bashnano /etc/thruk/thruk_local.conf
Append to the file:
<Component Thruk::Backend>
  <peer>
    name   = Local Nagios
    type   = livestatus
    <options>
      peer = /usr/local/nagios/var/rw/live
    </options>
  </peer>
</Component>
4.2 ISSUE: Thruk shows 0 hosts / 0 services
Cause: Apache (www-data user) does not have permissions to read the Livestatus socket.
Verification: Livestatus is functioning correctly when tested from CLI:
bashapt-get install -y socat
echo "GET hosts" | socat - UNIX-CONNECT:/usr/local/nagios/var/rw/live | head -5
…but the Thruk web UI still shows zero data.
SOLUTION: Add www-data to the nagios group:
bashusermod -aG nagios www-data

systemctl restart nagios
systemctl restart thruk
systemctl restart apache2
After this, Thruk shows all hosts and services at http://<HOSTNAME>/thruk/.
4.3 Change the default password
bashhtpasswd /etc/thruk/htpasswd thrukadmin

5. Nagstamon Desktop Client Integration
In Nagstamon Settings → Servers → New:
FieldValueServer typeThruk (NOT Nagios!)Monitor namee.g. Thruk-PRODMonitor URLhttp://<HOSTNAME>/thruk/Monitor CGI URLhttp://<HOSTNAME>/thruk/cgi-bin/UsernamethrukadminPassword(the password set via htpasswd)

IMPORTANT: Server type must be Thruk, not Nagios. Thruk emulates the Nagios CGI URLs but uses its own API behind the scenes.


6. Configuring NSClient++ Agents on Windows
For Windows servers, Nagios uses the check_nt plugin to talk to NSClient++ on TCP port 12489.
6.1 Reaching the host over Tailscale
If a Windows server is only reachable via Tailscale (not the local LAN), use its Tailscale IP in windows.cfg:
bashnano /usr/local/nagios/etc/objects/windows.cfg
define host {
    use                     windows-server
    host_name               winserverA
    alias                   Windows Server A
    address                 100.X.XXX.XX    # ← Tailscale IP of the Windows host
}
6.2 Configure nsclient.ini on Windows
Open C:\Program Files\NSClient++\nsclient.ini as Administrator:
ini[/modules]
NSClientServer = 1
CheckSystem = 1
CheckDisk = 1
CheckExternalScripts = 1

[/settings/NSClient/server]
allowed hosts = 192.168.X.XX, 100.X.X.XX
password = <YOUR_PASSWORD>
port = 12489

[/settings/external scripts]
allow arguments = true
allow nasty characters = true

allowed hosts must contain the Nagios server's IP as it appears on the network used to reach this host:

192.168.X.XX — Nagios local IP
100.X.X.XX — Nagios Tailscale IP (this is what NSClient++ sees when connections come over Tailscale!)


6.3 ISSUE #1: Missing [/modules] section → port not listening
Symptom:
powershellPS> netstat -an | findstr 12489
(no output)
Cause: Without [/modules] NSClientServer = 1, NSClient++ starts but never opens the port.
SOLUTION: Add the [/modules] section as shown above and restart the service:
powershellStop-Service nscp
Start-Service nscp
netstat -an | findstr 12489
Expected output:
TCP    0.0.0.0:12489          0.0.0.0:0              LISTENING
6.4 ISSUE #2: Service is named nscp, not NSClient++
powershellPS> Restart-Service NSClient++
Restart-Service : Cannot find any service with service name 'NSClient++'
SOLUTION: The actual service name is nscp:
powershellGet-Service | Where-Object {$_.DisplayName -like "*NSC*"}
Restart-Service nscp
6.5 ISSUE #3: Windows Firewall blocks port 12489
Symptom: CHECK_NRPE STATE CRITICAL: Socket timeout after 10 seconds
SOLUTION: Add a firewall rule (PowerShell as Administrator):
powershellNew-NetFirewallRule -DisplayName "NSClient++ 12489" `
  -Direction Inbound -Protocol TCP -LocalPort 12489 -Action Allow
6.6 ISSUE #4: Rejected connection from: 100.X.X.XX
Symptom in nsclient.log:
error: Rejected connection from: 100.X.X.XX
Cause: The Nagios server's Tailscale IP is not in allowed hosts.
SOLUTION: Add the Tailscale IP of the Nagios host to nsclient.ini:
iniallowed hosts = 192.168.X.XX, 100.X.X.XX
Save the file and restart:
powershellStop-Service nscp
Start-Service nscp
6.7 ISSUE #5: CHECK_NRPE: Could not complete SSL handshake
Cause: Attempting to test the Windows agent with check_nrpe, but NSClient++ on port 12489 speaks the NSClient protocol, not NRPE!
SOLUTION: Use check_nt instead of check_nrpe:
bash/usr/local/nagios/libexec/check_nt -H <WINDOWS_IP> -p 12489 \
  -s <PASSWORD> -v CLIENTVERSION
If you see something like NSClient++ 0.9.15 2025-08-16 — it's working!
6.8 ISSUE #6: NSClient - ERROR: Invalid password
Cause: The Nagios check_nt command does not pass the -s PASSWORD parameter.
SOLUTION: See section 7. Per-Host Password Custom Variables.

7. Per-Host Password Custom Variables
Since each Windows server may have a different NSClient++ password, the cleanest solution is to define the password as a Nagios custom variable on each host.
7.1 Edit commands.cfg
bashnano /usr/local/nagios/etc/objects/commands.cfg
Locate the check_nt command and update command_line:
BEFORE:
define command{
    command_name    check_nt
    command_line    $USER1$/check_nt -H $HOSTADDRESS$ -p 12489 -v $ARG1$ $ARG2$
}
AFTER:
define command{
    command_name    check_nt
    command_line    $USER1$/check_nt -H $HOSTADDRESS$ -p 12489 -s $_HOSTNSCLIENT_PASSWORD$ -v $ARG1$ $ARG2$
}
7.2 Edit windows.cfg — add _NSCLIENT_PASSWORD per host
bashnano /usr/local/nagios/etc/objects/windows.cfg
define host {
    use                     windows-server
    host_name               winserverA
    alias                   Windows Server A
    address                 100.X.XXX.XX
    _NSCLIENT_PASSWORD      <PASSWORD_FOR_A>
}

define host {
    use                     windows-server
    host_name               winserverB
    alias                   Windows Server B
    address                 192.168.X.XXX
    _NSCLIENT_PASSWORD      <PASSWORD_FOR_B>
}

IMPORTANT: The leading _ is REQUIRED — that's how Nagios recognizes a custom variable.
In the command, it is referenced as $_HOSTNSCLIENT_PASSWORD$ (_HOST prefix + variable name without the leading underscore).

7.3 Verify and restart
bash/usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg | tail -10
systemctl restart nagios
7.4 Force an immediate recheck
If you don't want to wait for the next scheduled check:
bashecho "[$(date +%s)] SCHEDULE_FORCED_SVC_CHECK;winserverA;C:\\ Drive Space;$(date +%s)" \
  > /usr/local/nagios/var/rw/nagios.cmd

8. What Can Be Monitored
8.1 Standard check_nt commands for Windows
CommandDescriptionExampleCPULOADCPU loadcheck_nt!CPULOAD!-l 5,80,90MEMUSERAM usagecheck_nt!MEMUSE!-w 80 -c 90USEDDISKSPACEDisk usage by drive lettercheck_nt!USEDDISKSPACE!-l c -w 80 -c 90UPTIMETime since bootcheck_nt!UPTIMESERVICESTATEWindows service statuscheck_nt!SERVICESTATE!-d SHOWALL -l W3SVCPROCSTATEProcess running checkcheck_nt!PROCSTATE!-d SHOWALL -l notepad.exeCOUNTERPerformance counterscheck_nt!COUNTER!-l "\Network Interface(*)\Bytes Total/sec"CLIENTVERSIONNSClient++ versioncheck_nt!CLIENTVERSION
8.2 CPU Load — multiple time windows (Windows)
Similar to Linux load average: 1m, 5m, 15m:
check_command    check_nt!CPULOAD!-l 1,90,95,5,80,90,15,70,80

1 min — WARN 90%, CRIT 95%
5 min — WARN 80%, CRIT 90%
15 min — WARN 70%, CRIT 80%

8.3 Linux servers — over NRPE
For Linux hosts, check_nrpe is used to invoke commands locally on the target Linux machine:
check_command    check_nrpe!check_load
check_command    check_nrpe!check_disk
check_command    check_nrpe!check_users

9. Troubleshooting & Useful Commands
9.1 Quick diagnostics — Thruk not working
bash# Is Apache running?
systemctl status apache2

# Is the Thruk service running?
systemctl status thruk

# Does the Livestatus socket exist?
ls -la /usr/local/nagios/var/rw/live

# Does www-data have access?
groups www-data
9.2 Quick diagnostics — NSClient++ not responding
bash# Test from the Nagios host to a Windows host
/usr/local/nagios/libexec/check_nt -H <IP> -p 12489 -s <PASSWORD> -v CLIENTVERSION

# Verify the port is reachable at all
nc -zv <IP> 12489
On the Windows server:
powershell# Is the service running?
Get-Service nscp

# Is the port listening?
netstat -an | findstr 12489

# Tail the log
Get-Content "C:\Program Files\NSClient++\nsclient.log" -Tail 20
9.3 Most common issues
SymptomLikely causeFixThruk shows 0 itemswww-data not in nagios groupusermod -aG nagios www-dataSocket timeoutFirewall, port not listening, wrong IPCheck firewall + [/modules] sectionRejected connectionIP missing from allowed hostsAdd IP in nsclient.iniInvalid passwordNagios password ≠ nsclient.ini passwordSync _NSCLIENT_PASSWORDSSL handshake errorMixing check_nrpe and check_ntUse the right pluginPort 12489 not listeningMissing [/modules] in nsclient.iniAdd NSClientServer = 1command not found check_nrpePlugin not installedapt install nagios-nrpe-plugin
9.4 Log files
bash# Nagios log
tail -f /usr/local/nagios/var/nagios.log

# Apache error log
tail -f /var/log/apache2/error.log

# Thruk service log
journalctl -u thruk -f

# Validate the Nagios configuration
/usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg
9.5 Useful grep recipes
bash# List all Windows host definitions
grep -A5 "define host" /usr/local/nagios/etc/objects/windows.cfg

# List all check commands
grep -B1 -A2 "command_name" /usr/local/nagios/etc/objects/commands.cfg

# Find every reference to a specific host
grep -rn "winserverA" /usr/local/nagios/etc/objects/
9.6 Services that must be running
bashsystemctl status nagios
systemctl status apache2
systemctl status thruk

# Restart everything
systemctl restart nagios && systemctl restart thruk && systemctl restart apache2

Final Checklist

 Thruk repository added with the GPG key imported
 libapache2-mod-fcgid installed and fcgid module enabled
 Thruk package installed successfully (version 3.28+)
 librrd-dev and libboost-all-dev installed
 mk-livestatus 1.5.0p25 built and installed
 broker_module line added to nagios.cfg
 Nagios restarted, socket /usr/local/nagios/var/rw/live exists
 thruk_local.conf contains a <Component Thruk::Backend> block with the peer
 www-data user added to the nagios group
 Default thrukadmin password changed
 Thruk reachable at http://<IP>/thruk/ and shows hosts
 Nagstamon configured with Server type = Thruk
 check_nt command in commands.cfg uses $_HOSTNSCLIENT_PASSWORD$
 Every Windows host in windows.cfg has a _NSCLIENT_PASSWORD line
 nsclient.ini on every Windows server has the [/modules] section
 allowed hosts contains the Nagios IP (both LAN and Tailscale)
 Firewall rule for port 12489 added on every Windows server
 netstat shows port 12489 LISTENING
 check_nt -v CLIENTVERSION returns the NSClient++ version
 All monitored services in Thruk show OK or accurate status


License
MIT License — feel free to adapt this guide to your own environment.
This documentation was written based on a real-world troubleshooting session — every error and solution comes from production experience.
