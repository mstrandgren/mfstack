_ = require('lodash')
Promise = require('promise')
AWS = require('aws-sdk')
awsConfig = require('./aws.json')

AWS.config =
	accessKeyId: awsConfig.key
	secretAccessKey: awsConfig.secret
	region: awsConfig.region
	sslEnabled: true

wrapPromise = (cb) ->
	(params) ->
		new Promise (resolve, reject) ->
			cb params, (err, data) ->
				if err then return reject(err)
				resolve(data)

wrapAPI = (original) ->
	wrapped = {}
	for key, fn of original when _.isFunction(fn)
		wrapped[key] = wrapPromise(fn.bind(original))
	return wrapped

ec2 = wrapAPI(new AWS.EC2())
s3 = wrapAPI(new AWS.S3())

module.exports = {
	ec2
	s3
}

