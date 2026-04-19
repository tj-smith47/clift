# jarvis persistent flags — --profile declared on the root Taskfile, accepted
# either before OR after any command. Cuts across every command.
# Run standalone: vhs .vhs/persistent.tape

Output .vhs/gifs/persistent.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Default profile (work) — briefing shows work-oriented content.
Type "jarvis brief --short"
Enter
Sleep 2s

# Persistent flag BEFORE the command — the wrapper binds it early.
Type "jarvis --profile home brief --short"
Enter
Sleep 2s

# Identical result, flag AFTER the command.
Type "jarvis brief --profile home --short"
Enter
Sleep 3s
