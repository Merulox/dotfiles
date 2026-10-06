{ config, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    age
    direnv
    fd
    fzf
    gh
    git
    jq
    ripgrep
    shellcheck
    sops
  ];

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.local/state/nix/profiles/home-manager/home-path/bin"
  ];

  home.file.".local/bin/dev" = {
    source = ../workflow/bin/dev;
    executable = true;
  };

  home.file.".local/bin/slack-ops" = {
    source = ../workflow/bin/slack-ops;
    executable = true;
  };

  home.file.".local/bin/realm-session" = {
    source = ../workflow/bin/realm-session;
    executable = true;
  };
  home.file.".local/bin/session-workspace" = {
    source = ../workflow/bin/session-workspace;
    executable = true;
  };
  home.file.".local/bin/omp-lifecycle" = {
    source = ../workflow/bin/omp-lifecycle;
    executable = true;
  };
  home.file.".local/bin/backup-secrets-proton" = {
    source = ../workflow/bin/backup-secrets-proton;
    executable = true;
  };

  xdg.configFile."dev-workflow/projects.toml".source =
    ../workflow/config/projects.toml;
  xdg.configFile."dev-workflow/dev-workflow.zsh".source =
    ../workflow/shell/dev-workflow.zsh;

  xdg.dataFile."dev-workflow/templates/project" = {
    source = ../workflow/templates/project;
    recursive = true;
  };

  xdg.dataFile."dev-workflow/slack_ops" = {
    source = ../workflow/slack_ops;
    recursive = true;
  };
  systemd.user.services.slack-ops-sync = {
    Unit = {
      Description = "Project read-only operating state to Slack projections";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python ${../workflow/slack_ops/cli.py} sync --apply";
      Environment = "PATH=${pkgs.systemd}/bin:${config.home.homeDirectory}/.local/bin:/run/current-system/sw/bin";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };
  systemd.user.timers.slack-ops-sync = {
    Unit.Description = "Run Slack operating-state projection every 15 minutes";
    Timer = {
      OnBootSec = "5m";
      OnUnitActiveSec = "15m";
      RandomizedDelaySec = "45s";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
  home.activation.migrateDevWorkflowClaimGenerations =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.python3}/bin/python ${../workflow/bin/session-workspace} migrate-generations
    '';
  home.activation.secureAgentVaultData =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 0700 \
        "${config.home.homeDirectory}/.local/share/agent-vault" \
        "${config.home.homeDirectory}/.local/share/agent-vault/data"
    '';


  programs.git = {
    enable = lib.mkDefault true;
    settings = {
      init.defaultBranch = lib.mkDefault "main";
      pull.ff = lib.mkDefault "only";
      fetch.prune = lib.mkDefault true;
      rerere.enabled = lib.mkDefault true;
      push.autoSetupRemote = lib.mkDefault true;
    };
  };

  programs.direnv = {
    enable = lib.mkDefault true;
    nix-direnv.enable = lib.mkDefault true;
  };

  programs.zsh.initContent = lib.mkAfter ''
    source "${config.xdg.configHome}/dev-workflow/dev-workflow.zsh"
  '';
}
