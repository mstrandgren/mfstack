module.exports = (grunt) ->
	grunt.initConfig
		build:
			template:
				tasks: [
					'clean'
					'bump'
					'copy'
				]

		clean:
			all: 'build'

		copy:
			all:
				expand: true
				src: [
					"lib/{,**/}*"
					"bin/{,**/}*"
					"package.json"
					"README.md"
				]
				dest: 'build'

		bump:
			options:
				commit: false
				tag: false
				push: false


	grunt.registerMultiTask 'build', 'Build app', ->
		grunt.task.run @data.tasks

	require('load-grunt-tasks')(grunt)

	grunt.registerTask('default', ['build'])
