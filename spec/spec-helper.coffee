require 'coffee-cache'

beforeEach ->
  document.querySelector('#jasmine-content').innerHTML = ""

exports.keydownEvent = (keyIdentifier, {ctrl, shift, alt, cmd, which, target}={}) ->
  event = document.createEvent('KeyboardEvent')
  bubbles = true
  cancelable = true
  view = null
  keyIdentifier = keyIdentifier.toUpperCase() if /^[a-z]$/.test(keyIdentifier) and shift
  keyIdentifier = "U+#{keyIdentifier.charCodeAt(0).toString(16)}" if keyIdentifier.length is 1
  location = KeyboardEvent.DOM_KEY_LOCATION_STANDARD
  event.initKeyboardEvent('keydown', bubbles, cancelable, view,  keyIdentifier, location, ctrl, alt, shift, cmd)
  Object.defineProperty(event, 'target', get: -> target) if target?
  Object.defineProperty(event, 'which', get: -> which) if which?
  event

exports.appendContent = (element) ->
  document.querySelector('#jasmine-content').appendChild(element)
  element
