# 1. BASE IMAGE
FROM quay.io/fedora/fedora-bootc:44

# Define the user's OSNAME (defaults to octopus if not overridden)
ARG OSNAME=octopus

# 2. HYPRLAND, SYSTEM CORE & HARDENED KERNEL
RUN dnf -y copr enable turing/kernel-hardened && \
    dnf -y install \
    kernel-hardened \
    hyprland \
    kitty \
    waybar \
    distrobox \
    ansible-core \
    && dnf clean all

# 3. ADVERSARY DEFENSE & SYSTEM HARDENING
RUN dnf -y remove kernel kernel-core

# 4. ACCOUNT PROVISIONING
RUN useradd -m -s /bin/bash ansible-bot && \
    chmod 700 /home/ansible-bot

# 5. DYNAMIC FSTAB PROVISIONING
# We write the filesystem logic mapping directly to the OSNAME variables.
# Note the strict security mount flags required for your /data partition.
RUN echo "LABEL=${OSNAME}-ESP   /boot/efi   vfat    defaults        0 2" >> /etc/fstab && \
    echo "LABEL=${OSNAME}-ROOT  /           ext4    defaults        1 1" >> /etc/fstab && \
    echo "LABEL=${OSNAME}-HOME  /home       ext4    defaults        1 2" >> /etc/fstab && \
    echo "LABEL=${OSNAME}-DATA  /data       ext4    defaults,noexec,nosuid,nodev  1 2" >> /etc/fstab

# 6. EMBED REMOTE TRACKING
ARG IMAGE_URL=ghcr.io/orange-4998/octopus-linux:latest
RUN echo "io.containers.bootc.clonable=true" > /usr/lib/bootc/bound-images.d/octopus.conf && \
    echo "image = \"$IMAGE_URL\"" >> /usr/lib/bootc/bound-images.d/octopus.conf
