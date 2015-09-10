_ = require('lodash')
Promise = require('promise')
aws = require('./AwsOperations.coffee')
{createTemplate} = require('./Template.coffee')
colors = require('colors/safe')
prompt = require('prompt')
path = require('path')
scriptName = path.basename(process.argv[1])
settings = require('./Settings.coffee')

init = (stackName, image) ->
	settings.load()
	.then (data) ->
		if _.keys(data).length
			throw new Error("A stack already exists in this directory. Run \n\n#{colors.cyan("$ #{scriptName} delete")}\n\nto remove it.")

		promptProps = {}
		defaultName = path.basename(process.cwd())
		if not stackName?
			promptProps.stackName =
				description: "Stack name [#{defaultName}]: "
		if not image
			promptProps.image =
				description: "Docker image: "
				pattern: /^[A-Za-z\-\/]+$/
				required: true
				message: 'Illegal image name'

		prompt.message = ""
		prompt.delimiter = ""
		prompt.colors = false
		prompt.start()
		new Promise (resolve, reject) ->
			prompt.get
				properties: promptProps
			, (err, data) ->
				stackName or= data.stackName or defaultName
				image or= data.image
				data = {stackName, image}
				resolve(settings.save(data))

create = (stackName, image) ->
	template = createTemplate({image})
	aws.createStack(stackName, template)
	.then (result) ->
		if not result.Outputs.length
			throw new Error "Stack creation failed, check the console for details"

		console.log "Stack '#{stackName}' is up and running"
		console.log "Visit #{result.Outputs[0].OutputValue}"

remove = ->
	settings.remove()

destroy = (stackName) ->
	aws.deleteStack(stackName)
	.then (result) ->
		console.log "Stack '#{stackName}' destroyed"

scale = (stackName, size) ->
	aws.scaleTo(stackName, size)
	.then (result) ->
		console.log "Stack '#{stackName}' updated"

redeploy = (stackName) ->
	aws.redeploy(stackName)
	.then (result) ->
		console.log "Stack '#{stackName}' updated"
	.then null, (e) ->
		console.error e
		console.error e.stack

module.exports = {
	init
	remove
	create
	destroy
	scale
	redeploy
}
