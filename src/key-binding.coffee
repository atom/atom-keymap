[fs, loophole, pegjs] = [] # required in dev mode only
{specificity} = require 'clear-cut'
{normalizeKeystrokeSequence} = require './helpers'

module.exports =
class KeyBinding
  @parser: null
  @currentIndex: 1
  @specificities: null

  @calculateSpecificity: (selector) ->
    @specificities ?= {}
    value = @specificities[selector]
    unless value?
      value = specificity(selector)
      @specificities[selector] = value
    value

  constructor: (source, command, keystroke, selector) ->
    @source = source
    @command = command
    @keystroke = normalizeKeystrokeSequence(keystroke)
    @selector = selector.replace(/!important/g, '')
    @specificity = KeyBinding.calculateSpecificity(selector)
    @index = KeyBinding.currentIndex++

  matches: (keystroke) ->
    multiKeystroke = /\s/.test keystroke
    if multiKeystroke
      keystroke == @keystroke
    else
      keystroke.split(' ')[0] == @keystroke.split(' ')[0]

  compare: (keyBinding) ->
    if keyBinding.specificity == @specificity
      keyBinding.index - @index
    else
      keyBinding.specificity - @specificity
