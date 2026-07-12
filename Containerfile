# 1. BASE IMAGE
FROM quay.io/fedora/fedora-bootc:44

# 2. HYPRLAND, SYSTEM CORE & HARDENED KERNEL
# We pull the hardened kernel COPR repository, then install Hyprland,
# its default terminal/dependencies, Distrobox, and Ansible.
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
# Force the system to use only the hardened kernel by removing the default
RUN dnf -y remove kernel kernel-core

# 4. ACCOUNT PROVISIONING
# Set up the isolated ansible-bot user
RUN useradd -m -s /bin/bash ansible-bot && \
    chmod 700 /home/ansible-bot

# 5. EMBED REMOTE TRACKING
# Links the installed system directly to your GitHub Container Registry for seamless updates
ARG IMAGE_URL=ghcr.io/your-github-username/octopus-linux:latest
RUN echo "io.containers.bootc.clonable=true" > /usr/lib/bootc/bound-images.d/octopus.conf && \
    echo "image = \"$IMAGE_URL\"" >> /usr/lib/bootc/bound-images.d/octopus.conf
