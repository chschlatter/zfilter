# zfilter

## Installation

### imapfilter

- `sudo apt-get update`
- `sudo apt-get install imapfilter`
- Copy `config.lua` into `/home/admin/.imapfilter/`

### zfilter

- `sudo apt-get install git`

### systemd

- Copy `imapfilter.service` into `/etc/systemd/system/`
- `sudo systemctl daemon-reload`
- `sudo systemctl enable imapfilter`
- `sudo systemctl start imapfilter.service`

## Monitoring

- `systemctl status imapfilter`
- `sudo journalctl -u imapfilter.service -f -n 500`

## Updating

- `sudo systemctl reload imapfilter.service`

## cron

- Copy `imapfilter.cron` into `/etc/cron.hourly/`
