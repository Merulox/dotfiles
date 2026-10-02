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
