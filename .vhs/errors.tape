# bm error UX — typo correction, choices violation, mutex violation. Every
# error names the offending value and points at the fix.
# Run standalone: vhs .vhs/errors.tape

Output .vhs/gifs/errors.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Typo with did-you-mean suggestion (subcommand alias is `ls`)
Type "bm lstt"
Enter
Sleep 2s

# Choices violation — --format must be one of table|json|yaml
Type "bm list --format bogus"
Enter
Sleep 2s

# Mutex — --add and --remove are in the same exclusive group 'mutation'
Type "bm tag mybook --add foo --remove bar"
Enter
Sleep 3s
