# bm persistent flags — --profile is declared on the root Taskfile, accepted
# either before OR after any command. Cuts across every command, segregating
# the bookmark store per-profile.
# Run standalone: vhs .vhs/persistent.tape

Output .vhs/gifs/persistent.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Persistent flag BEFORE the command — wrapper binds it early.
Type "bm --profile work add https://taskfile.dev --name task"
Enter
Sleep 2s

# Same persistent flag AFTER the command — equally valid.
Type "bm add https://example.com --name example --profile home"
Enter
Sleep 2s

# Each profile sees only its own store.
Type "bm --profile work list && bm --profile home list"
Enter
Sleep 3s
