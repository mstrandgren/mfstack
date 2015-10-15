require('es6-shim')
AWS = require('aws-sdk')

try
	awsConfig = require('./aws.json')

	AWS.config =
		accessKeyId: awsConfig.key
		secretAccessKey: awsConfig.secret
		region: awsConfig.region
		sslEnabled: true
catch e
	console.log "No aws.json, assuming we're in prod"

s3 = new AWS.S3()

getAwsCredentials = (key = 'environment') ->
	new Promise (resolve, reject) ->
		if process.env.AWS_KEY? and process.env.AWS_SECRET?
			console.log "Taking AWS credentials from env"
			return resolve
				accessKeyId: process.env.AWS_KEY
				secretAccessKey: process.env.AWS_SECRET
				region: process.env.AWS_REGION
		s3.getObject {Bucket: 'mf-stack', Key: "#{key}.json"}, (err, data) ->
			if err?
				return reject(err + '\n' + err.stack)
			env = JSON.parse(data.Body.toString('utf8'))
			resolve
				accessKeyId: env.key
				secretAccessKey: env.secret
				region: env.region


module.exports = {getAwsCredentials}