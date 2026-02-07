{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot.loader = {
    systemd-boot.enable = true;
    # Other than does not allowing EFI vars edition
    # the computer I'm running NixOS with is only
    # booting with Windows' EFI, so I need to manually
    # hijack the Windows EFI with the one of systemd-boot.
    # By "manually" I mean editing the partition with rEFInd.
    # There is no trace of that in this configuration file.
    efi.canTouchEfiVariables = false;
  }

  hardware.bluetooth.enable = true;

  networking = {
    hostName = "nixos"; # Define your hostname.
    networkmanager.enable = true;
  }

  time.timeZone = "Europe/Paris";

  i18n = {
    defaultLocale = "fr_FR.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "fr_FR.UTF-8";
      LC_IDENTIFICATION = "fr_FR.UTF-8";
      LC_MEASUREMENT = "fr_FR.UTF-8";
      LC_MONETARY = "fr_FR.UTF-8";
      LC_NAME = "fr_FR.UTF-8";
      LC_NUMERIC = "fr_FR.UTF-8";
      LC_PAPER = "fr_FR.UTF-8";
      LC_TELEPHONE = "fr_FR.UTF-8";
      LC_TIME = "fr_FR.UTF-8";
    };
  }

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
  ];

  services.printing.enable = false; # No CUPS on my system: don't need to print and vulnerable

  services.xserver = {
    enable = true;
    xkb = {
      layout = "fr";
      variant = "";
    };
  }
  console.keyMap = "fr";


  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Audio configuration
  services.pulseaudio.enable = false; # handled by pipewire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  nixpkgs.config.allowUnfree = true;

  services.redis.enable = true; # for testing rtdbin
  virtualisation.docker.enable = true;

  programs = {
    firefox.enable = true;
    git.enable = true;
  }

  environment.systemPackages = with pkgs; [
    easyeffects # EQ
    neovim
    vim
  ];

  users.users.antoine = {
    isNormalUser = true;
    description = "antoine";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      discord
      # gcc
      gnumake
      # kdePackages.kate
      keepassxc
      libgcc
      # mise
      prismlauncher
      # rquickshare # samsung quick share implementation
      rustup
      stow
      # thunderbird
      vscodium
      wezterm
    ];
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

}
