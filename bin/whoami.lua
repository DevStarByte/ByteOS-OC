-- whoami - print the user you are acting as (the kernel's view, not $USER)
term.write(k.user() .. "\n")
return 0
