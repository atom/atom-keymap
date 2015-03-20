helpers = require '../src/helpers'

start = Date.now()

for letter in 'abcdefghijklmnopqrztuvwxyz'
  helpers.normalizeKeystrokes(letter)
  helpers.normalizeKeystrokes("shift-#{letter}")

  helpers.normalizeKeystrokes("cmd-#{letter}")
  helpers.normalizeKeystrokes("cmd-shift-#{letter}")
  helpers.normalizeKeystrokes("cmd-alt-#{letter}")
  helpers.normalizeKeystrokes("cmd-alt-ctrl-#{letter}")
  helpers.normalizeKeystrokes("cmd-alt-ctrl-shfit-#{letter}")
  helpers.normalizeKeystrokes("cmd-#{letter} cmd-v")

  helpers.normalizeKeystrokes("alt-#{letter}")
  helpers.normalizeKeystrokes("alt-shift-#{letter}")
  helpers.normalizeKeystrokes("alt-cmd-#{letter}")
  helpers.normalizeKeystrokes("alt-cmd-ctrl-#{letter}")
  helpers.normalizeKeystrokes("alt-cmd-ctrl-shift-#{letter}")
  helpers.normalizeKeystrokes("alt-#{letter} alt-v")

  helpers.normalizeKeystrokes("ctrl-#{letter}")
  helpers.normalizeKeystrokes("ctrl-shift-#{letter}")
  helpers.normalizeKeystrokes("ctrl-alt-#{letter}")
  helpers.normalizeKeystrokes("ctrl-alt-cmd-#{letter}")
  helpers.normalizeKeystrokes("ctrl-alt-cmd-shift#{letter}")
  helpers.normalizeKeystrokes("ctrl-#{letter} ctrl-v")

console.log Date.now() - start
