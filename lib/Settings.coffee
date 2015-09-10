fs = require('fs')
Promise = require('promise')

CONFIG_FILE = '.mfstack'

remove = ->
	new Promise (resolve, reject) ->
		fs.unlink CONFIG_FILE, 'utf8', (err, data) ->
			if err then return resolve({})
			resolve(JSON.parse(data))

load = ->
	new Promise (resolve, reject) ->
		fs.readFile CONFIG_FILE, 'utf8', (err, data) ->
			if err then return resolve({})
			resolve(JSON.parse(data))

save = (data) ->
	new Promise (resolve, reject) ->
		fs.writeFile CONFIG_FILE, JSON.stringify(data, null, 2), 'utf8', (err, data) ->
			if err then return reject(err)
			else resolve()

module.exports = {
	remove
	load
	save
}