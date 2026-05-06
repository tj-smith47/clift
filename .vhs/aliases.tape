# bm aliases — subcommand aliases (`ls` resolves to `list`) and short-flag
# forms (`-n` resolves to `--name`, `-p` to `--profile`).
# (For command-level aliases and deprecated-flag warnings, see the
# tj-smith47/jarvis reference example.)
# Run standalone: vhs .vhs/aliases.tape

Output .vhs/gifs/aliases.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Seed a bookmark.
Type "bm add https://taskfile.dev -n task --tag build"
Enter
Sleep 2s

# Subcommand alias: `ls` resolves to `list`.
Type "bm ls"
Enter
Sleep 2s

# Short flag form: `-n` resolves to `--name`, `-p` to `--profile`.
Type "bm -p work add https://example.com -n example --tag misc"
Enter
Sleep 2s

# Per-command help shows the alias mapping.
Type "bm list --help"
Enter
Sleep 3s
