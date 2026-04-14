# Project Development Rules

## Git Workflow
- **Conventional Commits**: Always use the Conventional Commits specification for commit messages (e.g., `feat:`, `fix:`, `chore:`, `docs:`).
- **Proactive Commits**: Always commit changes after finishing a logical task or a major modification.
- **Logical Grouping**: Group related changes into single commits with descriptive messages.

## Build Process
- **Makefile**: Use `make build` to rebuild the application bundle and DMG installer after any changes to code or assets.
- **Asset Integrity**: Ensure `AppIcon.icns` is kept in sync with `icon.png` if branding changes.
