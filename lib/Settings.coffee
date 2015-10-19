{wrapApi} = require('mflib/ApiWrapper')

fs = wrapApi(require('fs'))


CONFIG_FILE = '.mfstack'

remove = ->
	fs.unlink(CONFIG_FILE, 'utf8')

load = (debug = false) ->
	fs.readFile(CONFIG_FILE, 'utf8')
	.then(JSON.parse)
	.then (data) ->
		getDockerCredentials()
		.then (credentials) ->
			data.dockerAuth = credentials
			return data
	.then null, (e) ->
		if debug then console.log e
		return {}

save = (data) ->
	fs.writeFile(CONFIG_FILE, JSON.stringify(data, null, 2))

getDockerCredentials = (repository = 'https://index.docker.io/v1/')->
	fs.readFile("#{process.env.HOME}/.dockercfg")
	.then null, ->
		fs.readFile("#{process.env.HOME}/.docker/config.json")
	.then(JSON.parse)
	.then (config) ->
		config.auths ? config

module.exports = {
	remove
	load
	save
}