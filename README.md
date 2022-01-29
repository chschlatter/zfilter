# zfilter

## Installation

- Copy `imapfilter.service` into `/etc/systemd/system/`
- `sudo systemctl daemon-reload`
- `sudo systemctl enable imapfilter`
- `sudo systemctl start imapfilter.service`

## Monitoring

- `systemctl status imapfilter`
- `sudo journalctl -u imapfilter.service -f -n 500`

## Updating

- `sudo systemctl reload imapfilter.service`

## cron

- Copy `imapfilter.cron` into `/etc/cron.hourly/`
