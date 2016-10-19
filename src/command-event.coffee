# This custom subclass of CustomEvent exists to provide the ::abortKeyBinding
# method, as well as versions of the ::stopPropagation methods that record the
# intent to stop propagation so event bubbling can be properly simulated for
# detached elements.
#
# CustomEvent instances are exotic objects, meaning the CustomEvent constructor
# *must* be called with an exact CustomEvent instance. We work around this fact
# by building a CustomEvent directly, then injecting this object into the
# prototype chain by setting its __proto__ property.
module.exports =
class CommandEvent extends CustomEvent
  keyBindingAborted: false
  propagationStopped: false

  abortKeyBinding: ->
    @stopImmediatePropagation()
    @keyBindingAborted = true

  stopPropagation: ->
    @propagationStopped = true
    super

  stopImmediatePropagation: ->
    @propagationStopped = true
    super
