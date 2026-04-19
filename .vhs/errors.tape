# jarvis error UX — typo correction, choices violation, pattern mismatch,
# mutex violation. Every error is actionable and names the offending value.
# Run standalone: vhs .vhs/errors.tape

Output .vhs/gifs/errors.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Typo with did-you-mean suggestion
Type "jarvis breif"
Enter
Sleep 2s

# Choices violation — priority must be low|med|high
Type "jarvis task add 'x' --priority bogus"
Enter
Sleep 2s

# Pattern violation — --in must match ^[0-9]+[smhd]$
Type "jarvis remind 'standup' --in 5"
Enter
Sleep 2s

# Mutex — --in and --at are in the same exclusive group 'when'
Type "jarvis remind 'standup' --in 10m --at 13:00"
Enter
Sleep 3s
