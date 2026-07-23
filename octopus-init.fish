# octopus-init.fish
# Only execute on physical TTY1 for our main user
if test (tty) = "/dev/tty1"; and test "$USER" = "human"
    echo "=================================================="
    echo "      🐙 WELCOME TO OCTOPUS LINUX CONSOLE         "
    echo "=================================================="
    echo ""
    
    # Prompt user with a 5-second timeout
    read -P "Launch graphical Hyprland session now? [y/N]: " -l mood
    echo ""

    if test "$mood" = "y"; or test "$mood" = "Y"
        echo "[*] Initializing security blast-doors..."
        
        # 1. Decrypt and Mount Home Space
        if not test -d /var/home/human/.config
            sudo cryptsetup open /dev/disk/by-partlabel/octopus-HOME luks-home
            sudo mount /dev/mapper/luks-home /var/home/human
        end

        # 2. Decrypt and Mount Shuttle Data Space
        if not test -d /data/.mounted
            sudo cryptsetup open /dev/disk/by-partlabel/octopus-DATA luks-data
            sudo mount -o noexec,nosuid,nodev,discard=async /dev/mapper/luks-data /data
        end

        echo "[*] Launching Hyprland matrix..."
        exec Hyprland
    else
        echo "[*] Remaining in raw CLI mode. Type 'exec Hyprland' manually when ready."
    end
end
