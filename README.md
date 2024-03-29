# zfilter

## Installation

### imapfilter

```bash
$ sudo apt-get update
$ sudo apt-get install imapfilter
```

### zfilter

- `cd ~` (`/home/admin`)
- `sudo apt-get install git`
- `git clone https://github.com/chschlatter/zfilter.git .imapfilter`
- create password file for IMAP login: `echo "<pwd>" > .imap_password`, `chmod 600 .imap_password`
- create log file
```
$ sudo touch /var/log/imapfilter
$ sudo chgrp adm /var/log/imapfilter
$ sudo chmod 660 /var/log/imapfilter
```
- test run: `imapfilter -c .imapfilter/config.lua -l /var/log/imapfilter`

### systemd

```bash
$ cd ~ (`/home/admin`)
$ sudo cp .imapfilter/imapfilter.service /etc/systemd/system
$ sudo systemctl daemon-reload
$ sudo systemctl enable imapfilter
$ sudo systemctl start imapfilter.service
```

## Monitoring

```bash
$ systemctl status imapfilter
$ sudo journalctl -u imapfilter.service -f -n 500
```

## Updating

```bash
$ sudo systemctl reload imapfilter.service
```

## cron (optional)

- Copy `imapfilter.cron` into `/etc/cron.hourly/`
