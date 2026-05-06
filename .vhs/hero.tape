# bm hero — a small bookmark manager built on clift. Three commands, six flags,
# a persistent profile, and dynamic completion — all the framework's primary
# surface in under 600 lines of bash.
# Run standalone: vhs .vhs/hero.tape

Output .vhs/gifs/hero.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 900
Set Padding 20
Set TypingSpeed 75ms

# Add a bookmark with a list flag (--tag, repeatable) and a string flag.
Type "bm add https://taskfile.dev --name task --tag rust --tag build"
Enter
Sleep 2s

# List in JSON — choices flag (--format) drives the renderer.
Type "bm list --format json"
Enter
Sleep 3s

# Persistent flag — --profile is declared once, accepted on every command.
Type "bm --profile work add https://example.com --name w"
Enter
Sleep 3s
