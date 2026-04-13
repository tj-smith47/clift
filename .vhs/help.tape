# clift help system — top-level and per-command help
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/help.tape

Output .vhs/gifs/help.gif

Set Shell "bash"
Set FontSize 16
Set Width 900
Set Height 500
Set Padding 20
Set TypingSpeed 50ms

# Top-level help listing
Type "kube --help"
Enter
Sleep 3s

# Per-command help with flags
Type "kube deploy --help"
Enter
Sleep 3s
