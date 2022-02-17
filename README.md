# zfilter

## Installation

### imapfilter

- `sudo apt-get update`
- `sudo apt-get install imapfilter`

### zfilter

- `cd ~` (`/home/admin`)
- `sudo apt-get install git`
- `git clone https://github.com/chschlatter/zfilter.git .imapfilter`
- create password file for IMAP login: `echo "<pwd>" > .imap_password`, `chmod 600 .imap_password`
- test run: `imapfilter -c .imapfilter/config.lua`

### systemd

- `cd ~` (`/home/admin`)
- `sudo cp .imapfilter/imapfilter.service /etc/systemd/system`
- `sudo systemctl daemon-reload`
- `sudo systemctl enable imapfilter`
- `sudo systemctl start imapfilter.service`

## Monitoring

- `systemctl status imapfilter`
- `sudo journalctl -u imapfilter.service -f -n 500`

## Updating

- `sudo systemctl reload imapfilter.service`

## cron (optional)

- Copy `imapfilter.cron` into `/etc/cron.hourly/`
