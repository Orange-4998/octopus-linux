# ==========================================
# 1. BASE IMAGE
# ==========================================
FROM quay.io/fedora/fedora-bootc:44

# Define the user's OSNAME (defaults to octopus if not overridden)
ARG OSNAME=octopus

# ==========================================
# 2. HYPRLAND, NATIVE HARDENING & SYSTEM CORE
# ==========================================
# 1. Install native DNF5 plugins to unlock repository management.
# 2. Feed the official upstream Fedora 44 and updates repo configuration files directly to DNF5.
# 3. Layer strictly authorized user-space utilities and let DNF resolve the deep graphical dependencies.

# ==========================================
# UBlue NVIDIA Drivers
# ==========================================
COPY --from=ghcr.io/ublue-os/akmods-nvidia-open:main-44-7.1.3-201.fc44 / /tmp/akmods-nvidia
RUN find /tmp/akmods-nvidia
## optionally install remove old and install new kernel
# dnf -y remove --no-autoremove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra
## install ublue support package and desired kmod(s)
RUN dnf install /tmp/rpms/ublue-os/ublue-os-nvidia*.rpm
RUN dnf install /tmp/rpms/kmods/kmod-nvidia*.rpm

RUN dnf -y install 'dnf5-command(copr)'

RUN dnf -y copr enable lionheartp/Hyprland

RUN dnf clean all

RUN dnf -y install \
    # useradd
    shadow-utils \
    # Nvidia driver
    libva-nvidia-driver \

    # Important LARPing
    fastfetch \
    
    # Sound
    pipewire \
    wireplumber \
    rtkit \
    alsa-utils


RUN dnf -y install \
    # System necessities
    vim \
    neovim \
    emacs-nox \
    fdisk \
    testdisk \
    ranger \
    w3m \
    
    # Virtualization
    qemu-kvm \
    libvirt \
    virt-install \
    virt-manager \
    
    # Compositor & UI Shell
    hyprland \
    kitty \
    waybar \
    fish \
    distrobox \
    ansible-core \
    clevis \
    clevis-dracut \
    cryptsetup

RUN dnf clean all

# ==========================================
# 2.5. ENSURING NVIDIA WORKS WITH HYPRLAND
# ==========================================
# Kernel Arguments & Bootc Hooks
RUN mkdir -p /usr/lib/bootc/kargs.d && \
    echo "nvidia-drm.modeset=1" > /usr/lib/bootc/kargs.d/nvidia.karg

# Driver Framework Configuration Files
RUN echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1" > /etc/modprobe.d/nvidia-power.conf && \
    echo "options nvidia_drm fbdev=1" >> /etc/modprobe.d/nvidia-power.conf

# Environment Variables for System-Wide Wayland Optimization
RUN echo "GBM_BACKEND=nvidia-drm" >> /etc/environment && \
    echo "__GLX_VENDOR_LIBRARY_NAME=nvidia" >> /etc/environment && \
    echo "ENABLE_VKB_LAYERS=1" >> /etc/environment && \
    echo "NVD_BACKEND=direct" >> /etc/environment && \
    echo "LIBVA_DRIVER_NAME=nvidia" >> /etc/environment && \
    echo "ELECTRON_OZONE_PLATFORM_HINT=auto" >> /etc/environment && \
    echo "WLR_DRM_NO_MODIFIERS=1" >> /etc/environment

## systemctl stuff
RUN systemctl enable libvirtd.service

# ==========================================
# 3. USER SETUP
# ==========================================
# let's hope the user changes their password from the default
RUN useradd -m -d /var/home/ansible-bot -s /bin/bash -u 1001 ansible-bot
RUN useradd -m -d /var/home/human -s /usr/bin/fish -G wheel,ansible-bot -u 1000 human && \
    echo "human:octopus" | chpasswd

# Establish mounting layout directories before assigning immutable policies
RUN mkdir -p /var/data && \
    chown human:human /var/data && \
    chown human:ansible-bot /var/home && \
    chmod 2770 /var/home && \
    chmod 700 /var/data

# ==========================================
# 5. SYSTEM FISH SHELL ENTRY HOOK
# ==========================================
# This directory is parsed by Fish on startup regardless of what is inside /home.
COPY octopus-init.fish /usr/share/fish/vendor_conf.d/octopus-init.fish
RUN chmod 644 /usr/share/fish/vendor_conf.d/octopus-init.fish

# ==========================================
# 6. ADVANCED KERNEL HARDENING VIA KARGS
# ==========================================
# Baked directly into a single, cohesive line inside the bootc kargs registry.
RUN mkdir -p /usr/lib/bootc/kargs.d && \
    echo 'init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 slab_nomerge vsyscall=none randomize_kstack_offset=on intel_iommu=on amd_iommu=on iommu=strict efi=disable_early_pci_dma lockdown=integrity' > /usr/lib/bootc/kargs.d/00-octopus-hardening.conf
