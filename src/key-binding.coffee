Grim = require 'grim'
PropertyAccessors = require 'property-accessors'
{calculateSpecificity} = require './helpers'

module.exports =
class KeyBinding
  PropertyAccessors.includeInto(this)

  @::accessor 'keystroke',
    get: ->
      Grim.deprecate("Use KeyBinding.keystrokes instead")
      @keystrokes

    set: (value) ->
      Grim.deprecate("Use KeyBinding.keystrokes instead")
      @keystrokes = value

  @currentIndex: 1

  enabled: true

  constructor: (@source, @command, @keystrokes, selector) ->
    @keystrokeCount = @keystrokes.split(' ').length
    @selector = selector.replace(/!important/g, '')
    @specificity = calculateSpecificity(selector)
    @index = @constructor.currentIndex++

  matches: (keystroke) ->
    multiKeystroke = /\s/.test keystroke
    if multiKeystroke
      keystroke == @keystroke
    else
      keystroke.split(' ')[0] == @keystroke.split(' ')[0]

  compare: (keyBinding) ->
    if keyBinding.specificity is @specificity
      keyBinding.index - @index
    else
      keyBinding.specificity - @specificity
