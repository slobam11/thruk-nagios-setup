# Contributing

Thanks for your interest in improving this guide! Pull requests and issues are welcome.

## How to contribute

### Reporting issues

If you ran into a problem the guide didn't cover, or noticed something inaccurate, please open an issue with:

- Your distribution and version (e.g., Ubuntu 24.04.4 LTS)
- Nagios Core version (`/usr/local/nagios/bin/nagios --version`)
- Thruk version (`dpkg -l | grep thruk`)
- The exact error message you saw
- The steps that led to the error

### Submitting changes

1. Fork the repository
2. Create a branch: `git checkout -b fix/short-description`
3. Make your changes — keep them focused and well-described
4. Test on a real system if possible
5. Open a pull request explaining what changed and why

## Style guide

- **Anonymize all real values.** No real IPs, hostnames, passwords, or domains. Use placeholders like `192.168.X.XX`, `100.X.X.XX`, `<PASSWORD>`, `winserverA`.
- **Match the existing tone.** Direct, practical, with copy-pasteable commands.
- **Document the *why*.** When showing a fix, explain why the problem occurred — not just the command that fixes it.
- **Test commands before submitting.** If a command doesn't run cleanly on a fresh system, it doesn't belong in the guide.

## Areas that would benefit from contributions

- Procedures for other distributions (Debian, RHEL, Rocky, AlmaLinux)
- Adding NRPE-based Linux monitoring examples
- Naemon as a Nagios alternative (Thruk's reference core)
- Grafana / PNP4Nagios integration
- HTTPS / TLS hardening for the Thruk web UI
- Translations (the guide is currently English only)

## Code of conduct

Be kind. Assume good faith. Help people learn.
