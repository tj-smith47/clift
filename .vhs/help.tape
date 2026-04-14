# clift help system — exploring help at every level
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/help.tape

Output .vhs/gifs/help.gif

Set Shell "bash"
Set FontSize 16
Set Width 900
Set Height 800
Set Padding 20
Set TypingSpeed 75ms

# Bare invocation — default help
Type "kube"
Enter
Sleep 4s

# Top-level help via flag
Type "clear && kube --help"
Enter
Sleep 4s

# Per-command help with flags
Type "clear && kube deploy --help"
Enter
Sleep 4s

# Subcommand help
Type "clear && kube deploy rollback --help"
Enter
Sleep 4s

# Help showing a required flag
Type "clear && kube logs --help"
Enter
Sleep 4s
