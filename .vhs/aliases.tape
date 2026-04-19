# jarvis aliases — commands AND flags can declare aliases; deprecated flags
# emit a one-shot warning and are flagged in help.
# Run standalone: vhs .vhs/aliases.tape

Output .vhs/gifs/aliases.gif

Set Shell "bash"
Set FontSize 22
Set Width 1200
Set Height 700
Set Padding 20
Set TypingSpeed 75ms

# Command alias: `n` resolves to `note`
Type "jarvis n 'quick idea' --tag arch"
Enter
Sleep 2s

# Subcommand alias: `task ls` resolves to `task list`
Type "jarvis task ls --priority high"
Enter
Sleep 2s

# Flag alias: --pri is an alias for --priority
Type "jarvis task add 'wire up jarvis' --pri low"
Enter
Sleep 2s

# Deprecated flag — still works, emits a warning
Type "jarvis task add 'old-school call' --urgency high"
Enter
Sleep 3s
