# oom-watch

Watch Linux OOM killer events and summarize memory pressure from the terminal.
One POSIX shell script, no dependencies.

When the kernel OOM killer terminates a process, the evidence is buried in the
kernel ring buffer. `oom-watch` extracts those events into a readable table and
pairs them with the current memory hogs, so post-mortems take seconds instead
of grep archaeology.

## Features

- `scan` - list OOM kill events (timestamp, pid, process, anon-rss) from
  `journalctl -k` / `dmesg`, or from any file with `-f`
- `top` - top processes by resident memory (RSS)
- `selftest` - built-in tests against an embedded fixture log
- Event count summary on stderr
- Works on Linux out of the box; on macOS use `scan -f FILE` with a copied log

## Usage

```console
$ oom-watch scan
Jun  4 09:12:01 | pid=1234   | python3                   | rss=1536000 kB
Jun  4 10:40:11 | pid=2048   | java                      | rss=6144000 kB
-- 2 OOM kill event(s) --

$ oom-watch scan -f /var/log/kern.log.1 -n 50
$ oom-watch top -n 10
 RSS(kB)  COMMAND
 8123456  /usr/lib/jvm/java-17/bin/java
 3210987  mysqld
 ...

$ oom-watch selftest
selftest: 8 passed, 0 failed
```

## Requirements

- POSIX shell (bash 3.2+ works), awk, ps, sort, head
- Linux: `journalctl` or `dmesg` for live scanning (root may be required)

## Testing

```console
$ ./oom-watch.sh selftest
```

The selftest verifies event extraction, RSS parsing and timestamps against a
fixture kernel log, and that `top` works on the current host.

## License

MIT
