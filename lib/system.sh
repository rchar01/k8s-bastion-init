reload_systemd() {
  systemctl daemon-reexec
  systemctl daemon-reload
}
