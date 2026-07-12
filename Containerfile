# ==========================================
# 1. BASE IMAGE
# ==========================================
FROM quay.io/fedora/fedora-bootc:44

# Define the user's OSNAME (defaults to octopus if not overridden)
ARG OSNAME=octopus

# ==========================================
# 2. HYPRLAND, HARDENED KERNEL & SYSTEM CORE
# ==========================================
RUN dnf -y copr enable turing/kernel-hardened && \
    dnf -y install \
    kernel-hardened \
    kernel-hardened-modules \
    hyprland \
    kitty \
    waybar \
    fish \
    distrobox \
    ansible-core \
    clevis clevis-dracut clevis-systemd cryptsetup \
    && dnf clean all

# Force the system to prioritize the hardened kernel on boot
RUN echo "UPDATER_DEFAULT_KERNEL=kernel-hardened" >> /etc/sysconfig/kernel

# ==========================================
# 3. USER SETUP
# ==========================================
RUN useradd -m -s /bin/bash ansible-bot
RUN useradd -m -s /usr/bin/fish -G wheel human && \
    echo "human:octopus" | chpasswd

# Establish mounting layout directories before assigning immutable policies
RUN mkdir -p /home/box-data /data && \
    chown human:human /data && \
    chown -R human:human /home/box-data

# ==========================================
# 4. IMMUTABLE SYSTEMD BLAST-DOOR MOUNTS
# ==========================================
# File paths must explicitly map to the mount destinations (hyphens for slashes)

# --- /home Mount (ext4) ---
RUN echo -e "[Unit]\n\
Description=User Space Home Directory (/home)\n\
ConditionPathExists=/home\n\
\n\
[Mount]\n\
What=LABEL=${OSNAME}-HOME\n\
Where=/home\n\
Type=ext4\n\
Options=defaults\n\
\n\
[Install]\n\
WantedBy=multi-user.target" > /usr/lib/systemd/system/home.mount

# --- /data Mount (Btrfs with SSD TRIM and strict blast-door security flags) ---
RUN echo -e "[Unit]\n\
Description=Secure Data Partition (/data)\n\
ConditionPathExists=/data\n\
\n\
[Mount]\n\
What=LABEL=${OSNAME}-DATA\n\
Where=/data\n\
Type=btrfs\n\
Options=defaults,noexec,nosuid,nodev,discard=async,workqueue=0\n\
\n\
[Install]\n\
WantedBy=multi-user.target" > /usr/lib/systemd/system/data.mount

# Force enable the immutable units so they run on system targets
RUN systemctl enable home.mount data.mount

# ==========================================
# 5. EMBED REMOTE TRACKING
# ==========================================
ARG IMAGE_URL=ghcr.io/orange-4998/octopus-linux:latest
RUN mkdir -p /usr/lib/bootc/bound-images.d && \
    echo "io.containers.bootc.clonable=true" > /usr/lib/bootc/bound-images.d/octopus.conf && \
    echo "image = \"$IMAGE_URL\"" >> /usr/lib/bootc/bound-images.d/octopus.conf
