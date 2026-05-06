# bm help — rich --help with subcommand aliases, choices, mutex groups,
# persistent flag rendering.
# Run standalone: vhs .vhs/help.tape

Output .vhs/gifs/help.gif

Set Shell "bash"
Set FontSize 20
Set Width 1200
Set Height 1000
Set Padding 20
Set TypingSpeed 75ms

# Top-level help — commands with aliases (list, ls), persistent --profile.
Type "bm --help"
Enter
Sleep 3s

# Per-command help — `tag` has a mutex group (mutation), --add and --remove.
Type "clear && bm tag --help"
Enter
Sleep 4s
