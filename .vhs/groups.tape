# clift flag groups — mutex (exclusive) and required-together (requires: all).
# `--json` / `--yaml` are in the `output` mutex group.
# `--user` / `--token` are in the `auth` requires-all group.
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/groups.tape

Output .vhs/gifs/groups.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Mutex violation: --json and --yaml cannot both be set
Type "kube deploy --json --yaml"
Enter
Sleep 2s

# Requires-all violation: --user without its partner --token
Type "kube deploy --user alice"
Enter
Sleep 2s

# Both satisfied — groups pass, deploy runs
Type "kube deploy --user alice --token xyz --force --target prod"
Enter
Sleep 3s
