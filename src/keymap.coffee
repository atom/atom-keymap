Modifiers = ['Control', 'Alt', 'Shift', 'Meta']

module.exports =
class Keymap
  # Public: Translate a keydown event to a keystroke string.
  #
  # event - A {KeyboardEvent} of type 'keydown'
  #
  # Returns a {String} describing the keystroke.
  keystrokeStringForKeyboardEvent: (event) ->
    unless event.keyIdentifier in Modifiers
      if event.keyIdentifier.indexOf('U+') is 0
        hexCharCode = event.keyIdentifier[2..]
        charCode = parseInt(hexCharCode, 16)
        charCode = event.which if not @isAscii(charCode) and @isAscii(event.which)
        key = @keyFromCharCode(charCode)
      else
        key = event.keyIdentifier.toLowerCase()

    keystroke = []
    keystroke.push 'ctrl' if event.ctrlKey
    keystroke.push 'alt' if event.altKey
    if event.shiftKey
      # Don't push 'shift' when modifying symbolic characters like '{'
      keystroke.push 'shift' unless /^[^A-Za-z]$/.test(key)
      # Only upper case alphabetic characters like 'a'
      key = key.toUpperCase() if /^[^a-z]$/.test(key)
    keystroke.push 'cmd' if event.metaKey
    keystroke.push(key) if key?
    keystroke.join('-')

  keyFromCharCode: (charCode) ->
    switch charCode
      when 8 then 'backspace'
      when 9 then 'tab'
      when 13 then 'enter'
      when 27 then 'escape'
      when 32 then 'space'
      when 127 then 'delete'
      else String.fromCharCode(charCode)

  isAscii: (charCode) ->
    0 <= charCode <= 127

  # Deprecated: Translate a jQuery keyboard event to a keystroke string. Use
  # keystrokeStringForKeyboardEvent with a raw KeyboardEvent instead.
  keystrokeStringForEvent: (event) ->
    @keystrokeStringForKeyboardEvent(event.originalEvent ? event)
