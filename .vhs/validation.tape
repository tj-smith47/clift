# clift flag validation — `choices:` constrains to an enum, `pattern:` to a regex.
# Both fail fast with a clear message before the user script ever runs.
# Prerequisite: run scripts/record-demos.sh (sets up kube on PATH)
# Run standalone: vhs .vhs/validation.tape

Output .vhs/gifs/validation.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# choices: bogus value rejected with the allowed list
Type "kube deploy --target bogus"
Enter
Sleep 2s

# pattern: 1.2 doesn't match semver; error names the offending pattern
Type "kube deploy --semver 1.2"
Enter
Sleep 2s

# Both constraints satisfied — deploy proceeds
Type "kube deploy --semver v1.2.3 --target prod --force"
Enter
Sleep 3s
