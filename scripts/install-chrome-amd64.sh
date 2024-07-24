#!/bin/bash
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list
rm -f /tmp/chrome_linux_signing_key.pub

apt-get install -y google-chrome-stable --no-install-recommends --fix-missing 