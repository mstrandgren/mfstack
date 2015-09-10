_ = require('lodash')
Promise = require('promise')
AWS = require('aws-sdk')


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

module.exports = (awsConfig) ->
	AWS.config = awsConfig
	ec2: wrapAPI(new AWS.EC2())
	s3: wrapAPI(new AWS.S3())
	cf: wrapAPI(new AWS.CloudFormation())
	ecs: wrapAPI(new AWS.ECS())
	as: wrapAPI(new AWS.AutoScaling())
