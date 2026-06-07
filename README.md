# Dotfiles

**A quiet, keyboard-driven NixOS environment built as an extension of thought.**

These are the configuration files behind my daily machine: NixOS, XMonad,
Emacs, dunst, i3blocks, shell utilities, connectivity helpers, and backup
scripts.

The aesthetic is restrained and functional. The environment should disappear
during focused work, expose state when it matters, and make repeated operations
available as compact commands.

## Principles

- Configuration should be explicit and recoverable.
- The keyboard is the primary control surface.
- Repeated actions should become small composable tools.
- System state should be legible without becoming visual noise.
- The environment should support deep work rather than perform technicality.
- Personal infrastructure should remain understandable by one person.

## Structure

- `nixos/` - declarative system, home, editor, notification, and window-manager
  configuration
- `i3blocks/` - compact status-bar configuration
- `scripts/` - machine-level utilities and frequently used commands

## Notable Commands

- `adl` - audio download workflow
- `airb` / `aird` - AirPods and audio controls
- `bconnect` / `dconnect` - connectivity helpers
- `dmenu-win` - window selection
- `dotfiles-link.sh` - dotfile linking
- `rclone-backup.sh` - backup workflow

## Recovery

The repository is the durable description of the environment, but applying
configuration remains a consequential action. Review local differences and
machine-specific assumptions before rebuilding NixOS or replacing active
configuration.

These files are personal infrastructure, not a general-purpose distribution.
