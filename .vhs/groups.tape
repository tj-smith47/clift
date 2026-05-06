# bm flag groups — mutex (exclusive). `tag --add` and `tag --remove` are in the
# `mutation` exclusive group; pick one per invocation.
# (For a requires-all group example, see tj-smith47/jarvis where
# `note --encrypt` requires --passphrase; that demo lives in the jarvis repo.)
# Run standalone: vhs .vhs/groups.tape

Output .vhs/gifs/groups.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Seed a bookmark to mutate.
Type "bm add https://taskfile.dev --name task --tag rust"
Enter
Sleep 2s

# Mutex violation: --add and --remove cannot both be set
Type "bm tag task --add cli --remove rust"
Enter
Sleep 2s

# Group satisfied — adding tags only
Type "bm tag task --add cli --add bash"
Enter
Sleep 2s

# Group satisfied — removing tags only
Type "bm tag task --remove rust"
Enter
Sleep 3s
