# ==========================================
# 1. BASE IMAGE
# ==========================================
FROM quay.io/fedora/fedora-bootc:44

# Define the user's OSNAME (defaults to octopus if not overridden)
ARG OSNAME=octopus

# ==========================================
# 2. HYPRLAND, HARDENED KERNEL & SYSTEM CORE
# ==========================================
RUN dnf -y install fedora-workstation-repositories && \
    dnf -y install \
        hyprland \
        kitty \
        waybar \
        fish \
        distrobox \
        ansible-core \
        clevis clevis-dracut clevis-systemd cryptsetup \
    && dnf clean all

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
Options=defaults,noexec,nosuid,nodev,discard=async\n\
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

# ==========================================
# 6. ADVANCED KERNEL HARDENING VIA KARGS
# ==========================================
# Baked directly into a single, cohesive line inside the bootc kargs registry.
RUN mkdir -p /usr/lib/bootc/kargs.d && \
    echo 'init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 slab_nomerge vsyscall=none randomize_kstack_offset=on intel_iommu=on amd_iommu=on iommu=strict efi=disable_early_pci_dma lockdown=integrity' > /usr/lib/bootc/kargs.d/00-octopus-hardening.conf
