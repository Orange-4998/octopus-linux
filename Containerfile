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

RUN dnf -y install 'dnf5-command(copr)'

RUN dnf -y copr enable lionheartp/Hyprland

RUN dnf clean all

RUN dnf -y install \
    # useradd
    shadow-utils \
    # Nvidia driver
    libva-nvidia-driver \
    egl-wayland \

    # Important LARPing
    fastfetch \
    systemd-ukify \
    
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

# fonts
RUN dnf install -y \
    fontconfig \
    dejavu-sans-mono-fonts \
    liberation-mono-fonts \
    google-noto-sans-fonts && \
    fc-cache -fv

# ========================================
# 2.1. INSTALLING OPEN SOURCE DRIVERS
# ========================================

# --- PURE OPEN SOURCE NVIDIA STACK (MESA + NVK + OPEN KERNEL) ---
# Target: bootc bare metal (Turing architectures and newer)

# 1. Install standard open source graphics libraries and tools
# This pulls in NVK, Zink, and the native VA-API translation layers via Mesa
RUN dnf install -y \
    mesa-vulkan-drivers \
    mesa-va-drivers \
    mesa-dri-drivers \
    vulkan-loader \
    kernel-devel-matched \
    kernel-headers \
    && dnf clean all

# 2. Add the out-of-tree open-source kernel driver modules
# (Note: For RHEL/Fedora streams transitioning to the modern 'Nova' Rust driver, 
# akmod-nvidia-open remains the bridge for compiling the open kernel modules)
RUN dnf install -y \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
    && dnf install -y akmod-nvidia-open \
    nvidia-gpu-firmware \
    xdg-desktop-portal-hyprland \
    && dnf clean all

# ========================================
# 2.2. PREPARING MOK KEYS
# ========================================

# 1. Create the target key directory infrastructure
RUN mkdir -p /etc/pki/akmods/private /etc/pki/akmods/certs /usr/share/octopus

# 2. Generate a valid, cryptographic Machine Owner Key pair inside the image layer
RUN openssl req -new -x509 -newkey rsa:2048 \
    -keyout /etc/pki/akmods/private/private.key \
    -out /etc/pki/akmods/certs/public.der \
    -nodes -days 3650 \
    -subj "/CN=Signed by the Maintainers of Octopus Linux/"

# 3. Cache a mirror clone of the public certificate for outside bare-metal enrollment
RUN cp /etc/pki/akmods/certs/public.der /usr/share/octopus/octopus-mok.der

# RUN sed -i 's|#WGKEY=.*|WGKEY=/etc/pki/akmods/private/private.key|' /etc/sysconfig/akmods && \
#    sed -i 's|#WGCERT=.*|WGCERT=/etc/pki/akmods/certs/public.der|' /etc/sysconfig/akmods

# ==========================================
# 2.3. COMPILING KERNEL WITH NVIDIA MODULE
# ==========================================

# Force compile the open-source kernel modules during the image build stage
RUN akmods --force --kernels $(rpm -q kernel --queryformat "%{VERSION}-%{RELEASE}.%{ARCH}\n" | tail -n 1)


# ==========================================
# 2.4. ENSURING NVIDIA WORKS WITH HYPRLAND
# ==========================================
# Allow GUI apps and Wayland shader compilation without SELinux execmem blocks
RUN setsebool -P selinuxuser_execmem 1 || true

# Kernel Arguments & Bootc Hooks
RUN mkdir -p /usr/lib/bootc/kargs.d && \
    echo 'kargs = ["nvidia-drm.modeset=1", "nvidia-drm.fbdev=1"]' > /usr/lib/bootc/kargs.d/nvidia.toml

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
# make data partition
RUN mkdir /data

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
    echo 'kargs = ["init_on_alloc=1", "init_on_free=1", "page_alloc.shuffle=1", "slab_nomerge", "vsyscall=none", "randomize_kstack_offset=on", "intel_iommu=on", "amd_iommu=on", "iommu=strict", "efi=disable_early_pci_dma", "lockdown=integrity"]' > /usr/lib/bootc/kargs.d/00-octopus-hardening.toml
# ==========================================
# 7. AUTOMATED SYSTEMD-BOOT & UKI PROFILES
# ==========================================
# 1. Enforce systemd-boot as the native system engine (bypassing GRUB entirely)
RUN mkdir -p /usr/lib/bootc/install.d && \
    echo '[install]' > /usr/lib/bootc/install.d/00-octopus.toml && \
    echo 'bootloader = "systemd-boot"' >> /usr/lib/bootc/install.d/00-octopus.toml

# 2. Instruct the image constructor to package everything into a single, cohesive UKI blob
# This combines the hardened kernel, your advanced kargs, and the initramfs components.
RUN mkdir -p /etc/kernel && \
    echo "layout=uki" > /etc/kernel/install.conf
