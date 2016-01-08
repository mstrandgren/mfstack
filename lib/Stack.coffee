_ = require('lodash')
colors = require('colors/safe')
prompt = require('prompt')
path = require('path')
{wrapApi} = require('mflib/ApiWrapper')
fs = wrapApi(require('fs'))
settings = require('./Settings.coffee')
aws = require('./AwsOperations.coffee')
{createTemplate} = require('./Template.coffee')

scriptName = path.basename(process.argv[1])

init = (stackName, {image, environment, keyName}) ->
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
		if not keyName?
			promptProps.keyName =
				description: "SSH key name (optional): "

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
				keyName or= data.keyName or undefined
				data = {stackName, image, keyName}
				resolve(settings.save(data))


create = (stackName, {image, environment, keyName, dockerAuth}) ->
	template = createTemplate(stackName, {image, environment, keyName})

	if dockerAuth
		aws.addEventListener 'stackchanged', ({resource, status}) ->
			if resource == 'Bucket' and status == 'CREATE_COMPLETE'
				putEcsConfig(stackName, dockerAuth)

	aws.createStack(stackName, template)
	.then (result) ->
		if not result.Outputs.length
			throw new Error "Stack creation failed, check the console for details"
		console.log "#{colors.green("Stack '#{stackName}' is up and running")}"
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

scaleVertically = (stackName, size) ->
	aws.scaleVertically(stackName, size)
	.then (result) ->
		console.log "Stack '#{stackName}' updated"


redeploy = (stackName) ->
	aws.redeploy(stackName)
	.then (result) ->
		console.log "Stack '#{stackName}' updated"

sshCommand = (stackName, keyName) ->
	aws.getIpForInstances(stackName)
	.then (ips) ->
		cmdline = "ssh -i \"#{keyName}.pem\" ec2-user@#{ips[0]}"
		console.log "Run $ #{colors.cyan(cmdline)}"

push = (stackName, files) ->
	aws.putConfigFiles(stackName, files, {log: true})

{exec} = require('child_process')

open = (stackName) ->
	aws.getElbPublicDns(stackName)
	.then (address) ->
		exec "open http://#{address}", (err, stdout, stderr) ->
			if err
				console.log err
				console.log stderr
				return

module.exports = {
	init
	remove
	create
	destroy
	scale
	scaleVertically
	redeploy
	sshCommand
	push
	open
}


putEcsConfig = (stackName, dockerAuth) ->
	fs.writeFile 'ecs.config', """
		ECS_ENGINE_AUTH_TYPE=dockercfg
		ECS_ENGINE_AUTH_DATA=#{JSON.stringify(dockerAuth)}
	"""
	.then ->
		aws.putConfigFiles(stackName, ['ecs.config'])
	.then ->
		fs.unlink('ecs.config')

