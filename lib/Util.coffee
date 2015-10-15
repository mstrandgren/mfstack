# Waiting for a better name

require('es6-shim')
_ = require('lodash')


wrapPromise = (cb) ->
	(params...) ->
		new Promise (resolve, reject) ->
			cb params..., (err, data) ->
				if err then return reject(err)
				resolve(data)

wrapApi = (original) ->
	wrapped = {}
	for key, fn of original when _.isFunction(fn)
		wrapped[key] = wrapPromise(fn.bind(original))
	return wrapped

module.exports = {
	wrapPromise
	wrapApi
}