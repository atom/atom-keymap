helpers = require '../src/helpers'

count = 0

normalize = (keystrokes) ->
  count++
  helpers.normalizeKeystrokes(keystrokes)

start = Date.now()

for letter in 'abcdefghijklmnopqrztuvwxyz0123456789'
  normalize(letter)
  normalize("shift-#{letter}")

  normalize("cmd-#{letter}")
  normalize("cmd-shift-#{letter}")
  normalize("cmd-alt-#{letter}")
  normalize("cmd-alt-ctrl-#{letter}")
  normalize("cmd-alt-ctrl-shfit-#{letter}")
  normalize("cmd-#{letter} cmd-v")

  normalize("alt-#{letter}")
  normalize("alt-shift-#{letter}")
  normalize("alt-cmd-#{letter}")
  normalize("alt-cmd-ctrl-#{letter}")
  normalize("alt-cmd-ctrl-shift-#{letter}")
  normalize("alt-#{letter} alt-v")

  normalize("ctrl-#{letter}")
  normalize("ctrl-shift-#{letter}")
  normalize("ctrl-alt-#{letter}")
  normalize("ctrl-alt-cmd-#{letter}")
  normalize("ctrl-alt-cmd-shift#{letter}")
  normalize("ctrl-#{letter} ctrl-v")

console.log "Normalized #{count} keystrokes in #{Date.now() - start}ms"
