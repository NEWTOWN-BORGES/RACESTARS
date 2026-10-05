#!/usr/bin/env bash
# Gera todas as imagens em ../images (precisa de Node + Playwright com Chromium)
set -e
cd "$(dirname "$0")"
node shot.mjs 01-canal.html ../images/01-canal.png
node shot.mjs 02-mar.html ../images/02-mar.png
node shot.mjs 03-ceu.html ../images/03-ceu.png
node shot.mjs 04-floresta.html ../images/04-floresta.png
node shot.mjs 05-hangar.html ../images/05-hangar.png
node shot.mjs "file://$PWD/01-canal.html?hud=1" 01-canal-hud.png
node shot.mjs 06-gameplay.html ../images/06-gameplay.png
