module.exports = (grunt) ->
  grunt.initConfig
    shell:
      'update-atomdoc':
        command: 'npm update grunt-atomdoc donna tello atomdoc'
        options:
          stdout: true
          stderr: true
          failOnError: true

  grunt.loadNpmTasks('grunt-shell')
  grunt.loadNpmTasks('grunt-atomdoc')
