var {
  calculateSpecificity
} = require('./helpers')

module.exports = class KeyBinding {
  static currentIndex = 1

  constructor (source, command, keystrokes, selector, priority) {
    this.source = source
    this.command = command
    this.keystrokes = keystrokes
    this.priority = priority
    this.keystrokeArray = this.keystrokes.split(' ')
    this.keystrokeCount = this.keystrokeArray.length
    this.selector = selector.replace(/!important/g, '')
    this.specificity = calculateSpecificity(selector)
    this.index = this.constructor.currentIndex++
  }

  matches (keystroke) {
    var multiKeystroke = /\s/.test(keystroke)

    if (multiKeystroke) {
      return keystroke === this.keystroke
    } else {
      return keystroke.split(' ')[0] === this.keystroke.split(' ')[0]
    }
  }

  compare (keyBinding) {
    if (keyBinding.priority === this.priority) {
      if (keyBinding.specificity === this.specificity) {
        return keyBinding.index - this.index
      } else {
        return keyBinding.specificity - this.specificity
      }
    } else {
      return keyBinding.priority - this.priority
    }
  }
}
