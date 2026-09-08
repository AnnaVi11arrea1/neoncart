#!/usr/bin/env bash
# Privileged install steps for Neoncart on the Jetson.
# Run once:  sudo bash /home/anna/neoncart/deploy/install.sh
set -euo pipefail

cd /home/anna/neoncart

echo "==> 1/5 libvips (image variants for product photos)"
apt-get install -y libvips42 libvips-tools

echo "==> 2/5 systemd units"
cp deploy/neoncart.service deploy/neoncart-worker.service /etc/systemd/system/
systemctl daemon-reload

echo "==> 3/5 nginx site"
cp deploy/neoncart.nginx /etc/nginx/sites-available/neoncart
ln -sfn /etc/nginx/sites-available/neoncart /etc/nginx/sites-enabled/neoncart
nginx -t
systemctl reload nginx

echo "==> 4/5 start neoncart + worker"
systemctl enable --now neoncart neoncart-worker

echo "==> 5/5 reload cloudflared (picks up everfluorescent.com ingress)"
# NOTE: the systemd unit runs with `--config /etc/cloudflared/config.yml`, NOT
# the ~/.cloudflared/config.yml that `cloudflared tunnel ingress validate`
# reads by default. Editing only the home copy silently changes nothing.
install -m 644 -o root -g root /home/anna/.cloudflared/config.yml /etc/cloudflared/config.yml
cloudflared --config /etc/cloudflared/config.yml tunnel ingress validate
systemctl restart cloudflared

echo
echo "Done. Status:"
systemctl --no-pager --lines=0 status neoncart neoncart-worker cloudflared nginx | grep -E 'Loaded|Active|●' || true
