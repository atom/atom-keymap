const {
  calculateSpecificity,
  isKeyup
} = require('./helpers')

const MATCH_TYPES = {
  EXACT: 'exact',
  PARTIAL: 'partial',
  PENDING_KEYUP: 'pendingKeyup'
}

module.exports.MATCH_TYPES = MATCH_TYPES

class KeyBinding {
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
    this.cachedKeyups = null
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

  getKeyups () {
    if (this.cachedKeyups != null) {
      return this.cachedKeyups
    }

    return (() => {
      for (var [i, keystroke] of this.keystrokeArray.entries()) {
        if (isKeyup(keystroke)) {
          this.cachedKeyups = this.keystrokeArray.slice(i)
          return this.cachedKeyups
        }
      }
    })()
  }

  matchesKeystrokes (userKeystrokes) {
    var doesMatch
    var userKeystrokeIndex = -1
    var userKeystrokesHasKeydownEvent = false

    var matchesNextUserKeystroke = function (bindingKeystroke) {
      while (userKeystrokeIndex < userKeystrokes.length - 1) {
        userKeystrokeIndex += 1
        var userKeystroke = userKeystrokes[userKeystrokeIndex]
        var isKeydownEvent = !userKeystroke.startsWith('^')

        if (isKeydownEvent) {
          userKeystrokesHasKeydownEvent = true
        }

        if (bindingKeystroke === userKeystroke) {
          return true
        } else if (isKeydownEvent) {
          return false
        }
      }

      return null
    }

    var isPartialMatch = false
    var bindingRemainderContainsOnlyKeyups = true

    for (var bindingKeystroke of this.keystrokeArray) {
      if (!isPartialMatch) {
        doesMatch = matchesNextUserKeystroke(bindingKeystroke)

        if (doesMatch === false) {
          return false
        } else if (doesMatch === null) {
          if (userKeystrokesHasKeydownEvent) {
            isPartialMatch = true
          } else {
            return false
          }
        }
      }

      if (isPartialMatch) {
        if (!bindingKeystroke.startsWith('^')) {
          bindingRemainderContainsOnlyKeyups = false
        }
      }
    }

    if (userKeystrokeIndex < userKeystrokes.length - 1) {
      return false
    }

    if (isPartialMatch && bindingRemainderContainsOnlyKeyups) {
      return MATCH_TYPES.PENDING_KEYUP
    } else if (isPartialMatch) {
      return MATCH_TYPES.PARTIAL
    } else {
      return MATCH_TYPES.EXACT
    }
  }
}

KeyBinding.currentIndex = 1

module.exports.KeyBinding = KeyBinding
