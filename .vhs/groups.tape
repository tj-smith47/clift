# jarvis flag groups — mutex (exclusive) and required-together (requires: all).
# `remind --in` / `--at` are in the `when` mutex group.
# `note --encrypt` / `--passphrase` are in the `enc` requires-all group.
# Run standalone: vhs .vhs/groups.tape

Output .vhs/gifs/groups.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Mutex violation: --in and --at can't both be set
Type "jarvis remind 'x' --in 10m --at 13:00"
Enter
Sleep 2s

# Requires-all violation: --encrypt without its partner --passphrase
Type "jarvis note 'secrets' --encrypt"
Enter
Sleep 2s

# Both satisfied — groups pass, note is saved encrypted
Type "jarvis note 'secrets' --encrypt --passphrase=hunter2 --tag private"
Enter
Sleep 3s
