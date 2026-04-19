# clift aliases — commands AND flags can declare aliases.
# `deploy` → alias `dep`; `--target` → alias `--env`.
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/aliases.tape

Output .vhs/gifs/aliases.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Command alias: `dep` resolves to `deploy`
Type "kube dep --target staging"
Enter
Sleep 2s

# Flag alias: --env is an alias for --target
Type "kube deploy --env prod --force"
Enter
Sleep 2s

# --help shows the aliases declared on the command
Type "kube --help | head -20"
Enter
Sleep 3s
