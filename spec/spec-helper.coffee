require 'coffee-cache'

exports.keydownEvent = (keyIdentifier, {ctrl, shift, alt, cmd, which, target}={}) ->
  event = document.createEvent('KeyboardEvent')
  bubbles = true
  cancelable = true
  view = null
  keyIdentifier = "U+#{keyIdentifier.charCodeAt(0).toString(16)}" if keyIdentifier.length is 1
  location = KeyboardEvent.DOM_KEY_LOCATION_STANDARD
  event.initKeyboardEvent('keydown', bubbles, cancelable, view,  keyIdentifier, location, ctrl, alt, shift, cmd)
  Object.defineProperty(event, 'target', get: -> target) if target?
  Object.defineProperty(event, 'which', get: -> which) if which?
  event
