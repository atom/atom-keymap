require 'coffee-cache'

beforeEach ->
  document.querySelector('#jasmine-content').innerHTML = ""

exports.keydownEvent = (key, {ctrl, shift, alt, cmd, which, target}={}) ->
  event = document.createEvent('KeyboardEvent')
  bubbles = true
  cancelable = true
  view = null
  key = key.toUpperCase() if /^[a-z]$/.test(key) and shift
  if key.length is 1
    keyIdentifier = "U+#{key.charCodeAt(0).toString(16)}"
  else
    keyIdentifier = key[0].toUpperCase() + key[1..]
  location = KeyboardEvent.DOM_KEY_LOCATION_STANDARD
  event.initKeyboardEvent('keydown', bubbles, cancelable, view,  keyIdentifier, location, ctrl, alt, shift, cmd)
  Object.defineProperty(event, 'target', get: -> target) if target?
  Object.defineProperty(event, 'which', get: -> which) if which?
  event

exports.appendContent = (element) ->
  document.querySelector('#jasmine-content').appendChild(element)
  element
