#!/bin/bash
set -euo nounset

read -rp "Enter your Linux username for auto-login and fingerprint setup: " USER_NAME

SWAPFILE="/swapfile"

#!/bin/bash

# Safe execution function with error handling
function safe_run {
    "$@" || { echo -e "\n[ERROR] Command failed: $*" >&2; exit 1; }
}

echo "[INFO] Updating system..."
safe_run sudo apt update
safe_run sudo apt upgrade -y

echo "[INFO] Enabling 'universe' repository if not already enabled..."
safe_run sudo add-apt-repository universe -y
safe_run sudo apt update

echo "[INFO] Installing KDE Plasma (minimal) and essential KDE applications..."
safe_run sudo apt install -y --no-install-recommends \
  kde-plasma-desktop sddm dolphin konsole kate vlc \
  kdeconnect plasma-discover plasma-nm plasma-pa powerdevil \
  kde-spectacle kde-config-screenlocker kde-config-gtk-style \
  kde-config-plymouth kscreen bluedevil \
  kio-extras kamoso dolphin-plugins ark filelight

# Check if SDDM is correctly installed before proceeding
if ! command -v sddm &> /dev/null; then
    echo "[ERROR] SDDM not found! Installation failed or package missing."
    echo "[INFO] Reverting to GDM3 as fallback..."
    echo "/usr/sbin/gdm3" | sudo tee /etc/X11/default-display-manager > /dev/null
    safe_run sudo apt install -y gdm3
    safe_run sudo systemctl enable gdm3 --now
    exit 1
fi

echo "[INFO] Setting SDDM as default display manager..."
echo "/usr/sbin/sddm" | sudo tee /etc/X11/default-display-manager > /dev/null
safe_run sudo dpkg-reconfigure -fnoninteractive sddm

echo "[INFO] Disabling GDM3 (if installed)..."
safe_run sudo systemctl disable gdm3 --now || true

echo "[INFO] Enabling and starting SDDM..."
safe_run sudo systemctl enable sddm --now

echo "[SUCCESS] KDE Plasma and SDDM have been installed and configured."

echo "[INFO] Removing GNOME Desktop and bloatware..."
safe_run sudo apt purge -y ubuntu-desktop gnome-shell gdm3 gnome-session gnome-terminal nautilus gedit \
    evince yelp gnome-control-center gnome-software gnome-calendar cheese gnome-screenshot \
    rhythmbox totem eog transmission-gtk libreoffice* thunderbird snapd
safe_run sudo apt autoremove -y --purge

echo "[INFO] Creating 8GB swapfile for hibernation..."
safe_run sudo fallocate -l 8G "$SWAPFILE"
safe_run sudo chmod 600 "$SWAPFILE"
safe_run sudo mkswap "$SWAPFILE"
safe_run sudo swapon "$SWAPFILE"
echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null

echo "[INFO] Configuring hibernation resume..."
SWAP_UUID=$(sudo blkid -s UUID -o value "$(findmnt -no SOURCE -T "$SWAPFILE")")
echo "RESUME=UUID=$SWAP_UUID" | sudo tee /etc/initramfs-tools/conf.d/resume > /dev/null
safe_run sudo sed -i "s|^GRUB_CMDLINE_LINUX=\"|GRUB_CMDLINE_LINUX=\"resume=UUID=$SWAP_UUID |" /etc/default/grub
safe_run sudo update-initramfs -u
safe_run sudo update-grub

echo "[INFO] Configuring KDE auto-login for user: $USER_NAME"
safe_run sudo mkdir -p /etc/sddm.conf.d
cat <<EOF | sudo tee /etc/sddm.conf.d/autologin.conf > /dev/null
[Autologin]
User=$USER_NAME
Session=plasma.desktop
EOF

echo "[INFO] Enabling graphical boot target..."
safe_run sudo systemctl set-default graphical.target

echo "[INFO] Installing fprintd for fingerprint support..."
safe_run sudo apt install -y fprintd libpam-fprintd

echo "[INFO] Checking fingerprint device and support..."
if sudo fprintd-list "$USER_NAME" &>/dev/null; then
    echo "[INFO] Fingerprint already enrolled for user $USER_NAME."
else
    if lsusb | grep -iE 'fingerprint|Validity|Synaptics' &>/dev/null || \
       sudo systemctl is-active fprintd.service &>/dev/null; then
        echo "[INFO] Fingerprint device detected."
        echo "[ACTION] Run the following command after reboot to enroll:"
        echo "         fprintd-enroll"
    else
        echo "[WARN] No fingerprint device detected or supported driver not installed."
    fi
fi

echo "[INFO] Installing Chrome, Brave, VS Code, Sublime, Warp, Node.js, Python..."

# Chrome
wget -qO - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null

# Brave
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave.com/signing-key.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null

# VS Code
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/packages.microsoft.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/vscode stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

safe_run sudo apt update
safe_run sudo apt install -y google-chrome-stable brave-browser code

# Sublime
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo gpg --dearmor -o /usr/share/keyrings/sublime.gpg
echo "deb [signed-by=/usr/share/keyrings/sublime.gpg] https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list > /dev/null
safe_run sudo apt update
safe_run sudo apt install -y sublime-text

# Warp Terminal
WARP_DEB="warp-terminal.deb"
wget https://releases.warp.dev/linux/download -O "$WARP_DEB"
safe_run sudo apt install -y ./"$WARP_DEB"
rm -f "$WARP_DEB"

# Node.js + Python
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
safe_run sudo apt install -y nodejs python3 python3-pip

echo -e "\\n✅ Setup Complete! Please reboot your system."
