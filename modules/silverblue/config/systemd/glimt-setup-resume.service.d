[Unit]
Description=Resume Glimt Silverblue setup after reboot
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=%h/glimt/setup-silverblue.sh
ExecStartPost=/usr/bin/systemctl --user disable glimt-setup-resume.service
ExecStartPost=/usr/bin/rm -f %h/.config/glimt/setup/autoresume.enabled

[Install]
WantedBy=default.target
