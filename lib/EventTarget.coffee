module.exports = EventTarget = ->
	listeners = new Map()

	addEventListener = (event, cb) ->
		callbacks = listeners.get(event) ? new Set()
		callbacks.add(cb)
		listeners.set(event, callbacks)

	removeEventListener = (event, cb) ->
		callbacks = listeners.get(event)
		callbacks.delete(cb)

	dispatchEvent = (event, args...) ->
		callbacks = listeners.get(event)
		return unless callbacks?
		callbacks.forEach (cb) ->
			cb(args...)

	{
		addEventListener
		removeEventListener
		dispatchEvent
	}