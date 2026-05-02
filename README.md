# Thruk + Nagios + NSClient++ Monitoring Setup

## Purpose

Monitoring shows you the health of your servers in real time and alerts you when something breaks — before your users notice. This guide sets up a complete stack for monitoring Linux and Windows hosts with a modern web interface and desktop notifications.

## Requirements

- Ubuntu Server 24.04 LTS
- Nagios Core 4.4.6
- Thruk 3.28
- Apache2 + `mod_fcgid`
- mk-livestatus 1.5.0p25
- NSClient++ (on each Windows host)
- Tailscale (optional — if hosts are on different networks)
- Nagstamon (optional — for desktop alerts)
