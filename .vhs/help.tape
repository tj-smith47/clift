# clift help system — rich --help output with groups, choices, deprecated markers,
# and the shell-completion install hint at the bottom.
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/help.tape

Output .vhs/gifs/help.gif

Set Shell "bash"
Set FontSize 20
Set Width 1200
Set Height 1000
Set Padding 20
Set TypingSpeed 75ms

# Top-level help — commands + aliases + persistent flags
Type "kube --help"
Enter
Sleep 3s

# Per-command help — groups (output / auth), choices, deprecated, pattern
Type "clear && kube deploy --help"
Enter
Sleep 5s
