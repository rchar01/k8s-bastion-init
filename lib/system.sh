#!/usr/bin/env bash

reload_systemd() {
  systemctl daemon-reexec
  systemctl daemon-reload
}
