module.exports = class CommandEvent extends CustomEvent {
  abortKeyBinding () {
    this.stopImmediatePropagation()
    this.keyBindingAborted = true
    return this.keyBindingAborted
  }

  stopPropagation () {
    this.propagationStopped = true
    return super.stopPropagation(...arguments)
  }

  stopImmediatePropagation () {
    this.propagationStopped = true
    return super.stopImmediatePropagation(...arguments)
  }
}
